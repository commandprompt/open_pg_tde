# Design: tablespace-level encryption

- Status: Proposed
- Date: 2026-07-07
- Scope: add an option to encrypt an entire tablespace, so that relations created
  in it are encrypted automatically, instead of opting in per table with the
  `tde_heap` access method.

This is a design and implementation plan. No code is proposed for merge here.

## Summary

Today a user encrypts data by creating a table with the `tde_heap` access
method (or by turning on `open_pg_tde.enforce_encryption`, which requires
`tde_heap`). This proposal adds a second, coarser policy: mark a tablespace as
encrypted, after which every user relation created in that tablespace is
encrypted automatically, regardless of the access method requested.

The encryption engine already keys its behavior on the relation file, not on the
access method, and it already tracks the tablespace OID as a first-class part of
each key. The feature is therefore mostly a policy and metadata layer on top of
the existing engine, plus careful handling of moving relations between
tablespaces.

## Background: how encryption is decided today

Three facts from the current code determine the shape of this feature.

1. `tde_heap` is the standard heap access method. `open_pg_tde.c` returns
   `GetHeapamTableAmRoutine()` for the `tde_heap` handler. The access method
   itself adds no behavior; it is a marker.

2. The storage manager encrypts a relation based on whether that relation has an
   internal key, not on its access method. In
   `src/smgr/open_pg_tde_smgr.c`, `tde_smgr_is_encrypted()` resolves to
   `open_pg_tde_has_smgr_key(rlocator)`, and read/write paths encrypt only when a
   key is present.

3. The decision to create a key for a new relation flows through a per-statement
   mode. The DDL event-capture layer (`src/open_pg_tde_event_capture.c`) sets
   `event.encryptMode = TDE_ENCRYPT_MODE_ENCRYPT` when it sees `tde_heap`, and at
   relation-create time the storage manager consults a single function:

   ```c
   /* src/smgr/open_pg_tde_smgr.c */
   tde_smgr_should_encrypt(rlocator, old_locator)
   {
       if (IsCatalogRelationOid(rlocator->locator.relNumber))
           return false;
       switch (currentTdeEncryptModeValidated())
       {
           case TDE_ENCRYPT_MODE_ENCRYPT: return true;   /* create key, encrypt */
           case TDE_ENCRYPT_MODE_PLAIN:   return false;
           case TDE_ENCRYPT_MODE_RETAIN:  /* inherit the old relfilenode's state */
       }
   }
   ```

   When this returns true, `tde_smgr_create_key()` creates the internal key and
   the relation is encrypted from then on. Everything downstream (page
   encrypt/decrypt, WAL, and key inheritance across TRUNCATE, VACUUM FULL,
   CLUSTER, CREATE DATABASE, and SET TABLESPACE) already works for any relation
   that has a key.

The tablespace is already a first-class dimension of the key map: each map entry
carries `spcOid`, and it is part of the key's additional authenticated data
(`src/access/open_pg_tde_tdemap.c`). The helper
`open_pg_tde_count_encryption_keys(dbOid, spcOid)` already reports encrypted
objects per tablespace, and the event-capture code already resolves the target
tablespace of a statement, including the database default
(`src/open_pg_tde_event_capture.c`).

## Key idea

Tablespace-level encryption means setting the encrypt mode to
`TDE_ENCRYPT_MODE_ENCRYPT` based on the target tablespace of a statement, instead
of (or in addition to) the presence of the `tde_heap` access method. The rest of
the engine is unchanged.

## Detailed design

### 1. Tablespace encryption policy (metadata + API)

Store which tablespaces are encrypted and which key material they use. Key
providers today are per database or global; a tablespace policy references one.

Proposed extension metadata: a mapping from tablespace OID to a policy record
`{ encrypted, key provider reference, principal key name }`. This can be a new
extension catalog table or an addition to the existing key metadata; it must be
consulted cheaply during DDL.

Proposed SQL API:

- `open_pg_tde_encrypt_tablespace(tablespace_name, provider_name, key_name)`
  marks a tablespace encrypted and records the key material to use for relations
  created in it.
- `open_pg_tde_decrypt_tablespace(tablespace_name)` clears the policy (affects
  only relations created afterward; see limitations).
- `open_pg_tde_is_tablespace_encrypted(tablespace_name) returns boolean`.
- `open_pg_tde_list_encrypted_tablespaces()`.

### 2. Policy hook in DDL event capture (core change)

In the relation-creating DDL paths already handled by event capture
(`CREATE TABLE`, `CREATE TABLE AS` / `SELECT INTO`, `CREATE MATERIALIZED VIEW`,
`CREATE INDEX`), resolve the effective tablespace using the logic already present
(explicit `TABLESPACE` clause, else the parent relation's tablespace, else the
database default tablespace) and, if that tablespace has an encryption policy,
set `event.encryptMode = TDE_ENCRYPT_MODE_ENCRYPT` regardless of the access
method. This reuses the existing mode machinery end to end.

