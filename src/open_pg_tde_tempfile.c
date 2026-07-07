/*-------------------------------------------------------------------------
 *
 * open_pg_tde_tempfile.c
 *	  Encryption of temporary (query-spill) files.
 *
 * When open_pg_tde is loaded and the core GUC encrypt_temp_files is on, this
 * module installs the core temporary-file encryption hooks (see
 * storage/tempfile_crypt.h) and supplies the cipher and key.
 *
 * Temporary files (sorts, hashes, and other BufFile spills) never outlive the
 * cluster: they are removed on restart and after a crash. The key that
 * protects them therefore does not need to be persisted or recovered. This
 * module generates a random AES-128 internal key in the postmaster, held only
 * in memory and inherited by every backend through fork, so backends that
 * share a temporary file set (for example parallel workers) use the same key.
 * Because the key is never written to disk, temporary data on disk cannot be
 * recovered once the cluster stops, even with access to the storage media.
 *
 * The buffer transformation is AES-128-CBC per 8 kB block, with the IV derived
 * from the block's logical position, and a partial trailing sub-block masked
 * with an AES-ECB keystream so the ciphertext length equals the plaintext
 * length and file offsets are unchanged.
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#ifdef USE_TDE_HOOKS

#include <openssl/evp.h>
#include <openssl/err.h>

#include "miscadmin.h"
#include "storage/tempfile_crypt.h"

#include "open_pg_tde_tempfile.h"

#define TEMPFILE_KEY_LEN 16		/* AES-128 */
#define TEMPFILE_IV_LEN 16

static bool tempfile_key_ready = false;
static unsigned char tempfile_key[TEMPFILE_KEY_LEN];
static unsigned char tempfile_base_iv[TEMPFILE_IV_LEN];

static void tempfile_encrypt(char *data, int nbytes, int64 blocknum);
static void tempfile_decrypt(char *data, int nbytes, int64 blocknum);

static void
tempfile_ssl_error(const char *what)
{
	elog(FATAL, "open_pg_tde: temporary file %s failed: %s", what,
		 ERR_error_string(ERR_get_error(), NULL));
}

/*
 * Generate the ephemeral temporary-file key. Called once in the postmaster so
 * the key is inherited by all backends through fork.
 */
static void
tempfile_init_key(void)
{
	if (tempfile_key_ready)
		return;

	if (!pg_strong_random(tempfile_key, TEMPFILE_KEY_LEN) ||
		!pg_strong_random(tempfile_base_iv, TEMPFILE_IV_LEN))
		elog(FATAL, "open_pg_tde: could not generate temporary file key");

	tempfile_key_ready = true;
}

/* Derive a per-block IV by mixing the block position into the base IV. */
static void
tempfile_block_iv(int64 blocknum, unsigned char *iv)
{
	memcpy(iv, tempfile_base_iv, TEMPFILE_IV_LEN);
	for (int i = 0; i < 8; i++)
		iv[TEMPFILE_IV_LEN - 1 - i] ^= (unsigned char) (blocknum >> (8 * i));
}

static void
tempfile_run_cbc(int enc, const unsigned char *iv, unsigned char *buf, int len)
{
	EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
	int			outl;
	int			finall;

	if (ctx == NULL)
		tempfile_ssl_error("EVP_CIPHER_CTX_new");

	if (EVP_CipherInit_ex(ctx, EVP_aes_128_cbc(), NULL, tempfile_key, iv, enc) == 0 ||
		EVP_CIPHER_CTX_set_padding(ctx, 0) == 0 ||
		EVP_CipherUpdate(ctx, buf, &outl, buf, len) == 0 ||
		EVP_CipherFinal_ex(ctx, buf + outl, &finall) == 0)
	{
		EVP_CIPHER_CTX_free(ctx);
		tempfile_ssl_error("AES-128-CBC");
	}
	EVP_CIPHER_CTX_free(ctx);
	Assert(outl + finall == len);
}

/* AES-ECB of a single 16-byte block, used to mask a sub-block tail. */
static void
tempfile_ecb_block(const unsigned char *in16, unsigned char *out16)
{
	EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
	int			outl;

	if (ctx == NULL)
		tempfile_ssl_error("EVP_CIPHER_CTX_new");

	if (EVP_EncryptInit_ex(ctx, EVP_aes_128_ecb(), NULL, tempfile_key, NULL) == 0 ||
		EVP_CIPHER_CTX_set_padding(ctx, 0) == 0 ||
		EVP_EncryptUpdate(ctx, out16, &outl, in16, 16) == 0)
	{
		EVP_CIPHER_CTX_free(ctx);
		tempfile_ssl_error("AES-128-ECB");
	}
	EVP_CIPHER_CTX_free(ctx);
}

/*
 * Encrypt or decrypt one temporary-file buffer in place. Full 16-byte blocks
 * are transformed with CBC; a partial trailing sub-block is masked with an ECB
 * keystream so the length is preserved.
 */
static void
tempfile_crypt_buffer(int enc, char *data, int nbytes, int64 blocknum)
{
	unsigned char iv[TEMPFILE_IV_LEN];
	int			full = nbytes & ~15;
	int			rem = nbytes - full;

	if (nbytes <= 0)
		return;
	if (!tempfile_key_ready)
		tempfile_init_key();

	tempfile_block_iv(blocknum, iv);

	if (full > 0)
		tempfile_run_cbc(enc, iv, (unsigned char *) data, full);

	if (rem > 0)
	{
		unsigned char ks[16];
		unsigned char iv2[16];

		memcpy(iv2, iv, 16);
		iv2[0] ^= 0x80;
		tempfile_ecb_block(iv2, ks);
		for (int i = 0; i < rem; i++)
			data[full + i] ^= ks[i];
	}
}

static void
tempfile_encrypt(char *data, int nbytes, int64 blocknum)
{
	tempfile_crypt_buffer(1, data, nbytes, blocknum);
}

static void
tempfile_decrypt(char *data, int nbytes, int64 blocknum)
{
	tempfile_crypt_buffer(0, data, nbytes, blocknum);
}

/*
 * Install the temporary-file encryption hooks. Called from _PG_init in the
 * postmaster. The key is generated here so it is inherited by every backend.
 */
void
TdeTempFileInit(void)
{
	tempfile_init_key();
	temp_file_encrypt_hook = tempfile_encrypt;
	temp_file_decrypt_hook = tempfile_decrypt;
}

#endif							/* USE_TDE_HOOKS */
