-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "ALTER EXTENSION pg_tde UPDATE TO '2.1'" to load this file. \quit

-- Fork note: the HashiCorp Vault (vault-v2) key provider has been removed from
-- this fork. The pg_tde_{add,change}_{database,global}_key_provider_vault_v2()
-- wrapper functions that previously lived here are intentionally omitted.
-- Only the file and kmip key providers are supported.
