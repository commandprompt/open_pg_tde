# Performance

Transparent Data Encryption adds CPU work: pages are decrypted when read from
disk and encrypted when written. This page reports a baseline measurement so you
can reason about the cost. Treat the numbers as indicative. Encryption overhead
depends on the workload, the data-to-memory ratio, and the hardware, so measure
your own workload before sizing.

## What was measured

A single PostgreSQL 18 instance, comparing tables created with `tde_heap`
(encrypted) against the same tables created with `heap` (not encrypted). Only
table and index data encryption is exercised here; WAL encryption is a separate
setting and was left off in both configurations.

- pgbench, scale factor 30 (about 460 MB of data plus indexes)
- `shared_buffers = 2GB`, so the working set is resident in memory. This
  isolates the CPU cost of the encrypted access path from disk I/O.
- 8 concurrent clients, 4 threads
- Each configuration warmed up, checkpointed, then measured over three 20 second
  runs and averaged
- Container: 8 vCPU, AES-NI available (AES-128-XTS default cipher)

## Results

| Workload | Unencrypted (tps) | Encrypted (tps) | Difference |
| -------- | ----------------- | --------------- | ---------- |
| Read-write (TPC-B-like) | ~1,510 to 1,610 | ~1,650 to 1,670 | none measurable |
| Read-only (SELECT) | ~24,900 | ~20,700 | about 17% lower |

## Interpretation

- **Write-heavy workloads showed no measurable encryption overhead.** The
  TPC-B-like test is bounded by WAL, commit, and locking, not by cipher work, so
  the difference stayed within run-to-run variance.
- **Read-saturated workloads paid a measurable cost**, about 17% fewer
  transactions per second in this test. The read-only test drives the storage
  and buffer path hard, and that is where the encryption CPU cost shows up.
- **I/O-bound workloads will show more overhead than this test.** When the
  working set does not fit in memory, every page fetched from disk is decrypted,
  so the cost grows with the disk read rate. This baseline deliberately keeps the
  data resident to measure the CPU cost in isolation.

## Guidance

- Encryption cost is CPU. A CPU with AES hardware acceleration (AES-NI on x86,
  the crypto extensions on ARM) keeps it low; confirm your build uses it.
- AES-128-XTS (the default) is the least expensive data cipher. AES-256 variants
  use a longer key schedule and cost slightly more.
- Encrypt selectively. `tde_heap` is per table, so tables that do not hold
  sensitive data can stay on `heap` and avoid the cost entirely.
- Size `shared_buffers` so the hot set stays resident, which keeps decryption off
  the read path for cached pages.
