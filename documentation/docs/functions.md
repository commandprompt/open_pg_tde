# Functions

The `open_pg_tde` extension provides functions for managing different aspects of its operation:

!!! note
    If no error is reported when running the commands below, the operation completed successfully.

## Key provider management

A key provider is a system or service responsible for managing encryption keys. For more information on the key providers `open_pg_tde` supports see the [Key management overview](key-management/overview.md).

Key provider management includes the following operations:

* [add a new key provider](#add-a-key-provider)
* [change an existing key provider](#change-an-existing-provider)
* [delete a key provider](#delete-a-provider)
* [list key providers](#list-key-providers)

### Add a key provider

You can add a new key provider using the provided functions, which are implemented for each provider type.

There are two functions to add a key provider: one function adds it for the current database and another one - for the global scope.

* `open_pg_tde_add_database_key_provider_<type>('provider-name', <provider specific parameters>)`
* `open_pg_tde_add_global_key_provider_<type>('provider-name', <provider specific parameters>)`

When you add a new provider, the provider name must be unique in the scope. But a local database provider and a global provider can have the same name.

Global provider visibility depends on the `open_pg_tde.inherit_global_providers` GUC. When it is `on`, global providers are visible to all databases and can be used for database keys. When it is `off`, global providers are used only for WAL encryption.

If you run with `open_pg_tde.inherit_global_providers = on`, reference global providers or the global default principal key in databases, and then change the setting to `off`, the existing references keep working. New references to the global scope cannot be made while the setting is `off`.

### Change an existing provider

You can change an existing key provider using the provided functions, which are implemented for each provider type.

There are two functions to change existing providers: one to change a provider in the current database, and another one to change a provider in the global scope.

* `open_pg_tde_change_database_key_provider_<type>('provider-name', <provider specific parameters>)`
* `open_pg_tde_change_global_key_provider_<type>('provider-name', <provider specific parameters>)`

When you change a provider, the referred name must exist in the database local or a global scope.

The `change` functions require the same parameters as the `add` functions. They overwrite the setting for every parameter except for the name, which can't be changed.

The `change` functions can also change the type of a provider, but they do not migrate any data. They are intended for infrastructure migration, for example when the address of a server changes.

Provider specific parameters differ for each implementation. Refer to the respective subsection for details.

!!! note
    The updated provider must be able to retrieve the same principal keys as the original configuration.
    If the new configuration cannot access existing keys, encrypted data and backups will become unreadable.

#### Add or modify KMIP providers

The KMIP provider uses a remote KMIP server.

Use these functions to add a KMIP provider:

```sql
SELECT open_pg_tde_add_database_key_provider_kmip(
  'provider-name',
  'kmip-host',
  port,
  '/path_to/client_certificate.pem',
  '/path_to/client_key.pem',
  '/path_to/ca_certificate.pem'
);

SELECT open_pg_tde_add_global_key_provider_kmip(
  'provider-name',
  'kmip-host',
  port,
  '/path_to/client_certificate.pem',
  '/path_to/client_key.pem',
  '/path_to/ca_certificate.pem'
);
```

These functions change the KMIP provider:

```sql
SELECT open_pg_tde_change_database_key_provider_kmip(
  'provider-name',
  'kmip-host',
  port,
  '/path_to/client_certificate.pem',
  '/path_to/client_key.pem',
  '/path_to/ca_certificate.pem'
);

SELECT open_pg_tde_change_global_key_provider_kmip(
  'provider-name',
  'kmip-host',
  port,
  '/path_to/client_certificate.pem',
  '/path_to/client_key.pem',
  '/path_to/ca_certificate.pem'
);
```

The parameters are supplied in the following order:

* `provider_name` is the name of the provider.
* `kmip_host` is the IP address or domain name of the KMIP server.
* `kmip_port` is the port used to communicate with the KMIP server.
  Most KMIP servers use port 5696.
* `kmip_cert_path` is the path to the client certificate.
* `kmip_key_path` is the path to the client private key.
* `kmip_ca_path` is the path to the CA certificate used to verify the KMIP server.

!!! note
    The specified access parameters require permission to read and write keys at the server.

#### Add or modify OpenBao providers

The OpenBao provider uses the Key/Value version 2 (KV v2) secrets engine of an OpenBao server.

Use these functions to add an OpenBao provider:

```sql
SELECT open_pg_tde_add_database_key_provider_openbao(
  'provider-name',
  'url',
  'mount',
  'token_path',
  'ca_path'
);

SELECT open_pg_tde_add_global_key_provider_openbao(
  'provider-name',
  'url',
  'mount',
  'token_path',
  'ca_path'
);
```

These functions change the OpenBao provider:

```sql
SELECT open_pg_tde_change_database_key_provider_openbao(
  'provider-name',
  'url',
  'mount',
  'token_path',
  'ca_path'
);

SELECT open_pg_tde_change_global_key_provider_openbao(
  'provider-name',
  'url',
  'mount',
  'token_path',
  'ca_path'
);
```

where:

* `provider-name` is the name of the provider.
* `url` is the URL of the OpenBao server.
* `mount` is the mount point where the keyring stores the keys.
* `token_path` is the path to a file that contains an access token with read and write access to the mount point.
* `ca_path` is the path of the CA file used for TLS verification. This parameter is optional.

A sixth `namespace` parameter is also accepted to select an OpenBao namespace. See [Using OpenBao as a key provider](key-management/openbao.md).

### Add or modify local key file providers

This provider manages database keys using a local key file.

This function is intended for development or quick testing, and stores the keys unencrypted in the specified data file.

!!! important
    Local key file providers are **not recommended** for production environments, they lack the security and manageability of external key management systems.

Add a local key file provider:

```sql
SELECT open_pg_tde_add_database_key_provider_file(
  'provider-name',
  '/path/to/the/key/provider/data.file'
);

SELECT open_pg_tde_add_global_key_provider_file(
  'provider-name',
  '/path/to/the/key/provider/data.file'
);
```

Change a local key file provider:

```sql
SELECT open_pg_tde_change_database_key_provider_file(
  'provider-name',
  '/path/to/the/key/provider/data.file'
);

SELECT open_pg_tde_change_global_key_provider_file(
  'provider-name',
  '/path/to/the/key/provider/data.file'
);
```

where:

* `provider-name` is the name of the provider. You can specify any name, it's for you to identify the provider.
* `/path/to/the/key/provider/data.file` is the path to the key provider file.

### Delete a provider

These functions delete an existing provider in the current database or in the global scope:

* `open_pg_tde_delete_database_key_provider('provider-name')`
* `open_pg_tde_delete_global_key_provider('provider-name')`

You can only delete key providers that are not currently in use. An error is returned if the current principal key is using the provider you are trying to delete.

If the use of global key providers is enabled via the `open_pg_tde.inherit_global_providers` GUC, you can delete a global key provider only if it isn't used anywhere, including any databases. If it is used in any database, an error is returned instead.

### List key providers

These functions list the details of all key providers for the current database or for the global scope, including all configuration values:

* `open_pg_tde_list_all_database_key_providers()`
* `open_pg_tde_list_all_global_key_providers()`

### Change a provider from the command line

`open_pg_tde` provides the `open_pg_tde_change_key_provider` command line tool to change a provider while the PostgreSQL server is stopped. It works like the `change` functions, with the following syntax:

```sh
open_pg_tde_change_key_provider <dbOid> <providerType> ... details ...
```

!!! note
    Because this tool is intended to run while the server is stopped, it bypasses all permission checks. It requires a database OID (`dbOid`) rather than a database name, because it cannot access the system catalogs. It does not validate any parameters.

### Key management permissions

`open_pg_tde` implements access control based on execute rights on the administration functions. These functions grant or revoke the permission to manage database keys for a role:

* `open_pg_tde_grant_database_key_management_to_role('role-name')`
* `open_pg_tde_revoke_database_key_management_from_role('role-name')`

A role with database key management permission can change the key for the database and call the current key functions, including creating keys using global providers when `open_pg_tde.inherit_global_providers` is enabled. This permission does not allow the role to modify the provider configuration.

## Principal key management

Use these functions to create a new principal key at a given keyprover, and to use those keys for a specific scope such as a current database, a global or default scope. You can also use them to start using a different existing key for a specific scope.

Principal keys are stored on key providers by the name specified in this function - for example, when using the KMIP provider, after creating a key named "foo", a key named "foo" will be visible on the KMIP server.

### open_pg_tde_create_key_using_database_key_provider

Creates a principal key using the database-local key provider with the specified name. Use this key later with [`open_pg_tde_set_key_using_database_key_provider()`](#open_pg_tde_set_key_using_database_key_provider).

```sql
SELECT open_pg_tde_create_key_using_database_key_provider(
  'key-name',
  'provider-name'
);
```

### open_pg_tde_create_key_using_global_key_provider

Creates a principal key at a global key provider with the given name. Use this key later with the `open_pg_tde_set_*` series of functions.

```sql
SELECT open_pg_tde_create_key_using_global_key_provider(
  'key-name',
  'provider-name'
);
```

### open_pg_tde_set_key_using_database_key_provider

Sets the principal key for the **current** database, using the specified local key provider. It also rotates internal encryption keys to use the specified principal key.

This function is typically used when working with per-database encryption through a local key provider.

```sql
SELECT open_pg_tde_set_key_using_database_key_provider(
  'key-name',
  'provider-name'
);
```

### open_pg_tde_set_key_using_global_key_provider

Sets or rotates the global principal key using the specified global key provider and the key name. This key is used for global settings like WAL encryption.

```sql
SELECT open_pg_tde_set_key_using_global_key_provider(
  'key-name',
  'provider-name'
);
```

### open_pg_tde_set_server_key_using_global_key_provider

Sets or rotates the server principal key using the specified global key provider. Use this function to set a principal key for WAL encryption.

```sql
SELECT open_pg_tde_set_server_key_using_global_key_provider(
  'key-name',
  'provider-name'
);
```

### open_pg_tde_set_default_key_using_global_key_provider

Sets or rotates the default principal key for the server using the specified global key provider.

The default key is automatically used as a principal key by any database that has the `open_pg_tde` extension enabled but doesn't have an individual key provider and key configuration. This lets the whole server use the same principal key for all databases, which disables multi-tenancy. It requires `open_pg_tde.inherit_global_providers` to be enabled.

```sql
SELECT open_pg_tde_set_default_key_using_global_key_provider(
  'key-name',
  'provider-name'
);
```

Changing the default principal key rotates the encryption of internal keys for all databases that use the current default principal key.

### open_pg_tde_delete_key

Unsets the principal key for the current database. If the current database has any encrypted tables, and there isn’t a default principal key configured, it reports an error instead. If there are encrypted tables, but there’s also a default principal key, internal keys will be encrypted with the default key.

```sql
SELECT open_pg_tde_delete_key();
```

!!! note
    WAL keys cannot be unset, because server keys are managed separately.

### open_pg_tde_delete_default_key

Unsets default principal key. It's possible only if no database uses default principal key.

```sql
SELECT open_pg_tde_delete_default_key();
```

## Encryption status check

### open_pg_tde_is_encrypted

Tells if a relation is encrypted using the `open_pg_tde` extension or not. Returns
`NULL` if a relation lacks storage like views, foreign tables, and partitioned
tables and indexes.

To verify that a table is encrypted, run the following statement:

```sql
SELECT open_pg_tde_is_encrypted(
  'table_name'
);
```

You can also verify if the table in a custom schema is encrypted. Pass the schema name for the function as follows:

```sql
SELECT open_pg_tde_is_encrypted(
  'schema.table_name'
);
```

This can additionally be used to verify that indexes and sequences are encrypted.

### open_pg_tde_key_info

Displays information about the principal key for the current database, if it exists.

```sql
SELECT open_pg_tde_key_info();
```

### open_pg_tde_server_key_info

Displays information about the principal key for the server scope, if exists.

```sql
SELECT open_pg_tde_server_key_info();
```

### open_pg_tde_default_key_info

Displays the information about the default principal key, if it exists.

```sql
SELECT open_pg_tde_default_key_info();
```

### open_pg_tde_verify_key

This function checks that the current database has a properly functional encryption setup, which means:

* A key provider is configured
* The key provider is accessible using the specified configuration
* There is a principal key for the database
* The principal key can be retrieved from the remote key provider
* The principal key returned from the key provider is the same as cached in the server memory

If any of the above checks fail, the function reports an error.

```sql
SELECT open_pg_tde_verify_key();
```

### open_pg_tde_verify_server_key

This function checks that the server scope has a properly functional encryption setup, which means:

* A key provider is configured
* The key provider is accessible using the specified configuration
* There is a principal key for the global scope
* The principal key can be retrieved from the remote key provider
* The principal key returned from the key provider is the same as cached in the server memory

If any of the above checks fail, the function reports an error.

```sql
SELECT open_pg_tde_verify_server_key();
```

### open_pg_tde_verify_default_key

This function checks that the default key is properly configured, which means:

* A key provider is configured
* The key provider is accessible using the specified configuration
* There is a principal key that can be used for any scope
* The principal key can be retrieved from the remote key provider
* The principal key returned from the key provider is the same as cached in the server memory

If any of the above checks fail, the function reports an error.

```sql
SELECT open_pg_tde_verify_default_key();
```
