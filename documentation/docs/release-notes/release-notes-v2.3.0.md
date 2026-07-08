# open_pg_tde 2.3.0

`open_pg_tde` brings [Transparent Data Encryption (TDE)](../concepts/about-tde.md) to upstream PostgreSQL and protects data at rest.

[Get Started](../install.md){.md-button}

## Release highlights

### Runs on upstream PostgreSQL 16, 17, and 18

`open_pg_tde` runs on community PostgreSQL through a gated core patch, with no vendor server fork required. The patch series is maintained per major version under `patches/postgresql/`. With the patch flag off, the tree builds as unmodified PostgreSQL. See the [comparison with Percona pg_tde](../concepts/comparison-percona.md).

### Temporary file encryption

Query-spill files (external sorts and hash joins that exceed `work_mem`) can be encrypted with the [`encrypt_temp_files`](../variables.md#encrypt_temp_files) setting. Temporary files are encrypted with AES-128-XTS using a key that is generated per boot and never written to disk.

### AES-256-XTS data cipher

[`open_pg_tde.data_cipher`](../variables.md#open_pg_tdedata_cipher) adds `aes_256_xts` for deployments that require AES-256 keys, alongside AES-128-XTS (the default) and the CBC ciphers. The cipher is recorded per table, so tables created with different ciphers coexist.

### FIPS enforcement

All cryptography runs through OpenSSL and uses FIPS-approved modes. The new [`open_pg_tde.require_fips`](../variables.md#open_pg_tderequire_fips) setting makes the server refuse to start unless OpenSSL is in FIPS mode. See [FIPS compliance](../concepts/fips.md).

### Documentation

- A [threat model](../concepts/threat-model.md) describing what encryption at rest does and does not protect.
- A [FIPS compliance](../concepts/fips.md) page.
- A [comparison with Percona pg_tde](../concepts/comparison-percona.md).
- A [performance](../reference/performance.md) baseline.

### Durability

`open_pg_tde` encrypts a whole page as one unit, so it now recommends and, at startup, checks for data checksums or `wal_log_hints`, which keep hint-bit updates safe against torn writes. See [Configure open_pg_tde](../setup.md#recommended-enable-data-checksums).

## Supported PostgreSQL versions

PostgreSQL 16, 17, and 18. PostgreSQL 16 is the minimum supported version.
