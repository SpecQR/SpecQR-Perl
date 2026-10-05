# Optional independent GS1 oracle audit

Normal library and package tests require only Perl/core modules. These harnesses
are developer-only provenance tools for regenerating independent expectations.
They contain no Perl implementation imports and must be run against the exact
pinned source commits below. They do not fetch or publish anything.

## Source pins

- Historical unchanged corpus: `verification/fixtures/gs1-upstream.json`, originating from SpecQR TypeScript `15ad15e5c770ea0e39072f8f88b2733018f02ffd`.
- Nim oracle: `https://github.com/SpecQR/SpecQR-Nim`, commit `4f9154664d35a24cecb30b75cfdba0a9f16ced3e`; `src/specqr/gs1.nim` SHA-256 `9df6a11927f265108e4d01e3321a208e1bcd4f9c484ff6aad5f9b8bd42734fa3`.
- Current TypeScript oracle: `https://github.com/SpecQR/SpecQR`, commit `16efc6c0a8e397c9df3d051d20fce6c1eebdfad7`; the GS1 Digital Link source hash is recorded in `gs1-perl-deltas.json`.

The original corpus contains exactly 1,411 cases. Every case is executed; no
case ID is skipped. All `input` values in that corpus are strings. This harness
maps JSON options into the typed Nim API; explicit `pathAis: []` sets Nim's
`explicitPathAis` flag. Neither harness transforms expected outcomes.

## Run from the package root

Supply existing verified local checkouts of the pinned sources. Example:

```sh
nim c --path:/path/to/SpecQR-Nim/src \
  --nimcache:/tmp/specqr-gs1-oracle-cache \
  -o:/tmp/specqr-gs1-oracle verification/gs1/nim_oracle.nim
/tmp/specqr-gs1-oracle verification/fixtures/gs1-upstream.json > /tmp/gs1-nim.json
node verification/gs1/current_ts_oracle.mjs /path/to/SpecQR \
  verification/fixtures/gs1-upstream.json > /tmp/gs1-current-ts.json
prove -lv t/gs1.t
```

The evidence was generated with Nim 2.2.12 C backend and Node.js v24.19.0.
Compare all public payload/metadata fields and diagnostic code/reason/count.
For cross-language comparison only, omit optional null fields,
`length.isVariable`, empty success `errors`, and English diagnostic wording.
Native Perl tests separately require those additional metadata fields.

`verification/fixtures/gs1-perl-deltas.json` preserves every historical difference
with its exact independent Nim result, case ID, operation, explanation, and
reason bucket. It also contains the six independently observed current
TypeScript changes. The historical fixture file is unchanged and its SHA-256 is
gated by the test. Detailed current URL and diagnostics differences are public
in `docs/gs1.md`.

Results:

- Nim reference versus Perl: 1,411/1,411 contracts equal.
- Historical TypeScript versus Perl: 1,159 equal, 252 explicit profile/diagnostic differences.
- Current TypeScript versus Perl: 1,163 equal, 248 explicit profile/diagnostic differences.

The two TypeScript counts do not claim failures in supported ordinary GS1 data.
They expose the exact conservative URI, diagnostic, and current data-safety
contract boundaries rather than claiming full browser URL equivalence.
