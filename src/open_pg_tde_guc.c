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

static const struct config_enum_entry data_cipher_options[] = {
	{"inherit", DATA_CIPHER_INHERIT, false},
	{"aes_128", CIPHER_AES_128, false},
	{"aes_256", CIPHER_AES_256, false},
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
