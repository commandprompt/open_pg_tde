# open_pg_tde 2.1.1 ({{date.2_1_1}})

The `open_pg_tde` extension adds [Transparent Data Encryption (TDE)](../index/about-tde.md) to PostgreSQL and helps protect sensitive data at rest.

[Get Started](../install.md){.md-button}

## Release Highlights

### Integrated Hashicorp Vault namespace

The namespace of Hashicorp vault is integrated with ``open_pg_tde`` through the  ``open_pg_tde_add_global_key_provider_vault_v2`` parameter.

### Documentation updates

Updated the [Global Principal Key configuration](../global-key-provider-configuration/set-principal-key.md) and [Configure WAL encryption](../wal-encryption.md) chapters with updated installation steps and removed outdated KMS configuration information.

## Known issues

* Creating, changing, or rotating global key providers (or their keys) while `open_pg_tde_basebackup` is running may cause standbys or standalone clusters initialized from the backup to fail during WAL replay and may also lead to the corruption of encrypted data (tables, indexes, and other relations).

    Avoid making these actions during backup windows. Run a new full backup after completing a rotation or provider update.

* Using `open_pg_tde_basebackup` with `--wal-method=fetch` produces warnings.

    This behavior is expected and will be addressed in a future release.

* The default `mlock` limit on Rocky Linux 8 for ARM64-based architectures equals the memory page size and is 64 Kb. This results in the child process with `open_pg_tde` failing to allocate another memory page because the max memory limit is reached by the parent process.

    To prevent this, you can change the `mlock` limit to be at least twice bigger than the memory page size:

    * temporarily for the current session using the `ulimit -l <value>` command.
    * set a new hard limit in the `/etc/security/limits.conf` file. To do so, you require the superuser privileges.

    Adjust the limits with caution since it affects other processes running in your system.

## Changelog

### New Features

* Namespace of Hashicorp vault is integrated with `open_pg_tde`
