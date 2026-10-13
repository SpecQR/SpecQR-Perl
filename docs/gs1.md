# GS1 and GS1 Digital Link

`SpecQR::GS1` は、50 AI に限定した SpecQR カタログ全体を native Perl と core module で実装します。ネットワークアクセス、DNS 解決、子 process の実行は行いません。個別の helper または `:all` を import してください。

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

対応する最小 runtime は Perl 5.42.3 です。文字列には実際の Perl 文字列 scalar が必要で、数値、`undef`、object、reference、型変換された JSON boolean は使えません。先頭のゼロを保持するため、AI と数値を表す値は引用符で囲んでください。ASCII 文字列は Perl の Unicode flag の有無を問いません。非 ASCII テキストは Unicode 文字列である必要があり、flag のない UTF-8 byte buffer は使えません。外部の bytes は、先に `Encode::decode('UTF-8', $bytes, Encode::FB_CROAK)` で明示的に decode してください。不正な内部 UTF-8、surrogate、U+10FFFF を超える code point は拒否します。

要素は、bless も tie もされていない hashref を格納する、bless も tie もされていない arrayref です。各 hashref は `ai` と `value` を持ちます。options は省略可能な hashref で、キーは camelCase です。未知の option key は拒否します。boolean option は数値の `0`/`1` または `JSON::PP` の boolean を受け入れ、文字列は受け入れません。options を省略するか `undef` にすると既定値を使います。
引数の scalar、array の要素、hash の field が tie されている場合、値を取得する前に拒否します。内部の型や値が不正な偽装 JSON boolean object も拒否します。結果の hash と metadata は、SpecQR の他言語版に合わせて camelCase のキーを使います。返される JSON boolean は、それぞれ独立に所有する `JSON::PP::Boolean` scalar object です。一つを変更しても、内部カタログや後続の結果は変わりません。

`normalize_gs1_elements($input)` は、要素の配列、`elements` を持つ解析結果の hash、または文字列を受け入れます。`(` で始まる文字列には human-readable 解析を、それ以外の文字列には raw element-string 解析を使います。正規化した要素はすべて新しい hash です。カタログの metadata はネストした field も含めてコピーするため、呼出側は内部カタログを変更できません。

## Catalog and field validation

`get_supported_gs1_ais()` は 50 個すべての metadata hash を返します。
`get_gs1_ai_info($ai)` は 1 個の metadata hash を返し、未対応の AI なら `undef` を返します。各レコードは `ai`、`label`、`length`、`valueKind`、`checkDigitRule`、`digitalLinkRole`、`separator`、`digitalLinkPathForPrimary` を持ちます。

- 固定長: `{ type => 'fixed', exact => N, isVariable => false }`
- 可変長: `{ type => 'variable', min => 1, max => N, isVariable => true }`
- `digitalLinkPathForPrimary` は qualifier では `['01']`、それ以外では `undef` です。

対応する AI:

- `00`, `01`, `02`, `10`, `11`, `12`, `13`, `15`, `16`, `17`, `20`, `21`, `22`, `30`, `37`
- `240`, `241`, `400`, `410`–`415`, `420`, `422`, `424`, `425`, `426`
- `3100`–`3105`, `3200`–`3205`, `91`–`99`

検査対象は、固定長・可変長、数値と printable ASCII の値の区別、GTIN/SSCC チェックディジット、raw の括弧、U+001D/FNC1 separator です。要素の値はすべて printable ASCII を使う必要があります。ここで `%` はデータそのものであり、FNC1 の代用記号ではありません。QR 符号化層は、独自にデータを失わない FNC1 表現へ変換します。

これは包括的な GS1 認証ではありません。日付 AI は 6 桁を要求しますが、暦上の有効な日付かどうかは確認しません。GLN AI `410`–`415` は、この共通カタログに合わせて 13 桁を要求します。GLN チェックディジットや、すべての GS1 AI 組合せ規則は検査しません。未対応の AI を黙って有効にはできません。

## Element strings

- `parse_gs1_human_readable($string)` は要素の配列を返します。
- `parse_gs1_element_string($string)` は `{ elements, hasSeparators }` を返します。
- `create_gs1_element_string($elements)` は末尾以外の各可変長 field の後に U+001D を挿入します。
- `gs1_to_human_readable($elements)` は AI の括弧を追加します。
- `gs1_element_string_to_human_readable($raw)` は raw data を解析して整形します。

末尾以外の可変長 field には区切りが必要です。parser は SpecQR の保守的な曖昧性検査を使います。区切りのない末尾の可変長値に、完全な固定長 AI に見える suffix がある場合、その suffix のデータ自体が数値検証に失敗する場合でも、separator の欠落として拒否します。このため、通常なら printable な末尾の lot 値の一部も拒否されます。そのような値を生成するときは、構造化した要素配列か human-readable 入力を使ってください。あらゆる raw 可変長 field が一意に解析できるとは限りません。

別名: `gs1_normalize`、`gs1_from_human_readable`、`gs1_to_element_string`、`gs1_build`、`gs1_parse`。

## Check digits

- `calculate_gs1_check_digit`, `validate_gs1_check_digit`
- `calculate_gtin_check_digit`, `append_gtin_check_digit`, `validate_gtin_check_digit`
- `calculate_sscc_check_digit`, `append_sscc_check_digit`, `validate_sscc_check_digit`

計算関数はチェックディジットを除いた本体を受け取り、検証関数は完全な値を受け取ります。GTIN の本体は 7、11、12、13 桁、SSCC の本体は 17 桁です。不正な形式の入力では例外を送出します。形式が正しくチェックディジットだけが誤っている数値は false を返します。計算は GS1 modulo-10 を使い、右から左へ 3、1 の重みを適用します。

