/*
 * GUC variables for pg_tde
 */

#include "postgres.h"

#include "utils/guc.h"

#include "encryption/enc_tde.h"
#include "keyring/keyring_api.h"
#include "pg_tde_guc.h"

bool		AllowInheritGlobalProviders = true;
bool		EncryptXLog = false;
bool		EnforceEncryption = false;
int			Cipher = CIPHER_AES_128;
int			KeyLength = KEY_DATA_SIZE_128;

/*
 * Cipher used to encrypt new data-file (relation) keys. -1 means "inherit",
 * i.e. follow pg_tde.cipher; any other value is a CipherType id and overrides
 * it. The chosen id is persisted per relation, so existing tables keep using
 * the cipher recorded at their creation.
 */
#define DATA_CIPHER_INHERIT (-1)
int			DataCipher = DATA_CIPHER_INHERIT;

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
	{NULL, 0, false}
};

static void
assign_keys_size(int newval, void *extra)
{
	KeyLength = pg_tde_cipher_key_length(newval);
}

void
TdeGucInit(void)
{
	DefineCustomBoolVariable("pg_tde.inherit_global_providers", /* name */
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

	DefineCustomBoolVariable("pg_tde.wal_encrypt",	/* name */
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

	DefineCustomBoolVariable("pg_tde.enforce_encryption",	/* name */
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

	DefineCustomEnumVariable("pg_tde.cipher",	/* name */
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

	DefineCustomEnumVariable("pg_tde.data_cipher",	/* name */
							 "Cipher used to encrypt new table data files.",	/* short_desc */
							 "'inherit' follows pg_tde.cipher; otherwise this overrides it for data files. "
							 "The chosen cipher is recorded per table at creation time.",	/* long_desc */
							 &DataCipher,	/* value address */
							 DATA_CIPHER_INHERIT,	/* boot value */
							 data_cipher_options,	/* options */
							 PGC_SUSET, /* context */
							 0, /* flags */
							 NULL,	/* check_hook */
							 NULL,	/* assign_hook */
							 NULL	/* show_hook */
		);

}
