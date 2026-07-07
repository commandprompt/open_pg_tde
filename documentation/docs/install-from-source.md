# Install open_pg_tde on native PostgreSQL

`open_pg_tde` runs on **standard, upstream PostgreSQL 14 and later**. It does
not require a vendor fork of the server. Encryption is implemented through two
extensibility points that upstream PostgreSQL does not yet expose: a pluggable
storage manager (for data files) and a WAL storage manager (for the write-ahead
log). `open_pg_tde` provides these as a small, self-contained patch that you
apply to a stock PostgreSQL source tree before building.

The patch is gated behind a build flag, so a patched tree builds as clean,
unmodified PostgreSQL unless you explicitly enable the hooks.

## Overview

1. Apply the `open_pg_tde` core patch to a stock PostgreSQL source tree.
2. Build and install PostgreSQL with the hooks enabled (`--enable-tde-hooks`).
3. Build and install the `open_pg_tde` extension against that install.
4. Enable the extension and configure a key provider.

## Prerequisites

- A stock PostgreSQL 14+ source tree (a release tarball or a `REL_<major>_STABLE`
  checkout).
- A C toolchain, plus the usual PostgreSQL build dependencies.
- OpenSSL development headers (`libssl-dev` / `openssl-devel`).
- `meson` and `ninja` (to build the extension).

## Step 1: Apply the core patch

The patches are organized by PostgreSQL major version under
`patches/postgresql/<major>/` and applied with the bundled driver, which
auto-detects the tree's version:

```sh
patches/postgresql/apply.sh /path/to/postgresql-src
```

To preview without modifying the tree, add `--check`; to undo, add `--reverse`.

## Step 2: Build PostgreSQL with the hooks enabled

The hooks are compiled out by default. Enable them at configure time.

=== "meson"

    ```sh
    cd /path/to/postgresql-src
    meson setup build -Dtde_hooks=enabled -Dprefix=/usr/local/pg-tde
    ninja -C build install
    ```

=== "autoconf"

    ```sh
    cd /path/to/postgresql-src
    ./configure --enable-tde-hooks --prefix=/usr/local/pg-tde --with-openssl
    make -j"$(nproc)"
    make install
    ```

!!! note
    If your `configure` script was not regenerated after patching (for example,
    `autoconf` is unavailable), pass `CPPFLAGS="-DUSE_TDE_HOOKS"` to `configure`
    instead of `--enable-tde-hooks`, or uncomment the `USE_TDE_HOOKS` define in
    `src/include/pg_config_manual.h`.

To confirm a build has the hooks compiled in, the `USE_TDE_HOOKS` macro is
defined in `pg_config.h`. Without it, the binary behaves identically to
unpatched PostgreSQL.

## Step 3: Build and install the extension

Build `open_pg_tde` against the `pg_config` from the install you just created:

```sh
meson setup build-ext -Dpg_config=/usr/local/pg-tde/bin/pg_config
ninja -C build-ext install
```

## Step 4: Enable the extension

Add `open_pg_tde` to `shared_preload_libraries` and restart the server:

```sql
ALTER SYSTEM SET shared_preload_libraries = 'open_pg_tde';
```

```sh
pg_ctl -D /path/to/datadir restart
```

Then create the extension:

```sql
CREATE EXTENSION open_pg_tde;
```

!!! note
    The `open_pg_tde` frontend tools (`open_pg_tde_basebackup`,
    `open_pg_tde_rewind`, and so on) link against the server's shared libraries.
    If they are installed outside your default linker path, set
    `LD_LIBRARY_PATH=/usr/local/pg-tde/lib` when running them.

## Verifying the build

To prove the gate works both ways on a patched tree (hooks off builds clean
PostgreSQL; hooks on encrypts), run the bundled verification script:

```sh
patches/postgresql/verify-gate.sh /path/to/postgresql-src /usr/local/pg-tde \
    --ext-build build-ext
```

## Next steps

[Set up open_pg_tde](setup.md){.md-button}
[Learn about key management](global-key-provider-configuration/overview.md){.md-button}
[Validate your encryption setup](test.md){.md-button}
[Enable WAL encryption](wal-encryption.md){.md-button}
