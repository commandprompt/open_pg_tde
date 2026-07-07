# Using OpenBao as a key provider

You can configure `pg_tde` to use OpenBao as a global key provider for managing encryption keys. OpenBao is an Apache 2.0 licensed fork of HashiCorp Vault and uses the Key/Value version 2 (KV v2) secrets engine.

!!! note
    This guide assumes that your OpenBao server is already set up and accessible. OpenBao configuration is outside the scope of this document. See the [OpenBao documentation](https://openbao.org/docs/) for more information.

## Example usage

To register an OpenBao server as a global key provider:

```sql
SELECT pg_tde_add_global_key_provider_openbao(
    'provider-name',
    'url',
    'mount',
    'secret_token_path',
    'ca_path',
    'namespace'
);
```

## Parameter descriptions

* `provider-name` is the name that identifies this key provider.
* `url` is the URL of the OpenBao server.
* `mount` is the mount point where the keyring stores the keys.
* `secret_token_path` is the path to a file that contains an access token with read and write access to the mount point.
* `ca_path` is the path of the CA file used for TLS verification. This parameter is optional.
* `namespace` is the namespace on the OpenBao server. This parameter is optional. See [namespace support in OpenBao](https://openbao.org/blog/namespaces-announcement/). You can set a namespace without a `ca_path` by passing `NULL` as the `ca_path` value.

The following example is for testing only. Use secure tokens and TLS validation in production:

```sql
SELECT pg_tde_add_global_key_provider_openbao(
    'my-openbao-provider',
    'https://openbao.example.com:8200',
    'secret/data',
    '/path/to/token_file',
    '/path/to/ca_cert.pem'
);
```

For the related functions, see the [pg_tde function reference](../functions.md){.md-button}.

## Next steps

[Global Principal Key Configuration :material-arrow-right:](set-principal-key.md){.md-button}
