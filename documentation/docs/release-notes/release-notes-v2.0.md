# open_pg_tde 2.0.0 ({{date.GA20}})

The `open_pg_tde` extension brings [Transparent Data Encryption (TDE)](../index/about-tde.md) to PostgreSQL and enables you to keep sensitive data safe and secure.

[Get Started](../install.md){.md-button}

## Release Highlights

### WAL encryption is now generally available

The WAL (Write-Ahead Logging) encryption feature is now fully supported and production-ready, it adds secure write-ahead logging to `open_pg_tde`, expanding its encryption coverage by enabling secure, transparent encryption of write-ahead logs using the same key infrastructure as data encryption.

### WAL encryption upgrade limitation

Clusters that used WAL encryption in the beta release (`open_pg_tde` 1.0 or older) cannot be upgraded to `open_pg_tde` 2.0. The following error indicates that WAL encryption was enabled:

```sql
FATAL: principal key not configured
HINT: Use open_pg_tde_set_server_key_using_global_key_provider() to configure one.
```

Clusters that did not use WAL encryption in beta can be upgraded normally.

### Documentation updates

* Updated the [Limitations](../index/tde-limitations.md) topic, it now includes WAL encryption limitations and both supported and unsupported WAL tools
* Added a new topic for [Backup with WAL encryption enabled](../how-to/backup-wal-enabled.md) that includes restoring a backup created with WAL encryption
* Added documentation for using the `open_pg_tde_archive_decrypt` and `open_pg_tde_restore_encrypt` utilities. These tools are now covered in [CLI Tools](../command-line-tools/cli-tools.md) to guide users on how to archive and restore encrypted WAL segments securely
* Updated documentation for [uninstalling `open_pg_tde`](../how-to/uninstall.md) with WAL encryption enabled and improved the uninstall instructions to cover cases where TDE is disabled while WAL encryption remains active

## Known issues

* Creating, changing, or rotating global key providers (or their keys) while `pg_basebackup` is running may cause standbys or standalone clusters initialized from the backup to fail during WAL replay and may also lead to the corruption of encrypted data (tables, indexes, and other relations).

    Avoid making these actions during backup windows. Run a new full backup after completing a rotation or provider update.

* Using `pg_basebackup` with `--wal-method=fetch` produces warnings.

    This behavior is expected and will be addressed in a future release.

* The default `mlock` limit on Rocky Linux 8 for ARM64-based architectures equals the memory page size and is 64 Kb. This results in the child process with `open_pg_tde` failing to allocate another memory page because the max memory limit is reached by the parent process.

    To prevent this, you can change the `mlock` limit to be at least twice bigger than the memory page size:

    * temporarily for the current session using the `ulimit -l <value>` command.
    * set a new hard limit in the `/etc/security/limits.conf` file. To do so, you require the superuser privileges.

    Adjust the limits with caution since it affects other processes running in your system.

## Changelog

### New Features

* PG-1497 WAL encryption is now generally available (GA)
* Added support for `pg_rewind` with encrypted WAL
* Added support for `pg_resetwal` with encrypted WAL
* Added support for `pg_basebackup` with encrypted WAL
* Added support for WAL archiving with encrypted WAL
* Added support for incremental backups with encrypted WAL, compatibility has been verified with `pg_combinebackup` and the WAL summarizer tool.
* Added support for `pg_createsubscriber` with encrypted WAL
* Added verified support for using `pg_waldump` with encrypted WAL
* Verified `pg_upgrade` with encryption

### Improvements

* Added validation for key material received from providers
* Validated Vault keyring engine type

### Bugs Fixed

* Fixed unencrypted checkpoint segment on replica with encrypted key
* Fixed an issue where `XLogFileCopy` failed with encrypted WAL during PITR and `pg_rewind`
* Fixed an issue where `open_pg_tde_change_key_provider` did not work without the `-D` flag even if `PGDATA` was set
* Fixed an issue where streaming replication failed with an invalid magic number in WAL when `wal_encryption` was enabled
* Fixed a crash during standby promotion caused by an invalid magic number when replaying two-phase transactions from WAL
* Fixed an issue where the global key provider could not be deleted after server restart
* Fixed an issue where `pg_resetwal` corrupted encrypted WAL, causing PostgreSQL to fail at startup with an invalid checkpoint
* Fixed a delay in replica startup with encrypted tables in streaming replication setups
* Fixed performance issues when creating encrypted tables
* Fixed an issue where unnecessary WAL was generated when creating temporary tables
* Fixed an issue where automatic restart after crash sometimes failed with WAL encryption enabled
* Fixed archive recovery with encrypted WAL
