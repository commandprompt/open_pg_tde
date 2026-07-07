# Features

`open_pg_tde` runs on upstream PostgreSQL 16 and later, patched with the `open_pg_tde` core patch. The patch provides the extended Storage Manager and WAL APIs that the extension uses to encrypt data at rest. See [Install from source](install-from-source.md).

The following features are available for the extension:

* [Table encryption](test.md#encrypt-data-in-a-new-table), including:
    * Data tables
    * Index data for encrypted tables
    * TOAST tables
    * Temporary tables

!!! note
    Metadata of those tables is not encrypted.

* Single-tenancy support via a [global keyring provider](global-key-provider-configuration/set-principal-key.md)
* [Multi-tenancy support](how-to/multi-tenant-setup.md)
* Table-level granularity for encryption and access control
* Multiple [Key management options](global-key-provider-configuration/overview.md)

## Next steps

Learn more about how `open_pg_tde` implements Transparent Data Encryption:

[About Transparent Data Encryption :material-arrow-right:](index/about-tde.md){.md-button}
