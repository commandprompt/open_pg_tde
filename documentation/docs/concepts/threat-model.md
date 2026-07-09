# Threat model

Transparent Data Encryption protects data **at rest**. Understanding what that
does and does not cover is important for deciding whether `open_pg_tde` fits
your requirements.

## What open_pg_tde protects against

`open_pg_tde` protects the confidentiality of data written to disk. It defends
against an attacker who obtains the stored bytes but not a running server:

- **Theft of storage media or a disk image.** A stolen disk, SAN volume, or
  virtual machine image reveals only ciphertext for encrypted tables, their
  indexes and TOAST data, and (when WAL encryption is enabled) the WAL.
- **Stolen or leaked file-level backups.** A copy of the data directory, or a
  physical backup taken with the `open_pg_tde` tools, is ciphertext at rest.
- **Decommissioned or improperly wiped disks.** Data left on retired hardware
  is not readable without the keys.

The encryption keys are not stored with the data. Each relation's internal key
is wrapped by a principal key held in a key management system or a key file that
the operator controls (see [key management](../key-management/overview.md)).
An attacker with the data files but not the principal key cannot decrypt them.
For temporary files the key is generated per boot and held only in memory, so
temporary data on a stolen disk cannot be recovered at all.

## What open_pg_tde does not protect against

TDE is not a substitute for access control, network security, or application
level protection. It does not defend against an adversary who can act on a
running server:

- **Data in memory.** Shared buffers hold decrypted pages; this is the
  "transparent" part of TDE. An attacker who can read server memory, or who has
  a live database connection with sufficient privileges, sees plaintext.
- **A privileged user on a running server.** A superuser, or anyone who can run
  queries against the data, reads decrypted data through normal SQL. TDE does
  not protect data from the database administrator.
- **Catalog metadata.** PostgreSQL system catalogs are not encrypted. Table and
  column names, table structure, and other schema metadata are stored in the
  clear. Optimizer statistics in `pg_statistic`, which can include sampled
  values from encrypted columns, are also not encrypted. TDE protects the table
  data, not the metadata that describes it. Note that this does not expose the
  encryption keys: the keys live in the `open_pg_tde` key files wrapped by the
  principal key, not in the catalog, so reading or altering catalog entries does
  not reveal key material.
- **Tampering (integrity).** The data-file cipher (XTS) provides
  confidentiality, not authentication. `open_pg_tde` does not currently detect
  deliberate modification of ciphertext on disk. Authenticated page encryption
  is a separate, larger initiative; see the design note on authenticated pages.
- **Column-level protection from the server.** All encryption is at the storage
  layer, so the server necessarily decrypts data to operate on it.
  `open_pg_tde` does not provide client-side or column-level encryption that
  would hide values from the server itself.

## Operational requirements

- **Use an external key management system.** Rooting the principal key in a KMS
  or a key file kept separate from the data is what makes the encryption
  meaningful. Storing the key alongside the data undermines it.
- **Enable data checksums.** `open_pg_tde` encrypts a whole page as one unit, so
  a hint-bit update re-encrypts the page. Initialize the cluster with
  `initdb --data-checksums` (or set `wal_log_hints = on`) so hint-bit changes
  are WAL-logged and torn writes are recoverable. PostgreSQL 18 enables data
  checksums by default. If neither data checksums nor `wal_log_hints` is
  enabled, `open_pg_tde` warns at server start. See
  [Configure open_pg_tde](../setup.md#recommended-enable-data-checksums).
- **Use a FIPS build of OpenSSL where required.** All of open_pg_tde's
  algorithms are FIPS-approved, and it can enforce that OpenSSL is in FIPS mode.
  See [FIPS compliance](fips.md).

## Summary

| Concern | Protected by open_pg_tde |
| ------- | ------------------------ |
| Stolen disk, media, or VM image | Yes |
| Stolen file-level backup | Yes |
| Decommissioned disks | Yes |
| Data in server memory | No |
| Privileged user on a running server | No |
| Catalog metadata and statistics | No |
| Tamper detection (integrity) | No |
| Encryption key exposure via the catalog | Not applicable (keys are not in the catalog) |
