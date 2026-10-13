<a id="english-api-reference"></a>

# API リファレンス

API reference for the native, dependency-free SpecQR Perl encoder.

## Runtime and installation

SpecQR 0.1.0 は、依存パッケージ不要のネイティブ Perl 実装です。対応する最小版は Perl 5.42.3 です。リリース検証の profile では、Linux x86-64 上の公式 Perl 5.42.3 と 5.44.0 を使います。package が使うのは Perl に同梱された module だけです。開発専用の参照プログラムと decoder は、実行時の依存関係ではありません。`perl Makefile.PL`、`make`、`make test`、`make install` でインストールし、必要に応じて `INSTALL_BASE` を指定します。CPAN への公開を意味するものではありません。

`use SpecQR qw(generate to_png);` で、名前を指定した関数を import します。任意に使える export tag は `:qr`、`:segments`、`:render`、`:gs1`、`:structured_append`、`:all` です。既定では何も export しません。結果、options、segment は bless されていない hash reference で、配列は通常の array reference です。公開操作は入力を検証してコピーし、呼出側が所有する segment の格納領域を保持しません。

## Text, bytes, and types

テキスト API は、Unicode scalar value を含む Perl 文字列を受け取ります。ASCII 文字列に特別な flag は不要です。非 ASCII 文字列には Perl の UTF8 flag が必要です。非 ASCII で flag のない scalar は、Latin-1 や UTF-8 と推測せず拒否します。ソースのリテラルには `use utf8`、外部の UTF-8 bytes には `Encode::decode('UTF-8', $octets, Encode::FB_CROAK)` を使ってください。不正な内部 UTF-8、surrogate、U+10FFFF を超える値は拒否します。

`generate([0,128,255])` は、テキストとして解釈しない byte 値を受け取ります。各値は 0..255 の数値の整数である必要があります。`byte_segment($octets)` は flag のない octet scalar または整数配列を受け取り、常に binary として扱います。`new_segment('byte', $characters)` は文字列を UTF-8 に符号化します。flag の付いた文字列を暗黙に raw octet として受け入れることはありません。ECI はデータにラベルを付けるもので、文字コード変換は行いません。

数値の設定には numeric scalar が必要です。数値に見える文字列、boolean、配列、object は使えません。boolean の設定は、数値の 0/1 または core の `JSON::PP` boolean を受け入れます。未知の option と、tie または bless された container は拒否します。JSON adapter と CLI は、それぞれの境界で明示的な変換を行います。

## Generating and planning

- `generate($text_or_byte_array, \%options)` は QR 結果を返します。
- `generate_segments(\@segments, \%options)` は、明示的に指定した segment の mode と境界を保持します。
- `plan($text_or_byte_array, \%options)` / `estimate(...)` は、算術計算だけによる計画を返します。
- `plan_segments(\@segments, \%options)` / `analyze_segments(...)` は、明示的に指定した segment の計画を立てます。
- `get_capacity($version, $ecc = 'M', $mode = '', $control_bits = 0)` は容量の詳細を返します。`version`、`errorCorrectionLevel`、`mode`、`controlBits` を持つ options hash も受け入れます。
- `diagnostics($result)` は、QR、計画、SA set、または結合結果の診断について、検査済みの独立した snapshot を返します。
- `size($qr)` はモジュール単位の幅です。`module_at($qr,$x,$y)` はゼロ始まりの座標を使います。

QR 結果の field は、`matrix`（0/1 の行からなる正方配列）、`version`、`maskPattern`、`errorCorrectionLevel`、`dataCodewords`、`codewords`（byte 配列）、`segments`、`options`、`diagnostics` です。

計画の field は、`ok`、`version`、`capacityVersion`、`errorCorrectionLevel`、`requestedErrorCorrectionLevel`、`boostedErrorCorrection`、`dataBitLength`、`capacityBits`、`remainingBits`、`segments`、`diagnostics` です。成功しなかった自動計画は `version => 0` となり、`capacityVersion` が最後に検査した容量を示します。計画では codeword も行列も生成しません。選択した範囲に収まらない場合、生成は `DATA_TOO_LONG` を送出します。

