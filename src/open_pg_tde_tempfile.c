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
 * module generates random keys in the postmaster, held only in memory and
 * inherited by every backend through fork, so backends that share a temporary
 * file set (for example parallel workers) use the same keys. Because the keys
 * are never written to disk, temporary data on disk cannot be recovered once
 * the cluster stops, even with access to the storage media.
 *
 * The buffer transformation is AES-128-XTS, keyed by the block's logical
 * position through the XTS tweak. XTS is length-preserving for any buffer of at
 * least one AES block (it uses ciphertext stealing for a non-block-multiple
 * length) and is safe when a block position is rewritten in place, which
 * temporary-file space reuse does. A buffer shorter than one AES block cannot
 * use XTS; such a tail is masked with an AES-128-CTR keystream instead. Both
 * XTS (NIST SP 800-38E) and CTR (SP 800-38A) are FIPS-approved modes, so with a
 * FIPS build of OpenSSL every temporary-file operation uses approved
 * cryptography. See documentation/docs/index/fips.md.
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

#define TEMPFILE_XTS_KEY_LEN 32 /* AES-128-XTS: two independent 128-bit keys */
#define TEMPFILE_CTR_KEY_LEN 16 /* AES-128-CTR, for sub-block tails */
#define TEMPFILE_IV_LEN 16
#define AES_BLOCK_LEN 16

static bool tempfile_key_ready = false;
static unsigned char tempfile_xts_key[TEMPFILE_XTS_KEY_LEN];
static unsigned char tempfile_ctr_key[TEMPFILE_CTR_KEY_LEN];
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
 * Generate the ephemeral temporary-file keys. Called once in the postmaster so
 * they are inherited by all backends through fork.
 */
static void
tempfile_init_key(void)
{
	if (tempfile_key_ready)
		return;

	if (!pg_strong_random(tempfile_xts_key, TEMPFILE_XTS_KEY_LEN) ||
		!pg_strong_random(tempfile_ctr_key, TEMPFILE_CTR_KEY_LEN) ||
		!pg_strong_random(tempfile_base_iv, TEMPFILE_IV_LEN))
		elog(FATAL, "open_pg_tde: could not generate temporary file key");

	tempfile_key_ready = true;
}

/* Derive a per-block IV (XTS tweak) by mixing the block position into the base. */
static void
tempfile_block_iv(int64 blocknum, unsigned char *iv)
{
	memcpy(iv, tempfile_base_iv, TEMPFILE_IV_LEN);
	for (int i = 0; i < 8; i++)
		iv[TEMPFILE_IV_LEN - 1 - i] ^= (unsigned char) (blocknum >> (8 * i));
}

/*
 * AES-128-XTS one buffer in place. The block position is the XTS tweak. len
 * must be at least one AES block; XTS uses ciphertext stealing for a length
 * that is not a block multiple, so the output length equals the input length.
 */
static void
tempfile_run_xts(int enc, const unsigned char *iv, unsigned char *buf, int len)
{
	EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
	int			outl;
	int			finall;

	if (ctx == NULL)
		tempfile_ssl_error("EVP_CIPHER_CTX_new");

	if (EVP_CipherInit_ex(ctx, EVP_aes_128_xts(), NULL, tempfile_xts_key, iv, enc) == 0 ||
		EVP_CIPHER_CTX_set_padding(ctx, 0) == 0 ||
		EVP_CipherUpdate(ctx, buf, &outl, buf, len) == 0 ||
		EVP_CipherFinal_ex(ctx, buf + outl, &finall) == 0)
	{
		EVP_CIPHER_CTX_free(ctx);
		tempfile_ssl_error("AES-128-XTS");
	}
	EVP_CIPHER_CTX_free(ctx);
	Assert(outl + finall == len);
}

/*
 * AES-128-CTR one buffer in place, for a tail shorter than one AES block. CTR
 * is its own inverse, so the same routine encrypts and decrypts.
 */
static void
tempfile_run_ctr(const unsigned char *iv, unsigned char *buf, int len)
{
	EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
	int			outl;
	int			finall;

	if (ctx == NULL)
		tempfile_ssl_error("EVP_CIPHER_CTX_new");

	if (EVP_EncryptInit_ex(ctx, EVP_aes_128_ctr(), NULL, tempfile_ctr_key, iv) == 0 ||
		EVP_CIPHER_CTX_set_padding(ctx, 0) == 0 ||
		EVP_EncryptUpdate(ctx, buf, &outl, buf, len) == 0 ||
		EVP_EncryptFinal_ex(ctx, buf + outl, &finall) == 0)
	{
		EVP_CIPHER_CTX_free(ctx);
		tempfile_ssl_error("AES-128-CTR");
	}
	EVP_CIPHER_CTX_free(ctx);
	Assert(outl + finall == len);
}

/*
 * Encrypt or decrypt one temporary-file buffer in place. A buffer of at least
 * one AES block is transformed with XTS; a shorter tail is masked with a CTR
 * keystream. The encrypt and decrypt directions must agree on the mode for a
 * given (blocknum, nbytes), which they do because a buffer is always read back
 * at the length it was written.
 */
static void
tempfile_crypt_buffer(int enc, char *data, int nbytes, int64 blocknum)
{
	unsigned char iv[TEMPFILE_IV_LEN];

	if (nbytes <= 0)
		return;
	if (!tempfile_key_ready)
		tempfile_init_key();

	tempfile_block_iv(blocknum, iv);

	if (nbytes >= AES_BLOCK_LEN)
		tempfile_run_xts(enc, iv, (unsigned char *) data, nbytes);
	else
		tempfile_run_ctr(iv, (unsigned char *) data, nbytes);
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
 * postmaster. The keys are generated here so they are inherited by every
 * backend.
 */
void
TdeTempFileInit(void)
{
	tempfile_init_key();
	temp_file_encrypt_hook = tempfile_encrypt;
	temp_file_decrypt_hook = tempfile_decrypt;
}

#endif							/* USE_TDE_HOOKS */
