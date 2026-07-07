#!/bin/bash
#
# verify-gate.sh - prove the compile-time gate both ways on a patched tree.
#
# Builds the SAME patched PostgreSQL source twice:
#   1. hooks OFF  -> expect a clean PostgreSQL: initdb works, a plain workload
#                    runs, and the tde_heap access method is ABSENT.
#   2. hooks ON   -> expect open_pg_tde to load and encrypt tde_heap at rest.
#
# This is the regression test for the USE_TDE_HOOKS gate: flag-off must be
# indistinguishable from stock PostgreSQL, flag-on must encrypt.
#
# Usage:
#   verify-gate.sh <postgres-src-dir> <install-prefix> [--ext-build <dir>]
#
# <install-prefix> is wiped and rebuilt into for each variant. --ext-build is a
# configured meson build dir for the open_pg_tde extension (needed for the ON
# check); if omitted, the ON check only asserts the server starts with the hooks.
#
# Must run as a non-root user that can run initdb/postgres.
set -uo pipefail

src="${1:?usage: verify-gate.sh <postgres-src> <install-prefix> [--ext-build <dir>]}"
prefix="${2:?missing install-prefix}"
shift 2
extbuild=""
[ "${1:-}" = "--ext-build" ] && extbuild="${2:?}"

MANUAL="$src/src/include/pg_config_manual.h"
PASS=0; FAIL=0
ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

set_gate() { # $1 = on|off
	# Toggle the documented pg_config_manual.h switch (works without autoconf).
	sed -i -E 's@^#define USE_TDE_HOOKS 1@/* #define USE_TDE_HOOKS 1 */@' "$MANUAL"
	if [ "$1" = "on" ]; then
		perl -0pi -e 's{/\* #define USE_TDE_HOOKS 1 \*/}{#define USE_TDE_HOOKS 1}' "$MANUAL"
	fi
	echo -n "gate $1 -> USE_TDE_HOOKS active: "
	grep -c '^#define USE_TDE_HOOKS 1' "$MANUAL"
}

build() {
	echo "building (clean) ..."
	( cd "$src" && make clean >/dev/null 2>&1 && make -s -j"$(nproc)" && make install -s -j"$(nproc)" ) \
		>/tmp/verify-gate-build.log 2>&1
	return $?
}

start_pg() { # $1 datadir  $2 port  [preload]
	local d="$1" port="$2" preload="${3:-}"
	rm -rf "$d"; "$prefix/bin/initdb" -D "$d" -A trust >/dev/null 2>&1 || return 1
	echo "port=$port" >> "$d/postgresql.conf"
	[ -n "$preload" ] && echo "shared_preload_libraries='$preload'" >> "$d/postgresql.conf"
	"$prefix/bin/pg_ctl" -D "$d" -o "-p $port" -l "$d/pg.log" -w start >/dev/null 2>&1
}
q() { "$prefix/bin/psql" -p "$1" -d postgres -tAqc "$2" 2>/dev/null; }

echo "=== variant 1: hooks OFF (expect clean PostgreSQL) ==="
set_gate off
if build; then
	if start_pg /tmp/gate_off 55501; then
		[ "$(q 55501 "CREATE TABLE t(x int); INSERT INTO t VALUES(1); SELECT count(*) FROM t")" = "1" ] \
			&& ok "plain workload runs" || bad "plain workload"
		[ "$(q 55501 "SELECT count(*) FROM pg_am WHERE amname='tde_heap'")" = "0" ] \
			&& ok "tde_heap access method absent (clean PG)" || bad "tde_heap present in clean build"
		"$prefix/bin/pg_ctl" -D /tmp/gate_off stop -m immediate >/dev/null 2>&1
	else bad "clean build did not initdb/start"; fi
else bad "OFF build failed (see /tmp/verify-gate-build.log)"; fi

echo "=== variant 2: hooks ON (expect encryption) ==="
set_gate on
if build; then
	[ -n "$extbuild" ] && ( cd "$extbuild/.." 2>/dev/null; meson install -C "$extbuild" >/dev/null 2>&1 )
	if start_pg /tmp/gate_on 55502 "${extbuild:+open_pg_tde}"; then
		ok "server starts with hooks compiled in"
		if [ -n "$extbuild" ]; then
			rm -f /tmp/gate_kr.per
			q 55502 "CREATE EXTENSION open_pg_tde" >/dev/null
			q 55502 "SELECT open_pg_tde_add_database_key_provider_file('kp','/tmp/gate_kr.per')" >/dev/null
			q 55502 "SELECT open_pg_tde_create_key_using_database_key_provider('k','kp')" >/dev/null
			q 55502 "SELECT open_pg_tde_set_key_using_database_key_provider('k','kp')" >/dev/null
			q 55502 "CREATE TABLE secret(s text) USING tde_heap; INSERT INTO secret VALUES('GATE_CANARY_x'); CHECKPOINT" >/dev/null
			[ "$(q 55502 "SELECT open_pg_tde_is_encrypted('secret')")" = "t" ] \
				&& ok "tde_heap reports encrypted" || bad "tde_heap not encrypted"
			f="$(q 55502 "SELECT pg_relation_filepath('secret')")"
			if grep -a -q GATE_CANARY "/tmp/gate_on/$f"; then bad "plaintext on disk"; else ok "ciphertext on disk"; fi
		fi
		"$prefix/bin/pg_ctl" -D /tmp/gate_on stop -m immediate >/dev/null 2>&1
	else bad "ON build did not start"; fi
else bad "ON build failed (see /tmp/verify-gate-build.log)"; fi

echo "=== gate verification: $PASS passed, $FAIL failed ==="
exit $((FAIL > 0 ? 1 : 0))
