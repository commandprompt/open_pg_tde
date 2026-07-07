# Building open_pg_tde against native PostgreSQL

`open_pg_tde` encrypts data pages through the storage manager (SMGR) and WAL
through the WAL segment I/O path. Native PostgreSQL does not make either of
these extensible, which is why the upstream `pg_tde` requires Percona Server
for PostgreSQL (a fork that carries these core changes).

`open_pg_tde` instead ships those core changes as a small, self-contained
patch you apply to a stock PostgreSQL source tree. This keeps the project on
native PostgreSQL rather than depending on a vendor fork.

## What the patch adds

A pluggable storage manager and a WAL storage manager, plus the small amount
of wiring they need. 11 files, about 400 added lines:

| Area | Files |
|------|-------|
| Pluggable SMGR | `src/include/storage/smgr.h`, `src/include/storage/md.h`, `src/backend/storage/smgr/smgr.c`, `src/backend/storage/smgr/md.c` |
| md registration wiring | `src/backend/utils/init/miscinit.c`, `src/include/miscadmin.h` |
| WAL storage manager | `src/include/access/xlog_smgr.h` (new), `src/backend/access/transam/xlog.c`, `src/backend/access/transam/xlogreader.c` |
| AIO completion callback (PG 18) | `src/include/storage/aio.h`, `src/backend/storage/aio/aio_callback.c` |

`smgr.c` becomes a registry: `smgr_register()` returns an `SMgrId`, the
built-in magnetic-disk manager registers itself as `MdSMgrId`, and
`storage_manager_id` selects the active manager. `xlog_smgr.h` defines a
read/write function-pointer pair for WAL segments with a default that calls
`pg_pread`/`pg_pwrite`; `open_pg_tde` installs an encrypting one via
`SetXLogSmgr()`.

## Applying

```sh
cd postgresql-src            # a stock REL_18_STABLE checkout
patch -p1 < pg18-smgr-wal.patch
./configure --with-openssl ...
make install
```

Then build `open_pg_tde` against the patched install with
`-Dpg_config=<prefix>/bin/pg_config`.

## Provenance and maintenance

This patch is **derived from Percona Server for PostgreSQL**
(`github.com/percona/postgres`, the `PSP_REL_*_STABLE` branches), which is the
canonical source of the pluggable-SMGR and WAL-SMGR work. Their copyright and
authorship apply to these changes.

**Maintenance rule: watch the Percona postgres branches for changes to the
files listed above and fold their fixes into this patch.** Percona actively
maintains this code (bug fixes, new PostgreSQL versions, and ongoing work to
upstream extensible SMGR into PostgreSQL). Whenever we add support for a new
PostgreSQL major or minor version, or on a periodic cadence, diff the relevant
`PSP_REL_<major>_STABLE` files against the matching stock PostgreSQL tag and
re-derive the per-version patch. Track it in `TODO.md`.

## Full scope

The 11 files above are the **core** and are enough to build, initdb, and
encrypt a freshly created `tde_heap` table at rest. Full feature parity needs
a further ~15 caller-side files from `percona/postgres` (all small; the true
pg_tde-relevant subset of Percona Server's fork). These carry:

- **New-file key inheritance** (TRUNCATE, VACUUM FULL, CLUSTER, reindex): the
  `RelationCreateStoragePercona()` / `smgrcreate_percona()` variants that pass
  the *old* relfilelocator so the new file inherits its key —
  `catalog/storage.{c,h}`, `catalog/heap.c`, `catalog/index.{c,h}`,
  `catalog/toasting.c`, `access/heap/heapam_handler.c`,
  `commands/tablecmds.c`, `commands/indexcmds.c`, `commands/sequence.c`,
  `utils/cache/relcache.c`.
- **WAL decryption on recovery / receive**: `access/transam/xlogrecovery.c`,
  `access/transam/xlogutils.c`, `replication/walreceiver.c`.
- **Buffer manager SMGR integration**: `storage/buffer/bufmgr.c`.

Derive these the same way (diff the file against the matching stock tag).

## Version status

| PostgreSQL | Status |
|------------|--------|
| 18 | Core (11 files) verified: builds, initdb, `CREATE EXTENSION open_pg_tde`, `tde_heap` encrypts at rest (`is_encrypted = t`, ciphertext on disk). The ~15 caller-side files above are still to be folded in for full feature parity (TRUNCATE/VACUUM inheritance, WAL recovery). |
| 14-17 | Not yet ported. The SMGR interface differs per version (zeroextend in 16, readv/writev in 17, AIO in 18), so each needs its own re-derived patch from the matching `PSP_REL_<major>_STABLE`. |
