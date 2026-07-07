# open_pg_tde 2.1.0 ({{date.2_1}})

The `open_pg_tde` extension brings [Transparent Data Encryption (TDE)](../index/about-tde.md) to PostgreSQL and enables you to keep sensitive data safe and secure.

[Get Started](../install.md){.md-button}

## Release Highlights

### Added support for PostgreSQL 18.1

`open_pg_tde` is fully supported with the Postgres 18.1 version.

### Packaging changes for PostgreSQL 18

Starting with PostgreSQL 18, `open_pg_tde` is distributed as a **standalone package** for RPM and DEB installations.

It is no longer bundled with the main PostgreSQL server package.

If your PostgreSQL 18 deployment uses `open_pg_tde`, make sure to install the matching `open_pg_tde` package separately.

`open_pg_tde` is built as an extension against a patched PostgreSQL. See the [install from source guide](../install-from-source.md).

For more information on the availability by PostgreSQL version, please see [Install open_pg_tde](../install.md).

### Added support for AIO

Added support for **asynchronous I/O (AIO)** which is now the default I/O mechanism.

### Added namespace support for Vault Enterprise and OpenBao

Added support for HashiCorp Vault and OpenBao namespaces. The `namespace` parameter is now documented in [OpenBao provider configuration](../global-key-provider-configuration/openbao.md) and fully supported.

### Repository split for multi-version PostgreSQL support

Reorganized the project into a multi-repository structure to support several PostgreSQL versions more efficiently.

### Tooling changes

The standard PostgreSQL command-line utilities can no longer operate on clusters encrypted with `open_pg_tde`. To manage encrypted data safely, use the `open_pg_tde_` equivalents:

* pg_basebackup to open_pg_tde_basebackup
* pg_checksums to open_pg_tde_checksums
* pg_resetwal to open_pg_tde_resetwal
* pg_rewind to open_pg_tde_rewind
* pg_waldump to open_pg_tde_waldump

!!! warning

    The non-open_pg_tde_* versions will not work on encrypted clusters and may fail with errors if used. Always use the `open_pg_tde_` variants when working with TDE-enabled data.

### Added Akeyless support

`open_pg_tde` is now compatible with the Akeyless CipherTrust Manager via the KMIP protocol. For more information, see the [Key management overview topic](../global-key-provider-configuration/overview.md).

### Added support for Vault and OpenBao namespaces

Implemented support for the "namespace" feature in Vault Enterprise and OpenBao, available both on the CLI and on the HTTP interface using the `X-Vault-Namespace` header.

### Documentation updates

- Added the [Akeyless topic](../global-key-provider-configuration/kmip-akeyless.md)
- Added the [Impact of open_pg_tde on database operations](../index/what-tde-impacts.md) topic which summarizes how `open_pg_tde` interacts with core PostgreSQL operations
- Updated the [FAQ](../faq.md) with an answer to logical replication keeping data encrypted on subscribers
- Updated [Install open_pg_tde](../install.md) with a table for the `open_pg_tde` availability by PostgreSQL version
- Updated [OpenBao provider configuration](../global-key-provider-configuration/openbao.md) to include the `namespace` parameter.

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
