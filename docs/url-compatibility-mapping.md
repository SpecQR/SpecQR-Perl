# GS1 URL assertion mapping

元のファイル `gs1-upstream.json`、`gs1-perl-deltas.json`、`strict-authority-vectors.json`、`cross-port-regressions.json`、`expected-contract-vectors.json` はバイト単位で変更していません。元の request は削除していません。

## Original 1,411-request corpus

すべての case を native test で評価します。履歴の 252 行の証拠は保持します。独立に実行した current TypeScript の positive 80 件と、独立に確認した拒否診断 5 件は、特定した case ID の期待値だけを上書きします。厳密な process gate は、request に結び付いた完全な current oracle と 168 residual に対して、全 1,411 件を再び独立に実行します。

## Seven historical authority hosts

各 host について parse/validate/normalize の 3 操作をすべて残します。`0x`、`0X`、`1.0x`、`0x.`、`1.0X`、`1.2.3.0x` は、18 個の正確な positive assertion になります。`example.0x` は 3 個の拒否のままです。`current-ts-gs1-shared49.json` と `native-shared-gs1-deltas3.json` を参照してください。

## Former native-test rejections now accepted

これらの元の入力は `url-compatibility-extra.json` に残し、それぞれについて parse、validate、固定した TypeScript の正確な normalize 出力を検査します。

- `legacy-host-0`: "https://0x/01/09506000134352"
- `legacy-host-1`: "https://0X/01/09506000134352"
- `legacy-host-2`: "https://1.0x/01/09506000134352"
- `legacy-host-4`: "https://0x./01/09506000134352"
- `legacy-host-5`: "https://1.0X/01/09506000134352"
- `legacy-host-6`: "https://1.2.3.0x/01/09506000134352"
- `legacy-host-7`: "https://0x7f000001/01/09506000134352"
- `legacy-host-8`: "https://0177.0.0.1/01/09506000134352"
- `legacy-host-9`: "https://127.1/01/09506000134352"
- `legacy-host-10`: "https://2130706433/01/09506000134352"
- `legacy-host-11`: "https://127.0.0.01/01/09506000134352"
- `legacy-host-13`: "https://1.2.3.4./01/09506000134352"
- `legacy-host-16`: "https://user:password@example.com/01/09506000134352"
- `legacy-host-17`: "https://user@example.com/01/09506000134352"
- `legacy-host-19`: "https://%65xample.com/01/09506000134352"
- `legacy-host-20`: "https://a..example/01/09506000134352"
- `legacy-host-21`: "https://-bad.example/01/09506000134352"
- `legacy-host-22`: "https://bad-.example/01/09506000134352"
- `legacy-host-23`: "https://bad_name.example/01/09506000134352"
- `legacy-empty-port`: "https://example.com:/01/09506000134352"
- `legacy-empty-fragment`: "https://example.com/01/09506000134352#"
- `legacy-path-backslash`: "https://example.com\\x/01/09506000134352"
- `legacy-leading-space`: " https://example.com/01/09506000134352"
- `legacy-query-space`: "https://example.com/01/09506000134352?x=raw space"

それ以外の既存 native assertion はすべて残します。元の空 host の表記 `https:///01/09506000134352` は引き続き拒否します。slash の修復により `01` が host となり、その後の path 検証は primary の欠落を、従来の未対応 host の reason ではなく `GS1_INVALID_DIGITAL_LINK_PLACEMENT` として拒否します。これは診断の移行であり、受理への変更ではありません。

## Additional negative and positive coverage

追加の独立した positive 139 件には、上記のすべての移行、credential escaping、IPv4 の上限と reg-name の区別、IPv6 圧縮候補が同長の場合、空の credentials、多数のゼロを先頭に付けた port を含みます。明示的な negative は、overflow、数値候補内の不正な octal/hex、符号化された authority delimiter、credentials/host/path/query 内の不正な percent/UTF-8/NUL、不正な IPv6、IDNA の制限、diagnostics に credentials が含まれないことを対象にします。`0xg`、`1.0xg`、`1.2.3.0xg` は、独立に確認した positive の reg-name です。`0xg.1` は拒否する IPv4 候補です。

この変更には、FNC1 や通常の QR コアの契約変更を含みません。元の percent vector 102 件、manual vector 4 件、共有 GS1 操作 49 件、matrix/codeword corpus、decoder gate は引き続き必須です。

The additional current-TypeScript caret-prefix targets cover parse/validate/normalize for ASCII and Unicode prefixes and builder base serialization. A fresh 1,813-case deterministic probe identified this normalization gap outside the original corpus; it is fixed only in GS1 URL path serialization.

## Additional reviewed scope limits outside the original corpus

完全な UTS46/ACE 検証はありません。`xn--a` のような不正な ASCII A-label は公開済み baseline でも受け入れており、bare `xn--` は一般的な ASCII reg-name とともに新たに受け入れます。current TypeScript はこれらの例を拒否します。この制限を完全な WHATWG 適合と混同したり、元の 168 residual の件数へ追加したりしないでください。builder の base `/a//b` は公開済み baseline と同様に `/a/b` へ正規化します。current TypeScript は prefix 内の重複する slash を保持します。どちらの観測も、GS1 payload の dot-path 保護を変更するものではありません。
