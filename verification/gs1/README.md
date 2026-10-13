# Optional independent GS1 oracle audit

Normal library and package tests require only Perl/core modules.

これらの harness は、独立した期待値を再生成するための開発専用の provenance tool です。Perl 実装の import は含まず、以下の正確な固定 source commit に対して実行する必要があります。取得や公開は行いません。

## Source pins

- 変更しない履歴 corpus: `verification/fixtures/gs1-upstream.json`。SpecQR TypeScript `15ad15e5c770ea0e39072f8f88b2733018f02ffd` に由来します。
- Nim oracle: `https://github.com/SpecQR/SpecQR-Nim`、commit `4f9154664d35a24cecb30b75cfdba0a9f16ced3e`。`src/specqr/gs1.nim` の SHA-256 は `9df6a11927f265108e4d01e3321a208e1bcd4f9c484ff6aad5f9b8bd42734fa3` です。
- current TypeScript oracle: `https://github.com/SpecQR/SpecQR`、commit `16efc6c0a8e397c9df3d051d20fce6c1eebdfad7`。GS1 Digital Link の source hash は `gs1-perl-deltas.json` に記録しています。

元の corpus は正確に 1,411 case です。すべての case を実行し、case ID は skip しません。その corpus の `input` の値はすべて文字列です。この harness は JSON options を型付き Nim API に対応付けます。明示的な `pathAis: []` は Nim の `explicitPathAis` flag を設定します。どちらの harness も期待結果を変換しません。

## Run from the package root

固定した source の検証済みローカル checkout を指定してください。例:

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
公開 payload/metadata field と、diagnostics の code/reason/count をすべて比較します。言語間の比較に限り、省略可能な null field、`length.isVariable`、成功時の空の `errors`、英語の診断文面を除外します。native Perl test では、これらの追加 metadata field も別途要求します。

`verification/fixtures/gs1-perl-deltas.json` は、すべての履歴差分を、正確な独立 Nim 結果、case ID、operation、説明、reason bucket とともに保持します。独立に観測した current TypeScript の 6 変更も含みます。履歴 fixture ファイルは変更せず、その SHA-256 をテストで検査します。現在の URL と診断の差分の詳細は `docs/gs1.md` で公開しています。

Current restoration results (Perl 5.42.3 and 5.44.0):

- Original published baseline versus current TS: 1,163 equal, 248 differences.
- Restored candidate versus current TS: 1,243 equal, 168 differences.
- All 80 restoration targets equal exact TypeScript expectations.
- Remaining categories: 132 diagnostic-only, 34 strict rejections, two safe-dot builder outputs.
- All 49 original shared operations and 139 extra positive operations are explicitly tested.

The historical 252-difference ledger remains unchanged as historical evidence.
現在の期待値と正確な assertion mapping は、`docs/gs1.md` と `docs/url-compatibility-mapping.md` に記載しています。完全な UTS46 は Perl core に含まれません。未変換の非 ASCII host は、外部依存を持たない実装の明示的な対象外です。
