# 検証とリリース手順 / Verification

This edition does not treat self-generated fixtures, a decoder's partial output, or a process that later fails as successful independent verification.

## Reproducible runtime profile

- Perl floor: 5.42.3; current stable: 5.44.0.
- Official source archives and SHA-256 values are pinned in `script/install_perl.py`.
- The profile is Linux x86-64. No unexecuted macOS/Windows lane is claimed.
- Runtime dependencies: only Perl core modules. Python, Node, Nayuki, ZXing-C++, ZXing Java, and image tooling are development-only verification assets.

Official references: [CPAN source distribution](https://www.cpan.org/src/), [Perl support policy](https://perldoc.perl.org/perlpolicy).

## Baselines and independent checks

The immediate source baselines are [SpecQR TS 16efc6c](https://github.com/SpecQR/SpecQR/commit/16efc6c0a8e397c9df3d051d20fce6c1eebdfad7) and [SpecQR Nim 4f91546](https://github.com/SpecQR/SpecQR-Nim/commit/4f9154664d35a24cecb30b75cfdba0a9f16ced3e). The Perl runtime is native implementation code, not a subprocess adapter to those editions.

Required gates:

1. Native tests for core arithmetic, capacities, Unicode, segments, optimizer, GS1, SA, and rendering under both exact runtimes.
2. Pinned public reference corpus: 5,610 records including generation, planning, capacity boundaries, and SA. Corpus bytes remain unchanged; exactly eight outdated high-level FNC1 percent expectations are replaced by an explicit overlay from the exact current TypeScript baseline. All other 5,602 public expectations remain unchanged, with no skipped records.
3. Unchanged pinned internal reference corpus: 4,576 records including all 65,536 GF products, Reed–Solomon cases, version/ECC/mask raw matrices, data and ECC codewords. Independent Nayuki-backed cases are identified in the corpus, not inferred from matching a related port.
4. The unchanged 1,411 GS1 historical requests against request-bound current TypeScript expectations: 80 restored positive targets, 168 exact residual contracts and five independently witnessed diagnostic migrations. All 49 shared authority/Digital Link operations and 139 extra current-TypeScript positives run. Original strict-authority inputs are retained with explicit assertion mapping; unsafe dot-path rejection remains required.
5. All 102 shared current FNC1/GS1/DPI/ECC regression records. Current TS safe percent escaping is tested rather than inheriting Nim's earlier byte-only fallback limitation.
6. Strict malformed-input and resource-boundary tests; independent optimizer checks; CLI Unicode, raw-byte, file and stdin/stdout behavior.
7. Independent C++ decoder tests against default scale-8 PNGs, verifying exact payload and SA metadata. PNG framing, checksums, RGBA dimensions, all pixels, and quiet zone are checked independently.
8. A separate Java strict-PNG lane. A detector `NotFound` is recorded as a detector limitation/failure, never relabeled successful decoding. The diagnostic lane does not replace the C++ required decode gate.
9. Fresh offline Makefile.PL installation into an isolated prefix and consumer process outside the source tree; installed library bytes must match the candidate.
10. Independent source review, sanitized publication inventory, exact public-commit CI, and a fresh public-source consumer.

## Harness integrity

The harness checks final exit status, response cardinality, JSON types, stderr policy, and absence of trailing output. It records input/output/source SHA-256 bindings and rejects source changes during a run. Negative controls include a valid prefix followed by exit failure, unwanted stderr, additional output, invalid/duplicate-key JSON, timeouts, and mismatched image framing. A test process still running is not a pass.

Generation tests that compare reference vectors are distinguished from independent decoder checks. A portability statement describes implementation design; only actual recorded platform/runtime runs support verified-platform claims.

## Running

Basic installed-package tests require only core Perl modules:

```sh
perl Makefile.PL
make test
```

Full source-bound verification uses `script/verify_native.py`, the checked-in fixture manifest, and the pinned tooling installer. See each script's `--help` for required paths. Development dependencies are isolated from package installation. CI runs the same required checks against its immutable checkout and uploads terminal evidence.

## Publication boundary

A new public GitHub repository is created only after review of the exact candidate and file inventory. Build trees, interpreter archives, caches, local account information, and private working files are not published. Publication is a source release only: no CPAN upload, registry publication, tag, or unrelated repository edit is included. Completion requires exact-commit hosted CI and the fresh public consumer to pass.

Terminal evidence is kept with the deliverable separately from runtime files. Claims and counts must come from completed receipts for the reviewed source hashes, not earlier development passes.
