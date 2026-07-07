CREATE SCHEMA IF NOT EXISTS _open_pg_tde;
CREATE EXTENSION IF NOT EXISTS open_pg_tde SCHEMA _open_pg_tde;
\! rm -f '/tmp/open_pg_tde_test_keyring.per'
SELECT _open_pg_tde.open_pg_tde_add_database_key_provider_file('reg_file-vault', '/tmp/open_pg_tde_test_keyring.per');
SELECT _open_pg_tde.open_pg_tde_create_key_using_database_key_provider('test-db-key', 'reg_file-vault');
SELECT _open_pg_tde.open_pg_tde_set_key_using_database_key_provider('test-db-key', 'reg_file-vault');