### 3. Coverage of all relation kinds

Per-table encryption today covers a heap plus its indexes and TOAST via key
inheritance. A tablespace policy should encrypt every user relation created in
the tablespace: heap tables under any access method, indexes, TOAST, sequences,
and materialized views. The storage manager and key lifecycle already handle any
relation with a key; the work is ensuring each relation-creating DDL path
consults the tablespace policy, in particular `CREATE INDEX ... TABLESPACE` and
indexes that inherit their table's tablespace.

### 4. SET TABLESPACE move semantics (the delicate part)

`ALTER TABLE ... SET TABLESPACE` creates a new relfilelocator in the destination
tablespace, which fires the storage-manager create path. The destination
tablespace's policy must decide the result:

- Moving a plaintext relation into an encrypted tablespace should encrypt it.
- Moving an encrypted relation out of an encrypted tablespace (into a plaintext
  one) should decrypt it.

Today the `RETAIN` mode inherits the old relfilenode's encryption state. For a
tablespace move the destination policy must take precedence instead. Because the
key's additional authenticated data binds `spcOid`, a move already re-writes the
key entry with the new tablespace OID through the inheritance path; when the
destination tablespace uses a different principal key or provider, the internal
key must be re-wrapped under the destination's principal key rather than only
re-tagged. This handoff is the main new correctness surface and needs tests in
both directions.

### 5. Pre-existing objects

Marking a populated tablespace encrypted does not change the relfilenodes of
relations already in it, so those relations are not retroactively encrypted. This
matches the per-table model, where an existing table is only encrypted by a
rewrite. At tablespace granularity this is more surprising, so it must be
documented, and we should offer a helper that rewrites existing relations in a
tablespace (equivalent to `VACUUM FULL` or `ALTER TABLE ... SET ACCESS METHOD`)
to encrypt what is already there.

### 6. Interaction with existing controls

- `open_pg_tde.enforce_encryption`: composes cleanly. Both the GUC and a
  tablespace policy simply request `ENCRYPT`.
- Catalogs and shared storage: catalog relations are already excluded
  (`IsCatalogRelationOid`), and shared catalogs live in `pg_global`. The policy
  must stay scoped to user relations. User tablespaces do not hold shared
  catalogs, so this is a guard and documentation concern.

## Implementation plan

1. Metadata and SQL API (self-contained): policy storage plus
   `open_pg_tde_encrypt_tablespace` / `open_pg_tde_decrypt_tablespace` /
   `open_pg_tde_is_tablespace_encrypted` / `open_pg_tde_list_encrypted_tablespaces`.
2. Core policy hook: set `ENCRYPT` mode in the relation-creating DDL paths when
   the effective tablespace is encrypted. Cover heap, index, TOAST, sequence, and
   materialized view creation.
3. SET TABLESPACE move semantics: destination-policy precedence, encrypt on move
   in, decrypt on move out, and principal-key re-wrap on provider handoff.
4. Rewrite helper for pre-existing relations in a tablespace (optional but
   recommended for a complete feature).
5. Tests and documentation: extend the existing `tablespace`, `relocate`, and
   `key_rotate_tablespace` tests; document the policy, its interaction with
   per-table encryption and `enforce_encryption`, and the pre-existing-objects
   limitation.

## Risks and open questions

- SET TABLESPACE re-wrap correctness when source and destination tablespaces use
  different providers or principal keys. This is the highest-risk area.
- WAL and recovery: a relation created in an encrypted tablespace must have its
  key-creation WAL-logged the same way `tde_heap` relations do; verify the redo
  path (`tde_smgr_create_key_redo`) is reached for the tablespace-triggered case.
- Backup and restore, `pg_rewind`, and `pg_basebackup`: encrypted relations in a
  tablespace must be handled by the existing frontend tools with no new special
  casing, since they already operate on keys per relation. Verify.
- Granularity of the key: whether all relations in an encrypted tablespace share
  a principal key (via the tablespace policy) while keeping distinct internal
  keys per relation, which matches the current per-relation internal-key model.
- Behavior when a tablespace policy is cleared while it still contains encrypted
  relations (those relations remain readable via their existing keys; the policy
  only governs new relations).

## Non-goals

- Retroactively encrypting existing data without a rewrite.
- Encrypting shared catalogs or anything in `pg_global`.
- Changing the per-table `tde_heap` workflow, which continues to work alongside
  this feature.

## Effort

Medium. The cryptographic core, key lifecycle, per-relation and per-tablespace
key storage, WAL, and key inheritance already exist and are exercised by tests.
The new work is a policy and metadata layer plus the SET TABLESPACE move
semantics, with tests and documentation. All C code must satisfy the
[PostgreSQL coding conventions](https://www.postgresql.org/docs/current/source.html)
per `CLAUDE.md`.
