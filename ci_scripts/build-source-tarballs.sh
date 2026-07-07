#!/bin/bash
#
# Build one source tarball per supported PostgreSQL major version. Each tarball
# is a complete open_pg_tde source tree (including the libkmip submodule, which
# git archive does not include on its own) with patches/postgresql pruned to
# only the target major, so it carries exactly the core patch it needs.
#
# Usage: ci_scripts/build-source-tarballs.sh [output-dir]
# Output: <output-dir>/open_pg_tde-<version>-pg<major>.tar.gz  (default dist/)
set -euo pipefail

repo="$(cd -- "$(dirname "$0")" >/dev/null 2>&1; pwd -P)/.."
cd "$repo"

majors="16 17 18"
version=$(grep -oE "version: '[0-9]+\.[0-9]+\.[0-9]+'" meson.build | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
[ -n "$version" ] || { echo "could not determine version from meson.build" >&2; exit 1; }

outdir="${1:-dist}"
mkdir -p "$outdir"
outdir="$(cd "$outdir" && pwd)"

for major in $majors; do
	name="open_pg_tde-${version}-pg${major}"
	stage="$outdir/$name"
	rm -rf "$stage"
	mkdir -p "$stage"

	# Main repository source at HEAD.
	git archive --format=tar HEAD | tar -x -C "$stage"

	# The libkmip submodule (git archive omits submodule contents).
	if [ -e src/libkmip/.git ]; then
		git -C src/libkmip archive --format=tar HEAD | tar -x -C "$stage/src/libkmip"
	else
		echo "warning: src/libkmip submodule is not checked out; tarball will be incomplete" >&2
	fi

	# Keep only the target major's core patch series.
	for other in $majors; do
		[ "$other" = "$major" ] || rm -rf "$stage/patches/postgresql/$other"
	done

	tar --owner=0 --group=0 --sort=name -czf "$outdir/$name.tar.gz" -C "$outdir" "$name"
	rm -rf "$stage"
	echo "built $outdir/$name.tar.gz"
done
