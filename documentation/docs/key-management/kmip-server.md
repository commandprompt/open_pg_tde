# KMIP configuration

To use a Key Management Interoperability Protocol (KMIP) server with `open_pg_tde`, you must configure it as a global key provider. This setup enables `open_pg_tde` to securely fetch and manage encryption keys from a centralized key management appliance.

!!! note
    You need the root certificate of the KMIP server and a client key/certificate pair with permissions to create and read keys on the server.

For testing purposes, you can use an Eviden KMS server, which enables easy certificate generation and basic KMIP behavior. If you're using a production-grade KMIP server, ensure you obtain valid, trusted certificates from the key management appliance.

## Example usage

```sql
SELECT open_pg_tde_add_global_key_provider_kmip(
    'provider-name',
    'kmip-IP', 
    port,
    '/path_to/client_cert.pem', 
    '/path_to/client_key.pem',
    '/path_to/ca_cert.pem'
);
```

## Parameter descriptions

* `provider-name` is the name of the provider. You can specify any name, it's for you to identify the provider
* `kmip-IP` is the IP address of a domain name of the KMIP server
* `port` is the port to communicate with the KMIP server. Typically used port is 5696
* `kmip_cert_path` is the path to the client certificate.
* `kmip_key_path` is the path to the client private key.
* `kmip_ca_path` is the path to the CA certificate used to verify the KMIP server.

## Certificate verification

`open_pg_tde` verifies the KMIP server's TLS certificate on every connection. The server certificate must be signed by the CA supplied in `kmip_ca_path`, and the certificate identity must match the `kmip-IP` value (an IP address SAN when you connect by IP, or a DNS name SAN when you connect by host name). The connection also requires TLS 1.2 or newer. A connection to a server that presents an untrusted, expired, or mismatched certificate is refused, which prevents a network attacker from impersonating the KMIP server and capturing principal keys. Make sure `kmip_ca_path` points to the CA that issued the server certificate and that the certificate includes the host or address you connect to.

The following example is for testing purposes only.

```sql
SELECT open_pg_tde_add_global_key_provider_kmip(
    'kmip','127.0.0.1', 
    5696, 
    '/tmp/client_cert_jane_doe.pem',
    '/tmp/client_key_jane_doe.pem',
    '/tmp/ca_certificate.pem'
);
```

For more information on related functions, see the link below:

[open_pg_tde Function Reference](../functions.md){.md-button}

## Next steps

[Global Principal Key Configuration :material-arrow-right:](set-principal-key.md){.md-button}
