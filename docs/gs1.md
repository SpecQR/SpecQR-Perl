# GS1 and GS1 Digital Link

`SpecQR::GS1` implements the entire bounded 50-AI SpecQR catalog with native
Perl and core modules. It performs no network access, DNS resolution, or
subprocess execution. Import individual helpers or `:all`:

```perl
use SpecQR::GS1 qw(:all);
my $elements = [
    { ai => '01', value => '09506000134352' },
    { ai => '10', value => 'LOT-A' },
    { ai => '17', value => '271231' },
];
my $raw = create_gs1_element_string($elements);
# "010950600013435210LOT-A\x1d17271231"
my $human = gs1_to_human_readable($elements);
# '(01)09506000134352(10)LOT-A(17)271231'
my $uri = create_gs1_digital_link($elements);
# 'https://id.gs1.org/01/09506000134352/10/LOT-A?17=271231'
my $parsed = parse_gs1_digital_link($uri);
```

## Inputs and return values

The supported runtime floor is Perl 5.42.3. Strings must be actual Perl string scalars,
not numbers, `undef`, objects, references, or coerced JSON booleans. Quote
AIs and numeric values to preserve leading zeroes. ASCII strings work with or
without Perl's Unicode flag. Non-ASCII text must be a Unicode character string,
not an unflagged UTF-8 byte buffer. Decode external bytes explicitly using
`Encode::decode('UTF-8', $bytes, Encode::FB_CROAK)` first. Invalid internal UTF-8,
surrogates, and code points above U+10FFFF are rejected.

Elements are unblessed, untied arrayrefs of unblessed, untied hashrefs containing
`ai` and `value`. Options are an optional hashref with camelCase keys. Unknown
option keys are rejected. Boolean options accept numeric `0`/`1` or
`JSON::PP` booleans, not strings. Omitted or `undef` options use defaults.
Tied argument scalars, array entries, and hash fields are rejected before
fetching them. Forged JSON boolean objects with an invalid underlying type or
value are rejected. Result hashes and metadata use camelCase keys, matching
SpecQR's other ports. Returned JSON booleans are independently owned
`JSON::PP::Boolean` scalar objects; changing one cannot alter the internal
catalog or a subsequent result.

`normalize_gs1_elements($input)` accepts an element array, a parse-result hash
with `elements`, or a string. Strings starting with `(` use human-readable
parsing; other strings use raw element-string parsing. All normalized elements
are fresh hashes. Catalog metadata is copied, including nested fields, so callers
cannot mutate the internal catalog.

## Catalog and field validation

`get_supported_gs1_ais()` returns all 50 metadata hashes.
`get_gs1_ai_info($ai)` returns one metadata hash or `undef` for an unsupported AI.
Each record has `ai`, `label`, `length`, `valueKind`, `checkDigitRule`,
`digitalLinkRole`, `separator`, and `digitalLinkPathForPrimary`.

- Fixed length: `{ type => 'fixed', exact => N, isVariable => false }`
- Variable length: `{ type => 'variable', min => 1, max => N, isVariable => true }`
- `digitalLinkPathForPrimary` is `['01']` for qualifiers and otherwise `undef`

Supported AIs:

- `00`, `01`, `02`, `10`, `11`, `12`, `13`, `15`, `16`, `17`, `20`, `21`, `22`, `30`, `37`
- `240`, `241`, `400`, `410`–`415`, `420`, `422`, `424`, `425`, `426`
- `3100`–`3105`, `3200`–`3205`, `91`–`99`

Checks cover fixed/variable lengths, numeric versus printable ASCII values,
GTIN/SSCC check digits, raw parentheses, and U+001D/FNC1 separators. All element
values must use printable ASCII. `%` is literal data here, not a placeholder for
FNC1. The QR encoding layer performs its own lossless FNC1 representation.

This is not comprehensive GS1 certification. Date AIs require six digits, not a
valid calendar date. GLN AIs `410`–`415` require 13 digits, consistent with this
shared catalog; GLN check digits and every GS1 AI combination rule are not checked.
Unsupported AIs cannot be silently enabled.

## Element strings

- `parse_gs1_human_readable($string)` returns an element array
- `parse_gs1_element_string($string)` returns `{ elements, hasSeparators }`
- `create_gs1_element_string($elements)` inserts U+001D after each nonfinal variable field
- `gs1_to_human_readable($elements)` adds AI parentheses
- `gs1_element_string_to_human_readable($raw)` parses and formats raw data

A nonfinal variable field must be separated. The parser uses SpecQR's
conservative ambiguity check: an apparent complete fixed-length AI suffix in
an unseparated final variable value is rejected as a missing separator, even if
the supposed suffix's data would fail its own numeric validation. This can reject
some otherwise printable terminal lot values; use a structured element array or
human-readable input when generating such values. Do not assume that every
possible raw variable field has an unambiguous parse.

