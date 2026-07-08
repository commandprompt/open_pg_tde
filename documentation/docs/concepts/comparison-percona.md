# Comparison with Percona pg_tde

`open_pg_tde` is an open fork of Percona's `pg_tde`, maintained by
[Command Prompt, Inc.](https://www.commandprompt.com/) It keeps the core
Transparent Data Encryption design of the original project: a two-tier key
hierarchy, the `tde_heap` access method, per-table encryption, WAL encryption,
and pluggable key providers. This page describes how the two differ, so you can
choose the one that fits your deployment. For the current state of Percona
pg_tde, see the [Percona pg_tde documentation](https://docs.percona.com/pg-tde/).

## The main difference: the PostgreSQL server

The two projects target different PostgreSQL builds.

- **open_pg_tde runs on upstream PostgreSQL.** It does not require a vendor fork
  of the server. Encryption relies on storage-manager and WAL extensibility that
  upstream PostgreSQL does not yet expose, so you apply the `open_pg_tde` core
  patch to a stock PostgreSQL source tree and build the extension against it. The
  patch is gated behind a build flag (`--enable-tde-hooks`); with the flag off,
  the same tree builds as unmodified PostgreSQL. open_pg_tde supports PostgreSQL
  16, 17, and 18.

- **Percona pg_tde requires Percona Server for PostgreSQL.** Percona's
  documentation states that pg_tde is bundled as a component of Percona Server
  for PostgreSQL and requires its patches to function.

If you run community PostgreSQL and do not want to adopt a vendor server
distribution, open_pg_tde is built for that case. If you already run Percona
Server for PostgreSQL, Percona pg_tde is integrated with it.

## Comparison

| Dimension | open_pg_tde | Percona pg_tde |
| --------- | ----------- | -------------- |
| Base server | Upstream PostgreSQL 16, 17, 18, with the gated open_pg_tde core patch | Percona Server for PostgreSQL |
| Maintainer | Command Prompt, Inc. | Percona |
| Relationship | Open fork of Percona pg_tde | Original project |
| Access method | `tde_heap` | `tde_heap` |
| Encrypted at rest | Table data, indexes, TOAST, WAL, temporary files | Table data, indexes, TOAST, WAL |
| Key providers | KMIP-compatible KMS (including Fortanix, Thales, Akeyless), OpenBao, keyring file | KMIP, HashiCorp Vault, OpenBao, keyring file, and others |

Both projects continue to develop independently. Confirm current specifics in
each project's own documentation.

## What open_pg_tde focuses on

Beyond running on upstream PostgreSQL, this fork has added:

- **Temporary file encryption.** Query-spill files (external sorts, hash joins)
  are encrypted with AES-128-XTS. See [`encrypt_temp_files`](../variables.md#encrypt_temp_files).
- **AES-256-XTS data cipher**, alongside AES-128-XTS and the CBC ciphers, for
  deployments that require AES-256 keys, through a pluggable cipher registry. See
  [`open_pg_tde.data_cipher`](../variables.md#open_pg_tdedata_cipher).
- **FIPS enforcement.** All cryptography runs through OpenSSL and uses
  FIPS-approved modes, and the server can be required to start only when OpenSSL
  is in FIPS mode. See [FIPS compliance](fips.md).
- **A documented threat model** stating what encryption at rest does and does not
  protect. See the [threat model](threat-model.md).

## Key management

open_pg_tde uses [OpenBao](https://openbao.org/), the Apache 2.0 licensed fork of
HashiCorp Vault, through its Key/Value version 2 secrets engine, rather than
HashiCorp Vault directly. It also supports KMIP-compatible key management
systems and a local keyring file. See the
[key management overview](../key-management/overview.md).

## Attribution

open_pg_tde is derived from Percona pg_tde, which is copyright Percona and
released under the PostgreSQL License. open_pg_tde retains that copyright and
license for the derived work. Command Prompt, Inc. maintains open_pg_tde and is
not affiliated with Percona.
