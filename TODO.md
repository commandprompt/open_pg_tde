# open_pg_tde TODO

## Core patch maintenance (ongoing)

- **Watch Percona Server for PostgreSQL for changes to the native-PostgreSQL
  core patch.** The pluggable-SMGR and WAL-SMGR patch under
  `patches/native-postgresql/` is derived from `github.com/percona/postgres`
  (`PSP_REL_*_STABLE`). Periodically diff the upstream files (listed in
  `patches/native-postgresql/README.md`) against the matching stock PostgreSQL
  tag and fold in any fixes or changes. Always re-check when Percona ships a
  new PostgreSQL minor or major version.

## Native PostgreSQL support

- [x] Port the SMGR/WAL core patch to native PostgreSQL 18 (builds; `tde_heap`
      encrypts at rest on stock PostgreSQL 18.4).
- [ ] Re-derive the patch for PostgreSQL 14, 15, 16, and 17 (the SMGR interface
      differs per version).
- [ ] Run the full test suite against patched native PostgreSQL (currently
      verified against Percona Server).

## Temporary file encryption

- [ ] Fold the temporary-file encryption hook (`encrypt_temp_files` +
      `tde_tempfile`, prototyped separately for PG 14/18) into this tree so all
      three data types (data files, WAL, temp files) share one key hierarchy.

## Branding

- [ ] Add the Command Prompt documentation theme (brand colors + mammoth logo).
- [ ] Finish removing Percona references from documentation content
      (install/support pages), aligning them with the native-PostgreSQL build.
