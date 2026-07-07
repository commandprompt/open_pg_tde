#!/bin/bash
#
# Fail if any TAP test file under t/ is not registered in meson.build's
# tap_tests list, or if a registered test file does not exist. Registered but
# unlisted tests silently never run, which is easy to introduce when resolving
# a merge conflict in the tap_tests array.
#
# Runs without a build; it only reads the repository.
set -euo pipefail

cd "$(cd -- "$(dirname "$0")" >/dev/null 2>&1; pwd -P)/.."

status=0

# Every t/*.pl must appear in the tap_tests list.
for f in t/*.pl; do
	if ! grep -qF "'$f'," meson.build; then
		echo "error: $f is not registered in meson.build (tap_tests)"
		status=1
	fi
done

# Every t/*.pl registered in tap_tests must exist on disk.
grep -oE "'t/[^']+\.pl'" meson.build | tr -d "'" | sort -u | while read -r t; do
	if [ ! -f "$t" ]; then
		echo "error: meson.build registers $t but the file does not exist"
		exit 1
	fi
done || status=1

if [ "$status" -eq 0 ]; then
	echo "OK: all t/*.pl tests are registered in meson.build."
fi
exit "$status"
