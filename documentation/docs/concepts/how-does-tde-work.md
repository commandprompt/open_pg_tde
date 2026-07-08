# How open_pg_tde works

To encrypt the data, two types of keys are used:

* **Internal encryption keys** to encrypt user data. They are stored internally, near the data that they encrypt.
* The **principal key** to encrypt database keys. It is kept separately from the database keys and is managed externally in the key management store.

!!! note
    For more information on managing and storing principal keys externally, including supported key management systems and the local keyring option, see [Key management overview](../key-management/overview.md).

The encryption process works as follows:

![image](../_images/tde-flow.png)

When a user creates an encrypted table using `open_pg_tde`, a new random internal key is generated for that table. This key is used to encrypt all data the user inserts in that table, using the AES-XTS cipher by default. Eventually the encrypted data gets stored in the underlying storage.

The internal key itself is wrapped (encrypted) by the principal key using AES-256-GCM. The principal key is stored externally in the key management store.

Similarly when the user queries the encrypted table, the principal key is retrieved from the key store to decrypt the internal key. Then the same unique internal key for that table is used to decrypt the data, and unencrypted data gets returned to the user. So, effectively, every TDE table has a unique key, and each table key is encrypted using the principal key.

[Understand the encrypted data scope :material-arrow-right:](tde-encrypts.md){.md-button}