## Digital Link API

`create_gs1_digital_link($elements, \%options)` は次に対応します。

- `baseUrl`: 既定値は `https://id.gs1.org`
- `primaryAi`: 既定値は `'01'`。`'00'` と `'414'` にも対応
- `pathAis`: 選択した qualifier AI。明示的な空配列では、すべての qualifier を query に配置
- `explicitPathAis`: 数値または JSON boolean。true では、`pathAis` を省略しても明示的な選択として扱う

primary が `01` の場合、既定では qualifier の `10`、`21`、`22` を path に配置します。それ以外の値は、AI、次に値の順で辞書順に並べた query に配置します。qualifier の path 内の順序は入力順に従います。`pathAis` の選択に primary AI を含めることもできますが、その位置は変わりません。不正な path 選択と重複する AI は拒否します。dot-only の qualifier 値は、path 向けに選択されていても必ず query に配置します。`gs1_digital_link` と `gs1_to_digital_link` は別名です。

`parse_gs1_digital_link($uri, \%options)` は次の値を返します。

```perl
{
    elements     => [...], # path elements followed by known query elements
    primary      => { ai => '01', value => '...' },
    pathElements => [...],
    queryElements => [...],
    unknownQuery => [ { key => 'utm', value => 'campaign' }, ... ],
}
```

options は `primaryAi`（既定では最初のリテラルの `00`、`01`、`414` の path segment を探索）と、`unknownQuery`（`'preserve'` または `'reject'`。既定は preserve）です。未知の query の重複と順序を保持します。数字で構成された 2–4 文字の query key は AI として扱い、対応済みである必要があります。黙って未知の query として再分類することはありません。符号化された primary-AI の path segment は探索に使いません。

`normalize_gs1_digital_link($uri, \%options)` は同じ options に加えて、唯一対応する mode である `mode => 'specqr-deterministic'` を受け入れます。既知の field を決定的に再構築し、既定で適格な qualifier を path に選び、既知の query data を並べ替え、未知の query pair を元の順序で末尾に追加します。文書化した URL profile の範囲で冪等です。IPv6 の hex group は小文字にし、先頭のゼロを除去し、最長のゼロの連続のうち最初のものを圧縮し、埋め込まれた IPv4 を hex group に変換します。

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

すべての percent escape を検査し、厳密な scalar UTF-8 として decode します。不正な escape、overlong sequence、孤立 surrogate、U+10FFFF を超える値、途中で切れた sequence、decode 後の NUL は、未知の query field を含む path と query で拒否します。未知の query の Unicode は保持し、query の `+` は空白へ decode します。出力には大文字の percent hex を使い、query には form encoding を使います。

path の AI/value segment は、dot-segment 正規化の*前に*検査します。リテラルまたは percent-encoded の `.`/`..` の path 値は拒否します。リテラルのデータ文字列 `%2e` は `%252e` として往復変換します。query 値の `.` と `..` はデータのまま保持します。dot-segment を整理するのは、GS1 データではない base/prefix path だけです。prefix 内の既存の有効な escape は保持します。未符号化の path 文字には、dot-path のデータを失わず、WHATWG と互換性のある UTF-8 percent serialization を適用します。内部の空 path segment は解析時に拒否しますが、先頭・末尾の slash は許容します。
builder は空の prefix segment を正規化します。たとえば base の `/a//b` は `/a/b` になりますが、current TypeScript は繰り返しの slash を保持します。これは元の 1,411 case の corpus の外にある、既存の builder 固有の差です。prefix の整理後、base URL にリテラルまたは符号化された primary-AI component が含まれていてはいけません。

## Validation and errors

- `validate_gs1_elements($elements, \%options)`
- `validate_gs1_element_string($raw, \%options)`
- `validate_gs1_digital_link($uri, \%options)`

要素の検証 options は、`context => 'element-string'` または `'digital-link'`、`collectAllErrors => 1`（既定値）、`allowUnsupportedAi => 0`（許可される唯一の値）です。raw の検証でも、指定された context を適用します。Digital Link の検証は解析 options と `normalize => 0` を受け入れます。入力の変換には、別の normalizer を使ってください。

`ok`、`errors`、`warnings` と、`elements`/`hasSeparators` または `result` を含む hash を返します。該当しない結果の値は `undef` で、成功時の errors は空です。field error はゼロ始まりの `elementIndex` と `offset` を使います。`collectAllErrors => 0` は最初の field error で停止します。全体の shape、型、資源の失敗は検証を直ちに停止します。HTTP と、保持した未知の query parameter は警告を発生させます。

例外を送出する helper は `SpecQR::Error` を使い、公開 `{code}` は `'INVALID_GS1'`、`{detailCode}` は個別の `GS1_*` reason、本文は `{message}` に格納します。検証 issue の `{code}` は詳細な reason です。任意の issue field も `undef` として存在します。英語の文面は説明用であり、互換性のキーではありません。

## Resource limits

- `GS1_MAX_INPUT_CHARACTERS`: 1,000,000 UTF-16 相当 units（補助平面の scalar は 2 と数える）
- `GS1_MAX_ELEMENTS`: 16,384
- 要素配列の AI/value 合計: 最大 1,000,000 UTF-8 bytes
- hash field: 入力 object ごとに最大 16,384。大きすぎる文字列 byte buffer は Unicode の走査前に拒否
- URL component、decode した field、出力サイズ、query-pair の合計には上限がある
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
