# Install open_pg_tde

`open_pg_tde` runs on upstream PostgreSQL 16 and later. It does not require a
vendor fork of the server. Because encryption relies on storage-manager and WAL
extensibility that upstream PostgreSQL does not yet expose, you install
`open_pg_tde` by applying a gated core patch to a PostgreSQL source tree and
building it, then building the extension against that install.

=== ":octicons-git-branch-16: From source (recommended)"

    Apply the `open_pg_tde` core patch to a stock PostgreSQL 16+ source tree,
    build with the hooks enabled, and build the extension against it. This is the
    supported path and works on any platform that can build PostgreSQL.

    [Install from source :material-arrow-right:](install-from-source.md){.md-button}

=== ":octicons-package-16: Prebuilt packages"

    Prebuilt DEB and RPM packages of `open_pg_tde` together with a compatible
    PostgreSQL build are planned. When available, they will be documented here.

## Supported PostgreSQL versions

| **PostgreSQL major** | **Status** |
| -------- | -------- |
| 18 | Supported |
| 17 | Supported |
| 16 | Supported |
| 14 - 15 | Not supported |

The core patch is maintained as a per-major-version series, since the storage
manager interface changes between PostgreSQL majors. See
`patches/postgresql/README.md` in the source tree for the current status and the
maintenance process.

## Next steps

After finishing the installation, you can proceed with:

[Set up open_pg_tde](setup.md){.md-button}
[Learn about key management](global-key-provider-configuration/overview.md){.md-button}
[Validate your encryption setup](test.md){.md-button}
[Enable WAL encryption](wal-encryption.md){.md-button}
