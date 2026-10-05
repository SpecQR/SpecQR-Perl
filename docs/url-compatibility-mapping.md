# GS1 URL assertion mapping

The original files `gs1-upstream.json`, `gs1-perl-deltas.json`, `strict-authority-vectors.json`, `cross-port-regressions.json`, and `expected-contract-vectors.json` remain byte-for-byte unchanged. No original request was removed.

## Original 1,411-request corpus

Every case is evaluated in native tests. Historical 252-row evidence stays in place; 80 independently executed current-TypeScript positives and five independently witnessed rejection diagnostics override only their identified case IDs. The strict process gate independently executes all 1,411 again against the complete request-bound current oracle plus 168 residuals.

## Seven historical authority hosts

All three parse/validate/normalize operations remain for each host. `0x`, `0X`, `1.0x`, `0x.`, `1.0X`, `1.2.3.0x` become 18 exact positive assertions. `example.0x` stays three rejections. See `current-ts-gs1-shared49.json` and `native-shared-gs1-deltas3.json`.

## Former native-test rejections now accepted

These original inputs remain in `url-compatibility-extra.json`, each checked for parse, validate, and exact normalize output from pinned TypeScript:

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

All other existing native assertions remain. The original empty-host spelling `https:///01/09506000134352` remains rejected: slash repair makes `01` the host, then path validation rejects missing primary with `GS1_INVALID_DIGITAL_LINK_PLACEMENT` instead of the old unsupported-host reason. This is a diagnostic migration, not acceptance.

## Additional negative and positive coverage

The 139 extra independent positives include every migration above, credential escaping, IPv4 limits and reg-name distinctions, IPv6 compression ties, empty credentials, and long zero-padded ports. Explicit negatives cover overflow, invalid octal/hex in numeric candidates, encoded authority delimiters, malformed percent/UTF-8/NUL in credentials/host/path/query, invalid IPv6, IDNA limits, and credentials absent from diagnostics. `0xg`, `1.0xg`, and `1.2.3.0xg` are independently verified positive reg-names; `0xg.1` is a rejected IPv4 candidate.

No FNC1 or ordinary QR-core contract changes are part of this batch. The 102 original percent vectors, four manual vectors, 49 shared GS1 operations, matrix/codeword corpus and decoder gates remain required.

The additional current-TypeScript caret-prefix targets cover parse/validate/normalize for ASCII and Unicode prefixes and builder base serialization. A fresh 1,813-case deterministic probe identified this normalization gap outside the original corpus; it is fixed only in GS1 URL path serialization.

## Additional reviewed scope limits outside the original corpus

Full UTS46/ACE validation is absent: malformed ASCII A-labels such as `xn--a` were already accepted by the published baseline, while bare `xn--` is newly accepted with general ASCII reg-names. Current TypeScript rejects these examples. Do not mistake these limits for full WHATWG conformance or add them to the original 168 residual count. Builder base `/a//b` still normalizes to `/a/b`, as in the published baseline; current TypeScript preserves duplicate prefix slashes. Neither observation changes GS1 payload dot-path protection.
