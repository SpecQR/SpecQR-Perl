# Getting Started

## 1. ランタイムを確認する

`perl -v` で Perl 5.42.3 以上を確認します。実行時に使うのは Perl コア配布のモジュールだけです。Python、Node.js、Java、C++ の QR 復号器は詳細な開発検証にだけ使います。

README の手順でインストールするか、このリポジトリから `perl -Ilib your-script.pl` を実行してください。

## 2. 文字列とバイトを区別する

```perl
use utf8;
use SpecQR qw(generate to_png);
use Encode qw(decode FB_CROAK);

my $literal = generate('漢字とひらがな');
my $decoded = decode('UTF-8', $raw_file_bytes, FB_CROAK);
my $text_qr = generate($decoded, { eciAssignment => 26 });
my $binary_qr = generate([unpack 'C*', $raw_file_bytes]);
```

ASCII は通常のスカラーで構いません。非 ASCII テキストは UTF8 フラグの付いた Perl 文字列を使います。`use utf8` はソースコードの文字列リテラルに作用し、ファイルを自動でデコードする指定ではありません。

`byte_segment($octets)` は明示的なバイナリです。文字としてバイトモードを指定する場合は `new_segment('byte', $text)` を使います。ECI 26 は UTF-8 を示すラベルで、変換処理はしません。

## 3. 容量とセグメントを選ぶ

```perl
use SpecQR qw(plan get_capacity numeric new_segment generate_segments);
my $plan = plan('1234567890HELLO', { maxVersion => 3 });
die '大きすぎます' unless $plan->{ok};
my $capacity = get_capacity(1, 'L', 'numeric');
my $manual = generate_segments([
    numeric('1234567890'),
    new_segment('byte', 'lowercase'),
]);
```

`plan` はコードワードや行列を生成しません。通常は `mode => 'auto'` の最適化を使えます。手動セグメントでは指定した境界とモードを保持します。

## 4. GS1 と FNC1

```perl
use SpecQR qw(create_gs1_element_string generate create_gs1_digital_link);
my $elements = [
    { ai => '01', value => '09506000134352' },
    { ai => '10', value => 'LOT1' },
];
my $element_string = create_gs1_element_string($elements);
my $gs1 = generate($element_string, { gs1 => 1 });
my $url = create_gs1_digital_link($elements);
```

高水準の FNC1 入力では `%` は文字どおりのパーセント、ASCII GS（`\x1d`）は区切りを表します。英数字セグメントに含まれる文字どおりの `%` は `%%` へエスケープします。GS はバイトモードで保持するため、GS を含む入力への英数字モード強制指定は拒否します。手動の英数字セグメントでは利用者が QR の FNC1 表現に従い、文字どおりの `%` を `%%`、区切りを `%` として渡します。

## 5. Structured Append

```perl
use SpecQR qw(generate_structured_append merge_structured_append_parts);
my $set = generate_structured_append('x' x 100, {
    version => 1, errorCorrectionLevel => 'L',
});
for my $qr (@{$set->{symbols}}) {
    # to_png($qr) などで各シンボルを保存
}
```

同じバージョン・誤り訂正レベルで 2–16 個に分割します。一つに収まる入力は通常の `generate` を使ってください。ECI、FNC1、GS1、ECC 自動強化との併用は認めません。復号器ごとに SA メタデータの取得方法が異なります。`merge_structured_append_parts` は `{index,total,parity,data}` の配列を受け取り、順序・欠落・重複・パリティを検査します。バイト配列と文字列は混在させません。

## 6. エラーと保存

失敗時は `SpecQR::Error` オブジェクトを例外として送出します。

```perl
my $qr = eval { generate('data', { version => 99 }) };
if (my $error = $@) {
    if (ref($error) eq 'SpecQR::Error') {
        warn $error->{code} . ': ' . $error->{message};
    } else {
        die $error;
    }
}
```

PNG とピクセルはオクテット列、SVG は ASCII 文字列です。サイズ・色・入力長には上限があります。読み取り用には既定の余白と倍率を維持し、診断の警告を確認してください。
