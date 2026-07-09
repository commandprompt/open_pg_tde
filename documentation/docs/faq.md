# FAQ

## Why do I need TDE?

Using TDE provides the following benefits:

- Compliance to security and legal regulations like General Data Protection Regulation (GDPR), Payment Card Industry Data Security Standard (PCI DSS), California Consumer Privacy Act (CCPA), Data Protection Act 2018 (DPA 2018) and others
- Encryption of backups. Even when an authorized person gets physical access to a backup, encryption ensures that the data remains unreadable and secure.
- Granular encryption of specific data sets and reducing the performance overhead that encryption brings.
- Additional layer of security to existing security measures

## When and how should I use TDE?

If you are dealing with Personally Identifiable Information (PII), data encryption is crucial. Especially if you are involved in areas with strict regulations like:

* financial services where TDE helps to comply with PCI DSS
* healthcare and insurance - compliance with HIPAA, HITECH, CCPA
* telecommunications, government and education to ensure data confidentiality.

Using TDE helps you avoid the following risks:

* Data breaches
* Identity theft that may lead to financial fraud and other crimes
* Reputation damage leading to loss of customer trust and business
* Legal consequences and financial losses for non-compliance with data protection regulations
* Internal threats by misusing unencrypted sensitive data

Sensitive data stored in your database takes the form of user data in tables, temporary files, and WAL files. TDE encrypts all these files.

`open_pg_tde` does not encrypt system catalogs yet. This means that statistics data and database metadata are not encrypted.

## Will logical replication work with open_pg_tde?

Yes, logical replication works with the encrypted tables.

## Does logical replication keep data encrypted on subscribers?

Logical replication **does not** preserve encryption state. If the publisher uses `open_pg_tde` but the subscriber does not, the replicated data will be stored **in plain text** on the subscriber.

Encryption is not propagated to the data-block level due to how logical replication operates.

!!! note
        This means encrypted publishers **do not guarantee** encrypted logical replicas.

## I use disk-level encryption. Why should I care about TDE?

Encrypting a hard drive encrypts all data, including system, application, and temporary files.

Full disk encryption protects your data from people who have physical access to your device and even if it is lost or stolen. However, it doesn't protect the data after system boot-up: the data is automatically decrypted when the system runs or when an authorized user requests it.

Another point to consider is PCI DSS compliance for Personal Account Numbers (PAN) encryption.

* **PCI DSS 3.4.1** standards might consider disk encryption sufficient for compliance if you meet these requirements:

   * Separate the logical data access from the operating system authentication.

   * Ensure the decryption key is not linked to user accounts.

   Note that PCI DSS 3.4.1 is retiring on March 31, 2025. Therefore, consider switching to PCI DSS 4.0.

* **PCI DSS 4.0** standards consider using only disk and partition-level encryption not enough to ensure PAN protection. It requires an additional layer of security that `open_pg_tde` can provide.

`open_pg_tde` focuses specifically on data files and offers more granular control over encrypted data. The data remains encrypted on disk during runtime and when you move it to another directory, another system or storage. An example of such data is backups. They remain encrypted when moved to the backup storage.

Thus, to protect your sensitive data, consider using TDE to encrypt it at the table level. Then use disk-level encryption to encrypt a specific volume where this data is stored, or the entire disk.

## Is TDE enough to ensure data security?

**No.** Transparent Data Encryption (TDE) adds an extra layer of security for data at rest. You should also consider implementing the following additional security features:

* Access control and authentication
* Strong network security like TLS
* Disk encryption
* Regular monitoring and auditing
* Additional data protection for sensitive fields (e.g., application-layer encryption)

## How does open_pg_tde make my data safe?

`open_pg_tde` uses two keys to encrypt data:

* Internal encryption keys to encrypt the data. These keys are stored internally in an encrypted format, in a single `$PGDATA/open_pg_tde` directory.
* Principal keys to encrypt internal encryption keys. These keys are stored externally, in the Key Management System (KMS).

You can use the following KMSs:

