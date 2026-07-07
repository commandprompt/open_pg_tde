-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "ALTER EXTENSION open_pg_tde UPDATE TO '2.1'" to load this file. \quit

CREATE FUNCTION open_pg_tde_add_database_key_provider_openbao(provider_name TEXT,
                                                openbao_url TEXT,
                                                openbao_mount_path TEXT,
                                                openbao_token_path TEXT,
                                                openbao_ca_path TEXT,
                                                openbao_namespace TEXT)
RETURNS VOID
LANGUAGE SQL
BEGIN ATOMIC
    SELECT open_pg_tde_add_database_key_provider('openbao', provider_name,
                            json_object('url' VALUE openbao_url,
                            'mountPath' VALUE openbao_mount_path,
                            'tokenPath' VALUE openbao_token_path,
                            'caPath' VALUE openbao_ca_path,
                            'namespace' VALUE openbao_namespace));
END;

CREATE FUNCTION open_pg_tde_add_global_key_provider_openbao(provider_name TEXT,
                                                        openbao_url TEXT,
                                                        openbao_mount_path TEXT,
                                                        openbao_token_path TEXT,
                                                        openbao_ca_path TEXT,
                                                        openbao_namespace TEXT)
RETURNS VOID
LANGUAGE SQL
BEGIN ATOMIC
    SELECT open_pg_tde_add_global_key_provider('openbao', provider_name,
                            json_object('url' VALUE openbao_url,
                            'mountPath' VALUE openbao_mount_path,
                            'tokenPath' VALUE openbao_token_path,
                            'caPath' VALUE openbao_ca_path,
                            'namespace' VALUE openbao_namespace));
END;

CREATE FUNCTION open_pg_tde_change_database_key_provider_openbao(provider_name TEXT,
                                                    openbao_url TEXT,
                                                    openbao_mount_path TEXT,
                                                    openbao_token_path TEXT,
                                                    openbao_ca_path TEXT,
                                                    openbao_namespace TEXT)
RETURNS VOID
LANGUAGE SQL
BEGIN ATOMIC
    SELECT open_pg_tde_change_database_key_provider('openbao', provider_name,
                            json_object('url' VALUE openbao_url,
                            'mountPath' VALUE openbao_mount_path,
                            'tokenPath' VALUE openbao_token_path,
                            'caPath' VALUE openbao_ca_path,
                            'namespace' VALUE openbao_namespace));
END;

CREATE FUNCTION open_pg_tde_change_global_key_provider_openbao(provider_name TEXT,
                                                           openbao_url TEXT,
                                                           openbao_mount_path TEXT,
                                                           openbao_token_path TEXT,
                                                           openbao_ca_path TEXT,
                                                           openbao_namespace TEXT)
RETURNS VOID
LANGUAGE SQL
BEGIN ATOMIC
    SELECT open_pg_tde_change_global_key_provider('openbao', provider_name,
                            json_object('url' VALUE openbao_url,
                            'mountPath' VALUE openbao_mount_path,
                            'tokenPath' VALUE openbao_token_path,
                            'caPath' VALUE openbao_ca_path,
                            'namespace' VALUE openbao_namespace));
END;