### Options

| キー | 既定値 | 契約 |
| --- | --- | --- |
| `errorCorrectionLevel` | `M` | `L`、`M`、`Q`、`H` のいずれかに厳密に一致 |
| `version` | `0` | `0` または `auto` は自動選択。それ以外は 1..40 |
| `minVersion`, `maxVersion` | 1, 40 | 順序が正しい自動探索範囲 |
| `maskPattern` | -1 | -1 または `auto` は自動選択。それ以外は 0..7 |
| `mode` | `auto` | `numeric`, `alphanumeric`, `byte`, `kanji`, `auto` |
| `optimizeSegments` | 1 | 混在 mode で bit 数を最小にする計画 |
| `allowKanji` | 1 | 自動最適化中の漢字 mode を許可 |
| `boostErrorCorrection` | 0 | 選んだ version を増やさず ECC を強化 |
| `eciAssignment` | -1 | -1 は未指定。それ以外は 0..999999 |
| `gs1` | 0 | GS1 要素文字列を検証し、FNC1 を挿入 |
| `fnc1` | 0 | GS1 要素の検証を行わない FNC1 第一位置 |
| `fnc1Second` | 空 | 対応する英字または 2 桁の application indicator |
| `structuredAppend` | 未指定 | 明示的な SA header segment |
| `margin`, `scale` | 4, 8 | margin は非負。scale は正の整数 |
| `foreground`, `background` | `#000000`, `#ffffff` | 安全な hex または単純な ASCII CSS 色名 |
| `printDpi` | 未指定 | 有限で正の寸法を得られる、有限の正数 |

`errorCorrection` は `errorCorrectionLevel` の別名であり、値が矛盾すると失敗します。`eci => 26` は `eciAssignment => 26` の別名です。JSON boolean の `true`/`false` は、UTF-8 ECI/未指定を意味します。`encoding` が対応するのは `utf-8` だけです。これらの互換 field は戻り値の型を変えません。描画には `to_svg` または `to_png` を明示的に呼び出します。`output` は対応する形式名を受け入れますが、生成は引き続き QR 結果を返します。`diagnostics` は検証され、結果の診断も引き続き利用できます。

FNC1、ECI、SA header は組み合わせられません。手動の GS1 データには、高水準の `gs1` option の代わりに、明示的な FNC1 segment を含める必要があります。

## Segments and controls

コンストラクター: `numeric($text)`、`alphanumeric($text)`、`kanji($text)`、`new_segment($mode,$text)`、`byte_segment($octets_or_array)`、`eci($assignment)`、`fnc1()`、`fnc1_second($indicator)`、`structured_append_segment($index,$total,$parity)`。

SA の index は 1 始まり、合計は 2..16、parity は 0..255 です。制御は QR の順序規則に従う必要があり、データの後には置けません。ECI assignment は宣言であり、文字コード変換ではありません。漢字 mapping は、固定した SpecQR baseline が使う、リポジトリ内の正確な WHATWG 由来の mapping です。host platform の CP932 や Shift_JIS codec は使いません。

高水準の FNC1 テキストでは、リテラルの `%` をデータ、U+001D を separator として扱います。英数字変換では、リテラルの percent を二重にします。GS は byte mode で保持し、GS を含むテキストへの英数字 mode の強制指定は拒否します。自動 mode は安全な選択肢を比較し、英数字 mode の強制指定でも同じ escaping と容量検査を行います。低水準の手動英数字 segment は、呼出側が指定した QR の FNC1 表現を既に含みます。`%` は separator、`%%` はリテラルの percent です。手動の byte data はテキストとして解釈しません。この区別は、共有する回帰 vector 102 件で検査します。

## Rendering

`to_svg`、`to_png`、`to_pixels`、`to_svg_data_url`、`to_png_data_url` は、QR 結果または行列と、任意の描画専用 options hash を受け取ります。上書き用の hash に含められるのは `margin`、`scale`、`foreground`、`background` だけです。任意の生成 field を結合するのではなく、既定値を置き換えます。

