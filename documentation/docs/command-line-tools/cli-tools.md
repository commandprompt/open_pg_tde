# Overview of open_pg_tde CLI tools

The `open_pg_tde` extension provides a set of command-line utilities designed specifically for operating on  encrypted data and clusters. These utilities exist in parallel with the standard PostgreSQL utilities but you **must** use them when working with data encrypted by `open_pg_tde`.

!!! note
    The standard PostgreSQL tools cannot operate on `open_pg_tde`-encrypted WAL or tables.

## New `open_pg_tde` specific tools

These tools are introduced exclusively by `open_pg_tde` to support key rotation and WAL encryption workflows:

* [open_pg_tde_change_key_provider](./pg-tde-change-key-provider.md): change the encryption key provider for a database
* [open_pg_tde_archive_decrypt](./pg-tde-archive-decrypt.md): decrypts WAL before archiving
* [open_pg_tde_restore_encrypt](./pg-tde-restore-encrypt.md): a custom restore command for making sure the restored WAL is encrypted

## Tools for working with `open_pg_tde`-encrypted data

These tools are modified versions of standard PostgreSQL utilities that include `open_pg_tde` support. You must use the `open_pg_tde_*` variants when working with encrypted WAL or tables:

* [open_pg_tde_checksums](./pg-tde-checksums.md): verify data checksums
* [open_pg_tde_waldump](./pg-tde-waldump.md): inspect and decrypt WAL files
* [open_pg_tde_basebackup](../how-to/backup-wal-enabled.md): create base backups that include encrypted data
* open_pg_tde_resetwal: reset the WAL for clusters using `open_pg_tde`
* open_pg_tde_rewind: rewind clusters that use encrypted WAL
* [open_pg_tde_upgrade](./pg-tde-upgrade.md): perform major version upgrades of clusters with `open_pg_tde`
