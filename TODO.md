# open_pg_tde TODO

## Native PostgreSQL: core patch framework

The patches live under `patches/postgresql/<major>/` and are applied with
`patches/postgresql/apply.sh`. They are a maintained, rebased series.

- [x] Framework: `apply.sh` (version-detect, apply/check/reverse), one series
      per major, `patches/postgresql/README.md`.
- [x] Data-file encryption on PostgreSQL 18 (full `tde_heap` suite: basic,
      AES-256, AES-XTS, cipher selection, TRUNCATE/VACUUM key inheritance).
- [ ] **Compile-time gate** (`--enable-tde-hooks` / `-Dtde_hooks=enabled` ->
      `USE_TDE_HOOKS`): guard every patched change with `#ifdef USE_TDE_HOOKS`
      so the patched tree builds as clean PostgreSQL by default. Plumbing:
      `configure.ac`, `src/include/pg_config.h.in`, `meson_options.txt`,
      `meson.build`, `src/include/pg_config_manual.h`. Then wrap smgr/md/xlog/
      inheritance changes with dual paths (vanilla when off).
- [ ] **WAL encryption/recovery** (a): hunk-level patches for
      `transam/xlogutils.c`, `transam/xlogrecovery.c`, `replication/walreceiver.c`.
      Clears `wal_encrypt`, `wal_key_tli`, `wal_archiving`, `crash_recovery`.
- [ ] **Encryption-aware frontend tools** (b): WAL/SMGR frontend integration for
      `open_pg_tde_rewind` / `open_pg_tde_basebackup`. Clears the `pg_rewind_*`,
      `pg_basebackup`, and upgrade tests.
- [ ] Series done for 16, 17, 18 (extension floor is 16; 14/15 unsupported).

## Tests (required for each of the above)

- [ ] Full extension suite green against patched native PostgreSQL (currently
      20/42 on PG 18; data-file paths pass, WAL + frontend pending).
- [ ] Gate test: build the patched tree with the flag OFF and confirm a clean
      PostgreSQL (initdb, a plain non-TDE workload, and that `tde_heap` is
      unavailable); build with the flag ON and confirm encryption. Add as a CI
      job / TAP test.

## Documentation (required)

- [ ] `patches/postgresql/README.md` kept current (apply, gate, maintenance).
- [ ] User docs: replace the "Percona Server for PostgreSQL" install pages with
      "apply the patch to PostgreSQL 16+ and build with `--enable-tde-hooks`".
- [ ] Architecture doc: the SMGR/WAL hook design and the gate.

## Core patch maintenance (ongoing)

- **Watch Percona Server for PostgreSQL** (`percona/postgres`, `PSP_REL_*_STABLE`)
  for changes to the patched files and fold them in. Always re-check on a new
  PostgreSQL minor or major release. Rebase the series; do not re-extract.

## Temporary file encryption

- [ ] Fold the temp-file hook (`encrypt_temp_files` + `tde_tempfile`, prototyped
      for PG 14/18) into the series so data files, WAL, and temp files share one
      key hierarchy.

## Branding / release

- [ ] Command Prompt docs theme (brand hex + mammoth logo, pending assets).
- [ ] Finish removing Percona references from doc content.
- [ ] Initial push to `commandprompt/open_pg_tde`.
