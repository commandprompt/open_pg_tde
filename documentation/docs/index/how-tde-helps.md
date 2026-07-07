# Benefits of open_pg_tde

The benefits of using `open_pg_tde` are outlined below for different users and organizations.

## Benefits for organizations

* **Data safety:** Prevents unauthorized access to stored data, even if backup files or storage devices are stolen or leaked.
* **Enterprise-ready Architecture:** Supports both single and multi-tenancy, giving flexibility for SaaS providers or internal multi-user systems.

## Benefits for DBAs and engineers

* **Granular control:** Encrypt specific tables or databases instead of the entire system, reducing performance overhead.
* **Operational simplicity:** Works transparently without requiring major application changes.
* **Defense in depth:** Adds another layer of protection to existing controls like TLS (encryption in transit), access control, and role-based permissions.

When combined with an external Key Management System (KMS), `open_pg_tde` enables centralized control, auditing, and rotation of encryption keys, which is important for production environments.

!!! admonition "See also"

    For more background on Transparent Data Encryption (TDE), see [About Transparent Data Encryption](about-tde.md).
    
[Learn how open_pg_tde works :material-arrow-right:](how-does-tde-work.md){.md-button}
