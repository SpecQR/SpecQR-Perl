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
It is idempotent in its documented URL profile. IPv6 hex groups use lowercase,
remove leading zeroes, compress the first longest zero run, and convert embedded
IPv4 into hex groups.

## 互換性を拡張したオフライン URL プロファイル

通常の QR 生成・FNC1・バイナリ API の契約を変えず、従来不要に拒否していた
URL を受け入れます。QR コアや実行時依存関係の変更はありません。URL を開く、
DNS を引く、認証情報を使って接続する操作は行いません。URL 構文の受け入れは
アクセス先の安全性や公開インターネット上の到達性を保証せず、SSRF 防御ではありません。

- 空のフラグメント `#` を許容します。非空フラグメントは拒否します。
  builder は空の `#` を末尾に保ち、normalizer はそれを取り除きます。
- builder の空 query `?` を許容します。非空の base query は拒否します。
- HTTP(S) の欠落・余分なスラッシュ、前後の ASCII 空白、TAB/LF/CR を
  ブラウザ互換に補正します。authority/path の backslash は slash に直し、
  query の backslash はデータとして保存します。
- ASCII percent-encoded host と URL reg-name を許容します。DNS label
  制限を URL 構文検証に流用しません。host の空白、区切り文字、NUL は拒否します。
- userinfo の構文を許容し、必要な escaping を行います。既存 percent bytes を
  二重デコードせず保存します。エラーに userinfo を追加しません。
- decimal/octal/hex の数値 IPv4 別名を通常の dotted decimal に直します。
  桁ごとの上限検査により overflow と不正な数値を拒否します。`0xg` のような
  非数値の最終ラベルは reg-name です。`08` や `0xg.1` は不正な IPv4 として拒否します。
- bracketed IPv6 は完全に検証してから正規化します。zone ID、不正な圧縮、
  不正な embedded IPv4 は拒否します。
- port は十進の 0–65535。空 port と先頭ゼロを許容し、既定 port は省略します。

Perl core には完全な UTS46/IDNA host 処理がありません。依存なしの契約を維持するため、
非 ASCII host は明示的な対象外とし、不完全な IDNA を実装しません。ASCII punycode
の表記は受け入れます。これは Godot の制約を転用した判断ではありません。
ASCII の `xn--` 接頭辞をもつ host も完全な UTS46/ACE 妥当性検証は行いません。
たとえば `xn--a` は以前から受け入れられ、bare `xn--` は今回の reg-name 拡張で
受け入れられますが、current TypeScript はどちらも拒否します。これは元の 1,411 件の
外側にある既知の相違で、168 件という corpus 内差分の集計には混ぜません。

Every percent escape is checked and decoded as strict scalar UTF-8. Invalid
escapes, overlong sequences, lone surrogates, values above U+10FFFF, truncated
sequences and decoded NUL are rejected in paths and queries, including unknown
query fields. Unknown query Unicode is preserved; query `+` decodes to a space.
Output uses uppercase percent hex and form encoding for queries.

Path AI/value segments are checked *before* any dot-segment normalization.
Literal or percent-encoded `.`/`..` path values are rejected. A literal data string
`%2e` roundtrips as `%252e`. Query values `.` and `..` remain data. Only the
non-GS1 base/prefix path receives dot-segment cleanup. Existing valid escapes in prefixes are preserved; raw path characters receive
WHATWG-compatible UTF-8 percent serialization without dot-path data loss. Empty internal path segments are
rejected during parsing, while leading/trailing slashes are tolerated. The
builder normalizes empty prefix segments. For example, base `/a//b` becomes
`/a/b`; current TypeScript preserves the repeated slash. This is an inherited
builder-only difference outside the original 1,411-case corpus. After prefix cleanup, a base URL may
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

## 検証と意図的な差分

`prove -lv t/gs1.t` は元の 1,411 入力をすべて実行します。履歴 corpus
`15ad15e5c770ea0e39072f8f88b2733018f02ffd` と旧 252 差分 ledger は変更していません。
現在の独立 TypeScript oracle は `16efc6c0a8e397c9df3d051d20fce6c1eebdfad7` です。
期待値を Perl 出力から生成せず、TypeScript の実行結果に request hash で結びます。

Perl 5.42.3 と 5.44.0 の公開版 baseline はどちらも 1,163 一致、248 差分でした。
受け入れ拡張の 77 件と IPv6 正規化の 3 件を復元し、現在は 1,243 一致、168 差分です。

- 診断だけの差分: 132
- TypeScript が受理し Perl が拒否: 34（不正 percent/UTF-8/NUL 20、IDNA host 12、raw Digital Link primary context 2）
- 安全なドット query builder 出力を Perl が受理: 2
- 受理済み出力の正規化差分: 0

`approved-restorations80.json` は 80 個の正確な positive assertion、
`native-intentional-deltas168.json` は残る各契約を記録します。
`diagnostic-migrations5.json` の 930/1038/1056 は lexical/authority 修復後の
primary 検証、1269/1272 は host percent decode に診断が移動します。
独立 Nim witness と同じ code/reason を各 Perl 実行でも確認します。

すべての旧 authority 入力を残し、6 host の 18 操作を TypeScript-positive に移し、
`example.0x` の 3 拒否を保ちます。共有 GS1 は全 49 操作、FNC1 percent は全 102 入力
（70 成功、10 forced-alpha 拒否、22 capacity 拒否）と manual 4 件を実行します。
追加の 139 TypeScript-positive 操作は旧 native URL assertion の移動と境界条件を検証します。
型、リソース制限、dot-path、percent data、認証情報の非漏洩、overflow の negative control も残します。

履歴 assertion の移動先は [URL assertion mapping](url-compatibility-mapping.md) に記載します。
`script/verify_gs1.py` は exit、stderr、response 数、fixture/source hash、unexpected field を
厳密に検査します。任意の oracle 再生成だけが Node/Nim を使い、通常の package test は
Perl core module のみです。
