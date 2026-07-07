# open_pg_tde 2.2.1 ({{date.2_2_1}})

The `open_pg_tde` extension adds [Transparent Data Encryption (TDE)](../index/about-tde.md) to PostgreSQL and helps protect sensitive data at rest.

[Get Started](../install.md){.md-button}

## Release Highlights

`open_pg_tde` 2.2.1 focuses on stability and compatibility improvements. This release improves `pg_rewind` reliability and Microsoft Visual C++ (MSVC) compatibility. For more details, see the [Changelog](#changelog).

!!! warning
    `open_pg_tde` 2.2.1 is not compatible with PostgreSQL builds older than 17.10.2 or 18.4.2.

## Known issues

* The default `mlock` limit on Rocky Linux 8 for ARM64-based architectures equals the memory page size and is 64 Kb. This results in the child process with `open_pg_tde` failing to allocate another memory page because the max memory limit is reached by the parent process.

    To prevent this, you can change the `mlock` limit to be at least twice the memory page size:

    * temporarily for the current session using the `ulimit -l <value>` command.
    * set a new hard limit in the `/etc/security/limits.conf` file. To do so, you require the superuser privileges.

    Adjust the limits with caution since it affects other processes running in your system.

## Changelog

Changes introduced in `open_pg_tde` 2.2.1:

### Bug Fixes

- Fixed build and runtime compatibility issues for Microsoft Visual C++ (MSVC) on Windows.
- Fixed multiple issues affecting `pg_rewind` for `open_pg_tde` clusters, improving reliability during rewind and recovery operations.
