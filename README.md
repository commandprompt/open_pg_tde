[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/commandprompt/open_pg_tde/badge)](https://scorecard.dev/viewer/?uri=github.com/commandprompt/open_pg_tde)

# open_pg_tde: Transparent Data Encryption for PostgreSQL

`open_pg_tde` is a PostgreSQL extension that provides Transparent Data Encryption (TDE) to protect data at rest.

> `open_pg_tde` is an open fork of [Percona's `pg_tde`](https://github.com/percona/pg_tde), maintained by Command Prompt, Inc. It keeps the file and KMIP key providers, keeps OpenBao (the Apache-2.0 KV v2 provider) while dropping HashiCorp Vault, and adds pluggable ciphers (AES-XTS for data files, AES-CTR for WAL) selectable via the `open_pg_tde.data_cipher` GUC.

## Table of Contents

1. [Overview](#overview)
2. [Documentation](#documentation)
3. [Installation](#installation)
4. [Set up open_pg_tde](#set-up-open_pg_tde)
5. [Additional functions](#additional-functions)

## Overview

Transparent Data Encryption offers encryption at the file level and solves the problem of protecting data at rest. The encryption is transparent for users allowing them to access and manipulate the data and not to worry about the encryption process. The extension supports [a keyring file and external Key Management Systems (KMS) through a Global Key Provider interface](documentation/docs/global-key-provider-configuration/overview.md).

### This extension provides the `tde_heap` access method

This access method:

- Works with upstream PostgreSQL 14 and later, patched with the `open_pg_tde` core patch (see [Installation](#installation))
- Uses extended Storage Manager and WAL APIs
- Encrypts tuples, WAL and indexes
- It **does not** encrypt temporary files and statistics **yet**

## Documentation

The documentation source is in [`documentation/`](documentation/). Start with the [installation guide](documentation/docs/install.md) and the [setup guide](documentation/docs/setup.md).

## Installation

`open_pg_tde` runs on upstream PostgreSQL 14 and later. You apply the `open_pg_tde` core patch to a PostgreSQL source tree, build it with the hooks enabled, and build the extension against that install. See [Install from source](documentation/docs/install-from-source.md) for the step-by-step guide, and [`patches/postgresql/README.md`](patches/postgresql/README.md) for the patch series and per-version status.

## Set up open_pg_tde

For setting up and configuring `open_pg_tde`, see the [setup guide](documentation/docs/setup.md). It covers:

- Installing and enabling the extension
- Setting up key providers
- Creating encrypted tables

## Additional functions

For the helper functions available in `open_pg_tde`, including how to check table encryption status with `open_pg_tde_is_encrypted`, see the [functions reference](documentation/docs/functions.md).
