# Key management overview

In production environments, storing encryption keys locally on the PostgreSQL server can introduce security risks. To enhance security, `open_pg_tde` supports integration with external Key Management Systems (KMS) through a Global Key Provider interface.

This section describes how you can configure `open_pg_tde` to use the local and external key providers.

To use an external KMS with `open_pg_tde`:

1. Configure a Key Provider
2. Set the [Global Principal Key](set-principal-key.md)

!!! note
    While key files may be acceptable for **local** or **testing environments**, KMS integration is the recommended approach for production deployments.

!!! warning
    Do not rotate encryption keys while a backup is running. This may result in an inconsistent backup and restore failure. This applies to all backup tools.

    Schedule key rotations outside backup windows. After rotating keys, take a new full backup.

    For more details, see [Limitations of open_pg_tde](../concepts/tde-limitations.md#limitations-when-using-open_pg_tde).

`open_pg_tde` has been tested with the following key providers:

| KMS Provider       | Description                                           | Documentation |
|--------------------|-------------------------------------------------------|---------------|
| **KMIP**           | Standard Key Management Interoperability Protocol.    | [Configure KMIP →](kmip-server.md) |
| **Fortanix**       | Fortanix DSM key management.                          | [KMIP-compatible servers →](kmip-servers.md) |
| **Thales**         | Thales CipherTrust Manager and DSM.                   | [KMIP-compatible servers →](kmip-servers.md) |
| **Akeyless**        | A cloud-based secrets management platform for securely storing and accessing credentials and encryption keys.            | [KMIP-compatible servers →](kmip-servers.md) |
| **OpenBao**        | Apache 2.0 licensed Vault fork using the KV v2 secrets engine.    | [Configure OpenBao →](openbao.md) |
| **Keyring file** *(not recommended)* | Local key file for dev/test only.                  | [Configure keyring file →](keyring.md) |
