# Contributing guide

Welcome to `open_pg_tde`, the Transparent Data Encryption extension for PostgreSQL, maintained by Command Prompt, Inc.

You can contribute in one of the following ways:

1. [Start a discussion or ask a question](https://github.com/commandprompt/open_pg_tde/discussions)
2. [Submit a bug report or a feature request](https://github.com/commandprompt/open_pg_tde/issues)
3. Submit a pull request with a code patch
4. Contribute to the documentation

## Coding standards

All code contributed to `open_pg_tde` must satisfy the [PostgreSQL coding conventions](https://www.postgresql.org/docs/current/source.html). This is a firm requirement, not a preference: C code must follow PostgreSQL's formatting, naming, error-reporting, and memory-management conventions, and both the core patch and the extension are held to the same standard as PostgreSQL itself. Run `pgindent` where applicable and match the style of the surrounding code.

## Submit a pull request

All bug reports, enhancements, and feature requests are tracked in [GitHub Issues](https://github.com/commandprompt/open_pg_tde/issues). Before you start, check the open issues and the [open pull requests](https://github.com/commandprompt/open_pg_tde/pulls) in case the change is already reported or in progress.

For feature requests and enhancements, open an issue that describes your idea so we can discuss the design before you invest in a large change.

Once the change is agreed:

1. [Fork](https://docs.github.com/en/github/getting-started-with-github/fork-a-repo) this repository.
2. Clone your fork.
3. Create a branch for your changes. If the change relates to an issue, include the issue number in the branch name, for example `123-encrypt-temp-files`.
4. Make your changes, following the [PostgreSQL coding conventions](https://www.postgresql.org/docs/current/source.html) (see [Coding standards](#coding-standards)).
5. Write documentation for user-facing changes. See [Write the docs](#write-the-docs).
6. Build and [test your changes locally](#run-local-tests).
7. Commit with a clear message. If the change relates to an issue, reference it in the body, for example `Fixes #123`. See the [commit message guidelines](https://gist.github.com/robertpainsi/b632364184e70900af4ab688decf6f53).
8. Open a pull request against [`commandprompt/open_pg_tde`](https://github.com/commandprompt/open_pg_tde).
9. A maintainer reviews your code and documentation. If everything is correct, we merge it. Otherwise, we follow up with questions or requests for changes.

### Run local tests

Build and install the extension against your patched PostgreSQL, then run the suite:

```sh
meson setup -Dpg_config=/path/to/postgresql/bin/pg_config ./build
meson install -C ./build
meson test -C ./build --print-errorlogs
```

Some tests need a KMIP server or OpenBao; set `PG_TEST_REQUIRE_COSMIAN_KMS=1` or `PG_TEST_REQUIRE_OPENBAO=1` to require them. The frontend tools link against the server libraries, so set `LD_LIBRARY_PATH=/path/to/postgresql/lib` when running the suite. See [Install from source](install-from-source.md) for how to build the patched PostgreSQL.

Tests also run automatically through GitHub Actions when you open a pull request.

## Contribute to documentation

The documentation is written in Markdown and built with [Material for MkDocs](https://squidfunk.github.io/mkdocs-material/). The source files are in the `documentation/docs` directory. You can [edit online via GitHub](#edit-documentation-online-via-github) or [edit locally](#edit-documentation-locally).

### Write the docs

When you add a feature, document it for users. Cover:

1. Feature description: what it is and why a user needs it.
2. User tasks: what a user can accomplish with it.
3. Functionality: how it works.
4. Setup requirements: preconditions, such as a configured Key Management System.
5. Setup steps: the commands and parameters, with examples and sample output.
6. Limitations and breaking changes: anything a user should know.

### Edit documentation online via GitHub

1. Open the source `.md` file on GitHub and click the edit (pencil) icon. GitHub creates a fork for you if needed.
2. Edit the page and review it on the **Preview** tab.
3. Commit to a new branch and open a pull request against [`commandprompt/open_pg_tde`](https://github.com/commandprompt/open_pg_tde).
4. A maintainer reviews the pull request and merges it once it is correct.

### Edit documentation locally

1. Fork and clone the repository:

    ```sh
    git clone git@github.com:<your-name>/open_pg_tde.git
    cd open_pg_tde
    git remote add upstream git@github.com:commandprompt/open_pg_tde.git
    ```

2. Create a branch for your changes:

    ```sh
    git checkout -b 123-doc-change
    ```

3. Make your changes and commit them.
4. Open a pull request against [`commandprompt/open_pg_tde`](https://github.com/commandprompt/open_pg_tde).

#### Preview the documentation locally

Install Material for MkDocs and the plugins the site uses from `documentation/requirements.txt`, then build or serve the site:

```sh
python3 -m venv .venv && . .venv/bin/activate
pip install -r documentation/requirements.txt
cd documentation
mkdocs build      # writes the static site to ./site
mkdocs serve      # or serve locally at http://127.0.0.1:8000
```

Open <http://127.0.0.1:8000> to review your changes. `mkdocs serve` rebuilds the site as you edit.

[MkDocs]: https://www.mkdocs.org/
[Markdown]: https://daringfireball.net/projects/markdown/
[Python]: https://www.python.org/downloads/
