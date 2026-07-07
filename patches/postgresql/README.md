# open_pg_tde core patches for PostgreSQL

`open_pg_tde` encrypts data pages through the storage manager (SMGR) and WAL
through the WAL segment I/O path. Native PostgreSQL does not make either
extensible, so `open_pg_tde` ships those extensibility points as a small,
maintained patch series that you apply to a stock PostgreSQL source tree. This
keeps the project on native PostgreSQL rather than a vendor fork.

The patch is **derived from** Percona Server for PostgreSQL
(`github.com/percona/postgres`), which is the canonical upstream for this work.

## Layout

```
patches/postgresql/
  apply.sh          # version-detecting apply/check/reverse driver
  <major>/          # one directory per PostgreSQL major version
    NNNN-*.patch    # an ordered, rebased patch series
```

There is one series per PostgreSQL major version because the SMGR interface
changes between majors (zeroextend in 16, readv/writev in 17, AIO in 18).

## Applying

```sh
# apply (auto-detects the major version of the tree)
patches/postgresql/apply.sh /path/to/postgresql-src

# dry-run / reverse
patches/postgresql/apply.sh /path/to/postgresql-src --check
patches/postgresql/apply.sh /path/to/postgresql-src --reverse
```

Then configure and build. **The hooks are gated behind a build flag**, so the
patched tree builds as clean PostgreSQL unless you opt in:

```sh
# clean PostgreSQL (hooks compiled out) - default
./configure ...              # autoconf
meson setup build ...        # meson

# open_pg_tde-enabled PostgreSQL (hooks compiled in)
./configure --enable-tde-hooks ...
meson setup build -Dtde_hooks=enabled ...
```

The flag defines the `USE_TDE_HOOKS` C macro (see `src/include/pg_config.h`).
Every change the patch makes is guarded by `#ifdef USE_TDE_HOOKS`, so with the
flag off the preprocessed source is the stock PostgreSQL source and the binary
behaves identically to unpatched PostgreSQL. With it on, the SMGR registry and
WAL storage-manager hooks are compiled in; they still default to standard
behavior until the `open_pg_tde` extension registers its encrypting handlers.

## What the patch contains

A pluggable storage manager and a WAL storage manager, plus their wiring:

| Area | Files |
|------|-------|
| Pluggable SMGR | `storage/smgr.h`, `storage/md.h`, `storage/smgr/smgr.c`, `storage/smgr/md.c` |
| md registration | `utils/init/miscinit.c`, `include/miscadmin.h` |
| WAL storage manager | `access/xlog_smgr.h` (new), `transam/xlog.c`, `transam/xlogreader.c` |
| AIO completion callback (PG 18) | `storage/aio.h`, `storage/aio/aio_callback.c` |
| New-file key inheritance (TRUNCATE / VACUUM FULL / CLUSTER) | `catalog/storage.{c,h}`, `catalog/heap.{c,h}`, `catalog/index.{c,h}`, `catalog/toasting.c`, `access/heap/heapam_handler.c`, `commands/tablecmds.c`, `commands/indexcmds.c`, `commands/sequence.c`, `utils/cache/relcache.c` |

`smgr.c` becomes a registry: `smgr_register()` returns an `SMgrId`, the
built-in magnetic-disk manager registers as `MdSMgrId`, and
`storage_manager_id` selects the active one. `xlog_smgr.h` defines a
read/write function-pointer pair for WAL segments whose default calls
`pg_pread`/`pg_pwrite`; `open_pg_tde` installs an encrypting one via
`SetXLogSmgr()`. The inheritance files add `RelationCreateStoragePercona()` /
`smgrcreate_percona()` variants that pass the old relfilelocator so a new file
inherits its key.

## Maintenance

**Watch the Percona postgres branches (`PSP_REL_*_STABLE`) for changes to the
files above and fold them into the series.** Percona actively maintains this
code (bug fixes, new PostgreSQL versions, and work to upstream extensible
SMGR). To rebase for a new PostgreSQL release, apply the series to the new tag,
resolve any rejects, and regenerate the series - do **not** re-extract from
scratch. Two lessons already recorded:

- Apply the WAL-recovery files as **hunk-level** patches, not whole-file
  copies: Percona's tree can predate native helpers (e.g.
  `XLogFlushBufferForRedoIfInit`), so a wholesale copy deletes symbols native
  index-AM redo needs.
- The md storage manager must register via `register_builtin_dynamic_managers()`
  in `miscinit.c`, or `smgropen` trips `Assert(NSmgr > 0)`.

## Status

| PostgreSQL | Data files | WAL | Frontend tools | Compile-time gate |
|------------|-----------|-----|----------------|-------------------|
| 18 | Done (full `tde_heap` suite: basic, AES-256, AES-XTS, cipher selection, TRUNCATE/VACUUM inheritance, CREATE DATABASE) | **Done** (encrypt, recovery, archiving, key TLI) | **Done** (rewind, basebackup, upgrade) | **Done** (verified OFF=clean PG / ON=encrypts; `verify-gate.sh`) |

**PostgreSQL 18: full extension suite passes (42/42).** Run the suite with
`LD_LIBRARY_PATH=<prefix>/lib` so the frontend tools find `libpq` at runtime.
| 14-17 | Not started | — | — | — |

See `../../TODO.md` for the tracked work.
