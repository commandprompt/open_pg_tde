# Encrypted data scope

`open_pg_tde` encrypts the following components:

* **User data** in tables using the extension, including associated TOAST data. The table metadata (column names, data types, etc.) is not encrypted.
* **Temporary tables** created during the query execution, for data tables created using the extension.
* **Write-Ahead Log (WAL) data** for the entire database cluster. This includes WAL data in encrypted and non-encrypted tables.
* **Indexes** on encrypted tables.

For what encryption at rest does and does not protect against, see the [threat model](threat-model.md).

[Check out the table access methods :material-arrow-right:](table-access-method.md){.md-button}
