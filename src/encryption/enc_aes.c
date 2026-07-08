#include "postgres.h"

#include <openssl/err.h>
#include <openssl/evp.h>

#include "encryption/enc_aes.h"
#include "encryption/cipher_provider.h"

#ifdef FRONTEND
#include "open_pg_tde_fe.h"
#endif

/* Implementation notes
 * =====================
 *
 * AES-CTR in a nutshell:
 * * Uses a counter, 0 for the first block, 1 for the next block, ...
 * * Encrypts the counter using AES-ECB
 * * XORs the data to the encrypted counter
 *
 * In our implementation, we want random access into any 16 byte part of the encrypted datafile.
 * This is doable with OpenSSL and directly using AES-CTR, by passing the offset in the correct format as IV.
 * Unfortunately this requires reinitializing the OpenSSL context for every seek, and that's a costly operation.
 * Initialization and then decryption of 8192 bytes takes just double the time of initialization and deecryption
 * of 16 bytes.
 *
 * To mitigate this, we reimplement AES-CTR using AES-ECB:
 * * We only initialize one ECB context per encryption key (e.g. table), and store this context
 * * When a new block is requested, we use this stored context to encrypt the position information
 * * And then XOR it with the data
 *
 * This is still not as fast as using 8k blocks, but already 2 orders of magnitude better than direct CTR with
 * 16 byte blocks.
 */

static const EVP_CIPHER *cipher_gcm_128 = NULL;
static const EVP_CIPHER *cipher_ctr_ecb_128 = NULL;

static const EVP_CIPHER *cipher_gcm_256 = NULL;
static const EVP_CIPHER *cipher_ctr_ecb_256 = NULL;

/*
 * A keyed cipher context together with the key and direction last loaded into
 * it. Expanding an AES key schedule is expensive, and on the data-page path the
 * key is constant for a whole relation while only the per-block IV/tweak
 * changes. These four contexts are shared across all relations of a given
 * cipher and key length, so caching the loaded key lets consecutive pages of
 * one relation (a sequential scan) re-key once instead of once per 8 KB page;
 * access that interleaves relations still re-keys per page but stays correct.
 * aes_ctx_prepare() re-keys only when the key or direction changes and
 * otherwise sets just the IV. The key copy lives no longer than the key
 * schedule the context already retains.
 */
typedef struct AesCtxCache
{
	EVP_CIPHER_CTX *ctx;
	unsigned char key[EVP_MAX_KEY_LENGTH];	/* last key loaded (XTS-256 = 64) */
	int			key_len;		/* 0 until a key has been loaded */
	int			enc;			/* last direction: 1 enc, 0 dec, -1 none */
} AesCtxCache;

static AesCtxCache ctx_cbc_128;
static AesCtxCache ctx_cbc_256;

/* AES-XTS uses a double-length key (two AES subkeys) and a 16-byte tweak. */
static AesCtxCache ctx_xts_128; /* AES-128-XTS, 32-byte key */
static AesCtxCache ctx_xts_256; /* AES-256-XTS, 64-byte key */

static EVP_CIPHER_CTX *
AesCbcInitCtx(const EVP_CIPHER *cipher, const char *name)
{
	EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();

	if (EVP_CipherInit_ex(ctx, cipher, NULL, NULL, NULL, 1) == 0)
		ereport(ERROR,
				errmsg("EVP_CipherInit_ex of %s failed. OpenSSL error: %s",
					   name, ERR_error_string(ERR_get_error(), NULL)));

	EVP_CIPHER_CTX_set_padding(ctx, 0);

	return ctx;
}

