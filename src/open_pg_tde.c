/*
 * Main file: setup GUCs, shared memory, hooks and other general-purpose
 * routines.
 */

#include "postgres.h"

#include <unistd.h>
#include <openssl/evp.h>
#if OPENSSL_VERSION_NUMBER >= 0x30000000L
#include <openssl/provider.h>
#endif

#include "access/tableam.h"
#include "access/xlog.h"
#include "access/xloginsert.h"
#include "funcapi.h"
#include "miscadmin.h"
#include "storage/ipc.h"
#include "storage/lwlock.h"
#include "storage/shmem.h"
#include "utils/builtins.h"

#include "access/open_pg_tde_tdemap.h"
#include "access/open_pg_tde_xlog.h"
#include "access/open_pg_tde_xlog_smgr.h"
#include "catalog/tde_global_space.h"
#include "catalog/tde_keyring.h"
#include "catalog/tde_principal_key.h"
#include "encryption/enc_aes.h"
#include "keyring/keyring_api.h"
#include "keyring/keyring_file.h"
#include "keyring/keyring_kmip.h"
#include "keyring/keyring_openbao.h"
#include "open_pg_tde.h"
#include "open_pg_tde_event_capture.h"
#include "open_pg_tde_guc.h"
#include "smgr/open_pg_tde_smgr.h"
#include "open_pg_tde_tempfile.h"

#if PG_VERSION_NUM >= 180000
PG_MODULE_MAGIC_EXT(.name = OPEN_PG_TDE_NAME,.version = OPEN_PG_TDE_VERSION);
#else
PG_MODULE_MAGIC;
#endif

#define KEYS_VERSION_FILE	"keys_version"

typedef struct keys_version_info
{
	int32		smgr_version;
	int32		wal_version;
} keys_version_info;

static void open_pg_tde_init_data_dir(void);
static void open_pg_tde_migrate_internal_keys(void);

static shmem_startup_hook_type prev_shmem_startup_hook = NULL;
static shmem_request_hook_type prev_shmem_request_hook = NULL;

PG_FUNCTION_INFO_V1(open_pg_tde_extension_initialize);
PG_FUNCTION_INFO_V1(open_pg_tde_version);
PG_FUNCTION_INFO_V1(open_pg_tdeam_handler);

static void
tde_shmem_request(void)
{
	Size		sz = 0;

	sz = add_size(sz, KeyProviderShmemSize());
	sz = add_size(sz, PrincipalKeyShmemSize());
	sz = add_size(sz, TDESmgrShmemSize());
	sz = add_size(sz, TDEXLogSmgrShmemSize());

	if (prev_shmem_request_hook)
		prev_shmem_request_hook();

	RequestAddinShmemSpace(sz);
	RequestNamedLWLockTranche(TDE_TRANCHE_NAME, TDE_LWLOCK_COUNT);
	ereport(LOG, errmsg("tde_shmem_request: requested %ld bytes", sz));
}

static void
tde_shmem_startup(void)
{
	if (prev_shmem_startup_hook)
		prev_shmem_startup_hook();

	LWLockAcquire(AddinShmemInitLock, LW_EXCLUSIVE);

	KeyProviderShmemInit();
	PrincipalKeyShmemInit();
	TDESmgrShmemInit();
	TDEXLogSmgrShmemInit();

	TDEXLogSmgrInit();
	open_pg_tde_migrate_internal_keys();
	TDEXLogSmgrInitWrite(EncryptXLog, KeyLength);

	LWLockRelease(AddinShmemInitLock);
}

/*
 * When open_pg_tde.require_fips is on, verify that OpenSSL will use its
 * FIPS-validated provider for cryptography, and refuse to start otherwise. All
 * of open_pg_tde's ciphers (AES in CBC, CTR, XTS, and GCM) are FIPS-approved,
 * so this makes the whole extension run on validated cryptography.
 */
static void
open_pg_tde_check_fips(void)
{
	if (!RequireFips)
		return;

#if OPENSSL_VERSION_NUMBER >= 0x30000000L
	if (EVP_default_properties_is_fips_enabled(NULL) != 1 ||
		!OSSL_PROVIDER_available(NULL, "fips"))
		ereport(FATAL,
				errmsg("open_pg_tde.require_fips is set but OpenSSL is not in FIPS mode"),
				errdetail("The OpenSSL FIPS provider is not active, so cryptography would not use FIPS-validated implementations."),
				errhint("Configure the OpenSSL FIPS provider, or turn off open_pg_tde.require_fips."));
#else
	ereport(FATAL,
			errmsg("open_pg_tde.require_fips requires OpenSSL 3.0 or later"),
			errhint("Turn off open_pg_tde.require_fips, or build against OpenSSL 3.0 or later with the FIPS provider."));
#endif
}