* KMIP-compatible servers. KMIP is a standardized protocol for handling cryptographic workloads and secrets management. For more information see [KMIP configuration](key-management/kmip-server.md).
* [OpenBao](https://openbao.org/), an Apache 2.0 licensed fork of HashiCorp Vault. `open_pg_tde` uses its Key/Value version 2 secrets engine. For more information see [Using OpenBao as a key provider](key-management/openbao.md).

For development and testing, keys can also be stored in a local keyring file instead of an external KMS.

Let's break the encryption down into two parts:

### Encryption of data files

Each data file is encrypted with its own internal key, and the internal key is wrapped by the principal key that is held in the key management store. For the full description of the key hierarchy and how files are marked for encryption, see [How open_pg_tde works](concepts/how-does-tde-work.md).

### WAL encryption

WAL is encrypted globally for the entire database cluster using the same two-key approach. For details, including how to enable it, see [WAL encryption](wal-encryption.md).

## Should I encrypt all my data?

It depends on your business requirements and the sensitivity of your data. Encrypting all data is a good practice but it can have a performance impact.

Consider encrypting only tables that store sensitive data. You can decide what tables to encrypt and with what key. The [Set up multi-tenancy](how-to/multi-tenant-setup.md) section in the documentation focuses on this approach.

We advise encrypting the whole database only if all your data is sensitive, like PII, or if there is no other way to comply with data safety requirements.

## What cipher mechanisms are used by open_pg_tde?

`open_pg_tde` currently uses the following encryption algorithms:

* Database files: `AES-128-XTS` by default. You can select `AES-256-XTS` with the `open_pg_tde.data_cipher` setting. Data files use the tweakable XTS mode designed for storage.
* WAL: `AES-CTR`.
* Internal keys: wrapped by the principal key with `AES-256-GCM`.
* Temporary and query-spill files: `AES-128-XTS` when enabled.

## Is post-quantum encryption supported?

No, it's not yet supported. In our implementation we rely on OpenSSL libraries that don't yet support post-quantum encryption.

## Can I encrypt an existing table?

Yes, you can encrypt an existing table. Run the `ALTER TABLE` command as follows:

```sql
ALTER TABLE table_name SET ACCESS METHOD tde_heap;
```

Since the `SET ACCESS METHOD` command drops hint bits and this may affect the performance, we recommend to run the `SELECT count(*)` command. It checks every tuple for visibility and sets its hint bits. Read more in the [Changing existing table](test.md) section.

## Do I have to restart the database to encrypt the data?

You must restart the database in the following cases to apply the changes:

* after you enabled the `open_pg_tde` extension
* when enabling WAL encryption

After that, no database restart is required. When you create or alter the table using the `tde_heap` access method, the files are marked as those that require encryption. The encryption happens at the storage manager level, before a transaction is written to disk. Read more about [how tde_heap works](concepts/table-access-method.md#how-tde_heap-works-with-open_pg_tde).

## What happens to my data if I lose a principal key?

If you lose encryption keys, especially, the principal key, the data is lost. That's why it's critical to back up your encryption keys securely and use the Key Management service for key management.

## Can I use open_pg_tde in a multi-tenant setup?

Multi-tenancy is the type of architecture where multiple users, or tenants, share the same resource. It can be a database, a schema or an entire cluster.

In `open_pg_tde`, multi-tenancy is supported via a separate principal key per database. This means that a database owner can decide what tables to encrypt within a database. The same database can have both encrypted and non-encrypted tables.

To control user access to the databases, you can use role-based access control (RBAC).

<!--- WAL files are encrypted globally across the entire PostgreSQL cluster using the same encryption keys. Users don't interact with WAL files as these are used by the database management system to ensure data integrity and durability. --->

## Are my backups safe? Can I restore from them?

`open_pg_tde` encrypts data at rest. This means that data is stored on disk in an encrypted form. During a backup, already encrypted data files are copied from disk onto the storage. This ensures the data safety in backups.

Since the encryption happens on the database level, it makes no difference for your tools and applications. They work with the data in the same way.

To restore from an encrypted backup, you must have the same principal encryption key, which was used to encrypt files in your backup.  

## I'm using OpenSSL in FIPS mode and need to use open_pg_tde. Does open_pg_tde comply with FIPS requirements? Can I use my own FIPS-mode OpenSSL library with open_pg_tde?

Yes. `open_pg_tde` works with a FIPS-compliant OpenSSL, whether it comes from your operating system or from your own libraries. For details, see [FIPS compliance](concepts/fips.md).

## How do I rotate internal encryption keys in open_pg_tde?

We don't have a dedicated function to rotate internal keys, because a key is effectively rotated any time a table's data file is completely rewritten. Operations like `VACUUM FULL`, `TRUNCATE`, or some but not all `ALTER TABLE` commands automatically generate a new internal key.

If you're concerned about internal keys being leaked, the best way to address it is by vacuuming the database. This operation rewrites the table's data and, in the process, creates a new internal key.

## What tools are supported with `open_pg_tde` WAL encryption?

For a comprehensive list of supported `open_pg_tde` WAL encryption tools see [Limitations of open_pg_tde](concepts/tde-limitations.md).
