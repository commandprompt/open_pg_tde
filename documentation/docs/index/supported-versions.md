# Versions and supported PostgreSQL deployments

`open_pg_tde` runs on upstream PostgreSQL. It does not require a vendor fork of
the server. Encryption relies on storage-manager and WAL extensibility that
upstream PostgreSQL does not yet expose, so you apply the `open_pg_tde` core
patch to a PostgreSQL source tree, build it with the hooks enabled, and build
the extension against that install. See [Install from source](../install-from-source.md).

## Supported PostgreSQL versions

| PostgreSQL major | Status |
| ---------------- | ------ |
| 18 | Supported |
| 17 | Supported |
| 16 | Supported |
| 14 - 15 | Not supported |

PostgreSQL 16 is the minimum supported version. The core patch is maintained as
a per-major-version series under `patches/postgresql/`, because the storage
manager interface changes between PostgreSQL majors. See
`patches/postgresql/README.md` in the source tree for the current status and the
maintenance process.

On a supported version, `open_pg_tde` provides the `tde_heap` access method and
encrypts tables, indexes, and WAL data.

!!! note
    Support for the earlier `tde_heap_basic` access method has been removed.
    Use `tde_heap`.

[Get started with installation :material-arrow-right:](../install.md){.md-button}
