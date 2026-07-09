/*
 * KMIP based keyring provider
 */

#include "postgres.h"

#include <openssl/err.h>
#include <openssl/ssl.h>
#include <openssl/x509v3.h>

#include "keyring/keyring_api.h"
#include "keyring/keyring_kmip.h"
#include "keyring/keyring_kmip_impl.h"

#ifdef FRONTEND
#include "open_pg_tde_fe.h"
#endif

#define MAX_LOCATE_LEN 128

static void set_key_by_name(GenericKeyring *keyring, KeyInfo *key);
static KeyInfo *get_key_by_name(GenericKeyring *keyring, const char *key_name, KeyringReturnCode *return_code);
static void validate(GenericKeyring *keyring);

static const TDEKeyringRoutine keyringKmipRoutine = {
	.keyring_get_key = get_key_by_name,
	.keyring_store_key = set_key_by_name,
	.keyring_validate = validate,
};

void
InstallKmipKeyring(void)
{
	RegisterKeyProviderType(&keyringKmipRoutine, KMIP_KEY_PROVIDER);
}

typedef struct KmipCtx
{
	SSL_CTX    *ssl;
	BIO		   *bio;
} KmipCtx;

static bool
kmipSslConnect(KmipCtx *ctx, KmipKeyring *kmip_keyring, bool throw_error)
{
	SSL		   *ssl = NULL;
	X509_VERIFY_PARAM *vpm;
	int			level = throw_error ? ERROR : WARNING;

	ctx->ssl = SSL_CTX_new(SSLv23_method());

	/*
	 * Require TLS 1.2 or newer. The principal key travels over this
	 * connection, so the obsolete SSLv3/TLS1.0/1.1 protocols must not be
	 * negotiated.
	 */
	SSL_CTX_set_min_proto_version(ctx->ssl, TLS1_2_VERSION);

	/*
	 * Verify the KMIP server's certificate against the configured CA. Without
	 * this OpenSSL defaults to SSL_VERIFY_NONE, which completes the handshake
	 * with any certificate and lets a network man-in-the-middle impersonate
	 * the KMIP server and capture or serve principal keys. The hostname/IP
	 * check below is only meaningful once SSL_VERIFY_PEER is set.
	 */
	SSL_CTX_set_verify(ctx->ssl, SSL_VERIFY_PEER, NULL);

	if (SSL_CTX_use_certificate_file(ctx->ssl, kmip_keyring->kmip_cert_path, SSL_FILETYPE_PEM) != 1)
	{
		SSL_CTX_free(ctx->ssl);
		ereport(level, errmsg("SSL error: Loading the client certificate failed"));
		return false;
	}

	if (SSL_CTX_use_PrivateKey_file(ctx->ssl, kmip_keyring->kmip_key_path, SSL_FILETYPE_PEM) != 1)
	{
		SSL_CTX_free(ctx->ssl);
		ereport(level, errmsg("SSL error: Loading the client key failed"));
		return false;
	}

	if (SSL_CTX_load_verify_locations(ctx->ssl, kmip_keyring->kmip_ca_path, NULL) != 1)
	{
		SSL_CTX_free(ctx->ssl);
		ereport(level, errmsg("SSL error: Loading the CA certificate failed"));
		return false;
	}

	ctx->bio = BIO_new_ssl_connect(ctx->ssl);
	if (ctx->bio == NULL)
	{
		SSL_CTX_free(ctx->ssl);
		ereport(level, errmsg("SSL error: BIO_new_ssl_connect failed"));
		return false;
	}

	BIO_get_ssl(ctx->bio, &ssl);
	SSL_set_mode(ssl, SSL_MODE_AUTO_RETRY);

	/*
	 * Bind the expected identity so OpenSSL rejects a valid certificate
	 * issued for a different host. kmip_host may be an IP literal (the common
	 * case) or a DNS name: X509_VERIFY_PARAM_set1_ip_asc() parses and matches
	 * IP address SANs, and only when the value is not a valid IP do we fall
	 * back to DNS name matching. Exactly one of the two is applied because
	 * the value is either an IP address or a name; the if/else below sets
	 * only the matching check (they are stored in independent fields, so a
	 * stray call to both would require the certificate to satisfy both at
	 * once).
	 */
	vpm = SSL_get0_param(ssl);
	if (X509_VERIFY_PARAM_set1_ip_asc(vpm, kmip_keyring->kmip_host) != 1)
	{
		if (X509_VERIFY_PARAM_set1_host(vpm, kmip_keyring->kmip_host, 0) != 1)
		{
			BIO_free_all(ctx->bio);
			SSL_CTX_free(ctx->ssl);
			ereport(level, errmsg("SSL error: could not set expected KMIP host name"));
			return false;
		}
	}

	BIO_set_conn_hostname(ctx->bio, kmip_keyring->kmip_host);
	BIO_set_conn_port(ctx->bio, kmip_keyring->kmip_port);

	/*
	 * With SSL_VERIFY_PEER set, BIO_do_connect() already fails if the
	 * certificate chain or the host identity does not verify. The explicit
	 * SSL_get_verify_result() check below is defense in depth against a
	 * future refactor that might weaken the handshake path.
	 */
	if (BIO_do_connect(ctx->bio) != 1)
	{
		BIO_free_all(ctx->bio);
		SSL_CTX_free(ctx->ssl);
		ereport(level, errmsg("SSL error: BIO_do_connect failed"));
		return false;
	}

	if (SSL_get_verify_result(ssl) != X509_V_OK)
	{
		BIO_free_all(ctx->bio);
		SSL_CTX_free(ctx->ssl);
		ereport(level, errmsg("SSL error: KMIP server certificate verification failed"));
		return false;
	}

	return true;
}

