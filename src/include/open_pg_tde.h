#ifndef OPEN_PG_TDE_H
#define OPEN_PG_TDE_H

#define OPEN_PG_TDE_NAME "open_pg_tde"
#define OPEN_PG_TDE_VERSION "2.2.0"
#define OPEN_PG_TDE_VERSION_STRING OPEN_PG_TDE_NAME " " OPEN_PG_TDE_VERSION

#define OPEN_PG_TDE_DATA_DIR	"open_pg_tde"
#define OPEN_PG_TDE_WAL_KEY_FILE_NAME "wal_keys"

#define TDE_TRANCHE_NAME "open_pg_tde_tranche"

/*
 * File format magics. Only the numeric version (the most significant byte)
 * should change when the format changes; otherwise migration breaks. The
 * current formats (WAL key file v3, map file v6) authenticate key_base_iv in
 * the AEAD additional authenticated data; the previous formats (WAL v2, map
 * v5) did not.
 */
#define OPEN_PG_TDE_WAL_KEY_FILE_MAGIC 0x034B4557	/* "WEK", version 3 */
#define OPEN_PG_TDE_SMGR_FILE_MAGIC 0x06454454	/* "TDE", version 6 */

#define FILEMAGIC_VERSION(FM) ((FM & 0xF000000) >> 24)
#define FILEMAGIC_TYPE(FM) ((FM & 0x0FFFFFF))

typedef enum
{
	TDE_LWLOCK_ENC_KEY,
	TDE_LWLOCK_PI_FILES,

	/* Must be the last entry in the enum */
	TDE_LWLOCK_COUNT
}			TDELockTypes;

typedef struct XLogExtensionInstall
{
	Oid			database_id;
} XLogExtensionInstall;

extern void extension_install_redo(XLogExtensionInstall *xlrec);

#endif							/* OPEN_PG_TDE_H */
