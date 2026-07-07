CREATE SCHEMA IF NOT EXISTS _open_pg_tde;
CREATE EXTENSION IF NOT EXISTS open_pg_tde SCHEMA _open_pg_tde;

\! rm -f '/tmp/open_pg_tde_test_keyring.per'
SELECT _open_pg_tde.open_pg_tde_add_global_key_provider_file('reg_file-global', '/tmp/open_pg_tde_test_keyring.per');
SELECT _open_pg_tde.open_pg_tde_create_key_using_global_key_provider('server-key', 'reg_file-global');
SELECT _open_pg_tde.open_pg_tde_set_server_key_using_global_key_provider('server-key', 'reg_file-global');
ALTER SYSTEM SET open_pg_tde.wal_encrypt = on;
ALTER SYSTEM SET default_table_access_method = 'tde_heap';
-- restart required
