# Design: authenticated page encryption (AES-GCM)

- Status: Proposed (not scheduled)
- Date: 2026-07-07
- Scope: add tamper detection to encrypted data pages by moving from a
  confidentiality-only mode (XTS/CBC) to an authenticated mode (AES-GCM), which
  stores a per-page authentication tag.

This is a scoping document for a future initiative. It proposes no code. It
exists so the cost and the hard problems are understood before anyone commits to
building it, and so it is not confused with the much smaller AES-256-XTS work
(`aes-256-xts.md`).

## Motivation and threat model

Today data pages are encrypted with XTS (or CBC), which provides
**confidentiality but not integrity**. An attacker who can write to the data
files can alter ciphertext, and the change is not detected on read: XTS decrypts
any input to some plaintext. Authenticated encryption (AES-GCM) attaches a
per-page authentication tag, so a modified or substituted page fails
verification on read.

This matters when the threat model includes an adversary who can tamper with
data at rest (a compromised storage layer, a malicious backup, a shared or
untrusted volume) and where silent corruption must be detected rather than
served. It is valuable hardening and is required by some compliance regimes. It
is not what a plain AES-256 key mandate asks for; that is addressed by
AES-256-XTS.

## Why this is hard

Unlike AES-256-XTS, which is a contained key-map change, authenticated pages
change the **page storage format** and introduce a nonce-management problem.

### 1. There is nowhere to put the tag

Pages are 8 kB and encryption is length-preserving today: the ciphertext is
exactly `BLCKSZ`, written in place. AES-GCM produces a 16-byte tag per page that
must be stored and retrieved atomically with the page. Options, all invasive:

- **A tag fork.** Store tags in a separate relation fork (like the free space
  map and visibility map). Adds an I/O per page access, fork lifecycle
  management, and a crash-consistency requirement between the page write and the
  tag write.
- **A side file per relation.** Similar trade-offs to a fork, outside the fork
  machinery.
- **Reserved space inside the page.** Shrinking the usable page size to hold the
  tag breaks the pervasive 8 kB assumption and the on-disk layout of every
  existing table. Not viable as a default.

Each option is a real storage-format change and needs a migration: existing
tables have no tags, so converting a table to authenticated encryption is a full
table rewrite (a tag cannot be added to an existing page in place).

### 2. Nonce reuse is catastrophic for GCM

GCM is a counter mode. Its security collapses (both confidentiality and
integrity) if a nonce is ever reused with the same key. Data pages are rewritten
in place many times. A nonce derived from `(relation, block number)`, which is
how the XTS tweak is derived today, would repeat on every rewrite of a block.
So GCM requires a nonce that is unique per write, not per position:

- A per-page write counter (an LSN-like value or an explicit counter) must be
  stored alongside the tag and fed into the nonce.
- That counter must be crash-consistent and monotonic across crashes and
  restarts, which pulls WAL into the design.

This is exactly why XTS, not GCM, is the standard for full-disk and
rewritable-block encryption. Adopting GCM at the page layer means taking on the
nonce-management problem that XTS avoids by construction.

### 3. Interaction with existing mechanisms

- **WAL.** Full-page images in WAL would also need tags, or a defined policy for
  how authenticated pages interact with WAL encryption.
- **Backups, pg_rewind, pg_basebackup.** Any tool that copies page files must
  copy tags consistently, or verification fails after a restore or rewind.
- **Checksums.** PostgreSQL page checksums already occupy the page header; the
  relationship between a data checksum and a cryptographic tag must be defined
  (the tag supersedes the checksum for tamper detection, but the checksum has
  other uses).

## Sketch of an approach (not a commitment)

If pursued, a plausible shape is:

1. A new relation fork holding one 16-byte tag plus a per-page nonce counter per
   block.
2. An authenticated cipher entry in the registry (AES-GCM) whose block operation
   also reads and writes the tag fork and manages the nonce counter.
3. WAL-logging of the nonce counter so it is crash-safe and monotonic.
4. A per-table opt-in (a new access method or a `data_cipher` value), with a
   table rewrite to convert existing data, since tags cannot be backfilled in
   place.
5. Backup and rewind tooling taught to carry the tag fork.

Each of these is a substantial piece. The realistic estimate is a multi-part
project, not a single change, which is why it is scoped separately here and left
unscheduled.

## Relationship to AES-256-XTS

AES-256-XTS (`aes-256-xts.md`) and authenticated pages are independent:

- AES-256-XTS changes the **key map** (a 64-byte key), needs no page-format
  change and no table rewrite, and is contained and low risk.
- Authenticated pages change the **page format** (per-page tag and nonce), need
  a table rewrite to adopt, and are a major project.

They should not be batched. AES-256-XTS closes a specific compliance gap now;
authenticated pages are a separate, larger hardening effort to be planned on its
own.

## Open questions

- Fork versus side file versus reserved page space for the tag: which trade-off
  is acceptable for the target deployments.
- Nonce source: dedicated counter versus reuse of an LSN-like value, and how to
  guarantee monotonicity across crashes.
- Whether authenticated encryption is a per-table option or a cluster policy.
- Performance cost of the extra I/O and the tag verification on the read path.
