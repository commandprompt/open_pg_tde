#!/bin/bash
#
# Apply the open_pg_tde core patches to a stock PostgreSQL source tree.
#
# Usage:
#   patches/postgresql/apply.sh /path/to/postgresql-src [--check] [--reverse]
#
# The script detects the PostgreSQL major version from the source tree and
# applies every patch under patches/postgresql/<major>/ in order. Patches are
# a maintained series: when a new PostgreSQL minor or major release lands, we
# rebase the series (git am --3way / patch), we do not re-extract from scratch.
#
# After applying, build with the hooks compiled OUT (clean PostgreSQL) by
# default, or compiled IN with:
#     ./configure --enable-tde-hooks ...        (autoconf)
#     meson setup -Dtde_hooks=enabled ...       (meson)
# See README.md.
set -euo pipefail

here="$(cd -- "$(dirname "$0")" >/dev/null 2>&1; pwd -P)"
src="${1:?usage: apply.sh <postgresql-src-dir> [--check] [--reverse]}"
shift || true

mode="apply"
for arg in "$@"; do
	case "$arg" in
		--check)   mode="check" ;;
		--reverse) mode="reverse" ;;
		*) echo "unknown option: $arg" >&2; exit 2 ;;
	esac
done

# Detect the major version from the configured version string.
if [ ! -f "$src/src/include/pg_config.h.in" ] && [ ! -f "$src/configure.ac" ]; then
	echo "error: $src does not look like a PostgreSQL source tree" >&2
	exit 2
fi
ver=$(sed -n "s/^AC_INIT(\[PostgreSQL\], \[\([0-9][0-9]*\).*/\1/p" "$src/configure.ac" 2>/dev/null | head -1)
[ -z "$ver" ] && ver=$(grep -oE 'PG_MAJORVERSION "[0-9]+"' "$src/src/include/pg_config.h" 2>/dev/null | grep -oE '[0-9]+' | head -1)
if [ -z "$ver" ]; then
	echo "error: could not detect the PostgreSQL major version of $src" >&2
	exit 2
fi

dir="$here/$ver"
if [ ! -d "$dir" ]; then
	echo "error: no patch series for PostgreSQL $ver (looked in $dir)" >&2
	echo "       supported: $(cd "$here" && ls -d [0-9]* 2>/dev/null | tr '\n' ' ')" >&2
	exit 2
fi

shopt -s nullglob
patches=("$dir"/*.patch)
if [ ${#patches[@]} -eq 0 ]; then
	echo "error: no *.patch files in $dir" >&2
	exit 2
fi

echo "PostgreSQL $ver: ${#patches[@]} patch(es) from $dir"
case "$mode" in
	check)   flags="-p1 --dry-run" ; order=("${patches[@]}") ;;
	reverse) flags="-p1 -R"        ; order=($(printf '%s\n' "${patches[@]}" | sort -r)) ;;
	apply)   flags="-p1"           ; order=("${patches[@]}") ;;
esac

for p in "${order[@]}"; do
	echo "  $mode $(basename "$p")"
	patch -d "$src" $flags < "$p"
done
echo "done ($mode)."
