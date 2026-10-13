# 検証とリリース手順 / Verification

この版では、自ら生成した fixture、decoder の部分的な出力、後から失敗する process を、独立検証の成功として扱いません。

## Reproducible runtime profile

- Perl の最小版: 5.42.3。この検証 profile の現行安定版: 5.44.0。
- 公式 source archive と SHA-256 は `script/install_perl.py` に固定しています。
- profile は Linux x86-64 です。実行していない macOS/Windows lane の成功は主張しません。
- 実行時の依存関係は Perl core module だけです。Python、Node、Nayuki、ZXing-C++、ZXing Java、画像用 tool は開発専用の検証資産です。

公式参照: [CPAN source distribution](https://www.cpan.org/src/)、[Perl support policy](https://perldoc.perl.org/perlpolicy)。

## Baselines and independent checks

直接の source baseline は [SpecQR TS 16efc6c](https://github.com/SpecQR/SpecQR/commit/16efc6c0a8e397c9df3d051d20fce6c1eebdfad7) と [SpecQR Nim 4f91546](https://github.com/SpecQR/SpecQR-Nim/commit/4f9154664d35a24cecb30b75cfdba0a9f16ced3e) です。Perl runtime は native 実装のコードであり、それらの版を子 process として呼び出す adapter ではありません。

必須の gate:

1. 正確な両 runtime で、core の算術、容量、Unicode、segment、optimizer、GS1、SA、描画の native test を実行します。
2. 固定した公開参照 corpus は、生成、計画、容量境界、SA を含む 5,610 レコードです。corpus のバイトは維持し、古くなった高レベル FNC1 percent の期待値ちょうど 8 件だけを、正確な current TypeScript baseline に由来する明示的な overlay で置き換えます。他の 5,602 件の公開期待値は変更せず、レコードを skip しません。
3. 固定した内部参照 corpus の 4,576 レコードは変更しません。全 65,536 GF 積、Reed–Solomon case、version/ECC/mask の raw matrix、data と ECC の codeword を含みます。独立した Nayuki に基づく case は corpus 内で明示し、関連する他言語版との一致から推測しません。
4. 元の GS1 履歴 request 1,411 件を変更せず、request に結び付いた current TypeScript の期待値と照合します。復元した positive target 80 件、正確な residual contract 168 件、独立に確認した診断移行 5 件を含みます。共有する authority/Digital Link の全 49 操作と、追加の current TypeScript positive 139 件を実行します。元の strict-authority 入力を明示的な assertion mapping とともに保持し、安全でない dot-path の拒否を引き続き必須にします。
5. 共有する current FNC1/GS1/DPI/ECC 回帰レコード 102 件をすべて実行します。Nim の以前の byte-only fallback 制限を引き継がず、current TS の安全な percent escaping を検証します。
6. 不正入力と資源境界の厳密なテスト、独立した optimizer 検査、CLI の Unicode・raw-byte・file・stdin/stdout の挙動を確認します。
7. 既定 scale 8 の PNG に対する独立 C++ decoder テストで、正確な payload と SA metadata を検証します。PNG framing、checksum、RGBA dimensions、全 pixel、quiet zone は独立に検査します。
8. Java の strict-PNG lane は別に実行します。detector の `NotFound` は detector の制限・失敗として記録し、復号成功に読み替えません。診断 lane は C++ の必須 decode gate を置き換えません。
9. 新しい offline の Makefile.PL インストールを、分離した prefix に行い、source tree 外の consumer process を使います。インストールしたライブラリのバイトは候補と一致する必要があります。
10. 独立した source review、公開向けに不要・非公開情報を除いた file inventory、正確な公開 commit に対する CI、新しい公開 source consumer を確認します。

## Harness integrity

harness は、最終 exit status、response 数、JSON 型、stderr 方針、末尾の余分な出力がないことを検査します。input/output/source の SHA-256 による結び付きを記録し、実行中の source 変更を拒否します。negative control は、有効な先頭部分に続く異常終了、不要な stderr、追加出力、不正または重複キーのある JSON、timeout、画像 framing の不一致を含みます。まだ動作中の test process は成功ではありません。

参照 vector と比較する生成テストと、独立した decoder 検査を区別します。移植性の説明は実装設計を述べるものです。検証済み platform と主張する根拠になるのは、実際に記録した platform/runtime の実行だけです。

## Running

基本的なインストール済み package のテストに必要なのは Perl core module だけです。

```sh
perl Makefile.PL
make test
```

source に結び付いた完全な検証には、`script/verify_native.py`、リポジトリ内の fixture manifest、固定した tooling installer を使います。必要な path は各 script の `--help` を参照してください。開発用の依存関係は package のインストールから分離しています。CI は変更しない checkout に対して同じ必須検査を実行し、完了時の証拠を upload します。

## Publication boundary

新しい公開 GitHub repository は、正確な候補と file inventory のレビュー後にだけ作成します。build tree、interpreter archive、cache、ローカルアカウント情報、非公開の作業ファイルは公開しません。公開対象は source release だけであり、CPAN upload、registry 公開、tag、無関係な repository の編集は含みません。完了には、正確な commit に対する hosted CI と、新しい公開 consumer の成功が必要です。

完了時の証拠は成果物とともに、runtime ファイルとは別に保存します。主張と件数は、レビューした source hash に対して完了した receipt に基づく必要があり、以前の開発時の成功から流用してはいけません。