void
AesInit(void)
{
	/* Make sure we do not try to initialize crypto twice */
	Assert(cipher_gcm_128 == NULL);

	OPENSSL_init_crypto(OPENSSL_INIT_ADD_ALL_CIPHERS | OPENSSL_INIT_LOAD_CRYPTO_STRINGS, NULL);

	cipher_gcm_128 = EVP_aes_128_gcm();
	cipher_ctr_ecb_128 = EVP_aes_128_ecb();
	ctx_cbc_128.ctx = AesCbcInitCtx(EVP_aes_128_cbc(), "AES-128-CBC");
	ctx_cbc_128.enc = -1;

	cipher_gcm_256 = EVP_aes_256_gcm();
	cipher_ctr_ecb_256 = EVP_aes_256_ecb();
	ctx_cbc_256.ctx = AesCbcInitCtx(EVP_aes_256_cbc(), "AES-256-CBC");
	ctx_cbc_256.enc = -1;

	/* AesCbcInitCtx just wraps EVP_CipherInit_ex; it works for XTS too. */
	ctx_xts_128.ctx = AesCbcInitCtx(EVP_aes_128_xts(), "AES-128-XTS");
	ctx_xts_128.enc = -1;
	ctx_xts_256.ctx = AesCbcInitCtx(EVP_aes_256_xts(), "AES-256-XTS");
	ctx_xts_256.enc = -1;

	/* Register the built-in cipher suites that wrap the primitives above. */
	TdeCipherRegistryInit();
}

static void
AesEcbEncrypt(EVP_CIPHER_CTX **ctxPtr, const unsigned char *key, int key_len, const unsigned char *in, int in_len, unsigned char *out)
{
	int			out_len;
	const EVP_CIPHER *cipher;

	Assert(key_len == 16 || key_len == 32);
	cipher = key_len == 32 ? cipher_ctr_ecb_256 : cipher_ctr_ecb_128;

	if (*ctxPtr == NULL)
	{
		Assert(cipher != NULL);

		*ctxPtr = EVP_CIPHER_CTX_new();

		if (EVP_CipherInit_ex(*ctxPtr, cipher, NULL, key, NULL, 1) == 0)
			ereport(ERROR,
					errmsg("EVP_CipherInit_ex failed. OpenSSL error: %s", ERR_error_string(ERR_get_error(), NULL)));

		EVP_CIPHER_CTX_set_padding(*ctxPtr, 0);
	}
	else
		Assert(EVP_CIPHER_CTX_key_length(*ctxPtr) == key_len);

	if (EVP_CipherUpdate(*ctxPtr, out, &out_len, in, in_len) == 0)
		ereport(ERROR,
				errmsg("EVP_CipherUpdate failed. OpenSSL error: %s", ERR_error_string(ERR_get_error(), NULL)));

	Assert(out_len == in_len);
}

/*
 * Load key, direction, and IV into a cached context. Re-keying (which re-expands
 * the AES key schedule) happens only when the key or direction differs from what
 * the context already holds; otherwise only the IV/tweak is set. The key is
 * constant for a whole relation on the data-page path, so a sequential scan
 * re-keys once per relation rather than once per page.
 */
static void
aes_ctx_prepare(AesCtxCache *cc, int enc, const unsigned char *key, int key_len, const unsigned char *iv)
{
	/* The cached-key buffer is EVP_MAX_KEY_LENGTH; guard the memcmp/memcpy. */
	if (key_len < 0 || key_len > (int) sizeof(cc->key))
		ereport(ERROR,
				errmsg("unsupported key length %d for cached cipher context", key_len));

	if (cc->key_len == key_len && cc->enc == enc &&
		memcmp(cc->key, key, key_len) == 0)
	{
		/* Same key and direction: keep the key schedule, set only the IV. */
		if (EVP_CipherInit_ex(cc->ctx, NULL, NULL, NULL, iv, -1) == 0)
			ereport(ERROR,
					errmsg("EVP_CipherInit_ex failed. OpenSSL error: %s", ERR_error_string(ERR_get_error(), NULL)));
		return;
	}

	if (EVP_CipherInit_ex(cc->ctx, NULL, NULL, key, iv, enc) == 0)
		ereport(ERROR,
				errmsg("EVP_CipherInit_ex failed. OpenSSL error: %s", ERR_error_string(ERR_get_error(), NULL)));

	memcpy(cc->key, key, key_len);
	cc->key_len = key_len;
	cc->enc = enc;
}

