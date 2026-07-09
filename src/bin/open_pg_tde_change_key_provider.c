#include "postgres_fe.h"

#include "common/controldata_utils.h"
#include "common/logging.h"
#include "getopt_long.h"

#include "catalog/tde_global_space.h"
#include "catalog/tde_keyring.h"
#include "common/open_pg_tde_utils.h"
#include "open_pg_tde.h"

static const char *progname;

static void
usage(void)
{
	printf(_("%s changes the configuration of a open_pg_tde key provider\n\n"), progname);
	printf(_("Usage:\n"));
	printf(_("  %s [-D <datadir>] <dbOid> <provider_name> <new_provider_type> <provider_parameters...>\n\n"), progname);
	printf(_("  Where <new_provider_type> can be file, openbao or kmip\n\n"));
	printf(_("Depending on the provider type, the complete parameter list is:\n\n"));
	printf(_("open_pg_tde_change_key_provider [-D <datadir>] <dbOid> <provider_name> file <filename>\n"));
	printf(_("open_pg_tde_change_key_provider [-D <datadir>] <dbOid> <provider_name> openbao <url> <mount_path> <token_path> [<ca_path>]\n"));
	printf(_("open_pg_tde_change_key_provider [-D <datadir>] <dbOid> <provider_name> kmip <host> <port> <cert_path> <key_path> [<ca_path>]\n"));
	printf(_("\nUse dbOid %d for global key providers.\n\n"), GLOBAL_DATA_TDE_OID);
	printf(_("WARNING:\n"));
	printf(_("  This tool only changes the values, without properly XLogging the changes, or validating that keys can be fetched using them. Only use it in case the database is inaccessible and can't be started.\n"));
}

#define BUFFER_SIZE 1024

/*
 * Append src to buffer (capacity bufsize) and report whether it still fits.
 * strlcat never overflows and always NUL-terminates; it returns the length the
 * result would have had, so a return >= bufsize means the value was truncated
 * and the caller must treat the configuration as too long. Checking after every
 * append (rather than once at the end, as the previous strcat-based code did)
 * is what prevents a single over-long argument from overrunning the buffer
 * before the bound is tested.
 */
static bool
json_append(char *buffer, size_t bufsize, const char *src)
{
	return strlcat(buffer, src, bufsize) < bufsize;
}

static bool
build_json(char *buffer, size_t bufsize, int count,...)
{
	va_list		args;
	bool		ok = true;

	va_start(args, count);

	buffer[0] = '\0';
	ok = json_append(buffer, bufsize, "{");

	for (int i = 0; ok && i < count; ++i)
	{
		/*
		 * The key/value pairs are not JSON-escaped: the values are file paths
		 * and endpoints supplied by the operator running this offline tool,
		 * and a malformed result is rejected when the provider file is read
		 * back.
		 */
		const char *key = va_arg(args, const char *);
		const char *value = va_arg(args, const char *);

		bool		addQuotes = value == NULL || (value[0] != '{' && value[0] != '"');

		if (i != 0)
			ok = ok && json_append(buffer, bufsize, ",");

		ok = ok && json_append(buffer, bufsize, "\"");
		ok = ok && json_append(buffer, bufsize, key);
		ok = ok && json_append(buffer, bufsize, "\":");

		if (addQuotes)
			ok = ok && json_append(buffer, bufsize, "\"");
		if (value != NULL)
			ok = ok && json_append(buffer, bufsize, value);
		if (addQuotes)
			ok = ok && json_append(buffer, bufsize, "\"");
	}
	va_end(args);

	ok = ok && json_append(buffer, bufsize, "}");

	if (!ok)
	{
		pg_log_error("configuration too long");
		return false;
	}

	return true;
}

