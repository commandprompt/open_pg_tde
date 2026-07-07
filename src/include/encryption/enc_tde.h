/*
 * Encryption / Decryption of functions for TDE
 */

#ifndef ENC_TDE_H
#define ENC_TDE_H

#include "common/relpath.h"
#include "storage/block.h"

#define TDE_KEY_NAME_LEN 256
#define KEY_DATA_SIZE_128 16	/* 128 bit encryption */
#define KEY_DATA_SIZE_256 32	/* 256 bit encryption */
#define MAX_KEY_DATA_SIZE KEY_DATA_SIZE_256 /* maximum 256 bit encryption */

typedef enum CipherType
{
	CIPHER_AES_128,
	CIPHER_AES_256,
	CIPHER_AES_128_XTS,			/* AES-128-XTS, 32-byte key; data files only */
} CipherType;

extern uint32 open_pg_tde_cipher_key_length(CipherType cipher);

#define INTERNAL_KEY_MAX_LEN 32 /* Max size of an Internal Key */
#define INTERNAL_KEY_IV_LEN 16

typedef struct InternalKey
{
	uint32		key_len;
	CipherType	cipher;			/* which registered cipher this key uses */
	uint8		base_iv[INTERNAL_KEY_IV_LEN];
	uint8		key[INTERNAL_KEY_MAX_LEN];
} InternalKey;

extern void open_pg_tde_generate_internal_key(InternalKey *int_key, CipherType cipher);
extern void open_pg_tde_stream_crypt(const char *iv_prefix,
									 uint32 start_offset,
									 const char *data,
									 uint32 data_len,
									 char *out,
									 const uint8 *key,
									 int key_len,
									 void **ctxPtr);

extern void tde_decrypt_smgr_block(InternalKey *rel_key, ForkNumber forknum,
								   BlockNumber blocknum, const unsigned char *in,
								   unsigned char *out);
extern void tde_encrypt_smgr_block(InternalKey *rel_key, ForkNumber forknum,
								   BlockNumber blocknum, const unsigned char *in,
								   unsigned char *out);
#endif							/* ENC_TDE_H */
