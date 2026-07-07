SELECT * FROM pg_get_loaded_modules() WHERE file_name IN ('open_pg_tde.so', 'open_pg_tde.dylib');
CREATE EXTENSION open_pg_tde;
SELECT open_pg_tde_version();
DROP EXTENSION open_pg_tde;
