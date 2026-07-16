# open_pg_tde 2.4.0

`open_pg_tde` 2.4.0 is a security hardening release. It resolves the findings of an internal security review of the extension and the core patch, strengthening how key material is protected on disk and in memory and how `open_pg_tde` communicates with external key management systems.

[Get Started](../install.md){.md-button}

## Release highlights

### Authenticated key metadata

The internal keys that encrypt relation data and WAL are stored on disk wrapped by the principal key with AES-GCM. The `key_base_iv`, the base IV that seeds each block's IV or tweak, is now part of the AEAD additional authenticated data, so altering it on disk is detected when the key is read. Previously it was stored outside the authenticated data and could be changed undetected, which would shift every block IV of the affected relation or the WAL stream.

This changes the on-disk key file formats, which are migrated automatically at server start (see [Upgrading](#upgrading)):

- the relation key map file (`<dbOid>_keys`), from version 5 to version 6;
- the WAL key file (`wal_keys`), from version 2 to version 3.

### XTS-only data ciphers

Data files are always encrypted with a length-preserving XTS cipher. The non-tweakable AES-CBC options for [`open_pg_tde.data_cipher`](../variables.md#open_pg_tdedata_cipher) have been removed: their deterministic per-block IV leaks the length of an unchanged leading prefix across successive versions of a page, and CBC ciphertext is malleable. The supported values are now `aes_xts` (AES-128-XTS, the default), `aes_256_xts`, and `inherit`. Tables already created with a CBC cipher stay readable with their recorded cipher. See [Upgrading](#upgrading).

### Hardened temporary file encryption

Each temporary file now mixes a value unique to that file into the cipher tweak, so two temporary files that hold the same data no longer produce the same ciphertext. This removes an IV reuse across separate query-spill files, including the files that parallel workers share.

### KMIP server certificate verification

The KMIP key provider now verifies the KMIP server's TLS certificate: peer verification, a host name or IP address match, and TLS 1.2 or later. A connection to a server that presents an untrusted certificate is refused.

### Key management hardening

- The OpenBao key provider no longer follows HTTP redirects, so a redirect cannot divert a key request to another host.
- Decrypted and encrypted WAL files written by the command-line tools are created with owner-only (0600) permissions.
- Input and bounds handling in the command-line key provider tool was hardened.

### Key material is zeroized

Plaintext key material, including relation and principal key buffers and the shared-memory relation key when it is evicted, is wiped from memory after use. This narrows the window in which key material could be recovered from a core dump or freed memory.

### Faster page encryption

The AES key schedule is reused across the pages of a relation instead of being rebuilt for each 8 KB page, reducing per-page encryption overhead.

### Threat model

The [threat model](../concepts/threat-model.md) now documents that an unlogged table's init and main forks share the data-file tweak. PostgreSQL resets an unlogged relation after a crash by copying the init fork over the main fork, so the two forks must share the tweak for the copy to decrypt. An observer with the data files can therefore tell which main-fork blocks are byte-identical to the init-fork template. This affects unlogged tables only.

## Upgrading

2.4.0 changes on-disk key file formats. The upgrade is one way: once a cluster has started under 2.4.0 its key files are rewritten and are not read by 2.3.0. Take a file-level backup before upgrading.

- **Key file migration is automatic.** On first start under 2.4.0, the relation key map files and the WAL key file are migrated to the new authenticated formats. No action is required.
- **AES-CBC data cipher removed.** If [`open_pg_tde.data_cipher`](../variables.md#open_pg_tdedata_cipher) is set explicitly to a removed CBC value (`aes_128` or `aes_256`), change it to `aes_xts` or `aes_256_xts` before starting 2.4.0, or the server rejects the value. The default is unaffected. Tables already encrypted with a CBC cipher continue to be read with their recorded cipher.

## Supported PostgreSQL versions

PostgreSQL 16, 17, and 18. PostgreSQL 16 is the minimum supported version.
