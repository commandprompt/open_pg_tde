#ifndef OPEN_PG_TDE_UTILS_H
#define OPEN_PG_TDE_UTILS_H

extern void open_pg_tde_set_data_dir(const char *dir);
extern const char *open_pg_tde_get_data_dir(void);
extern const char *get_wal_key_file_path(void);

#endif							/* OPEN_PG_TDE_UTILS_H */
