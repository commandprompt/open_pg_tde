# Limitations of open_pg_tde

## Known incompatibilities on a patched PostgreSQL

Some PostgreSQL extensions may not work on a PostgreSQL build patched with the `open_pg_tde` core patch, because of the storage-manager changes the patch introduces.

These incompatibilities can occur even when the hooks are enabled but `open_pg_tde` is not installed. A build with the hooks compiled out behaves as unmodified PostgreSQL.

### Distributed and extension-based systems

!!! warning "Citus and TimescaleDB are not supported"
    A patched PostgreSQL build with the hooks enabled is not compatible with distributed PostgreSQL extensions such as Citus or time-series extensions such as TimescaleDB.

    This limitation is caused by the storage-manager changes the core patch introduces, and does not depend on enabling `open_pg_tde`.

## Limitations when using open_pg_tde

Limitations of `open_pg_tde` {{release}}:

* PostgreSQL’s internal system catalogs are not encrypted. Table and column names, table structure, and other schema metadata are stored in the clear, as are optimizer statistics in `pg_statistic`, which can include sampled values from encrypted columns. This does not expose encryption keys: the keys are held in the `open_pg_tde` key files wrapped by the principal key, not in the catalog. See the [threat model](threat-model.md) for the full scope.
* Temporary files created when queries exceed `work_mem` are not encrypted. These files may persist during long-running queries or after a server crash which can expose sensitive data in plaintext on disk.

## Recovery without `open_pg_tde` in `shared_preload_libraries`

!!! danger "Risk of corruption when recovering encrypted clusters without open_pg_tde loaded"
    When recovering a PostgreSQL cluster that contains encrypted tables, the `open_pg_tde` extension must be loaded through the `shared_preload_libraries` configuration parameter.

## `pg_rewind` and `open_pg_tde_rewind`

!!! danger "Risk of corruption when using `pg_rewind` or `open_pg_tde_rewind` with TDE"
    When TDE is enabled, using `pg_rewind` or `open_pg_tde_rewind` between diverged PostgreSQL nodes may corrupt encrypted relations.

    This happens because `pg_rewind` and `open_pg_tde_rewind` copy relation files between the data directories of two clusters. In some cases, only parts of files are replaced, leaving data encrypted with the internal encryption keys of the source cluster. This data cannot be decrypted by the destination cluster.
    
    For more information about how `open_pg_tde` manages internal encryption keys, see [How open_pg_tde works](how-does-tde-work.md) and [Encryption of data files](../faq.md#encryption-of-data-files).

    This behavior is inherited from `pg_rewind` and is currently a known issue in `open_pg_tde_rewind`.

    As a result, `open_pg_tde` may be unable to decrypt the copied data, causing queries to fail with errors such as:

    ```bash
    ERROR: 16 invalid pages among blocks 15..30 of relation "base/16384/16438"
    ```

## `ALTER DATABASE ... SET TABLESPACE`

!!! warning "Changing a database tablespace has limited support with `open_pg_tde`"
    The `ALTER DATABASE ... SET TABLESPACE` command bypasses PostgreSQL's storage manager (SMGR), which `open_pg_tde` relies on to enforce encryption.

    - If encrypted objects exist in the database's default tablespace, the operation is refused.
    - If no encrypted objects are present in the default tablespace, the operation is allowed.

    Only objects in the default tablespace are checked. Objects in other tablespaces are not evaluated by `open_pg_tde`.

    To move encrypted tables individually, use `ALTER TABLE ... SET TABLESPACE`, which operates through SMGR and is compatible with `open_pg_tde`.

## Currently unsupported WAL tools

The following tools are currently unsupported with `open_pg_tde` WAL encryption:

* `pg_createsubscriber`
* `pg_receivewal`
* `Barman`
* `pg_verifybackup` by default fails with checksum or WAL key size mismatch errors.
  As a workaround, use `-s` (skip checksum) and `-n` (`--no-parse-wal`) to verify backups.
* The asynchronous archiving feature of pgBackRest.

## Supported WAL tools

The following tools have been tested to work with `open_pg_tde` WAL encryption:

* Patroni, for an example configuration see the following [Patroni configuration file](#example-patroni-configuration)
* `open_pg_tde_basebackup` (with `--wal-method=stream` or `--wal-method=none`), for details on using `open_pg_tde_basebackup` with WAL encryption, see [Backup with WAL encryption enabled](../how-to/backup-wal-enabled.md)
* `open_pg_tde_resetwal`
* `open_pg_tde_rewind`
* `open_pg_tde_upgrade`
* `open_pg_tde_waldump`
* pgBackRest (asynchronous archiving is NOT supported with encrypted WAL)

## Example Patroni configuration

The following is an example configuration.

??? example "Click to expand the example Patroni configuration"
    ```yaml
    # Example Patroni configuration file
    # Source: https://github.com/jobinau/pgscripts/blob/main/patroni/patroni.yml
    scope: tde
    name: pg1
    restapi:
      listen: 0.0.0.0:8008
      connect_address: pg1:8008
    etcd3:
      host: etcd1:2379
    bootstrap:
      dcs:
        ttl: 30
        loop_wait: 10
        retry_timeout: 10
        maximum_lag_on_failover: 1048576
        postgresql:
          use_pg_rewind: true
          use_slots: true
          parameters:
            archive_command: "/lib/postgresql/17/bin/open_pg_tde_archive_decrypt %f %p \"pgbackrest --stanza=tde archive-push %%p\""
            archive_timeout: 600s
            archive_mode: "on"
            logging_collector: "on"
            restore_command: "/lib/postgresql/17/bin/open_pg_tde_restore_encrypt %f %p \"pgbackrest --stanza=tde archive-get %%f \\\"%%p\\\"\""
          pg_hba:
            - local all all peer
            - host all all 0.0.0.0/0 scram-sha-256
            - host all all ::/0 scram-sha-256
            - local replication all peer
            - host replication all 0.0.0.0/0 scram-sha-256
            - host replication all ::/0 scram-sha-256
      initdb:
        - encoding: UTF8
        - data-checksums
        - set: shared_preload_libraries=open_pg_tde
      post_init: /usr/local/bin/setup_cluster.sh
    postgresql:
      listen: 0.0.0.0:5432
      connect_address: pg1:5432
      data_dir: /var/lib/postgresql/patroni-17
      bin_dir: /lib/postgresql/17/bin
      bin_name:
        pg_basebackup: open_pg_tde_basebackup
        pg_rewind: open_pg_tde_rewind
      pgpass: /var/lib/postgresql/patronipass
      authentication:
        replication:
          username: replicator
          password: rep-pass
        superuser:
          username: postgres
          password: secretpassword
      parameters:
        unix_socket_directories: /tmp
        # Use unix_socket_directories: /var/run/postgresql for Debian/Ubuntu distributions
    watchdog:
      mode: off
    tags:
      nofailover: false
      noloadbalance: false
      clonefrom: false
      nosync: false
    ```

!!! warning  
    The above example is provided as a reference, but Patroni versions differ, especially with discovery backends such as `etcd`. Ensure you adjust the configuration to match your environment, version, and security requirements.

## Next steps

Check which PostgreSQL versions and deployment types are compatible with `open_pg_tde` before planning your installation.

[View the versions and supported deployments :material-arrow-right:](supported-versions.md){.md-button}

Begin the installation process when you're ready to set up encryption.

[Start installing `open_pg_tde`](../install.md){.md-button}
