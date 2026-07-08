# Configure open_pg_tde

Before you can use `open_pg_tde` for data encryption, you must enable the extension and configure PostgreSQL to load it at startup. This setup ensures that the necessary hooks and shared memory are available for encryption operations.

!!! note
    To learn how to configure multi-tenancy, refer to the [Configure multi-tenancy](how-to/multi-tenant-setup.md) guidelines.

The `open_pg_tde` extension requires additional shared memory. You need to configure PostgreSQL to preload it at startup.

## 1. Configure shared_preload_libraries

You can configure the `shared_preload_libraries` parameter in two ways:

* Add the following line to the `postgresql.conf` file:

    ```bash
    shared_preload_libraries = 'open_pg_tde'
    ```

* Use the [ALTER SYSTEM :octicons-link-external-16:](https://www.postgresql.org/docs/current/sql-altersystem.html) command. Run the following command in `psql` as a **superuser**:

    ```sql
    ALTER SYSTEM SET shared_preload_libraries = 'open_pg_tde';
    ```

## 2. Restart the PostgreSQL cluster

Restart the `postgresql` cluster to apply the configuration.

* On Debian and Ubuntu:

       ```sh
       sudo systemctl restart postgresql.service
       ```

* On RHEL and derivatives:

       ```sh
       sudo systemctl restart postgresql-17
       ```

## 3. Create the extension

After restarting PostgreSQL, connect to `psql` as a **superuser** or **database owner** and run:

```sql
CREATE EXTENSION open_pg_tde;
```

See [CREATE EXTENSION :octicons-link-external-16:](https://www.postgresql.org/docs/current/sql-createextension.html) for more details.

!!! note
    The `open_pg_tde` extension is created only for the current database. To enable it for other databases, you must run the command in each individual database.

## 4. (Optional) Enable open_pg_tde by default

To automatically have `open_pg_tde` enabled for all new databases, modify the `template1` database:

```sql
psql -d template1 -c 'CREATE EXTENSION open_pg_tde;'
```

!!! note
    It’s recommended to use an external key provider (KMS) to manage encryption keys. For configuration instructions, see [Next steps](#next-steps).

## Recommended: enable data checksums

`open_pg_tde` encrypts a whole 8 kB page as one unit. When a hint bit is updated
on a page, the entire page is re-encrypted. PostgreSQL does not, by default,
write-ahead log a hint-bit-only change, so under whole-page encryption a torn
write of such a page during a crash could damage the page.

Enable **data checksums** so PostgreSQL WAL-logs hint-bit changes and full-page
images protect against torn pages. Initialize the cluster with checksums:

```sh
initdb --data-checksums -D /path/to/datadir
```

If the cluster was not initialized with checksums, set `wal_log_hints = on`
instead. Data checksums also verify page integrity on read; the checksum is
computed on the plaintext page and then the page is encrypted, so verification
runs on the decrypted page and works normally with `open_pg_tde`.

PostgreSQL 18 enables data checksums by default, so a default PostgreSQL 18
cluster is already safe. On earlier versions checksums are off unless you enable
them. If neither data checksums nor `wal_log_hints` is enabled, `open_pg_tde`
emits a warning at server start:

```
WARNING:  open_pg_tde is loaded but neither data checksums nor wal_log_hints is enabled
```

## Next steps

[Configure Key Management (KMS) :material-arrow-right:](key-management/overview.md){.md-button}
