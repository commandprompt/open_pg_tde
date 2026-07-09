/*
 * GUC variables for open_pg_tde
 */

#include "postgres.h"

#include "utils/guc.h"

#include "encryption/enc_tde.h"
#include "keyring/keyring_api.h"
#include "open_pg_tde_guc.h"

bool		AllowInheritGlobalProviders = true;
bool		EncryptXLog = false;
bool		EnforceEncryption = false;
bool		RequireFips = false;
int			Cipher = CIPHER_AES_128;
int			KeyLength = KEY_DATA_SIZE_128;

/*
 * Cipher used to encrypt new data-file (relation) keys. -1 means "inherit",
 * i.e. follow open_pg_tde.cipher; any other value is a CipherType id and overrides
 * it. The chosen id is persisted per relation, so existing tables keep using
 * the cipher recorded at their creation. Data files default to AES-XTS, the
 * standard tweakable mode for storage encryption.
 */
#define DATA_CIPHER_INHERIT (-1)
int			DataCipher = CIPHER_AES_128_XTS;

/* Custom GUC variable */
static const struct config_enum_entry cipher_options[] = {
	{"aes_128", CIPHER_AES_128, false},
	{"aes_256", CIPHER_AES_256, false},
	{NULL, 0, false}
};

/*
 * Ciphers selectable for NEW data-file (relation) keys. Only the XTS variants
 * are offered: XTS is the tweakable mode designed for random-access block
 * storage. The non-tweakable AES-CBC modes are intentionally not selectable
 * here because, for a whole page at rest, their deterministic per-block IV
 * leaks the length of an unchanged leading prefix across successive versions of
 * a page and CBC is malleable. 'inherit' follows open_pg_tde.cipher for the key
 * strength (128 vs 256) but always maps to the XTS variant for data files (see
 * tde_smgr_data_cipher()). The CBC cipher implementations remain registered (see
 * cipher_provider.c) so relations already encrypted with a CBC data cipher
 * continue to decrypt; this list only governs the cipher chosen for a new key.
 */
static const struct config_enum_entry data_cipher_options[] = {
	{"inherit", DATA_CIPHER_INHERIT, false},
	{"aes_xts", CIPHER_AES_128_XTS, false},
	{"aes_256_xts", CIPHER_AES_256_XTS, false},
	{NULL, 0, false}
};

static void
assign_keys_size(int newval, void *extra)
{
	KeyLength = open_pg_tde_cipher_key_length(newval);
}

void
TdeGucInit(void)
{
	DefineCustomBoolVariable("open_pg_tde.inherit_global_providers",	/* name */
							 "Allow using global key providers for databases.", /* short_desc */
							 NULL,	/* long_desc */
							 &AllowInheritGlobalProviders,	/* value address */
							 true,	/* boot value */
							 PGC_SUSET, /* context */
							 0, /* flags */
							 NULL,	/* check_hook */
							 NULL,	/* assign_hook */
							 NULL	/* show_hook */
		);

	DefineCustomBoolVariable("open_pg_tde.wal_encrypt", /* name */
							 "Enable/Disable encryption of WAL.",	/* short_desc */
							 NULL,	/* long_desc */
							 &EncryptXLog,	/* value address */
							 false, /* boot value */
							 PGC_POSTMASTER,	/* context */
							 0, /* flags */
							 NULL,	/* check_hook */
							 NULL,	/* assign_hook */
							 NULL	/* show_hook */
		);

	DefineCustomBoolVariable("open_pg_tde.enforce_encryption",	/* name */
							 "Only allow the creation of encrypted tables.",	/* short_desc */
							 NULL,	/* long_desc */
							 &EnforceEncryption,	/* value address */
							 false, /* boot value */
							 PGC_SUSET, /* context */
							 0, /* flags */
							 NULL,	/* check_hook */
							 NULL,	/* assign_hook */
							 NULL	/* show_hook */
		);

	DefineCustomBoolVariable("open_pg_tde.require_fips",	/* name */
							 "Refuse to start unless OpenSSL is in FIPS mode.", /* short_desc */
							 "When on, open_pg_tde verifies at startup that the OpenSSL FIPS "
							 "provider is active and raises a fatal error otherwise, so that all "
							 "encryption uses FIPS-validated cryptography.",	/* long_desc */
							 &RequireFips,	/* value address */
							 false, /* boot value */
							 PGC_POSTMASTER,	/* context */
							 0, /* flags */
							 NULL,	/* check_hook */
							 NULL,	/* assign_hook */
							 NULL	/* show_hook */
		);

	DefineCustomEnumVariable("open_pg_tde.cipher",	/* name */
							 "TDE encryption algorithm.",	/* short_desc */
							 NULL,	/* long_desc */
							 &Cipher,	/* value address */
							 CIPHER_AES_128,	/* boot value */
							 cipher_options,	/* options */
							 PGC_SUSET, /* context */
							 0, /* flags */
							 NULL,	/* check_hook */
							 assign_keys_size,	/* assign_hook */
							 NULL	/* show_hook */
		);

	DefineCustomEnumVariable("open_pg_tde.data_cipher", /* name */
							 "Cipher used to encrypt new table data files.",	/* short_desc */
							 "'inherit' follows open_pg_tde.cipher; otherwise this overrides it for data files. "
							 "The chosen cipher is recorded per table at creation time.",	/* long_desc */
							 &DataCipher,	/* value address */
							 CIPHER_AES_128_XTS,	/* boot value */
							 data_cipher_options,	/* options */
							 PGC_SUSET, /* context */
							 0, /* flags */
							 NULL,	/* check_hook */
							 NULL,	/* assign_hook */
							 NULL	/* show_hook */
		);

}