Aliases: `gs1_normalize`, `gs1_from_human_readable`, `gs1_to_element_string`,
`gs1_build`, `gs1_parse`.

## Check digits

- `calculate_gs1_check_digit`, `validate_gs1_check_digit`
- `calculate_gtin_check_digit`, `append_gtin_check_digit`, `validate_gtin_check_digit`
- `calculate_sscc_check_digit`, `append_sscc_check_digit`, `validate_sscc_check_digit`

Calculation accepts the body without its check digit; validation accepts the
complete value. GTIN bodies have 7, 11, 12, or 13 digits; SSCC bodies have 17.
Malformed input throws. A correctly shaped number with a wrong check digit
returns false. The calculation uses GS1 modulo-10 with right-to-left weights 3, 1.

## Digital Link API

`create_gs1_digital_link($elements, \%options)` supports:

- `baseUrl`: defaults to `https://id.gs1.org`
- `primaryAi`: defaults to `'01'`; `'00'` and `'414'` are also supported
- `pathAis`: selected qualifier AIs; an explicit empty array puts all qualifiers in query
- `explicitPathAis`: numeric/JSON boolean; true uses an explicit selection even when `pathAis` is omitted

For primary `01`, qualifiers `10`, `21`, `22` enter the path by default. Other
values enter a query sorted lexicographically by AI and then value. Qualifier
path order follows input order. A `pathAis` selection may include the primary AI;
it does not change its position. Invalid path selections and duplicate AIs are
rejected. Dot-only qualifier values are always routed into query, even when
selected for the path. `gs1_digital_link` and `gs1_to_digital_link` are aliases.

`parse_gs1_digital_link($uri, \%options)` returns:

```perl
{
    elements     => [...], # path elements followed by known query elements
    primary      => { ai => '01', value => '...' },
    pathElements => [...],
    queryElements => [...],
    unknownQuery => [ { key => 'utm', value => 'campaign' }, ... ],
}
```

Options are `primaryAi` (default: discover the first literal `00`, `01`, or `414`
path segment) and `unknownQuery` (`'preserve'` or `'reject'`; default: preserve).
Unknown query duplicates and their order are retained. A numeric 2–4-character
query key is treated as an AI and must be supported; it is never silently reclassified
as unknown. An encoded primary-AI path segment is not used for discovery.

`normalize_gs1_digital_link($uri, \%options)` accepts the same options plus
`mode => 'specqr-deterministic'`, the only supported mode. It rebuilds known
fields deterministically, chooses default eligible qualifiers for the path,
sorts known query data, and appends unknown query pairs in their original order.
It is idempotent in its documented URL profile. Normalizing is not a promise that
all semantically equivalent IPv6 spellings become the same string.

## Explicit strict offline URL profile

This implements the current Nim SpecQR profile, not the full browser WHATWG URL
algorithm. It is not a safety check, a public-Internet eligibility check, or an
SSRF defense. Localhost, private addresses and loopback are accepted syntax.

Accepted authorities:

- ASCII DNS labels, including punycode labels and one trailing DNS dot; 1–63 characters per label, maximum 253 excluding that final dot
- Canonical four-component decimal IPv4, without leading zeroes or a trailing dot
- Bracketed RFC-style IPv6, including a canonical dotted-decimal IPv4 tail
- Decimal ports containing 1–5 digits in 0–65535; default HTTP/HTTPS ports are removed and other leading zeroes are normalized

DNS/scheme case and IPv6 hex case are normalized. IPv6 zero compression and
embedded IPv4 spelling are preserved rather than rewritten. No IDNA mapping,
DNS lookup, address resolution, or hostname reachability test is performed.

Rejected forms include credentials, raw non-ASCII hosts, percent-encoded hosts,
IPv6 zone identifiers, underscores or malformed DNS labels, and browser IPv4
aliases such as `127.1`, `0177.0.0.1`, `0x7f000001`, `0x`, or `1.0x`.

The URL must explicitly use `http://` or `https://`. Browser repairs such as
`https:example.com`, `https:/example.com`, excess authority slashes, backslashes,
or trimming whitespace are not performed. Any literal `#` is rejected, including
an empty fragment. Base URLs cannot contain even an empty query delimiter.
Raw U+0000–U+0020, U+007F and backslashes are rejected everywhere. Unknown
percent-encoded non-NUL controls may be preserved as query data; URL parsing
is not general content sanitization.

