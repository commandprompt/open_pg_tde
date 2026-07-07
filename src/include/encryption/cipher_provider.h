/*
 * Pluggable cipher provider interface for open_pg_tde.
 *
 * open_pg_tde encrypts data pages with a block cipher (AES-CBC) and the WAL /
 * streamed files with a CTR keystream (AES-CTR, implemented on top of ECB).
 * Historically both were hard-wired to AES with the key length (16 vs 32
 * bytes) selecting AES-128 vs AES-256.
 *
 * This interface introduces a small registry of named cipher "suites". Each
 * suite bundles the block-mode ops used for data pages and the keystream op
 * used for the WAL stream. All crypto in enc_tde.c dispatches through a
 * resolved TdeCipher instead of calling the AES primitives directly, so a new
 * algorithm can be added by registering another TdeCipher in
 * TdeCipherRegistryInit() -- no changes to the call sites.
 *
 * The built-in suites wrap the existing OpenSSL-backed primitives in
 * enc_aes.c, so registering them is behaviour-preserving.
 */

#ifndef CIPHER_PROVIDER_H
#define CIPHER_PROVIDER_H

#include <stdint.h>

/*
 * Block-mode encrypt/decrypt of one buffer (used for fixed-size data pages).
 * Signature intentionally matches AesEncrypt/AesDecrypt in enc_aes.h.
 */
typedef void (*TdeBlockCryptFn) (const unsigned char *key, int key_len,
								 const unsigned char *iv,
								 const unsigned char *in, int in_len,
								 unsigned char *out);

/*
 * Fill out[] with the CTR keystream for blocks [block1, block2) (used for the
 * WAL / streamed-file XOR path). Signature matches AesCtrEncryptedZeroBlocks.
 */
typedef void (*TdeKeystreamFn) (void *ctxPtr, const unsigned char *key, int key_len,
								const char *iv_prefix,
								uint64_t block1, uint64_t block2,
								unsigned char *out);

typedef struct TdeCipher
{
	uint32_t	id;				/* stable numeric id; persisted in the key map
								 * (map_entry->cipher) and the WAL key file,
								 * so ids must never be reused for a different
								 * algorithm. Matches the CipherType enum. */
	const char *name;			/* stable identifier, e.g. "aes-256" */
	uint32_t	key_len;		/* key length in bytes (16, 32, or 64) */

	/* Block mode for data pages (AES-CBC for the built-ins). */
	TdeBlockCryptFn encrypt_block;
	TdeBlockCryptFn decrypt_block;

	/* Keystream for the WAL/stream XOR path (AES-CTR for the built-ins). */
	TdeKeystreamFn keystream;
} TdeCipher;

/* Registers the built-in cipher suites. Idempotent; called from AesInit(). */
extern void TdeCipherRegistryInit(void);

/* Look up a registered cipher by name, or NULL if none matches. */
extern const TdeCipher *TdeCipherByName(const char *name);

/*
 * Look up a registered cipher by its stable id (the value persisted in the key
 * map / WAL key file). Raises an error if no suite matches. This is the
 * dispatch path used when encrypting/decrypting an existing relation, so the
 * cipher is chosen by what was recorded at key-creation time rather than by
 * key length.
 */
extern const TdeCipher *TdeCipherById(uint32_t id);

/*
 * Look up the registered cipher for a given key length. This preserves the
 * historical "key length selects the cipher" behaviour while routing through
 * the registry. Raises an error if no suite matches.
 */
extern const TdeCipher *TdeCipherByKeyLen(int key_len);

#endif							/* CIPHER_PROVIDER_H */
