# KMIP-compatible servers

`open_pg_tde` connects to any key management appliance that implements the Key Management Interoperability Protocol (KMIP). The following vendors have been validated with `open_pg_tde`. Each connects over KMIP, so you configure it the same way regardless of vendor.

| Vendor | Product | Protocol | Vendor documentation |
|--------|---------|----------|----------------------|
| Fortanix | Data Security Manager (DSM) | KMIP | [Fortanix documentation](https://support.fortanix.com/docs) |
| Thales | CipherTrust Manager | KMIP | [Thales documentation](https://thalesdocs.com/ctp/cm/2.19/reference/kmip-ref/index.html?) |
| Akeyless | Akeyless Platform | KMIP | [Akeyless documentation](https://docs.akeyless.io/docs/akeyless-overview) |

To configure any of these servers as a global key provider, see the [KMIP configuration](kmip-server.md) page.

## Next steps

[Global Principal Key Configuration :material-arrow-right:](set-principal-key.md){.md-button}
