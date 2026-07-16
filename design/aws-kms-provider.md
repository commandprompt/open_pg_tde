# Design: AWS KMS key provider

- Status: Proposed (scoping)
- Date: 2026-07-16
- Scope: add AWS as a key provider that protects the principal key, the first
  cloud KMS integration, alongside the existing file, KMIP, and OpenBao
  providers. No change to data-file, WAL, or temporary-file encryption.

## Motivation

Managed and cloud deployments commonly require that the root of trust for
encryption live in the cloud provider's key management service, under the
customer's IAM controls and audit trail (CloudTrail), rather than in a keyring
file or a self-hosted KMIP or OpenBao server. AWS KMS is the most requested of
these. This is a key-provider addition: it changes where the **principal key**
is protected, and nothing else in the cryptographic stack.

## Constraint: how the principal key works today

`open_pg_tde` uses a two-tier key hierarchy. A **principal key** wraps the
per-relation and WAL **internal keys** with AES-GCM; the internal keys encrypt
data. The principal key lives in a **key provider**, and the provider interface
(`TDEKeyringRoutine` in `src/include/keyring/keyring_api.h`) is a **named secret
store**:

- `keyring_get_key(keyring, name)` returns the principal key's raw bytes;
- `keyring_store_key(keyring, KeyInfo)` stores the raw bytes under a name;
- `KeyringGenerateNewKeyAndStore` generates a random key and stores it.

`open_pg_tde` generates the principal key, stores it in the provider by name,
and fetches it (into server memory) to wrap and unwrap internal keys. The file,
KMIP, and OpenBao providers all implement this store-and-fetch contract. The
OpenBao provider, the closest analog to a cloud provider, is HTTPS over libcurl
to a KV-v2 secret engine (`src/keyring/keyring_openbao.c`).

**AWS KMS does not store secrets.** It is a stateless encrypt and decrypt
service: the customer master key (CMK) never leaves KMS, and KMS returns
ciphertext or plaintext but keeps nothing. That mismatch, a stateful
store-and-fetch interface over a stateless wrap-and-unwrap service, is the whole
design problem.

## The envelope model, resolved inside the provider

The resolution is that the provider performs the KMS wrap and unwrap **inside**
`keyring_store_key` and `keyring_get_key`, and keeps the small KMS ciphertext
blob in a place the provider owns:

- `keyring_store_key(key)`: call KMS `Encrypt` on the principal key under the
  configured CMK, then persist the returned ciphertext blob under the key name.
- `keyring_get_key(name)`: read the ciphertext blob for the name, call KMS
  `Decrypt`, and return the plaintext principal key.

The principal key still comes back into server memory to wrap internal keys,
exactly as with every provider today, so nothing downstream changes. What
changes is the property at rest: the principal key is stored only as a KMS
ciphertext that is useless without an authorized KMS `Decrypt` call, the CMK
never leaves KMS, and every access is logged and revocable through AWS.

**This needs no change to the `TDEKeyringRoutine` vtable.** The earlier roadmap
note that envelope mode "needs the interface extended with a wrap/unwrap
operation" applies only to a design that keeps the key wrapped past the provider
boundary and unwraps it elsewhere. Doing the KMS calls inside the existing
get/store keeps the provider a drop-in like OpenBao. A future lazy-unwrap
refactor could still extend the vtable, but it is not required here.

### Where the wrapped blob lives

Two options, both keep the CMK as the root of trust:

- **Local wrapped-key file (recommended for v1).** The provider writes the KMS
  ciphertext blobs to a file it owns, in the data directory, indexed by key
  name, the same shape as the file provider but the file contents are KMS
  ciphertext rather than raw keys. Self-contained, no per-secret cost, and the
  data directory then holds only KMS-wrapped keys: a stolen disk yields nothing
  without KMS access. This is the truest "AWS KMS" provider.
- **AWS Secrets Manager backing (option).** Store the principal key in Secrets
  Manager with the CMK as its encryption key. Fully managed, no local file, and
  it maps directly onto `get_key`/`store_key` as `GetSecretValue` and
  `PutSecretValue`. Costs per secret and adds a second service and IAM surface.
  Offer it where operators prefer managed storage over a local ciphertext file.

## Configuration and SQL surface

New provider type `AWS_KMS_KEY_PROVIDER` and the usual pair of registration
functions, mirroring the OpenBao ones:

```
open_pg_tde_add_global_key_provider_aws_kms(provider_name, region, key_arn, ...)
open_pg_tde_add_database_key_provider_aws_kms(provider_name, region, key_arn, ...)
```

Options JSON (parsed in `src/catalog/tde_keyring_parse_opts.c`, stored in a new
`AwsKmsKeyring` struct in `keyring_api.h`):

- `region` (required), for example `us-east-1`.
- `keyArn` (required), the CMK ARN or key id/alias used for `Encrypt`. `Decrypt`
  derives the key from the ciphertext, so the ARN is only needed for wrap.