static void
set_key_by_name(GenericKeyring *keyring, KeyInfo *key)
{
	KmipCtx		ctx;
	KmipKeyring *kmip_keyring = (KmipKeyring *) keyring;
	int			result;

	kmipSslConnect(&ctx, kmip_keyring, true);

	result = open_pg_tde_kmip_set_by_name(ctx.bio, key->name, key->data.data, key->data.len);

	BIO_free_all(ctx.bio);
	SSL_CTX_free(ctx.ssl);

	if (result != 0)
		ereport(ERROR, errmsg("KMIP server reported error on register symmetric key: %i", result));
}

static KeyInfo *
get_key_by_name(GenericKeyring *keyring, const char *key_name, KeyringReturnCode *return_code)
{
	KeyInfo    *key = NULL;
	KmipKeyring *kmip_keyring = (KmipKeyring *) keyring;
	char		id[MAX_LOCATE_LEN];
	KmipCtx		ctx;

	*return_code = KEYRING_CODE_SUCCESS;

	if (!kmipSslConnect(&ctx, kmip_keyring, false))
	{
		return NULL;
	}

	/* 1. locate key */

	{
		int			result;
		size_t		ids_found;

		result = open_pg_tde_kmip_locate_key(ctx.bio, key_name, &ids_found, id);

		if (result != 0)
		{
			*return_code = KEYRING_CODE_RESOURCE_NOT_AVAILABLE;
			BIO_free_all(ctx.bio);
			SSL_CTX_free(ctx.ssl);
			return NULL;
		}

		if (ids_found == 0)
		{
			BIO_free_all(ctx.bio);
			SSL_CTX_free(ctx.ssl);
			return NULL;
		}

		if (ids_found > 1)
		{
			ereport(WARNING, errmsg("KMIP server contains multiple results for key, ignoring"));
			*return_code = KEYRING_CODE_RESOURCE_NOT_AVAILABLE;
			BIO_free_all(ctx.bio);
			SSL_CTX_free(ctx.ssl);
			return NULL;
		}
	}

	/* 2. get key */

	key = palloc_object(KeyInfo);

	{
		char	   *keyp = NULL;
		int			result = open_pg_tde_kmip_get_key(ctx.bio, id, &keyp, (int *) &key->data.len);

		if (result != 0)
		{
			ereport(WARNING, errmsg("KMIP server LOCATEd key, but GET failed with %i", result));
			*return_code = KEYRING_CODE_RESOURCE_NOT_AVAILABLE;
			pfree(key);
			BIO_free_all(ctx.bio);
			SSL_CTX_free(ctx.ssl);
			return NULL;
		}

		if (key->data.len > sizeof(key->data.data))
		{
			ereport(WARNING, errmsg("keyring provider returned invalid key size: %d", key->data.len));
			*return_code = KEYRING_CODE_INVALID_KEY;
			pfree(key);
			BIO_free_all(ctx.bio);
			SSL_CTX_free(ctx.ssl);
			free(keyp);
			return NULL;
		}

		memset(key->name, 0, sizeof(key->name));
		memcpy(key->name, key_name, strnlen(key_name, sizeof(key->name) - 1));
		memcpy(key->data.data, keyp, key->data.len);
		free(keyp);
	}

	BIO_free_all(ctx.bio);
	SSL_CTX_free(ctx.ssl);

	return key;
}

static void
validate(GenericKeyring *keyring)
{
	KmipKeyring *kmip_keyring = (KmipKeyring *) keyring;
	KmipCtx		ctx;

	kmipSslConnect(&ctx, kmip_keyring, true);

	BIO_free_all(ctx.bio);
	SSL_CTX_free(ctx.ssl);
}
