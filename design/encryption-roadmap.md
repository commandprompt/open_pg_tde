# Design: encryption feature roadmap

- Status: Living document
- Date: 2026-07-07
- Scope: candidate encryption features that `open_pg_tde` does not have today,
  with a rough assessment of value, effort, and fit with the current
  architecture. This is a planning document. It proposes no code.

## What exists today

For reference, the current feature surface:

- **Data at rest**: `tde_heap` tables and their indexes and TOAST, encrypted
  through the storage manager. Ciphers: AES-128-XTS (default), AES-256-XTS,
  AES-128-CBC, AES-256-CBC (selected per table via `open_pg_tde.data_cipher`,
  backed by a pluggable cipher registry).
- **WAL**: full WAL encryption with AES-CTR (`open_pg_tde.wal_encrypt`).
- **Temporary files**: query-spill files encrypted with AES-128-XTS
  (`encrypt_temp_files`), using a memory-only per-boot key.
- **Keys**: two-tier hierarchy (principal key wraps per-relation internal
  keys). Providers: keyring file, KMIP, OpenBao. Per-database and global
  (server) providers. Manual principal key rotation.
- **Compliance**: all cryptography runs through OpenSSL with FIPS-approved
  modes; `open_pg_tde.require_fips` enforces OpenSSL FIPS mode.
- **Controls**: `enforce_encryption`, `inherit_global_providers`.

Known gaps that the documentation already calls out: PostgreSQL system catalogs
and statistics are not encrypted.

## PostgreSQL version support

`open_pg_tde` runs on upstream PostgreSQL through the gated core patch under
`patches/postgresql/<major>/`.

| PostgreSQL major | Status |
| ---------------- | ------ |
| 18 | Supported |
| 17 | Supported |
| 16 | Supported (minimum) |
| 19 (Beta 1) | Port in progress, not released |

**PostgreSQL 19.** The storage-manager core, which is the hardest part, ports
cleanly, and the mechanical differences are worked out (an `off_t` to `pgoff_t`
rename in the WAL I/O path, the new `BMR_GET_SMGR()` buffer accessor, an
`index_create` argument type change, and a set of extension header and API
adjustments). Two items remain and are deliberately being handled with care
because they touch recovery and the asynchronous I/O data path, where a subtle
error would write unencrypted data:

- Re-porting sequence WAL redo. PostgreSQL 19 restructured `seq_redo` and removed
  the helper the patch used to encrypt init-fork buffers during recovery.
- Re-porting AIO key handling. PostgreSQL 19 refactored the AIO subsystem
  (including the shmem sizing the extension relied on).

These are scheduled for closer to the PostgreSQL 19 release candidate, since Beta
internals still change. The port also confirmed that the per-major patch must be
applied strictly rather than with fuzz, verified by comparing the gated hunk
count against the PostgreSQL 18 tree.

## Candidate features

Grouped by theme, with a priority tier. Tier 1 is high value and a natural fit
with the current architecture; Tier 2 is high value but more effort; Tier 3 is
large or needs a different architecture.

### Data-at-rest coverage

**1. Temporary file encryption (Tier 1, done).**
Queries that exceed `work_mem` spill to temporary files in plaintext, and these
can persist after a crash. This is a real data-at-rest leak and a documented
limitation. A prototype already exists (a `BufFile` hook gated by an
`encrypt_temp_files` GUC, wired to the same key hierarchy). Folding it in closes
the most visible gap, so data files, WAL, and temp files all share one key
hierarchy. Highest priority.

**2. Statistics encryption (Tier 2).**
`pg_statistic` stores sampled column values (most-common-values lists, histogram
bounds) from encrypted tables in plaintext, so sensitive values can leak through
the catalog. Encrypting or redacting statistics for encrypted relations closes
this. Effort is moderate and the threat is concrete.

**3. Tablespace-level encryption (Tier 1).**
Encrypt an entire tablespace so relations created in it are encrypted
automatically, instead of opting in per table. Covered by its own design doc
(`tablespace-encryption.md`); the engine already keys on the relation file and
tracks the tablespace OID, so this is mostly a policy layer.

### Ciphers and cryptographic strength