void
_PG_init(void)
{
	if (!process_shared_preload_libraries_in_progress)
	{
		/*
		 * psql/pg_restore continue on error by default, and change access
		 * methods using set default_table_access_method. This error needs to
		 * be FATAL and close the connection, otherwise these tools will
		 * continue execution and create unencrypted tables when the intention
		 * was to make them encrypted.
		 */
		elog(FATAL, "open_pg_tde can only be loaded at server startup. Restart required.");
	}

	open_pg_tde_init_data_dir();
	AesInit();
	TdeGucInit();
	open_pg_tde_check_fips();
#ifdef USE_TDE_HOOKS
	TdeTempFileInit();
#endif
	TdeEventCaptureInit();
	InstallFileKeyring();
	InstallKmipKeyring();
	InstallOpenBaoKeyring();
	RegisterTdeRmgr();
	RegisterStorageMgr();

	/*
	 * open_pg_tde encrypts each page as a whole, so a hint-bit update
	 * re-encrypts the page. If hint-bit changes are not WAL-logged, a torn
	 * write of a hint-bit-only change during a crash may not be recoverable.
	 * Warn if neither data checksums nor wal_log_hints is enabled.
	 */
	if (!XLogHintBitIsNeeded())
		ereport(WARNING,
				errmsg("open_pg_tde is loaded but neither data checksums nor wal_log_hints is enabled"),
				errdetail("Encrypted pages are encrypted as a whole, so a hint-bit update re-encrypts the page. Without hint-bit WAL logging, a torn write of a hint-bit-only page change during a crash may not be recoverable."),
				errhint("Initialize the cluster with data checksums (initdb --data-checksums) or set wal_log_hints = on."));

	prev_shmem_request_hook = shmem_request_hook;
	shmem_request_hook = tde_shmem_request;
	prev_shmem_startup_hook = shmem_startup_hook;
	shmem_startup_hook = tde_shmem_startup;
}

static void
extension_install(Oid databaseId)
{
	key_provider_startup_cleanup(databaseId);
	principal_key_startup_cleanup(databaseId);
}

Datum
open_pg_tde_extension_initialize(PG_FUNCTION_ARGS)
{
	XLogExtensionInstall xlrec;

	xlrec.database_id = MyDatabaseId;
	extension_install(xlrec.database_id);

	/*
	 * Also put this info in xlog, so we can replicate the same on the other
	 * side
	 */
	XLogBeginInsert();
	XLogRegisterData((char *) &xlrec, sizeof(XLogExtensionInstall));
	XLogInsert(RM_TDERMGR_ID, XLOG_TDE_INSTALL_EXTENSION);

	PG_RETURN_VOID();
}

void
extension_install_redo(XLogExtensionInstall *xlrec)
{
	extension_install(xlrec->database_id);
}

static void
open_pg_tde_create_keys_version_file(void)
{
	char		version_file_path[MAXPGPATH] = {0};
	int			fd;
	keys_version_info curr_version = {
		.smgr_version = OPEN_PG_TDE_SMGR_FILE_MAGIC,
		.wal_version = OPEN_PG_TDE_WAL_KEY_FILE_MAGIC,
	};

	join_path_components(version_file_path, OPEN_PG_TDE_DATA_DIR, KEYS_VERSION_FILE);

	fd = OpenTransientFile(version_file_path, O_RDWR | O_CREAT | O_TRUNC | PG_BINARY);

	if (pg_pwrite(fd, &curr_version, sizeof(keys_version_info), 0) != sizeof(keys_version_info))
	{
		/*
		 * The worst that may happen is that we will re-scan all *_keys on the
		 * next start. So a failed write isn't worth aborting the cluster
		 * start.
		 */
		ereport(WARNING,
				errcode_for_file_access(),
				errmsg("failed to write keys version file \"%s\": %m", version_file_path));
	}

	CloseTransientFile(fd);
}

/* Creates a tde directory for internal files if not exists */
static void
open_pg_tde_init_data_dir(void)
{
	if (access(OPEN_PG_TDE_DATA_DIR, F_OK) == -1)
	{
		if (MakePGDirectory(OPEN_PG_TDE_DATA_DIR) < 0)
			ereport(ERROR,
					errcode_for_file_access(),
					errmsg("could not create tde directory \"%s\": %m",
						   OPEN_PG_TDE_DATA_DIR));

		open_pg_tde_create_keys_version_file();
	}
}

/* Migrate *_keys files to the new format if needed. */
static void
open_pg_tde_migrate_internal_keys(void)
{
	char		version_file_path[MAXPGPATH] = {0};
	keys_version_info curr_version;
	int			fd;

	join_path_components(version_file_path, OPEN_PG_TDE_DATA_DIR, KEYS_VERSION_FILE);

	if (access(version_file_path, F_OK) == 0)
	{
		fd = OpenTransientFile(version_file_path, O_RDONLY | PG_BINARY);

		if (pg_pread(fd, &curr_version, sizeof(keys_version_info), 0) != sizeof(keys_version_info))
		{
			ereport(FATAL,
					errcode_for_file_access(),
					errmsg("internal keys version file \"%s\" is corrupted: %m", version_file_path),
					errhint("Try to remove the file and restart server."));
		}

		CloseTransientFile(fd);

		/* All is up-to-date, nothing to do */
		if (curr_version.smgr_version == OPEN_PG_TDE_SMGR_FILE_MAGIC &&
			curr_version.wal_version == OPEN_PG_TDE_WAL_KEY_FILE_MAGIC)
			return;
	}

	open_pg_tde_update_wal_keys_file();
	open_pg_tde_migrate_smgr_keys_file();

	open_pg_tde_create_keys_version_file();
}

/* Returns package version */
Datum
open_pg_tde_version(PG_FUNCTION_ARGS)
{
	PG_RETURN_TEXT_P(cstring_to_text(OPEN_PG_TDE_VERSION_STRING));
}

Datum
open_pg_tdeam_handler(PG_FUNCTION_ARGS)
{
	PG_RETURN_POINTER(GetHeapamTableAmRoutine());
}
