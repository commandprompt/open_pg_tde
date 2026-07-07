\! rm -f '/tmp/open_pg_tde_test_keyring.per'

CREATE EXTENSION open_pg_tde;

SELECT open_pg_tde_add_database_key_provider_file('file-vault','/tmp/open_pg_tde_test_keyring.per');
SELECT open_pg_tde_create_key_using_database_key_provider('test-db-key','file-vault');
SELECT open_pg_tde_set_key_using_database_key_provider('test-db-key','file-vault');

CREATE TABLE src (f1 TEXT STORAGE EXTERNAL) USING tde_heap;
INSERT INTO src VALUES(repeat('abcdeF',1000));
SELECT * FROM src;

DROP TABLE src;

DROP EXTENSION open_pg_tde;
