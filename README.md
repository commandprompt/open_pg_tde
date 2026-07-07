[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/commandprompt/open_pg_tde/badge)](https://scorecard.dev/viewer/?uri=github.com/commandprompt/open_pg_tde)

# open_pg_tde: Transparent Data Encryption for PostgreSQL

`open_pg_tde` is a PostgreSQL extension that provides Transparent Data Encryption (TDE) to protect data at rest.

> `open_pg_tde` is an open fork of [Percona's `pg_tde`](https://github.com/percona/pg_tde), maintained by Command Prompt, Inc. It keeps the file and KMIP key providers, keeps OpenBao (the Apache-2.0 KV v2 provider) while dropping HashiCorp Vault, and adds pluggable ciphers (AES-XTS for data files, AES-CTR for WAL) selectable via the `open_pg_tde.data_cipher` GUC.

## Table of Contents

1. [Overview](#overview)
2. [Documentation](#documentation)
3. [Percona Server for PostgreSQL](#percona-server-for-postgresql)
4. [Run in docker](#run-in-docker)
5. [Set up open_pg_tde](#set-up-open_pg_tde)
6. [Downloads](#downloads)
7. [Additional functions](#additional-functions)

## Overview

Transparent Data Encryption offers encryption at the file level and solves the problem of protecting data at rest. The encryption is transparent for users allowing them to access and manipulate the data and not to worry about the encryption process. The extension supports [keyringfile and external Key Management Systems (KMS) through a Global Key Provider interface](../open_pg_tde/documentation/docs/global-key-provider-configuration/index.md).

### This extension provides the `tde_heap` access method

This access method:

- Works only with [Percona Server for PostgreSQL 17](https://docs.percona.com/postgresql/17/postgresql-server.html) or [Percona Server for PostgreSQL 18](https://docs.percona.com/postgresql/18/postgresql-server.html)
- Uses extended Storage Manager and WAL APIs
- Encrypts tuples, WAL and indexes
- It **does not** encrypt temporary files and statistics **yet**

## Documentation

For more information about `open_pg_tde`, [see the official documentation](https://docs.percona.com/pg-tde/index.html).

## Percona Server for PostgreSQL

Percona provides binary packages of `open_pg_tde` extension only for Percona Server for PostgreSQL. Learn how to install them or build `open_pg_tde` from sources for PSPG in the [documentation](https://docs.percona.com/pg-tde/install.html).

## Run in Docker

To run `open_pg_tde` in Docker, follow the instructions in the [official open_pg_tde Docker documentation](https://docs.percona.com/postgresql/17/docker.html#enable-encryption).

_For details on the build process and developer setup, see [Make Builds for Developers](https://github.com/commandprompt/open_pg_tde/wiki/Make-builds-for-developers)._

## Set up open_pg_tde

For more information on setting up and configuring `open_pg_tde`, see the [official open_pg_tde setup topic](https://docs.percona.com/pg-tde/setup.html).

The guide also includes instructions for:

- Installing and enabling the extension
- Setting up key providers
- Creating encrypted tables

## Additional functions

Learn more about the helper functions available in `open_pg_tde`, including how to check table encryption status, in the [Functions topic](https://docs.percona.com/pg-tde/functions.html?h=open_pg_tde_is_encrypted#encryption-status-check).
