\! rm -f '/tmp/open_pg_tde_test_keyring.per'

CREATE EXTENSION open_pg_tde;

SELECT open_pg_tde_add_database_key_provider_file('local-file-provider', '/tmp/open_pg_tde_test_keyring.per');

CREATE USER regress_open_pg_tde_access_control;

SET ROLE regress_open_pg_tde_access_control;

-- should throw access denied
SELECT open_pg_tde_create_key_using_database_key_provider('test-db-key', 'local-file-provider');
SELECT open_pg_tde_set_key_using_database_key_provider('test-db-key', 'local-file-provider');
SELECT open_pg_tde_delete_key();
SELECT open_pg_tde_list_all_database_key_providers();
SELECT open_pg_tde_list_all_global_key_providers();
SELECT open_pg_tde_key_info();
SELECT open_pg_tde_server_key_info();
SELECT open_pg_tde_default_key_info();
SELECT open_pg_tde_verify_key();
SELECT open_pg_tde_verify_server_key();
SELECT open_pg_tde_verify_default_key();

RESET ROLE;

-- Only superusers can execute key management functions, regardless of role grants
GRANT EXECUTE ON FUNCTION open_pg_tde_add_database_key_provider(TEXT, TEXT, JSON) TO regress_open_pg_tde_access_control;
GRANT EXECUTE ON FUNCTION open_pg_tde_add_global_key_provider(TEXT, TEXT, JSON) TO regress_open_pg_tde_access_control;
GRANT EXECUTE ON FUNCTION open_pg_tde_change_database_key_provider(TEXT, TEXT, JSON) TO regress_open_pg_tde_access_control;
GRANT EXECUTE ON FUNCTION open_pg_tde_change_global_key_provider(TEXT, TEXT, JSON) TO regress_open_pg_tde_access_control;
GRANT EXECUTE ON FUNCTION open_pg_tde_create_key_using_global_key_provider(TEXT, TEXT) TO regress_open_pg_tde_access_control;
GRANT EXECUTE ON FUNCTION open_pg_tde_delete_database_key_provider(TEXT) TO regress_open_pg_tde_access_control;
GRANT EXECUTE ON FUNCTION open_pg_tde_delete_global_key_provider(TEXT) TO regress_open_pg_tde_access_control;
GRANT EXECUTE ON FUNCTION open_pg_tde_set_default_key_using_global_key_provider(TEXT, TEXT) TO regress_open_pg_tde_access_control;
GRANT EXECUTE ON FUNCTION open_pg_tde_set_key_using_global_key_provider(TEXT, TEXT) TO regress_open_pg_tde_access_control;
GRANT EXECUTE ON FUNCTION open_pg_tde_set_server_key_using_global_key_provider(TEXT, TEXT) TO regress_open_pg_tde_access_control;
GRANT EXECUTE ON FUNCTION open_pg_tde_delete_default_key() TO regress_open_pg_tde_access_control;

SET ROLE regress_open_pg_tde_access_control;

SELECT open_pg_tde_add_database_key_provider_file('local-file-provider', '/tmp/open_pg_tde_test_keyring.per');
SELECT open_pg_tde_change_global_key_provider_file('local-file-provider', '/tmp/open_pg_tde_test_keyring.per');
SELECT open_pg_tde_delete_database_key_provider('local-file-provider');
SELECT open_pg_tde_add_global_key_provider_file('global-file-provider', '/tmp/open_pg_tde_test_keyring.per');
SELECT open_pg_tde_change_global_key_provider_file('global-file-provider', '/tmp/open_pg_tde_test_keyring.per');
SELECT open_pg_tde_delete_global_key_provider('global-file-provider');
SELECT open_pg_tde_create_key_using_global_key_provider('key1', 'global-file-provider');
SELECT open_pg_tde_set_key_using_global_key_provider('key1', 'global-file-provider');
SELECT open_pg_tde_set_default_key_using_global_key_provider('key1', 'global-file-provider');
SELECT open_pg_tde_set_server_key_using_global_key_provider('key1', 'global-file-provider');
SELECT open_pg_tde_delete_default_key();

RESET ROLE;

DROP EXTENSION open_pg_tde CASCADE;
