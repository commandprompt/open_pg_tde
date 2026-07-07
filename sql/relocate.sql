CREATE SCHEMA other;

CREATE EXTENSION open_pg_tde SCHEMA other;

SELECT other.open_pg_tde_add_database_key_provider_file('file-vault', '/tmp/open_pg_tde_test_keyring.per');

ALTER EXTENSION open_pg_tde SET SCHEMA public;

DROP EXTENSION open_pg_tde;

DROP SCHEMA other;
