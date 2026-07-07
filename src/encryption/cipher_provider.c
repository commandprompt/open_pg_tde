/*
 * Pluggable cipher provider registry for pg_tde.
 *
 * See cipher_provider.h for the rationale. The built-in suites simply point at
 * the OpenSSL-backed primitives in enc_aes.c, so this layer is a dispatch seam
 * rather than a new implementation.
 */

#include "postgres.h"

#include "encryption/cipher_provider.h"
#include "encryption/enc_aes.h"
#include "encryption/enc_tde.h"		/* CipherType ids */

#ifdef FRONTEND
#include "pg_tde_fe.h"
#endif

#define MAX_TDE_CIPHERS 8

static TdeCipher tde_ciphers[MAX_TDE_CIPHERS];
static int	tde_cipher_count = 0;
static bool tde_cipher_registry_initialized = false;

static void
register_cipher(uint32_t id, const char *name, uint32_t key_len,
				TdeBlockCryptFn encrypt_block, TdeBlockCryptFn decrypt_block,
				TdeKeystreamFn keystream)
{
	Assert(tde_cipher_count < MAX_TDE_CIPHERS);

	tde_ciphers[tde_cipher_count].id = id;
	tde_ciphers[tde_cipher_count].name = name;
	tde_ciphers[tde_cipher_count].key_len = key_len;
	tde_ciphers[tde_cipher_count].encrypt_block = encrypt_block;
	tde_ciphers[tde_cipher_count].decrypt_block = decrypt_block;
	tde_ciphers[tde_cipher_count].keystream = keystream;
	tde_cipher_count++;
}

void
TdeCipherRegistryInit(void)
{
	if (tde_cipher_registry_initialized)
		return;

	/*
	 * Built-in AES suites. Data pages use AES-CBC (AesEncrypt/AesDecrypt) and
	 * the WAL/stream path uses AES-CTR (AesCtrEncryptedZeroBlocks). The key
	 * length selects AES-128 vs AES-256; the underlying primitives pick the
	 * matching OpenSSL cipher from the key length as well.
	 *
	 * To add another algorithm, register it here with its own name/key length
	 * and block/keystream implementations -- the enc_tde.c call sites resolve
	 * ciphers through this registry and need no changes.
	 */
	register_cipher(CIPHER_AES_128, "aes-128", 16, AesEncrypt, AesDecrypt, AesCtrEncryptedZeroBlocks);
	register_cipher(CIPHER_AES_256, "aes-256", 32, AesEncrypt, AesDecrypt, AesCtrEncryptedZeroBlocks);

	/*
	 * AES-128-XTS is a data-file (block) cipher only. It has no keystream, so
	 * it is never selected for the WAL/stream path (see TdeCipherByKeyLen).
	 */
	register_cipher(CIPHER_AES_128_XTS, "aes-128-xts", 32, AesXtsEncrypt, AesXtsDecrypt, NULL);

	tde_cipher_registry_initialized = true;
}

const TdeCipher *
TdeCipherByName(const char *name)
{
	for (int i = 0; i < tde_cipher_count; i++)
	{
		if (strcmp(tde_ciphers[i].name, name) == 0)
			return &tde_ciphers[i];
	}

	return NULL;
}

const TdeCipher *
TdeCipherByKeyLen(int key_len)
{
	/*
	 * Used only by the WAL/stream path, which needs a keystream cipher. Skip
	 * block-only ciphers (e.g. XTS) so a shared key length does not resolve to
	 * the wrong suite.
	 */
	for (int i = 0; i < tde_cipher_count; i++)
	{
		if (tde_ciphers[i].key_len == (uint32_t) key_len && tde_ciphers[i].keystream != NULL)
			return &tde_ciphers[i];
	}

	ereport(ERROR,
			errcode(ERRCODE_INTERNAL_ERROR),
			errmsg("no pg_tde keystream cipher registered for key length %d", key_len));

	return NULL;				/* keep the compiler happy */
}

const TdeCipher *
TdeCipherById(uint32_t id)
{
	for (int i = 0; i < tde_cipher_count; i++)
	{
		if (tde_ciphers[i].id == id)
			return &tde_ciphers[i];
	}

	ereport(ERROR,
			errcode(ERRCODE_INTERNAL_ERROR),
			errmsg("no pg_tde cipher registered for id %u", id));

	return NULL;				/* keep the compiler happy */
}
