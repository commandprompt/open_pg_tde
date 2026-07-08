<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="documentation/docs/_images/open_pg_tde-logo/horizontal/horizontal-white.svg">
    <img alt="open_pg_tde" width="460" src="documentation/docs/_images/open_pg_tde-logo/horizontal/horizontal-color.svg">
  </picture>
</p>

<p align="center">
  <strong>Transparent Data Encryption for upstream PostgreSQL</strong>
</p>

<p align="center">
  <a href="https://scorecard.dev/viewer/?uri=github.com/commandprompt/open_pg_tde"><img alt="OpenSSF Scorecard" src="https://api.scorecard.dev/projects/github.com/commandprompt/open_pg_tde/badge"></a>
  <img alt="PostgreSQL 16 | 17 | 18" src="https://img.shields.io/badge/PostgreSQL-16%20%7C%2017%20%7C%2018-336791?logo=postgresql&logoColor=white">
  <img alt="License: PostgreSQL" src="https://img.shields.io/badge/License-PostgreSQL-336791">
</p>

---

`open_pg_tde` is a PostgreSQL extension that encrypts data at rest. It provides
the `tde_heap` access method, so tables, their indexes, TOAST, and the
write-ahead log are encrypted on disk while remaining transparent to queries. It
runs on **upstream PostgreSQL 16, 17, and 18**, with no vendor server fork
required.

> `open_pg_tde` is an open fork of [Percona `pg_tde`](https://github.com/percona/pg_tde),
> maintained by [Command Prompt, Inc.](https://www.commandprompt.com/) See how
> they differ in the [comparison with Percona pg_tde](documentation/docs/index/comparison-percona.md).

## Features

- **Per-table encryption** with the `tde_heap` access method. The cipher is
  recorded per table, so encrypted and plain tables coexist.
- **Encrypted at rest:** table data, indexes, TOAST, the WAL, and temporary
  (query-spill) files. System catalogs and statistics are not encrypted; see the
  [threat model](documentation/docs/index/threat-model.md).
- **Data ciphers:** AES-128-XTS (default), AES-256-XTS, AES-128-CBC, and
  AES-256-CBC, selected with [`open_pg_tde.data_cipher`](documentation/docs/variables.md).
  The WAL uses AES-CTR.
- **Key management:** a two-tier hierarchy (a principal key wraps per-relation
  keys), with a keyring file, KMIP-compatible systems, or
  [OpenBao](https://openbao.org/) as providers, per database or cluster-wide.
- **FIPS:** all cryptography runs through OpenSSL with FIPS-approved modes, and
  the server can be required to start only in OpenSSL FIPS mode. See
  [FIPS compliance](documentation/docs/index/fips.md).
- **Upstream PostgreSQL:** a gated core patch adds the storage-manager and WAL
  hooks. With the flag off, the tree builds as unmodified PostgreSQL.

## Supported PostgreSQL versions

| Version | Status |
| ------- | ------ |
| 18 | Supported |
| 17 | Supported |
| 16 | Supported (minimum) |
| 19 | Beta port in progress ([roadmap](docs/design/encryption-roadmap.md#postgresql-version-support)) |

## Installation

`open_pg_tde` builds against a PostgreSQL source tree patched with the
`open_pg_tde` core patch. Apply the patch, build PostgreSQL with the hooks
enabled, then build the extension against that install:

- [Install from source](documentation/docs/install-from-source.md), the
  step-by-step guide.
- [`patches/postgresql/README.md`](patches/postgresql/README.md), the per-version
  patch series and status.

Prebuilt source tarballs for each PostgreSQL major are attached to each
[release](https://github.com/commandprompt/open_pg_tde/releases).

## Quick start

After installing the extension and adding `open_pg_tde` to
`shared_preload_libraries`:

```sql
CREATE EXTENSION open_pg_tde;

-- Configure a key provider and a principal key (a keyring file here; use a KMS
-- in production, see the setup guide).
SELECT open_pg_tde_add_database_key_provider_file('file-keyring', '/path/to/keyring');
SELECT open_pg_tde_create_key_using_database_key_provider('my-key', 'file-keyring');
SELECT open_pg_tde_set_key_using_database_key_provider('my-key', 'file-keyring');

-- Create an encrypted table.
CREATE TABLE secret (id int, data text) USING tde_heap;
SELECT open_pg_tde_is_encrypted('secret');  -- t
```

See the [setup guide](documentation/docs/setup.md) for key management, WAL
encryption, and enabling encryption by default.

## Documentation

The full documentation source is in [`documentation/`](documentation/).

| | |
| --- | --- |
| [Setup and configuration](documentation/docs/setup.md) | Install, key providers, encrypted tables |
| [Key management](documentation/docs/global-key-provider-configuration/overview.md) | Keyring file, KMIP, OpenBao |
| [GUC variables](documentation/docs/variables.md) | All settings |
| [Functions](documentation/docs/functions.md) | Helper functions |
| [Threat model](documentation/docs/index/threat-model.md) | What encryption at rest does and does not protect |
| [FIPS compliance](documentation/docs/index/fips.md) | Approved algorithms and FIPS mode |
| [Comparison with Percona pg_tde](documentation/docs/index/comparison-percona.md) | How the fork differs |

## Contributing

Contributions are welcome. See [`CONTRIBUTING.md`](CONTRIBUTING.md) for building,
testing, and coding standards, and [`RELEASING.md`](RELEASING.md) for how
releases are built. All C code follows the
[PostgreSQL coding conventions](https://www.postgresql.org/docs/current/source.html).

## License

`open_pg_tde` is derived from Percona `pg_tde` and is distributed under the
PostgreSQL License. It retains the original copyright for the derived work.
Command Prompt, Inc. maintains `open_pg_tde` and is not affiliated with Percona.
