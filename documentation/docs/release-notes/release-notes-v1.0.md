# open_pg_tde 1.0.0 ({{date.GA10}})

The `open_pg_tde` extension brings [Transparent Data Encryption (TDE) :octicons-link-external-16:](../index/about-tde.md) to PostgreSQL and enables you to keep sensitive data safe and secure.

[Get Started](../install.md){.md-button}

## Release Highlights

* **`open_pg_tde` 1.0 is now GA (Generally Available)**

And **stable** for encrypting relational data in PostgreSQL using [Transparent Data Encryption (TDE) :octicons-link-external-16:](../index/about-tde.md). This milestone brings production-level data protection to PostgreSQL workloads.

* **WAL encryption is still in Beta**

The WAL encryption feature is currently still in beta and is not effective unless explicitly enabled. **It is not yet production ready.** Do **not** enable this feature in production environments.

## Upgrade considerations

`open_pg_tde` 1.0 is **not** backward compatible with previous `open_pg_tde` versions, like Release Candidate 2, due to significant changes in code. This means you **cannot** directly upgrade from one version to another. You must do **a clean installation** of `open_pg_tde`.

## Known issues

* The default `mlock` limit on Rocky Linux 8 for ARM64-based architectures equals the memory page size and is 64 Kb. This results in the child process with `open_pg_tde` failing to allocate another memory page because the max memory limit is reached by the parent process.

To prevent this, you can change the `mlock` limit to be at least twice bigger than the memory page size:

* temporarily for the current session using the `ulimit -l <value>` command.
* set a new hard limit in the `/etc/security/limits.conf` file. To do so, you require the superuser privileges.

Adjust the limits with caution since it affects other processes running in your system.

## Changelog

### New Features

- Added SQL function to remove the current principal key  

### Improvements

- Removed relation key cache
- User-facing TDE functions now return void
- Removed undeclared dependencies for `open_pg_tde_grant_database_key_management_to_role()`

### Bugs Fixed

- Fixed PostgreSQL crashes on table access when KMIP key is unavailable after restart  
- Fixed a crash when dropping the `open_pg_tde` extension with CASCADE after changing the key provider file  
- Fixed the vault provider re-addition that failed after server restart with a new token  
- Improve error logs when Server Key Info is requested without being created  
- Fixed runtime failures when invalid Vault tokens are allowed during key provider creation
- Fixed Postmaster error when dropping a table with an unavailable key provider  
- Fixed missing superuser check in role grant function leads to misleading errors  
- Improved CA parameter order and surrounding documentation for clearer interpretation
- Updated and fixed global key configuration parameters in documentation  
- Tested and improved the `open_pg_tde_change_key_provider` CLI utility
- Fixed unused keys in key files which caused issues after OID wraparound  
- Fixed the CLI tool when working with Vault key export/import  
- Fixed when the server fails to find encryption keys after CLI-based provider change  
- Fixed the creation of inconsistent encryption status when altering partitioned tables
- Fixed the indexes on partitioned tables which were not encrypted
- Fixed the error hint when the principal key is missing
