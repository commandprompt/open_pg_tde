# Architecture overview

`open_pg_tde` is a customizable data-at-rest encryption extension, delivered as a PostgreSQL extension.

!!! note
    `open_pg_tde` relies on extensibility changes in the PostgreSQL core. You add these by applying the `open_pg_tde` core patch to upstream PostgreSQL 16 or later and building it with the hooks enabled. See [Install from source](../install-from-source.md).

The following sections break down the key architectural components of this design.

**a. Customizable** means that `open_pg_tde` supports many different use cases:

* Encrypting all tables in all databases, or only selected ones
* Storing encryption keys in different external key storage servers, for a list of these see [Key management overview](../key-management/overview.md)
* Using a single key for a clusters, or different keys for different clusters
* Centralizing all keys in one provider, or splitting them across providers
* Controlling permissions: who manages keys and who can create encrypted or unencrypted tables

**b. Complete** means that `open_pg_tde` aims to encrypt data at rest.

**c. Data at rest** means everything written to the disk. This includes the following:

* Table data files
* Indexes
* Sequences
* Temporary tables
* Write Ahead Log (WAL)

## Main components

The main components of `open_pg_tde` are:

* **Core server changes** focus on making the server more extensible, allowing the main logic of `open_pg_tde` to remain separate, as an extension. Core changes also add encryption-awareness to some command line tools that have to work directly with encrypted tables or encrypted WAL files.

    These changes are shipped as a gated patch that you apply to upstream PostgreSQL. See the patch series and its per-version status in `patches/postgresql/` and the [install from source guide](../install-from-source.md).

* The **`open_pg_tde` extension** implements the encryption code by hooking into the extension points introduced in the core changes, and the already existing extension points in the PostgreSQL server.

    Everything is controllable with GUC variables and SQL statements, similar to other extensions.

* The **keyring API and libraries** implement the key storage logic with different key providers. The API is internal only, the keyring the libraries are currently part of the main codebase but could be separated into shared libraries in the future.
