# GUC Variables

The `open_pg_tde` extension provides GUC variables to configure the behaviour of the extension:

## open_pg_tde.wal_encrypt

**Type** - boolean <br>
**Default** - off

A `boolean` variable that controls if WAL writes are encrypted or not.

Changing this variable requires a server restart, and can only be set at the server level.

WAL encryption is controlled globally. If enabled, all WAL writes are encrypted in the entire PostgreSQL cluster.

This variable only controls new writes to the WAL, it doesn't affect existing WAL records.

`open_pg_tde` is always capable of reading existing encrypted WAL records, as long as the keys used for the encryption are still available.

Enabling WAL encryption requires a configured global principal key. Refer to the [WAL encryption configuration](wal-encryption.md) topic for more information.

## open_pg_tde.enforce_encryption

**Type** - boolean <br>
**Default** - off

A `boolean` variable that controls if the creation of new, not encrypted tables is allowed.

If enabled, `CREATE TABLE` statements will fail unless they use the `tde_heap` access method.

Similarly, `ALTER TABLE <x> SET ACCESS METHOD` is only allowed, if the access method is `tde_heap`.

Other DDL operations are still allowed. For example other `ALTER` commands are allowed on unencrypted tables, as long as the access method isn't changed.

You can set this variable at the following levels:

* global - for the entire PostgreSQL cluster
* database - for specific databases
* user - for specific users
* session - for the current session

Setting or changing the value requires superuser permissions. For examples, see the [Encryption Enforcement](how-to/enforcement.md) topic.

## open_pg_tde.inherit_global_providers

**Type** - boolean <br>
**Default** - on

A `boolean` variable that controls if databases can use global key providers for storing principal keys.

If disabled, functions that change the key providers can only work with database local key providers.

In this case, the default principal key, if set, is also disabled.

You can set this variable at the following levels:

* global - for the entire PostgreSQL cluster
* database - for specific databases
* user - for specific users
* session - for the current session

!!! note
    Setting this variable doesn't affect existing uses of global keys. It only prevents the creation of new principal keys using global providers.

## open_pg_tde.cipher

**Type** - string <br>
**Default** - aes_128

A `string` variable that selects the cipher (encryption algorithm). Currently, the supported values are `aes_128` and `aes_256`, corresponding to AES 128-bit and 256-bit key lengths, respectively.

The setting applies only to objects created after the value is set, including principal keys, internal keys, and data encrypted by those keys. Existing objects are not re-encrypted.

## open_pg_tde.data_cipher

**Type** - enum <br>
**Default** - aes_xts

Selects the cipher used to encrypt the data files of **new** encrypted tables (`tde_heap`). Supported values:

* `aes_xts` - AES-128-XTS. This is the default and the recommended mode for data files. XTS is a tweakable block cipher intended for storage encryption.
* `aes_256` - AES-256-CBC.
* `aes_128` - AES-128-CBC.
* `inherit` - follow the [`open_pg_tde.cipher`](#open_pg_tdecipher) setting.

The chosen cipher is recorded per table when its internal key is created, and reads always use the recorded cipher regardless of the current value of this variable. Changing `open_pg_tde.data_cipher` therefore only affects tables created afterwards. Existing tables continue to decrypt with the cipher they were created with, and different tables in the same cluster may use different ciphers.

This variable selects the cipher independently of the key length, which is what allows additional algorithms to be added to the [cipher provider registry](architecture/encryption-architecture.md#pluggable-cipher-providers) without changing the on-disk format. WAL is always encrypted with AES-CTR and is not affected by this setting.