/*
 * Used to encrypt or decrypt a page in shared buffers
 *
 * For performance reasons the cipher context is created once on startup and
 * re-used, re-keying only when the relation key changes (see aes_ctx_prepare).
 */
static void
AesRunCbc(int enc, const unsigned char *key, int key_len, const unsigned char *iv, const unsigned char *in, int in_len, unsigned char *out)
{
	int			out_len;
	int			out_len_final;
	AesCtxCache *cc;
	EVP_CIPHER_CTX *ctx;

	Assert(key_len == 16 || key_len == 32);
	cc = key_len == 32 ? &ctx_cbc_256 : &ctx_cbc_128;
	ctx = cc->ctx;

	Assert(ctx != NULL);
	Assert(in_len % EVP_CIPHER_CTX_block_size(ctx) == 0);

	aes_ctx_prepare(cc, enc, key, key_len, iv);

	if (EVP_CipherUpdate(ctx, out, &out_len, in, in_len) == 0)
		ereport(ERROR,
				errmsg("EVP_CipherUpdate failed. OpenSSL error: %s", ERR_error_string(ERR_get_error(), NULL)));

	if (EVP_CipherFinal_ex(ctx, out + out_len, &out_len_final) == 0)
		ereport(ERROR,
				errmsg("EVP_CipherFinal_ex failed. OpenSSL error: %s", ERR_error_string(ERR_get_error(), NULL)));

	/*
	 * We encrypt one block (16 bytes) Our expectation is that the result
	 * should also be 16 bytes, without any additional padding.
	 */
	out_len += out_len_final;
	Assert(in_len == out_len);
}

/*
 * AES-XTS variant of AesRunCbc, used to encrypt/decrypt a data page. XTS is a
 * tweakable block cipher intended for storage: the IV is used as the tweak
 * (the block's logical position) and, unlike CBC, no chaining crosses page
 * boundaries. The key holds the two AES subkeys XTS requires (32 bytes for
 * AES-128-XTS, 64 bytes for AES-256-XTS).
 */
static void
AesRunXts(int enc, const unsigned char *key, int key_len, const unsigned char *iv, const unsigned char *in, int in_len, unsigned char *out)
{
	int			out_len;
	int			out_len_final;
	AesCtxCache *cc = (key_len == 64) ? &ctx_xts_256 : &ctx_xts_128;
	EVP_CIPHER_CTX *ctx = cc->ctx;

	Assert(key_len == 32 || key_len == 64);
	Assert(ctx != NULL);

	aes_ctx_prepare(cc, enc, key, key_len, iv);

	if (EVP_CipherUpdate(ctx, out, &out_len, in, in_len) == 0)
		ereport(ERROR,
				errmsg("EVP_CipherUpdate failed. OpenSSL error: %s", ERR_error_string(ERR_get_error(), NULL)));

	if (EVP_CipherFinal_ex(ctx, out + out_len, &out_len_final) == 0)
		ereport(ERROR,
				errmsg("EVP_CipherFinal_ex failed. OpenSSL error: %s", ERR_error_string(ERR_get_error(), NULL)));

	out_len += out_len_final;
	Assert(in_len == out_len);
}

void
AesXtsEncrypt(const unsigned char *key, int key_len, const unsigned char *iv, const unsigned char *in, int in_len, unsigned char *out)
{
	AesRunXts(1, key, key_len, iv, in, in_len, out);
}

void
AesXtsDecrypt(const unsigned char *key, int key_len, const unsigned char *iv, const unsigned char *in, int in_len, unsigned char *out)
{
	AesRunXts(0, key, key_len, iv, in, in_len, out);
}

