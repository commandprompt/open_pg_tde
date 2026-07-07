# open_pg_tde 2.2.0 ({{date.2_2_0}})

The `open_pg_tde` extension adds [Transparent Data Encryption (TDE)](../index/about-tde.md) to PostgreSQL and helps protect sensitive data at rest.

[Get Started](../install.md){.md-button}

## Release Highlights

`open_pg_tde` now supports 256-bit AES encryption and introduces [`open_pg_tde_upgrade`](../command-line-tools/pg-tde-upgrade.md), a utility that simplifies the upgrades of encrypted clusters. For more details, see the [Changelog](#changelog).

!!! warning
    `open_pg_tde` 2.2.0 is not compatible with PostgreSQL builds older than 17.10 or 18.4.

### Documentation updates

* The [Limitations of open_pg_tde](../index/tde-limitations.md) topic is updated to include a new section on known incompatibilities with Citus and TimescaleDB, and a clarification of the `ALTER DATABASE ... SET TABLESPACE` behavior, the command can be used but with restrictions when `open_pg_tde` is active.
* The [Backup with WAL encryption enabled](../how-to/backup-wal-enabled.md) topic is updated with a clearer description of the key rotation limitation during backups.

## Known issues

* `pg_rewind` and `open_pg_tde_rewind`

    Using `pg_rewind` or `open_pg_tde_rewind` between diverged nodes in clusters that use `open_pg_tde` may lead to corrupted tables or indexes due to internal encryption key differences between clusters.

    Queries may fail with:

    ```bash
    ERROR: invalid page in block 0 of relation "base/..."
    ```

    This behavior is a known issue.

    For more information, see [open_pg_tde limitations](../index/tde-limitations.md).

* The default `mlock` limit on Rocky Linux 8 for ARM64-based architectures equals the memory page size and is 64 Kb. This results in the child process with `open_pg_tde` failing to allocate another memory page because the max memory limit is reached by the parent process.

    To prevent this, you can change the `mlock` limit to be at least twice the memory page size:

    * temporarily for the current session using the `ulimit -l <value>` command.
    * set a new hard limit in the `/etc/security/limits.conf` file. To do so, you require the superuser privileges.

    Adjust the limits with caution since it affects other processes running in your system.

## Changelog

Changes introduced in `open_pg_tde` 2.2.0:

### New Features

- AES-256 encryption support, `open_pg_tde` now supports 256-bit AES encryption, providing stronger cryptographic protection for encrypted tablespaces.
- AES-256 compatibility for `open_pg_tde_resetwal`, the `open_pg_tde_resetwal` utility has been updated to work correctly with AES-256 encrypted data.
- AES-256 compatibility for `open_pg_tde_basebackup`, the `open_pg_tde_basebackup` utility now fully supports AES-256 encryption, ensuring consistent backup and restore behavior for databases using the new cipher.
- Introducing `open_pg_tde_upgrade`, a utility that automates the steps required to upgrade a `open_pg_tde`-enabled cluster, making the upgrade process more convenient.

### Improvements

- Storage manager (SMGR) encryption has been optimized to reuse OpenSSL cipher contexts, reducing overhead and improving throughput for encrypted I/O operations.

### Bug Fixes

- Fixed an issue where `pg_upgrade` would fail when run against databases containing encrypted data.
- Resolved a bug where performing WAL key rotation or SMGR key rotation during a `pg_basebackup` operation could prevent the secondary server from starting successfully.
- Fixed key creation failures that occurred when `open_pg_tde` was configured to use HashiCorp Vault via the KMIP protocol.
