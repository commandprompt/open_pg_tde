# Design: AES-256-XTS for data files

- Status: Implemented (PR #3)
- Date: 2026-07-07
- Scope: add AES-256-XTS as a data-file cipher, alongside the existing
  AES-128-XTS, AES-128-CBC, and AES-256-CBC options.

## Motivation

XTS is the mode designed for storage (disk block) encryption: the block's
logical position is the tweak, no chaining crosses block boundaries, and it is
resistant to the nonce-misuse hazards that plague counter modes on rewritable
storage. `open_pg_tde` already defaults to AES-128-XTS for data files.

The single driver for AES-256-XTS is **compliance**. Some regimes (for example
FIPS-aligned government and financial deployments) mandate AES-256 keys. Those
deployments can already select `aes_256`, but that is AES-256-**CBC**, which is
a weaker mode for storage than XTS. AES-256-XTS gives them AES-256 key strength
**and** the XTS storage mode. For deployments without an AES-256 mandate,
AES-128-XTS remains the recommended default; AES-256-XTS is not a general
upgrade.

## Why the key-map format bump, and not a KDF shortcut

AES-256-XTS needs a 64-byte key: XTS uses two independent AES keys, so
AES-256-XTS is two 256-bit keys. The internal key today is capped at 32 bytes
(`INTERNAL_KEY_MAX_LEN`, the `InternalKey.key` buffer, and the on-disk
`TDEMapEntry.encrypted_key_data`).

There are two ways to get a 64-byte key:

1. **Store a 64-byte key** (this design): enlarge the internal key and the
   on-disk key map, generating two independent 256-bit subkeys.
2. **Derive 64 bytes from the stored 32-byte key** with a KDF at use time: no
   format change, but the two XTS subkeys are then derived from a single
   256-bit seed rather than generated independently.

We choose (1) deliberately. The reason to implement AES-256-XTS at all is
compliance, and NIST SP 800-38E (XTS-AES) requires the two keys to be
independent. Strict FIPS validation of XTS-AES has historically required the
keys to be generated from independent sources, not derived from a common
master. The KDF shortcut would be simpler, but it would undermine the exact
requirement that motivates the feature. So we take the format bump and generate
two independent 256-bit subkeys.

## Why not authenticated encryption (AES-GCM) instead

A reasonable question is why add another confidentiality-only cipher rather than
move to authenticated encryption, which would also detect tampering. The short
answer is that the two are unrelated in cost and scope, and XTS is the correct
mode for this layer:

- **XTS is the right tool for rewritable disk blocks.** It is length-preserving
  and nonce-misuse resistant. GCM is a counter mode: reusing a nonce (which
  happens naturally when a disk block is rewritten in place) is catastrophic for
  both confidentiality and integrity, so GCM at the page layer needs per-write
  nonce management that XTS does not.
- **GCM needs a page-format change; AES-256-XTS does not.** GCM produces a
  16-byte authentication tag per page. Pages are encrypted length-preserving
  today with nowhere to store a tag, so GCM requires new per-page storage (a tag
  fork or side file) and crash-consistent handling of it. That is a separate,
  much larger project, scoped in `aes-gcm-authenticated-pages.md`.
- **Integrity is a different security property with a different threat model.**
  XTS provides confidentiality. Whether tamper detection is required depends on
  the deployment; it is valuable hardening but is not what an AES-256 compliance
  mandate asks for.

AES-256-XTS closes a concrete compliance gap with a contained change.
Authenticated pages remain on the roadmap as a separate initiative.

## Detailed design

The on-disk key map is already versioned. `OPEN_PG_TDE_SMGR_FILE_MAGIC`
encodes a version in its high nibble (`FILEMAGIC_VERSION`), currently 4, and
there is a working migration from version 3 (`TDEMapEntryV3` and
`map_from_disk_entry_v3`). This design follows that precedent.

1. **Enlarge the internal key.** `INTERNAL_KEY_MAX_LEN` 32 to 64. This widens
   `InternalKey.key` (in memory) and `TDEMapEntry.encrypted_key_data` (on disk).

2. **Bump the file version.** `OPEN_PG_TDE_SMGR_FILE_MAGIC` from version 4 to 5.
   Add a `TDEMapEntryV4` struct capturing the current (32-byte-key) layout and a
   `map_from_disk_entry_v4` reader, exactly as `TDEMapEntryV3` did.

3. **Migrate on startup.** Extend `open_pg_tde_migrate_smgr_keys_file` so a
   version-4 file is re-read with the V4 reader and rewritten in the version-5
   layout. Existing AES-128 and AES-256 and AES-128-XTS entries keep their
   ciphers and keys; only the entry stride grows. No table data is rewritten.

4. **Relax the wrap assumption.** The internal-key wrap path asserts
   `key_len == 16 || key_len == 32`; allow 64. GCM-wrapping a 64-byte key under
   a 32-byte principal key is fine and keeps a 16-byte tag. Review the
   `principal_key->keyLength != rel_key->key_len` warning so a 64-byte internal
   key under a 32-byte principal key is not spuriously flagged.

5. **Register the cipher.** Add `CIPHER_AES_256_XTS` to the cipher enum and a
   registry entry with key length 64 that wraps `EVP_aes_256_xts()`. Add a
   second XTS `EVP_CIPHER_CTX` (`ctx_xts_256`) and select it by key length in
   the XTS crypt path. XTS is block-only (no keystream), so, like AES-128-XTS,
   it is skipped by the WAL/stream key-length lookup.

6. **Expose the GUC value.** Add `aes_256_xts` to `open_pg_tde.data_cipher`.

The cipher id is recorded per relation, so existing tables continue to decrypt
with the cipher they were created with, and different tables in one cluster may
use different ciphers. WAL is unaffected (it uses AES-CTR).

## The WAL key format is intentionally not bumped

`INTERNAL_KEY_MAX_LEN` is used in three places: the in-memory `InternalKey`, the
data key map entry (`TDEMapEntry.encrypted_key_data`), and the **WAL** key file
entry (`WalKeyFileEntry.encrypted_key_data`). Growing it to 64 everywhere would
also change the WAL key file format and force a WAL key file migration. This
design deliberately does **not** do that: it grows the in-memory key and the
data key map to 64, and pins the WAL key entry at its previous 32-byte size, so
the WAL key file format is byte-for-byte unchanged.

Reasoning:

- **WAL genuinely never needs a 64-byte key.** WAL is encrypted with AES-CTR, a
  stream cipher suited to append-only data. XTS is for rewritable disk blocks;
  AES-256-XTS is meaningless for WAL. WAL keys are AES-128 (16 bytes) or AES-256
  (32 bytes), never larger.
- **Smaller blast radius, lower-risk upgrade.** Existing clusters' WAL key files
  stay untouched and no WAL migration runs. Only the small data key map migrates
  (version 4 to 5) on first startup. The most crash-sensitive subsystem is not
  disturbed. Bumping both formats would waste 32 bytes per WAL entry, require a
  WAL migration, and buy nothing.
- **The two key files already version independently.** The data key map and the
  WAL key file have separate magics (`OPEN_PG_TDE_SMGR_FILE_MAGIC` and
  `OPEN_PG_TDE_WAL_KEY_FILE_MAGIC`). A change that only affects data-file ciphers
  should not force a WAL format bump; decoupling their evolution is correct.

Implication and safeguard: pinning the WAL entry at 32 bytes while the in-memory
`InternalKey.key` is 64 creates an invariant, that a WAL key is always at most
32 bytes. Nothing can violate it today, because WAL ranges only ever use CTR
ciphers. To keep a future change from silently overflowing the 32-byte WAL
buffer, the WAL key write path keeps its `key_len == 16 || key_len == 32`
assertion (it is not relaxed like the data path) and adds an always-on runtime
check that fails loudly if a key longer than the WAL entry ever reaches it.
`INTERNAL_KEY_MAX_LEN` therefore documents the in-memory and data-key maximum,
while the WAL entry size is fixed independently.

## Migration and compatibility

- Existing clusters: the key map files migrate from version 4 to 5 on the first
  startup after upgrade. This rewrites the small key map files only; user data
  is untouched.
- Reading old files: the version-4 reader is retained for the migration, as the
  version-3 reader was.
- Downgrade is not supported once files are at version 5, consistent with prior
  format bumps.

## Testing

- A `tde_heap` table created with `open_pg_tde.data_cipher = 'aes_256_xts'`
  encrypts and decrypts correctly, is ciphertext on disk, and survives a
  restart.
- Mixed ciphers in one database (AES-128-XTS and AES-256-XTS tables) both read
  back correctly.
- Migration: a key map file written by the current (version-4) format is
  migrated to version 5 on startup and its tables remain readable. This mirrors
  the existing `keys_update` migration test.

## Non-goals

- Authenticated encryption or tamper detection (see
  `aes-gcm-authenticated-pages.md`).
- Re-encrypting existing tables to AES-256-XTS automatically. As with any cipher
  choice, existing tables keep their cipher; converting one is a table rewrite.