Every percent escape is checked and decoded as strict scalar UTF-8. Invalid
escapes, overlong sequences, lone surrogates, values above U+10FFFF, truncated
sequences and decoded NUL are rejected in paths and queries, including unknown
query fields. Unknown query Unicode is preserved; query `+` decodes to a space.
Output uses uppercase percent hex and form encoding for queries.

Path AI/value segments are checked *before* any dot-segment normalization.
Literal or percent-encoded `.`/`..` path values are rejected. A literal data string
`%2e` roundtrips as `%252e`. Query values `.` and `..` remain data. Only the
non-GS1 base/prefix path receives dot-segment cleanup. Other prefix spelling is
preserved, including valid escapes and Unicode; this is not WHATWG percent
serialization of arbitrary prefix characters. Empty internal path segments are
rejected during parsing, while leading/trailing slashes are tolerated. The
builder normalizes empty prefix segments. After prefix cleanup, a base URL may
not contain literal or encoded primary-AI components.

## Validation and errors

- `validate_gs1_elements($elements, \%options)`
- `validate_gs1_element_string($raw, \%options)`
- `validate_gs1_digital_link($uri, \%options)`

Element validation options: `context => 'element-string'` or `'digital-link'`,
`collectAllErrors => 1` (default), `allowUnsupportedAi => 0` (the only permitted
value). Raw validation also enforces the requested context. Digital Link
validation accepts parsing options and `normalize => 0`; use the separate
normalizer to transform input.

Validators return a hash containing `ok`, `errors`, `warnings`, and either
`elements`/`hasSeparators` or `result`. Irrelevant result values are `undef`;
errors are empty on success. Field errors use zero-based `elementIndex` and
`offset`. `collectAllErrors => 0` stops at the first field error. Global shape,
type, and resource failures stop validation immediately. HTTP and preserved
unknown query parameters generate warnings.

Throwing helpers use `SpecQR::Error`, with public `{code}` `'INVALID_GS1'`,
`{detailCode}` containing the specific `GS1_*` reason, and `{message}`.
Validation issue `{code}` is the detailed reason. Optional issue fields are
present as `undef`. English wording is informative, not a compatibility key.

## Resource limits

- `GS1_MAX_INPUT_CHARACTERS`: 1,000,000 UTF-16-equivalent units (an astral scalar counts as two)
- `GS1_MAX_ELEMENTS`: 16,384
- Element-array AI/value aggregate: at most 1,000,000 UTF-8 bytes
- Hash fields: at most 16,384 per input object; oversized string byte buffers reject before Unicode traversal
- URL components, decoded fields, output size and query-pair aggregate are bounded
- `GS1_FNC1_SEPARATOR`: U+001D

## Verification and intentional reference differences

Run `prove -lv t/gs1.t`. It executes all 1,411 pinned historical TypeScript GS1
cases, every strict-authority vector, plus native catalog, type, Unicode,
resource-budget, validation and data-preservation tests. No case is skipped.

The historical corpus is unchanged from TypeScript commit
`15ad15e5c770ea0e39072f8f88b2733018f02ffd`. Expected profile differences are
independently generated from Nim commit
`4f9154664d35a24cecb30b75cfdba0a9f16ced3e`, not inferred from this Perl
implementation. The pinned Nim GS1 source SHA-256 is
`9df6a11927f265108e4d01e3321a208e1bcd4f9c484ff6aad5f9b8bd42734fa3`.
All 1,411 Perl contracts match that oracle. `gs1-perl-deltas.json` records each
of 252 historical differences, its explanation, expected outcome, and provenance:

- 50 empty values receive `invalid-length`
- 27 invalid-option reason labels follow Nim
- 2 raw validations enforce Digital Link primary context
- 18 missing-primary diagnostics use placement errors
- 8 malformed-path reason labels follow Nim
- 27 strict percent/Unicode differences
- 11 fragment differences
- 10 explicit absolute-URI differences
- 80 authority-profile differences
- 4 empty-base-query differences
- 2 safe dot-only builder outputs
- 3 IPv6 textual-normalization differences
- 6 raw-whitespace/backslash differences
- 4 early dot-path rejection differences

Current TypeScript commit `16efc6c0a8e397c9df3d051d20fce6c1eebdfad7` was
also independently executed over the same 1,411 inputs with Node.js v24.19.0.
It changes six historical dot-safety cases. Against that current reference,
1,163 Perl contracts agree and 248 retain the documented Nim profile/diagnostic
differences. The current audit's six exact outputs and source hash are retained
in the delta artifact. This is an explicit bounded compatibility profile, not
an assertion of full WHATWG or full GS1 coverage.

Optional oracle harnesses are under `verification/gs1/`. Nim/Node.js are needed
only to regenerate reference evidence, never to run the library or normal tests.