int
main(int argc, char *argv[])
{
	static struct option long_options[] = {
		{"pgdata", required_argument, NULL, 'D'},
		{NULL, 0, NULL, 0}
	};

	int			c;
	int			option_index;
	char	   *datadir = NULL;
	Oid			db_oid;
	char	   *provider_name;
	char	   *new_provider_type;

	/*
	 * The assembled JSON is ultimately stored in record.provider.options, so
	 * build_json() is bounded by that field's size (below), not by
	 * sizeof(json). The scratch buffer is a little larger so build_json() can
	 * detect and reject an over-long configuration rather than have it
	 * silently truncated on the way into the smaller destination.
	 */
	char		json[BUFFER_SIZE * 2] = {0};
	ControlFileData *controlfile;
	bool		crc_ok;
	char		tdedir[MAXPGPATH] = {0};
	char	   *cptr = tdedir;
	KeyringProviderRecordInFile record;

	pg_logging_init(argv[0]);
	set_pglocale_pgservice(argv[0], PG_TEXTDOMAIN("open_pg_tde_change_key_provider"));
	progname = get_progname(argv[0]);

	if (argc > 1)
	{
		if (strcmp(argv[1], "--help") == 0 || strcmp(argv[1], "-?") == 0)
		{
			usage();
			exit(0);
		}
		if (strcmp(argv[1], "--version") == 0 || strcmp(argv[1], "-V") == 0)
		{
			puts("open_pg_tde_change_key_provider (PostgreSQL) " PG_VERSION);
			exit(0);
		}
	}

	while ((c = getopt_long(argc, argv, "D:", long_options, &option_index)) != -1)
	{
		switch (c)
		{
			case 'D':
				datadir = optarg;
				break;
			default:
				/* getopt_long already emitted a complaint */
				pg_log_error_hint("Try \"%s --help\" for more information.", progname);
				exit(1);
		}
	}

	if (datadir == NULL)
	{
		datadir = getenv("PGDATA");

		/* If no datadir was specified, and none could be found, error out */
		if (datadir == NULL)
		{
			pg_log_error("no data directory specified");
			pg_log_error_hint("Try \"%s --help\" for more information.", progname);
			exit(1);
		}
	}

	if (argc - optind < 3)
	{
		pg_log_error("too few arguments");
		pg_log_error_hint("Try \"%s --help\" for more information.", progname);
		exit(1);
	}

	db_oid = atoi(argv[optind++]);
	provider_name = argv[optind++];
	new_provider_type = argv[optind++];

	if (strcmp("file", new_provider_type) == 0)
	{
		if (argc - optind != 1)
		{
			pg_log_error("wrong number of arguments for \"%s\"", new_provider_type);
			pg_log_error_hint("Try \"%s --help\" for more information.", progname);
			exit(1);
		}

		if (!build_json(json, sizeof(record.provider.options), 1, "path", argv[optind]))
		{
			exit(1);
		}
	}
	else if (strcmp("openbao", new_provider_type) == 0)
	{
		if (argc - optind != 3 && argc - optind != 4)
		{
			pg_log_error("wrong number of arguments for \"%s\"", new_provider_type);
			pg_log_error_hint("Try \"%s --help\" for more information.", progname);
			exit(1);
		}

		if (!build_json(json, sizeof(record.provider.options), 4,
						"url", argv[optind],
						"mountPath", argv[optind + 1],
						"tokenPath", argv[optind + 2],
						"caPath", (argc - optind > 3 ? argv[optind + 3] : "")))
		{
			exit(1);
		}
	}
	else if (strcmp("kmip", new_provider_type) == 0)
	{
		if (argc - optind != 4 && argc - optind != 5)
		{
			pg_log_error("wrong number of arguments for \"%s\"", new_provider_type);
			pg_log_error_hint("Try \"%s --help\" for more information.", progname);
			exit(1);
		}

		if (!build_json(json, sizeof(record.provider.options), 5,
						"host", argv[optind],
						"port", argv[optind + 1],
						"certPath", argv[optind + 2],
						"keyPath", argv[optind + 3],
						"caPath", argc - optind > 4 ? argv[optind + 4] : ""))
		{
			exit(1);
		}
	}
	else
	{
		pg_log_error("unknown provider type \"%s\"", new_provider_type);
		pg_log_error_hint("Try \"%s --help\" for more information.", progname);
		exit(1);
	}

	/*
	 * Check if cluster is running.  This way we can be sure we have no
	 * concurrent modifcations of the key providers.  Note that this doesn't
	 * guard against someone starting the cluster concurrently.
	 */
	controlfile = get_controlfile(datadir, &crc_ok);
	if (!crc_ok)
		pg_fatal("pg_control CRC value is incorrect");

	if (controlfile->state != DB_SHUTDOWNED &&
		controlfile->state != DB_SHUTDOWNED_IN_RECOVERY)
		pg_fatal("cluster must be shut down");

	pfree(controlfile);
	cptr = strcat(cptr, datadir);
	cptr = strcat(cptr, "/");
	cptr = strcat(cptr, OPEN_PG_TDE_DATA_DIR);
	open_pg_tde_set_data_dir(tdedir);

	if (get_keyring_info_file_record_by_name(provider_name, db_oid, &record) == false)
		pg_fatal("provder \"%s\" not found for database %u", provider_name, db_oid);

	record.provider.provider_type = get_keyring_provider_from_typename(new_provider_type);
	memset(record.provider.options, 0, sizeof(record.provider.options));
	strlcpy(record.provider.options, json, sizeof(record.provider.options));

	write_key_provider_info(&record, false);

	printf("Key provider updated successfully!\n");

	return 0;
}