SVG は、黒 module ごとに 1 個の path command を持つ ASCII テキストです。PNG は flag のない octet 文字列で、形式は RGBA8 です。stored DEFLATE、CRC-32、Adler-32 は Perl で実装しています。`to_pixels` は `{width,height,pixels}` を返します。`pixels` は flag のない、行優先順に詰めた RGBA octet 文字列です。保存には `>:raw` を使い、PNG/pixels にテキストの encoding layer を適用しないでください。

raster の色は `#rgb`、`#rgba`、`#rrggbb`、`#rrggbbaa`、`black`、`white`、`transparent` を受け入れます。それ以外の単純な ASCII CSS 色名は SVG 専用であり、contrast 診断は、その色を検査できないことを明示します。`render_dimensions($result_or_matrix, \%render_options, $dpi)` は pixel 単位の寸法と、任意の mm 単位の寸法を返します。DPI の非正規化数・overflow・underflow の値は、有限で正の寸法を得られない場合に拒否します。

資源上限は、payload 単位 1,000,000、手動 segment 16,384、raster pixel 4,194,304（辺は最大 2048）、SVG 文字数 8 MiB、data URL 文字数 32 MiB、寸法の整数は最大 1,000,000,000 です。大きな raster 領域を割り当てる前に上限を検査します。QR 容量は、これよりはるかに小さい独立した上限です。単一 symbol の自動最適化は 7,089 文字を上限とします。

## Structured Append

`generate_structured_append($text_or_bytes, \%options, $max_symbols=16, $diagnostics=0)` は `{symbols,total,parity,inputLength,byteLength,diagnostics}` を返します。すべての symbol は選択した version と ECC を共有し、mask はそれぞれで選べます。自動探索は、有効な 2..16 個の symbol set を構成できる最小 version を選びます。テキストは Unicode scalar の境界、binary は byte の境界で分割します。parity は、元の UTF-8 または raw bytes の XOR です。

`generate_segments_structured_append(\@segments, \%options, $max_symbols=16, $diagnostics=0, $split_units='summary', $symbol_results='')` は、byte 以外の segment を分割せず保持し、byte segment だけを細分化します。テキストに由来する byte segment では文字境界を守ります。`full` で完全な分割単位の診断を利用できます。`symbol_results` は `output` または `diagnostics` を受け入れます。

高水準の SA 操作は、単一 symbol に収まる入力、空データ、ECI/FNC1/GS1、既存の SA header、ECC 強化、互換性のない手動 mode 設定を拒否します。外部で管理する set には、引き続き低水準の SA header を使えます。

`merge_structured_append_parts(\@parts)` は、復号済みの mapping `{index,total,parity,data}` を受け取ります。index が欠落・重複なく揃っていること、metadata の整合性、データがすべてテキストまたはすべて binary であること、XOR parity を検証し、`{data,total,parity,parts,diagnostics}` を返します。画像の復号は行いません。decoder の metadata は呼出側が渡す必要があります。非公開の decoder 拡張は前提にしません。

## GS1 and errors

対応するカタログ全体、検証規則、Digital Link の authority profile、過去の参照との明示的な差分は、[GS1 の対応範囲](gs1.md) を参照してください。未対応の AI は推測せず拒否します。

すべての検証失敗は `SpecQR::Error` を送出します。この例外は `code` と `message` を持ちます。GS1 エラーは追加で `detailCode` を持ちます。代表的な code は `INVALID_INPUT`、`INVALID_MODE`、`INVALID_ECC_LEVEL`、`INVALID_VERSION`、`INVALID_ECI`、`INVALID_COLOR`、`INVALID_OUTPUT`、`INVALID_GS1`、`DATA_TOO_LONG` です。CLI の I/O 失敗は `IO_ERROR` として報告し、終了コード 2 を返します。診断は quiet zone、contrast、alpha、容量、物理的な module サイズ、全体的な読み取りリスクについて警告します。すべてのカメラや decoder がすべての symbol を読めるという保証ではありません。