**4. AES-256-XTS for data files (Tier 2, done).**
XTS is the recommended mode for storage encryption, but only AES-128-XTS is
available today. AES-256-XTS needs a 64-byte key (two AES-256 subkeys), while
the internal key is capped at 32 bytes (`INTERNAL_KEY_MAX_LEN`, the
`InternalKey.key` buffer, and the on-disk `TDEMapEntry.encrypted_key_data`).
Supporting it requires a **key-map** format bump: enlarge the key entry, bump
the file-version magic, and migrate existing key files (the existing
`FILEMAGIC_VERSION` mechanism, mirroring the V3 to V4 migration). This is a
contained, low-risk change with a migration, and it needs no table rewrite,
since only newly created AES-256-XTS tables use the larger key; existing tables
keep their ciphers. See the dedicated design doc,
[`aes-256-xts.md`](aes-256-xts.md).

**5. Authenticated page encryption, AES-GCM (Tier 2).**
Data pages use XTS/CBC, which provide confidentiality but not integrity, so
tampering with an encrypted page on disk is not detected. AES-GCM would add a
per-page authentication tag and detect tampering. This is a **separate and much
larger** change from the AES-256-XTS key-map bump: the cost is in the page
format, not the key map. Pages are encrypted length-preserving today, with no
room for a per-page tag, and GCM's nonce-reuse hazard on in-place page rewrites
requires per-write nonce management. It is the highest-value hardening on this
list and also the highest effort. Scoped in its own design doc,
[`aes-gcm-authenticated-pages.md`](aes-gcm-authenticated-pages.md); not planned
for near-term implementation.

**6. ChaCha20-Poly1305 (Tier 3).**
An authenticated stream cipher that performs well on platforms without AES
hardware acceleration. Low priority given AES-NI is common, but cheap to add to
the registry if a use case appears.

### Key management

**7. Cloud KMS providers: AWS KMS, GCP KMS, Azure Key Vault (Tier 1).**
Today external keys go through KMIP or OpenBao. Native integrations with the
major cloud KMS services are a common requirement for managed deployments and
extend the existing key-provider interface rather than changing the core. High
commercial value.

**8. Automatic principal key rotation (Tier 2).**
Rotation is manual today. A scheduled or policy-driven rotation (interval or
external trigger) that re-wraps internal keys under the new principal key,
without downtime, is a standard compliance feature. The re-wrap machinery
already exists for manual rotation.

**9. HSM support via PKCS#11 (Tier 2).**
Hold the principal key in a hardware security module and perform wrap/unwrap in
the HSM. A key-provider addition, valuable for regulated environments.

**10. Key-access audit logging (Tier 2).**
Log every principal key access and unwrap (who, when, which key) for compliance
and incident response. Fits alongside the key providers and is largely
additive.

### Granular and compliance features

**11. Column-level encryption (Tier 3).**
Encrypt specific columns rather than whole tables, protecting selected fields
(for example PII) under a distinct threat model. This is a different
architecture from the storage-manager approach (it needs type or expression
level handling and query-path integration) and is a large effort, but it
addresses a use case whole-relation encryption cannot.

**12. FIPS enforcement (Tier 3, done).**
Run crypto through the OpenSSL FIPS provider and restrict to approved ciphers
and key sizes, for deployments with a FIPS requirement. Mostly a build and
policy effort on top of the existing OpenSSL usage.

## Suggested sequencing

1. **Temporary file encryption** (done): closed a known gap, reuses the
   existing key hierarchy (temp files use AES-CBC, so the 32-byte internal key
   is enough, with no format change).
2. **AES-256-XTS**: a contained key-map format bump for compliance regimes that
   mandate AES-256 with the XTS storage mode. See `aes-256-xts.md`.
3. **Cloud KMS providers**: high demand, extends the provider interface.
4. **Tablespace-level encryption**: per its own design doc.
5. **Automatic key rotation** and **key-access audit logging**: compliance
   features on top of the existing key hierarchy.
6. **Statistics encryption**: catalog change to stop `pg_statistic` leaking
   sampled values.
7. **Authenticated page encryption (AES-GCM)**: a large standalone project
   (page-format change plus nonce management). Scoped separately in
   `aes-gcm-authenticated-pages.md`; not near-term.
8. **HSM/PKCS#11**, **FIPS mode**, and **column-level encryption**: larger or
   more specialized, scheduled by demand.

## Notes

- Anything touching the on-disk page format (AES-GCM tags) or the cipher set
  must preserve the ability to read data written by earlier versions, since the
  cipher id is recorded per relation and drives decryption.
- New ciphers and providers should extend the existing registries rather than
  branch the core, to keep the maintenance burden of tracking the upstream
  patch low.
- All C code must satisfy the
  [PostgreSQL coding conventions](https://www.postgresql.org/docs/current/source.html)
  per `CLAUDE.md`.
