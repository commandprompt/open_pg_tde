# OpenSSF Scorecard: review and improvement plan

Status as of 2026-07-16: **score 4.5 / 10** (scorecard v5.1.1, evaluated at
main commit 15616ca).

This is a planning document, not part of the documentation site. It reviews
each failing check and lists the work, ordered by score impact per unit of
effort. Scorecard weights checks by risk: High risk checks (Token-Permissions,
Branch-Protection, Code-Review, Vulnerabilities, Signed-Releases, Maintained)
move the aggregate score the most; Medium (Pinned-Dependencies, SAST, Fuzzing)
less; Low (CII-Best-Practices, License) least.

## Current results

| Check | Score | Notes |
| --- | --- | --- |
| Token-Permissions | 0 | 6 workflows have no top-level `permissions:`; docs.yml grants `contents: write` at top level |
| Branch-Protection | 0 | no protection on `main` |
| Code-Review | 0 | 0 of the last 30 changesets merged with an approving review |
| Signed-Releases | 0 | 2.3.0 and 2.4.0 tarballs unsigned, no provenance |
| Vulnerabilities | 9 | PYSEC-2026-89 / GHSA-5wmx-573v-2qwq: Python-Markdown, pulled unpinned by documentation/requirements.txt |
| Pinned-Dependencies | 1 | 18 of 20 GitHub-owned and 2 of 3 third-party actions not pinned by SHA; 1 unpinned pip install in docs.yml |
| SAST | 0 | no static analysis runs on commits (no CodeQL workflow in the fork) |
| Fuzzing | 0 | no fuzzing integration |
| CII-Best-Practices | 0 | not registered for the OpenSSF Best Practices badge |
| Maintained | 0 | repository is younger than 90 days; resolves on its own with continued activity |
| License | 9 | COPYRIGHT file present but not recognized as an OSI/FSF license text |
| Packaging | n/a | no publishing workflow detected; does not count against the score |

Passing already: Security-Policy, Dangerous-Workflow, Binary-Artifacts,
CI-Tests, Contributors, Dependency-Update-Tool.

## TODO, in priority order

### 1. Set least-privilege token permissions on all workflows (High risk, trivial) - DONE
Added a top-level `permissions: contents: read` to build-and-test.yml,
coverage.yml, matrix.yml, pgindent.yml, sanitizers.yml, and
tests-registered.yml. In docs.yml, moved `contents: write` from the top level
down to the deploy job and set the top level to `contents: read`. This takes
Token-Permissions from 0 to 9 or 10.
(Branch security/scorecard-token-permissions.)

### 2. Fix the known vulnerability in the docs toolchain (High risk, trivial)
`documentation/requirements.txt` lists `Markdown` with no version bound.
Pin it at or above the version that fixes GHSA-5wmx-573v-2qwq. While there,
pin the other docs requirements to majors or exact versions so the docs build
is reproducible.

### 3. Pin GitHub Actions by commit SHA (Medium risk, mechanical)
Replace every `uses: owner/action@vN` with `@<full-sha> # vN` across all eight
workflows. Dependabot (already detected by Scorecard) keeps SHA pins current,
so this costs nothing ongoing. Also pin the `pip install` in docs.yml
(requirements file with versions, or `--require-hashes`). Confirm the
dependency-update tool covers `github-actions` and `pip` ecosystems; add
`.github/dependabot.yml` if the current setup is repo-settings only.

### 4. Enable branch protection on main (High risk, settings only)
Require pull requests before merging, require the Check and build status
checks, require at least 1 approving review, and disallow force pushes and
deletions. Public repositories get branch protection for free. Note that part
of this check needs admin-token access to verify, so the public Scorecard run
may not award the full 10, but it moves from 0 either way.

### 5. Get approving reviews on PRs before merge (High risk, process)
Code-Review scores the last 30 changesets, so this recovers slowly: every
future PR should get a human approval before merge (self-merge without review
is what zeroes this). Requiring 1 approval in branch protection (item 4)
enforces it. With a small team this needs a second maintainer account
reviewing, since GitHub does not count self-approval.

### 6. Add a CodeQL workflow (Medium risk, small)
Add `.github/workflows/codeql.yml` running the C/C++ pack on pull_request and
push to main. Upstream Percona had CodeQL infra; the fork currently runs
none. This satisfies SAST (CodeQL on PRs is the exact pattern Scorecard looks
for). Follow item 1's permissions pattern (`security-events: write` at the job
level only).

### 7. Sign releases and attach provenance (High risk, next release) - SET UP for 2.5.0
Added `.github/workflows/sign-release.yml`: on `release: published` (and
`workflow_dispatch` with a tag input for back-signing), it signs each source
tarball and SHA256SUMS with cosign keyless (Sigstore, no stored key, GitHub
OIDC) and uploads a `<asset>.cosign.bundle` next to each. RELEASING.md now
documents this and the `cosign verify-blob` command. This keeps the existing
manual `gh release create` flow (maintainer cuts the release; signing is
automatic on publish).
Remaining/optional: the 2.3.0 and 2.4.0 releases are still unsigned - run the
workflow by hand against those tags to back-sign if we want the check to count
them among the last 5 releases sooner. Could also add
`actions/attest-build-provenance` for SLSA provenance later.

### 8. Register for the OpenSSF Best Practices badge (Low risk, small)
Register the project at bestpractices.dev and fill in the passing-level
questionnaire. Much of it (security policy, CI tests, docs site, released
versions) is already true. Even "in progress" (>= 25%) scores 2, passing
scores 10 on this check.

### 9. License recognition (Low risk, trivial)
Scorecard sees COPYRIGHT but cannot classify it as an OSI/FSF license. Add a
`LICENSE` file containing the PostgreSQL License text (SPDX: PostgreSQL) and
keep COPYRIGHT as is. 9 to 10, cosmetic.

### 10. Fuzzing (Medium risk, real work, longer term)
The crypto and key-parsing paths (keyring JSON options parsing, KMIP protocol
handling, WAL/page encryption round-trip) are good fuzz targets. Options, in
increasing effort: a `t/` style deterministic corpus test, a libFuzzer harness
built in CI (Scorecard detects libFuzzer usage), or applying to OSS-Fuzz.
Worth doing for its own sake given this is security software; schedule as a
proper task alongside the cloud KMS work rather than as scorecard polish.

### No action
- **Maintained**: scores 0 only because the repository is under 90 days old.
  It resolves automatically with ongoing commit activity.
- **Packaging**: becomes a real score once releases are built by a workflow
  (item 7).

## Expected outcome

Items 1 through 4 are one short PR plus repository settings and should land
the score around 6.5 to 7. Items 5 through 7 accrue over the next weeks and
releases and push it past 8. Fuzzing and the badge close the rest.