void
AesEncrypt(const unsigned char *key, int key_len, const unsigned char *iv, const unsigned char *in, int in_len, unsigned char *out)
{
	AesRunCbc(1, key, key_len, iv, in, in_len, out);
}

void
AesDecrypt(const unsigned char *key, int key_len, const unsigned char *iv, const unsigned char *in, int in_len, unsigned char *out)
{
	AesRunCbc(0, key, key_len, iv, in, in_len, out);
}

void
AesGcmEncrypt(const unsigned char *key, int key_len, const unsigned char *iv, int iv_len, const unsigned char *aad, int aad_len, const unsigned char *in, int in_len, unsigned char *out, unsigned char *tag, int tag_len)
{
	int			out_len;
	int			out_len_final;
	EVP_CIPHER_CTX *ctx;
	const EVP_CIPHER *cipher;

	Assert(key_len == 16 || key_len == 32);
	cipher = key_len == 32 ? cipher_gcm_256 : cipher_gcm_128;

	Assert(cipher != NULL);
	Assert(aad != NULL);
	Assert(in != NULL);
	Assert(out != NULL);
	Assert(in_len % EVP_CIPHER_block_size(cipher) == 0);

	ctx = EVP_CIPHER_CTX_new();

	if (EVP_EncryptInit_ex(ctx, cipher, NULL, NULL, NULL) == 0)
		ereport(ERROR,
				errmsg("EVP_EncryptInit_ex failed. OpenSSL error: %s", ERR_error_string(ERR_get_error(), NULL)));

	if (EVP_CIPHER_CTX_set_padding(ctx, 0) == 0)
		ereport(ERROR,
				errmsg("EVP_CIPHER_CTX_set_padding failed. OpenSSL error: %s", ERR_error_string(ERR_get_error(), NULL)));

	if (EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, iv_len, NULL) == 0)
		ereport(ERROR,
				errmsg("EVP_CTRL_GCM_SET_IVLEN failed. OpenSSL error: %s", ERR_error_string(ERR_get_error(), NULL)));

	if (EVP_EncryptInit_ex(ctx, NULL, NULL, key, iv) == 0)
		ereport(ERROR,
				errmsg("EVP_EncryptInit_ex failed. OpenSSL error: %s", ERR_error_string(ERR_get_error(), NULL)));

	if (EVP_EncryptUpdate(ctx, NULL, &out_len, (unsigned char *) aad, aad_len) == 0)
		ereport(ERROR,
				errmsg("EVP_CipherUpdate failed. OpenSSL error: %s", ERR_error_string(ERR_get_error(), NULL)));

	if (EVP_EncryptUpdate(ctx, out, &out_len, in, in_len) == 0)
		ereport(ERROR,
				errmsg("EVP_CipherUpdate failed. OpenSSL error: %s", ERR_error_string(ERR_get_error(), NULL)));

	if (EVP_EncryptFinal_ex(ctx, out + out_len, &out_len_final) == 0)
		ereport(ERROR,
				errmsg("EVP_CipherFinal_ex failed. OpenSSL error: %s", ERR_error_string(ERR_get_error(), NULL)));

	if (EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_GET_TAG, tag_len, tag) == 0)
		ereport(ERROR,
				errmsg("EVP_CTRL_GCM_GET_TAG failed. OpenSSL error: %s", ERR_error_string(ERR_get_error(), NULL)));

	/*
	 * We encrypt one block (16 bytes) Our expectation is that the result
	 * should also be 16 bytes, without any additional padding
	 */
	out_len += out_len_final;
	Assert(in_len == out_len);

	EVP_CIPHER_CTX_free(ctx);
}

