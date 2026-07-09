# FIPS compliance

FIPS 140-2 and 140-3 are US government standards for cryptographic modules.
This page describes how `open_pg_tde` relates to them: which algorithms it uses,
how to run it so that all cryptography is FIPS-validated, and the distinction
between using a validated module and being one.

## Compliance model

`open_pg_tde` does not implement its own cryptography. Every cryptographic
operation, for table data, indexes, WAL, temporary files, key wrapping, and
random number generation, is performed through OpenSSL's EVP interface. When
OpenSSL is configured to use its FIPS-validated provider, `open_pg_tde`'s
cryptography runs on validated implementations.

This is the standard way software achieves FIPS compliance: it relies on a
validated cryptographic module (OpenSSL's FIPS provider) rather than certifying
its own. `open_pg_tde` is therefore **FIPS-compliant when run against a
FIPS-validated OpenSSL**. It is not itself a separately validated FIPS 140
module; the validated module boundary is OpenSSL, not the extension. Deployments
that must cite a validation certificate cite the OpenSSL FIPS provider's
certificate.

## Approved algorithms

Every algorithm `open_pg_tde` uses is FIPS-approved:

| Purpose | Algorithm | Standard |
| ------- | --------- | -------- |
| Table and index data files | AES-128-XTS, AES-256-XTS | NIST SP 800-38E |
| WAL | AES-CTR (128 or 256) | NIST SP 800-38A |
| Temporary files | AES-128-XTS, with AES-128-CTR for sub-block tails | NIST SP 800-38E, 800-38A |
| Internal key wrapping | AES-256-GCM | NIST SP 800-38D |
| Random keys and IVs | OpenSSL DRBG | NIST SP 800-90A |

XTS-AES requires its two subkeys to be independent (NIST SP 800-38E). OpenSSL
enforces this by rejecting an XTS key whose halves are equal. `open_pg_tde`
generates independent subkeys for every XTS key, including the 64-byte key for
AES-256-XTS. Each XTS data unit is a single page (at most 512 AES blocks), well
within the SP 800-38E limit on data unit size.

## Running in FIPS mode

1. Configure OpenSSL to use its FIPS provider. This is done in the operating
   system's OpenSSL configuration and is independent of PostgreSQL. Follow the
   OpenSSL FIPS documentation for your distribution. `open_pg_tde` requires
   OpenSSL 3.0 or later for FIPS operation.

2. Set `open_pg_tde.require_fips = on` in `postgresql.conf` and restart. On
   start, `open_pg_tde` verifies that the OpenSSL FIPS provider is active. If it
   is not, the server stops with a fatal error rather than run on non-validated
   cryptography:

   ```
   FATAL:  open_pg_tde.require_fips is set but OpenSSL is not in FIPS mode
   ```

   `require_fips` does not put OpenSSL into FIPS mode; it enforces that OpenSSL
   is already configured for it. Leaving it off does not disable encryption; it
   only removes the startup check.

## Scope and caveats

- FIPS addresses the cryptographic algorithms and their implementation. It does
  not change what encryption at rest protects. See the [threat model](threat-model.md)
  for that scope, including that catalog metadata is not encrypted.
- FIPS compliance depends on the OpenSSL build in use. Verify that the OpenSSL
  linked by your PostgreSQL packages provides a validated FIPS provider.
- `open_pg_tde` selects algorithms and modes; it does not weaken them. There is
  no configuration that selects a non-approved algorithm.
