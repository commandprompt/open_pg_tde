#!/bin/bash

set -e

SCRIPT_DIR="$(cd -- "$(dirname "$0")" >/dev/null 2>&1; pwd -P)"
INSTALL_DIR="$SCRIPT_DIR/../../pginst"
cd "$SCRIPT_DIR/../"

if ! test -f typedefs.list; then
  echo "typedefs.list doesn't exists, run dump-typedefs.sh first"
  exit 1
fi

cd ../postgres/src/tools/pg_bsd_indent
make install

cd "$SCRIPT_DIR/.."

export PATH=$SCRIPT_DIR/../../postgres/src/tools/pgindent/:$INSTALL_DIR/bin/:$PATH

# Check open_pg_tde with the fresh list extraxted from the object file.
# src/libkmip and fetools/ are vendored copies of third-party / upstream
# PostgreSQL code; keeping them close to their source matters more than
# pgindent conformance, so they are excluded.
pgindent --typedefs=typedefs.list \
	--excludes=<(printf 'src/libkmip\nfetools\n') "$@" .
