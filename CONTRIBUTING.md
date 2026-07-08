# Contributing guide

Welcome to `open_pg_tde`, Transparent Data Encryption for PostgreSQL, maintained by Command Prompt, Inc.

You can contribute in one of the following ways:

1. [Start a discussion or ask a question](https://github.com/commandprompt/open_pg_tde/discussions)
2. [Submit a bug report or a feature request](#submit-a-bug-report-or-a-feature-request)
3. [Submit a pull request (PR) with a code patch](#submit-a-pull-request)
4. [Contribute to the documentation](#documentation-contribution)

## Submit a bug report or a feature request

All bug reports, enhancements, and feature requests are tracked in [GitHub Issues](https://github.com/commandprompt/open_pg_tde/issues). If you found a bug, or you want to suggest a feature or an improvement, open an issue there.

Start by searching the open issues for a similar report. If someone has already reported it, add a reaction or a comment so we can gauge interest.

If there is no existing report, open a new issue and aim for a report that is:

* Reproducible: describe the steps to reproduce the problem, including the PostgreSQL major version.
* Unique: check that no existing issue already describes it.
* Scoped to a single bug: report one bug per issue.

For feature requests and enhancements, open an issue that describes your idea so we can discuss the design before you start on a large change.

## Submit a pull request

Before writing code, check the [open issues](https://github.com/commandprompt/open_pg_tde/issues) and [open pull requests](https://github.com/commandprompt/open_pg_tde/pulls) in case the change is already in progress.

Then:

1. [Fork](https://docs.github.com/en/github/getting-started-with-github/fork-a-repo) this repository.

2. Clone your fork.

3. Create a branch for your changes. If the change relates to an issue, include the issue number in the branch name, for example `123-encrypt-temp-files`.

4. Make your changes. Follow the [PostgreSQL coding standards](https://www.postgresql.org/docs/current/source.html) for C code.

5. Test your changes locally. See [Run tests](#run-tests).

6. If your change needs documentation, see [Documentation contribution](#documentation-contribution).

7. Commit your changes with a clear message. If the change relates to an issue, reference it in the body, for example `Fixes #123`. Follow this pattern:

    ```
    Short summary of the change

    Details of the change and why it is needed.
    ```

    See the [commit message guidelines](https://gist.github.com/robertpainsi/b632364184e70900af4ab688decf6f53) for more information.

8. Open a pull request against [`commandprompt/open_pg_tde`](https://github.com/commandprompt/open_pg_tde).

9. A maintainer will review your code. If everything is correct, we merge it. Otherwise, we will follow up with questions or requests for changes.

### Build open_pg_tde

`open_pg_tde` runs on upstream PostgreSQL 16 and later. You apply the `open_pg_tde` core patch to a PostgreSQL source tree, build it with the hooks enabled, and build the extension against that install.

To build from source you need:

* git
* Meson and Ninja
* gcc or clang
* OpenSSL development headers

See the [install from source guide](documentation/docs/install-from-source.md) for the full steps, and [`patches/postgresql/README.md`](patches/postgresql/README.md) for the core patch series and per-version status.

### Run tests

The tests live in the `sql` and `t` directories.

1. Build and install the extension against your patched PostgreSQL:

    ```sh
    meson setup -Dpg_config=/path/to/postgresql/bin/pg_config ./build
    meson install -C ./build
    ```

2. Run the suite:

    ```sh
    meson test -C ./build --print-errorlogs
    ```

    Some tests need a KMIP server or OpenBao; set `PG_TEST_REQUIRE_COSMIAN_KMS=1` or `PG_TEST_REQUIRE_OPENBAO=1` to require them. The frontend tools link against the server libraries, so set `LD_LIBRARY_PATH=/path/to/postgresql/lib` when running the suite.

Tests also run automatically through GitHub Actions when you open a pull request.

### Build the release tarballs

Maintainers cutting a release build one source tarball per supported PostgreSQL major with `ci_scripts/build-source-tarballs.sh` and publish them as GitHub release assets. See [RELEASING.md](RELEASING.md) for the full process.

## Documentation contribution

To contribute to the documentation, see the [contributing guide](documentation/docs/contribute.md).
