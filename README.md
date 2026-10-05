# SpecQR Perl

Perl だけで動く QR コード生成ライブラリです。QR のビット列、GF(256)、Reed–Solomon、マスク評価、SVG、PNG をこのリポジトリで実装しています。実行時の CPAN パッケージ、外部 QR エンコーダ、FFI、JavaScript ランタイムは不要です。

- QR Model 2、バージョン 1–40、誤り訂正 L/M/Q/H、全 8 マスクと自動選択
- 数字・英数字・バイト・漢字モード、混在セグメント最適化、ECI、FNC1 第一／第二位置
- 容量照会、行列を作らない事前計画、マスク・印刷・読み取りリスク診断
- GS1 要素文字列、チェックディジット、50 個の対応 AI、Digital Link
- 2–16 個の Structured Append、自動分割、手動セグメント、復号結果の結合と検査
- SVG、RGBA ピクセル、PNG、各 data URL、バイナリ入出力対応 CLI

対応ランタイムは Perl 5.42.3 以上です。検証対象は Linux x86-64 の Perl 5.42.3 と 5.44.0。OS 固有の機能には依存しませんが、未検証 OS の動作を実測済みとは扱いません。

## インストール

```sh
git clone https://github.com/SpecQR/SpecQR-Perl.git
cd SpecQR-Perl
perl Makefile.PL INSTALL_BASE="$HOME/.local/specqr-perl"
make
make test
make install
export PERL5LIB="$HOME/.local/specqr-perl/lib/perl5${PERL5LIB:+:$PERL5LIB}"
export PATH="$HOME/.local/specqr-perl/bin:$PATH"
```

開発時は `perl -Ilib examples/consumer.pl` でも利用できます。CPAN への公開・登録を前提にしません。

## 最初の QR

```perl
use strict;
use warnings;
use utf8;
use SpecQR qw(generate to_svg to_png);

my $qr = generate('こんにちは、SpecQR', {
    errorCorrectionLevel => 'M',
    eciAssignment => 26,  # UTF-8 の宣言。文字コード変換ではありません。
});
open my $out, '>:raw', 'hello.png' or die $!;
print {$out} to_png($qr) or die $!;
close $out or die $!;
```

文字列は Perl のデコード済み文字列です。UTF-8 のファイルを API に渡す場合は `Encode::decode('UTF-8', $bytes, Encode::FB_CROAK)` で明示的にデコードしてください。非 ASCII の UTF8 フラグなしスカラーは、文字列とバイトの取り違えを避けるため拒否します。任意バイト列は整数配列で渡します。

```perl
my $binary = generate([0, 1, 127, 128, 255]);
```

出力 PNG と RGBA ピクセルは UTF8 フラグなしのオクテット列です。保存時は必ず `:raw` を使います。

## CLI

```sh
specqr --text 'Hello, SpecQR' --output hello.svg
specqr --text-file message.txt --eci 26 --format png --output message.png
specqr --bytes-file payload.bin --format png --output payload.png
specqr --text '1234567890' --plan
specqr --text-file long.txt --version 2 --structured-append --format json
```

既定値は誤り訂正 M、余白 4 モジュール、倍率 8。CLI の文字列・文字ファイルは厳密な UTF-8、バイトファイルは無変換です。`--text-file -` と `--bytes-file -` は標準入力を読みます。JSON・SVG には末尾改行を付け、PNG には追加しません。

## ドキュメント

- [日本語 Getting Started](docs/getting-started.md)
- [English API reference](docs/reference.md)
- [GS1 / Digital Link の対応範囲](docs/gs1.md)
- [検証とリリース手順](docs/verification.md)

GS1 Digital Link では通常の QR 生成との互換性を保ち、空フラグメント、HTTP(S) スラッシュ補正、ASCII ホスト、認証情報の構文、数値 IPv4 別名、IPv6 正規化などの受け入れ範囲を拡張しました。不正な percent encoding・UTF-8・NUL と GS1 データを消すドットパスは引き続き拒否します。Unicode ホストの IDNA 変換は対象外です。正確な対応範囲と検証結果は [GS1 ガイド](docs/gs1.md) を参照してください。

## ライセンス

MIT。SpecQR の既存版を参考にしたネイティブ Perl 実装です。テスト専用の参照データ・独立復号器の出典は検証ドキュメントに分離しています。
