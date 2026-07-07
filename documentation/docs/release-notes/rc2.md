# open_pg_tde Release Candidate 2 ({{date.RC2}})

`open_pg_tde` extension brings in [Transparent Data Encryption (TDE)](../index/about-tde.md) to PostgreSQL and enables you to keep sensitive data safe and secure.

[Get Started](../install.md){.md-button}

## Release Highlights

This release provides the following features and improvements:

* **Restricted key provider configuration to superusers**

    The database owners can no longer configure key providers directly. Instead, they must refer to the superuser who manages the provider setup. This security improvement clearly separates the responsibilities between users and administrators.

* **WAL encryption supports Vault**.

    `open_pg_tde` now supports using the Vault keyring for secure storage and management of WAL encryption keys.

* **Automatic WAL internal key generation at server startup**.

    On each server start, a new internal key is generated for encrypting subsequent WAL records (assuming WAL encryption is enabled). The existing WAL records and their keys remain unchanged, this ensures continuity and secure key management without affecting historical data.

* **Proper removal of relation-level encryption keys on table drop**

    Previously, encrypted relation keys persisted even after dropping the associated tables, potentially leaving orphaned entries in the map file. This is now corrected, when an encrypted table is dropped, its corresponding key is also removed from the key map.

* **Fixed external tablespace data loss with encrypted partitions**

    An issue was fixed where data could be lost when the encrypted partitioned tables were moved to external tablespaces.  

* **New visibility and verification functions for default principal keys**

    Added additional functions to help you verify and inspect the state of default principal keys more easily.

* **Fixed SQL failures caused by inconsistent key provider switching**

    An issue was resolved where SQL queries could fail after switching key providers while the server was running.
    This occurred because principal keys became inaccessible when spread across multiple keyring backends, triggering the single-provider-at-a-time design constraint.
    `open_pg_tde` now enforces consistency during provider changes to prevent a corrupted key state and query errors.

## Upgrade considerations

`open_pg_tde` Release Candidate 2 is not backward compatible with `open_pg_tde` Beta2 due to significant changes in code. This means you cannot directly upgrade from one version to another. You must [uninstall](../how-to/uninstall.md) `open_pg_tde` Beta2 first and then [install](../install.md) and configure the new Release Candidate version.

## Known issues

* The default `mlock` limit on Rocky Linux 8 for ARM64-based architectures equals the memory page size and is 64 Kb. This results in the child process with `open_pg_tde` failing to allocate another memory page because the max memory limit is reached by the parent process.

To prevent this, you can change the `mlock` limit to be at least twice bigger than the memory page size:

* temporarily for the current session using the `ulimit -l <value>` command.
* set a new hard limit in the `/etc/security/limits.conf` file. To do so, you require the superuser privileges.

Adjust the limits with caution since it affects other processes running in your system.

## Changelog

### New Features

* Added fuzz testing to `pstress` to strengthen validation and resilience.
* Ensured fsync is called on `open_pg_tde.map`, `open_pg_tde.dat`, and FS key provider files.
* Implemented full WAL encryption using Vault keyring.
* Tested WAL recovery and both streaming and logical replication compatibility.
* Added a contributor guide to help new developers engage with open_pg_tde.
* Evaluated use of `pg_basebackup` for automated backup validation with open_pg_tde.
* Automated test cases to validate data integrity after PostgreSQL restart.
* Verified encryption behavior of temporary tables.
* Developed automation for bare-metal performance benchmarking.
* Added test cases for verifying compatibility with different PostgreSQL versions.
* Implemented support for removing relation-level encryption keys when dropping tables.
* Introduced random base numbers in encryption IVs for enhanced security.
* Added visibility and verification functions for default principal keys.
* Enabled automatic rotation of WAL internal keys on server start.
* Implemented random IV initialization for WAL keys.
* Added parameter support for client certificates in KMIP provider configuration.

## Improvements

* Documented how to encrypt and decrypt existing tables using open_pg_tde.
* Fixed CI pipeline tests on the smgr branch.
* Resolved issues with `CREATE ... USING open_pg_tde` on the smgr branch.
* Tested and fixed KMIP implementation for Thales support.
* Handled ALTER TYPE operations in the TDE event trigger.
* Fixed encryption state inconsistencies when altering inherited tables.
* Restricted database owners from creating key providers to improve security.
* Verified and fixed KMIP compatibility with Fortanix HSM.

### Bugs Fixed

* Fixed segmentation fault during replication with WAL encryption enabled.
* Resolved invalid WAL magic number errors after toggling encryption.
* Fixed SQL query failures caused by inconsistent key provider switching.
* Fixed WAL read failures on replicas after key rotation.
* Corrected `open_pg_tde_is_encrypted()` behavior for partitioned tables.
* Fixed data loss when encrypted partitioned tables were moved to external tablespaces.
* Blocked deletion of global key providers still associated with principal keys.
* Ensured correct encryption inheritance in partitioned `tde_heap` tables.
* Used different keys and IVs for PostgreSQL forks to prevent conflicts.
* Fixed inability to read WAL after toggling WAL encryption.
* Resolved errors rewriting owned sequences when open_pg_tde isn't in the default schema.
* Prevented server crash on calling `open_pg_tde_principal_key_info()`.
* Fixed crash on NULL input in user-facing functions.
* Handled principal key header verification errors gracefully.
* Ensured sequences are assigned correct encryption status.
* Resolved WAL decryption failure after key rotation.
* Fixed validation error when multiple server keys exist.
* Resolved error from `open_pg_tde_grant_grant_management_to_role()` execution.
* Fixed incorrect behavior in role grant function.
* Improved handling of short reads and errors in WAL storage code.
* Fixed WAL decryption failure due to corrupted or mismatched principal keys.
* Prevented crash during WAL replay when lock was not held.
* Ensured encrypted WAL is readable by streaming replica.
* Resolved crash from malformed JSON in user-facing functions.
