# open_pg_tde Release Candidate 1 ({{date.RC}})

`open_pg_tde` extension brings in [Transparent Data Encryption (TDE)](../index/about-tde.md) to PostgreSQL and enables you to keep sensitive data safe and secure.

[Get started](../install.md){.md-button}

## Release Highlights

This release provides the following features and improvements:

* **Improved performance with redesigned WAL encryption**.

    The approach to WAL encryption has been redesigned. Now, `open_pg_tde` encrypts entire WAL files starting from the first WAL write after the server was started with the encryption turned on. The information about what is encrypted is stored in the internal key metadata. This change improves WAL encryption flow with native replication and increases performance for large scale databases. 

* **Default encryption key for single-tenancy**.

    The new functionality allows you to set a default principal key for the entire database cluster. This key is used to encrypt all databases and tables that do not have a custom principal key set. This feature simplifies encryption configuration and management in single-tenant environments where each user has their own database instance.

* **Ability to change key provider configuration**

    You no longer need to configure a new key provider and set a new principal key if the provider's configuration changed. Now can change the key provider configuration both for the current database and the entire PostgreSQL cluster using [functions](../functions.md#key-provider-management). This enhancement lifts existing limitations and is a native and common way to operate in PostgreSQL.

* **Key management permissions**

    The new functions allow you to manage permissions for global and database key management separately. This feature provides more granular control over key management operations and allows you to delegate key management tasks to different roles.

* **Additional information about principal keys and providers**

    The new functions allow you to display additional information about principal keys and providers. This feature helps you to understand the current key configuration and troubleshoot issues related to key management.

* **`tde_heap_basic` access method deprecation**

    The `tde_heap_basic` access method has limitations in encryption capabilities and affects performance. Also, it poses a potential security risk when used in production environments due to indexes remaining unencrypted. Considering all the above, we decided to deprecate this access method and remove it in future releases. Use the `tde_heap` access method instead.

## Upgrade considerations

`open_pg_tde` Release Candidate is not backward compatible with `open_pg_tde` Beta2 due to significant changes in code. This means you cannot directly upgrade from one version to another. You must [uninstall](../how-to/uninstall.md) `open_pg_tde` Beta2 first and then [install](../install.md) and configure the new Release Candidate version.

## Known issues

* The default `mlock` limit on Rocky Linux 8 for ARM64-based architectures equals the memory page size and is 64 Kb. This results in the child process with `open_pg_tde` failing to allocate another memory page because the max memory limit is reached by the parent process.

    To prevent this, you can change the `mlock` limit to be at least twice bigger than the memory page size:

    * temporarily for the current session using the `ulimit -l <value>` command.
    * set a new hard limit in the `/etc/security/limits.conf` file. To do so, you require the superuser privileges.

    Adjust the limits with caution since it affects other processes running in your system.

* You can now delete global key providers even when their associated principal key is still in use. This known issue will be fixed in the next release. For now, avoid deleting global key providers. 

## Changelog

### New Features

* Added functions for separate global and database key management permissions.

* Added functionality to delete key providers.

* Added single-tenant support via the default principal key functionality.

* Added functions to display additional information  about principal keys / providers.

* Redesigned WAL encryption.

* Deprecated tde_heap_basic access method.

## Improvements

* Refactored internal/principal key LWLocks to make local databases inherit a global key provider.

* Investigated performance issues at a specific threshold and large databases and updated documentation about handling hint bits.

* Added access method enforcement via the GUC variable.

* Fixed open_pg_tde relocatability.

* Added support for `open_pg_tde_is_encrypted()` function on indexes and sequences.

### Bugs Fixed

* Fixed the issue with `pg_basebackup` failing when configuring replication.

* Fixed the issue with `pg_basebackup` and `pg_checksum` throwing an error on files created by `open_pg_tde` when the checksum is enabled on the database cluster.

* Fixed the issue with `pg_checksums` utility failing during checksum verification on `open_pg_tde` tables. Now `pg_checksum` skips encrypted relations by looking if the relation has a custom storage manager (SMGR) key.

* Fixed the issue with potential unterminated strings by using the `memcpy()` or `strlcpy()` instead of the `strncpy()` function.

* Fixed the issue with toast tables created by the `ALTER TABLE` command not being encrypted.

* Fixed sequence and alter table handling in the event trigger.

* Fixed the bug with  confused relations with the same `RelFileNumber` in different databases.

* Corrected the open_pg_tde_change_key_provider naming in help.

* Fixed the issue with inheriting an encryption status during the ALTER TABLE SET access method command execution by basing a new encryption status only on the new encryption setting.

* Fixed the error message wording when configuring WAL encryption by referencing to a correct function.

* Fixed the `open_pg_tde_delete_key_provider()` function behavior when called multiple times by ignoring already deleted records.

* Fixed the issue with the repeating error message about inability to retrieve a principal key even when a user creates non-encrypted tables by checking the current transaction ID in both the event trigger start function and during a file creation. If the transaction changed during the setup of the current event trigger data, the event trigger is reset.

* Allowed only users with key viewer privileges to execute `open_pg_tde_verify_principal_key()` and `open_pg_tde_verify_global_principal_key()` functions.

* Fixed the issue with the principal key reference corruption when reassigning it to a key provider with the same name by setting the key name in vault/kmip getters.

* Fixed the issue with the server failing to start when WAL encryption is enabled by creating a new principal key for WAL in case only one default key exists in the database.

* PG-1479, Fixed the issue with the lost access to data after the global key provider change and the server restart by fixing the incorrect parameter order in default key rotation.

* Fixed the issue with replicating the keys and key provider configuration by creating the `open_pg_tde` directory on the replica server.
/browse/PG-1476) - Fixed the issue with the server failing to start when WAL encryption is enabled by creating a new principal key for WAL in case only one default key exists in the database.

* PG-1479, Fixed the issue with the lost access to data after the global key provider change and the server restart by fixing the incorrect parameter order in default key rotation.

* Fixed the issue with replicating the keys and key provider configuration by creating the `open_pg_tde` directory on the replica server.