bool
AesGcmDecrypt(const unsigned char *key, int key_len, const unsigned char *iv, int iv_len, const unsigned char *aad, int aad_len, const unsigned char *in, int in_len, unsigned char *out, unsigned char *tag, int tag_len)
{
	int			out_len;
	int			out_len_final;
	EVP_CIPHER_CTX *ctx;
	const EVP_CIPHER *cipher;

	Assert(key_len == 16 || key_len == 32);
	cipher = key_len == 32 ? cipher_gcm_256 : cipher_gcm_128;

	Assert(aad != NULL);
	Assert(in != NULL);
	Assert(out != NULL);
	Assert(in_len % EVP_CIPHER_block_size(cipher) == 0);

	ctx = EVP_CIPHER_CTX_new();

	if (EVP_DecryptInit_ex(ctx, cipher, NULL, NULL, NULL) == 0)
		ereport(ERROR,
				errmsg("EVP_EncryptInit_ex failed. OpenSSL error: %s", ERR_error_string(ERR_get_error(), NULL)));

	if (EVP_CIPHER_CTX_set_padding(ctx, 0) == 0)
		ereport(ERROR,
				errmsg("EVP_CIPHER_CTX_set_padding failed. OpenSSL error: %s", ERR_error_string(ERR_get_error(), NULL)));

	if (EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, iv_len, NULL) == 0)
		ereport(ERROR,
				errmsg("EVP_CTRL_GCM_SET_IVLEN failed. OpenSSL error: %s", ERR_error_string(ERR_get_error(), NULL)));

	if (EVP_DecryptInit_ex(ctx, NULL, NULL, key, iv) == 0)
		ereport(ERROR,
				errmsg("EVP_EncryptInit_ex failed. OpenSSL error: %s", ERR_error_string(ERR_get_error(), NULL)));

	if (EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_TAG, tag_len, tag) == 0)
		ereport(ERROR,
				errmsg("EVP_CTRL_GCM_SET_TAG failed. OpenSSL error: %s", ERR_error_string(ERR_get_error(), NULL)));

	if (EVP_DecryptUpdate(ctx, NULL, &out_len, aad, aad_len) == 0)
		ereport(ERROR,
				errmsg("EVP_CipherUpdate failed. OpenSSL error: %s", ERR_error_string(ERR_get_error(), NULL)));

	if (EVP_DecryptUpdate(ctx, out, &out_len, in, in_len) == 0)
		ereport(ERROR,
				errmsg("EVP_CipherUpdate failed. OpenSSL error: %s", ERR_error_string(ERR_get_error(), NULL)));

	if (EVP_DecryptFinal_ex(ctx, out + out_len, &out_len_final) == 0)
	{
		EVP_CIPHER_CTX_free(ctx);
		return false;
	}

	/*
	 * We encrypt one block (16 bytes) Our expectation is that the result
	 * should also be 16 bytes, without any additional padding
	 */
	out_len += out_len_final;
	Assert(in_len == out_len);

	EVP_CIPHER_CTX_free(ctx);

	return true;
}

/*
 * This function assumes that the out buffer is big enough: at least (blockNumber2 - blockNumber1) * 16 bytes
 */
void
AesCtrEncryptedZeroBlocks(void *ctxPtr, const unsigned char *key, int key_len, const char *iv_prefix, uint64_t blockNumber1, uint64_t blockNumber2, unsigned char *out)
{
	unsigned char *p;

	Assert(blockNumber2 >= blockNumber1);

	p = out;

	for (int32 j = blockNumber1; j < blockNumber2; ++j)
	{
		/*
		 * We have 16 bytes, and a 4 byte counter. The counter is the last 4
		 * bytes. Technically, this isn't correct: the byte order of the
		 * counter depends on the endianness of the CPU running it. As this is
		 * a generic limitation of Postgres, it's fine.
		 */
		memcpy(p, iv_prefix, 16 - sizeof(j));
		p += 16 - sizeof(j);
		memcpy(p, (char *) &j, sizeof(j));
		p += sizeof(j);
	}

	AesEcbEncrypt(ctxPtr, key, key_len, out, p - out, out);
}
