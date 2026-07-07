# Releasing open_pg_tde

Releases are published on GitHub as one source tarball per supported PostgreSQL
major version, attached as release assets. Tarballs are build artifacts and are
not committed to the repository; they are produced from the tagged source by the
script below.

## Building the source tarballs

```sh
git submodule update --init            # libkmip must be checked out
ci_scripts/build-source-tarballs.sh dist
```

This writes `dist/open_pg_tde-<version>-pg16.tar.gz`, `-pg17.tar.gz`, and
`-pg18.tar.gz`. Each tarball is a complete source tree that includes:

- the extension source and build files,
- the `libkmip` submodule contents (which `git archive` does not include on its
  own), and
- only the `patches/postgresql/<major>/` core patch for that PostgreSQL major.

The version in the file name comes from the `version` field in `meson.build`.

To build from a tarball, apply its core patch to a matching stock PostgreSQL
source tree with `patches/postgresql/apply.sh`, build PostgreSQL with the hooks
enabled, and build the extension against that install. See
`documentation/docs/install-from-source.md`.

## Cutting a release

1. Bump the `version` in `meson.build` (for example `2.2.0` to `2.3.0`).
2. Add `documentation/docs/release-notes/release-notes-v<version>.md` and list it
   in the `nav` of `documentation/mkdocs.yml`.
3. Commit the version bump and release notes to `main`.
4. Tag the release commit and push the tag:

   ```sh
   git tag -a <version> -m "open_pg_tde <version>"
   git push origin <version>
   ```

5. Build the tarballs and their checksums:

   ```sh
   ci_scripts/build-source-tarballs.sh dist
   ( cd dist && sha256sum open_pg_tde-<version>-pg*.tar.gz > SHA256SUMS )
   ```

6. Create the GitHub release with the tarballs and checksums as assets:

   ```sh
   gh release create <version> --repo commandprompt/open_pg_tde \
     --title "open_pg_tde <version>" \
     --notes-file dist/RELEASE_BODY.md \
     dist/open_pg_tde-<version>-pg16.tar.gz \
     dist/open_pg_tde-<version>-pg17.tar.gz \
     dist/open_pg_tde-<version>-pg18.tar.gz \
     dist/SHA256SUMS
   ```

7. Verify the assets:

   ```sh
   gh release view <version> --repo commandprompt/open_pg_tde --json assets
   ```

Consumers verify a download with `sha256sum -c SHA256SUMS`.