- `wrappedKeyPath` (v1 local-file storage) or a Secrets Manager prefix (option).
- `endpointUrl` (optional), to point at LocalStack or a VPC endpoint.
- Auth fields are optional; see below. Prefer the ambient credential chain over
  putting credentials in the provider config.

Existing providers, on-disk key file formats, and the `data_cipher` / WAL /
temp-file settings are untouched. This is purely additive.

## Authentication

Follow the standard AWS credential resolution so it works in the environments
operators actually run in, without static keys in the catalog:

1. Explicit credentials in the provider options (discouraged, but supported for
   parity and testing).
2. Environment (`AWS_ACCESS_KEY_ID` and friends) and the shared config/profile.
3. **IMDSv2 instance role** (EC2): token-first metadata calls to
   `169.254.169.254`.
4. **IRSA / EKS web identity**: read the projected token file and call STS
   `AssumeRoleWithWebIdentity`; **ECS task role** via the container credentials
   endpoint.

Requests are signed with **AWS Signature Version 4** (HMAC-SHA256 over a
canonical request), which OpenSSL already provides. The credential chain, not
the signing, is the bulk of the work, and it is what the AWS SDKs exist to
provide.

## Implementation approach

Use **raw HTTPS with SigV4 over libcurl and OpenSSL**, the libraries already
linked (`libcurl`, `libcrypto`, `libssl`), rather than the AWS C++ SDK, which
would add a large C++ dependency to a C extension. This matches the existing
curl-based providers (`keyring_curl.c`, `keyring_openbao.c`).

KMS is a JSON-over-HTTPS API: POST to `kms.<region>.amazonaws.com` with
`X-Amz-Target: TrentService.Encrypt` or `TrentService.Decrypt` and a small JSON
body (`KeyId` and base64 `Plaintext` for Encrypt; base64 `CiphertextBlob` for
Decrypt). Secrets Manager is the same style (`secretsmanager.<region>...`).

The one heavier piece is the credential chain. Options:

- Implement IMDSv2 and env/profile in v1 (small), defer IRSA/STS to v2; or
- Link a focused credentials library (for example `aws-c-auth`) for credentials
  only, and keep the KMS calls hand-rolled. This trades a dependency for
  correct, maintained credential resolution.

Recommend hand-rolling IMDSv2 + env/profile for v1 and revisiting a credentials
library when IRSA/STS lands.

## Security properties

- The CMK never leaves KMS; the principal key at rest is only KMS ciphertext.
- IAM policy gates `kms:Decrypt`; revoking it makes the database unreadable
  without touching the data, and CloudTrail records every wrap and unwrap.
- The principal key is still present in server memory while in use, the same as
  every provider today (documented in the threat model). KMS does not change the
  live-server threat model, only the at-rest and access-control story.
- Reuse the KMIP provider's TLS hardening (peer verification, host match, TLS
  1.2+, from PR #8) for the KMS and metadata endpoints.

## Testing

An env-gated TAP test `t/aws_kms.pl`, gated like `t/kmip.pl` and `t/openbao.pl`
(`PG_TEST_REQUIRE_AWS_KMS`), run against **LocalStack** (which implements KMS
and Secrets Manager) or **moto**. Cover: create and set a principal key backed
by KMS, restart and re-read (unwrap), rotate the principal key, and a negative
test that a wrong or denied CMK fails cleanly. CI can run LocalStack as a
service container.

## Effort and risk

Tier 1, contained, no core or on-disk format change. Rough breakdown:

- Provider skeleton (struct, parse, register, SQL functions): small, mirrors
  OpenBao.
- KMS `Encrypt`/`Decrypt` over HTTPS with JSON and SigV4: medium; SigV4 is the
  fiddly part but well specified.
- Credential chain (IMDSv2, env, profile; then IRSA/STS): medium to large, the
  main effort and the main risk, since matching SDK behavior across environments
  is broad.
- Wrapped-key storage (local file, then optional Secrets Manager): small to
  medium.
- LocalStack test and docs: medium.

Risk is concentrated in the credential chain breadth, not in the cryptography or
the `open_pg_tde` integration.

## Suggested phasing

1. **v1**: AWS KMS provider, envelope with a local wrapped-key file; auth via
   env, shared profile, and IMDSv2 instance role; SigV4 over libcurl; LocalStack
   test and documentation.
2. **v2**: IRSA / EKS web identity and STS `AssumeRoleWithWebIdentity`, ECS task
   role; optional Secrets Manager storage backing.
3. **Generalize**: GCP Cloud KMS and Azure Key Vault reuse the envelope shape
   and the HTTP scaffolding; the credential chains differ per cloud.

## Open questions

- v1 storage: local wrapped-key file (recommended) or Secrets Manager first?
- Credential chain scope for v1: is IMDSv2 + env/profile enough, or is IRSA
  required on day one for EKS users?
- Credentials: hand-rolled, or link `aws-c-auth` for credential resolution only?
- Principal key rotation: `open_pg_tde`'s manual rotation re-wraps internal keys
  under a new principal key, which the KMS provider stores as a fresh wrapped
  blob; CMK rotation inside AWS is transparent to `Decrypt`. Confirm both paths
  in the rotation test.
