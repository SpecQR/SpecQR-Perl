# English API reference

## Runtime and installation

SpecQR 0.1.0 is a native, dependency-free Perl implementation. Supported minimum: Perl 5.42.3. The release validation profile uses official Perl 5.42.3 and 5.44.0 on Linux x86-64. The package uses only modules shipped with Perl; developer-only reference and decoder programs are not runtime dependencies. Install with `perl Makefile.PL`, `make`, `make test`, `make install`, optionally setting `INSTALL_BASE`. No CPAN publication is implied.

Import named functions with `use SpecQR qw(generate to_png);`. Optional export tags are `:qr`, `:segments`, `:render`, `:gs1`, `:structured_append`, and `:all`. Nothing is exported by default. Results, options, and segments are unblessed hash references; arrays are ordinary array references. Public operations validate and copy their inputs rather than retaining caller-owned segment storage.

## Text, bytes, and types

Text APIs take Perl character strings containing Unicode scalar values. ASCII strings need no special flag. Non-ASCII character strings must carry Perl's UTF8 flag. A non-ASCII, unflagged scalar is rejected rather than guessed to be Latin-1 or UTF-8. Use `use utf8` for source literals and `Encode::decode('UTF-8', $octets, Encode::FB_CROAK)` for external UTF-8 bytes. Malformed internal UTF-8, surrogates, and values above U+10FFFF are rejected.

`generate([0,128,255])` accepts opaque byte values, never text. Each value must be a numeric integer in 0..255. `byte_segment($octets)` accepts an unflagged octet scalar or an integer array and is always binary. `new_segment('byte', $characters)` encodes character text as UTF-8. A flagged string is not implicitly accepted as raw octets. ECI labels data; it does not transcode it.

Numeric settings require numeric scalars, not numeric-looking strings, booleans, arrays, or objects. Boolean settings accept numeric 0/1 or the core `JSON::PP` booleans. Unknown options and tied/blessed containers are rejected. JSON adapters and the CLI perform their own explicit conversion at the boundary.

## Generating and planning

- `generate($text_or_byte_array, \%options)` returns a QR result.
- `generate_segments(\@segments, \%options)` preserves explicit segment modes and boundaries.
- `plan($text_or_byte_array, \%options)` / `estimate(...)` return an arithmetic-only plan.
- `plan_segments(\@segments, \%options)` / `analyze_segments(...)` plan explicit segments.
- `get_capacity($version, $ecc = 'M', $mode = '', $control_bits = 0)` returns capacity details. An options hash with `version`, `errorCorrectionLevel`, `mode`, `controlBits` is also accepted.
- `diagnostics($result)` returns a checked, independent snapshot of QR, plan, SA-set, or merge diagnostics.
- `size($qr)` is its module width; `module_at($qr,$x,$y)` uses zero-based coordinates.

QR result fields: `matrix` (square array of 0/1 rows), `version`, `maskPattern`, `errorCorrectionLevel`, `dataCodewords`, `codewords` (byte arrays), `segments`, `options`, `diagnostics`.

Plan fields: `ok`, `version`, `capacityVersion`, `errorCorrectionLevel`, `requestedErrorCorrectionLevel`, `boostedErrorCorrection`, `dataBitLength`, `capacityBits`, `remainingBits`, `segments`, `diagnostics`. An unsuccessful automatic plan has `version => 0`; `capacityVersion` identifies the last tested capacity. Planning builds neither codewords nor matrices. Generation throws `DATA_TOO_LONG` when the selected range does not fit.

### Options

| Key | Default | Contract |
| --- | --- | --- |
| `errorCorrectionLevel` | `M` | Exactly `L`, `M`, `Q`, `H` |
| `version` | `0` | `0` or `auto` for automatic, otherwise 1..40 |
| `minVersion`, `maxVersion` | 1, 40 | Automatic search range, ordered |
| `maskPattern` | -1 | -1 or `auto` for selection; otherwise 0..7 |
| `mode` | `auto` | `numeric`, `alphanumeric`, `byte`, `kanji`, `auto` |
| `optimizeSegments` | 1 | Mixed-mode minimum-bit planning |
| `allowKanji` | 1 | Allow Kanji during automatic optimization |
| `boostErrorCorrection` | 0 | Increase ECC without increasing chosen version |
| `eciAssignment` | -1 | -1 absent; otherwise 0..999999 |
| `gs1` | 0 | Validate a GS1 element string and insert FNC1 |
| `fnc1` | 0 | FNC1 first position without GS1 element validation |
| `fnc1Second` | empty | A supported alphabetic or two-digit application indicator |
| `structuredAppend` | absent | Explicit SA header segment |
| `margin`, `scale` | 4, 8 | Nonnegative margin; positive integer scale |
| `foreground`, `background` | `#000000`, `#ffffff` | Safe hex or simple ASCII CSS color name |
| `printDpi` | absent | Finite positive number yielding finite positive geometry |

`errorCorrection` aliases `errorCorrectionLevel`; conflicting values fail. `eci => 26` aliases `eciAssignment => 26`; JSON booleans `true`/`false` mean UTF-8 ECI/absent. `encoding` supports only `utf-8`. These compatibility fields do not change the return type: rendering is explicitly invoked with `to_svg` or `to_png`. `output` accepts supported format names but generation still returns the QR result; `diagnostics` is validated and diagnostics remain available on results.

FNC1, ECI, and SA headers cannot be combined. Manual GS1 data must carry an explicit FNC1 segment instead of the high-level `gs1` option.

## Segments and controls

Constructors: `numeric($text)`, `alphanumeric($text)`, `kanji($text)`, `new_segment($mode,$text)`, `byte_segment($octets_or_array)`, `eci($assignment)`, `fnc1()`, `fnc1_second($indicator)`, `structured_append_segment($index,$total,$parity)`.

SA indices are one-based, totals 2..16, parity 0..255. Controls must obey QR ordering and cannot appear after data. An ECI assignment is a declaration, not an encoding conversion. Kanji mapping is the exact checked-in WHATWG-derived mapping used by the pinned SpecQR baseline, not the host platform's CP932 or Shift_JIS codec.

High-level FNC1 text treats literal `%` as data and U+001D as a separator. Alphanumeric conversion doubles literal percent. GS is preserved in byte mode; forcing alphanumeric for text containing GS is rejected. Automatic mode compares safe alternatives; forced alphanumeric performs the same escaping and capacity check. Low-level manual alphanumeric segments already contain the caller's QR FNC1 representation: `%` separator, `%%` literal percent. Manual byte data is opaque. This distinction is covered by the 102 shared regression vectors.

## Rendering

`to_svg`, `to_png`, `to_pixels`, `to_svg_data_url`, and `to_png_data_url` take either a QR result or a matrix, plus an optional render-only options hash. The override hash contains only `margin`, `scale`, `foreground`, `background`; it replaces defaults rather than merging arbitrary generation fields.

SVG is ASCII text with one path command per dark module. PNG is an unflagged octet string, RGBA8, with stored DEFLATE, CRC-32, and Adler-32 implemented in Perl. `to_pixels` returns `{width,height,pixels}` with `pixels` an unflagged packed RGBA octet string in row-major order. Save with `>:raw`; never apply a text encoding layer to PNG/pixels.

Raster colors accept `#rgb`, `#rgba`, `#rrggbb`, `#rrggbbaa`, `black`, `white`, `transparent`. Other simple ASCII CSS names are SVG-only, and contrast diagnostics explicitly indicate they cannot inspect them. `render_dimensions($result_or_matrix, \%render_options, $dpi)` returns pixel and optional millimetre geometry. Subnormal/overflow/underflow DPI values are rejected if they cannot produce finite positive dimensions.

Resource limits: 1,000,000 payload units, 16,384 manual segments, 4,194,304 raster pixels (side at most 2048), 8 MiB SVG characters, 32 MiB data-URL characters, geometry integers at most 1,000,000,000. Limits are checked before large raster allocation. QR capacity is a much smaller independent limit. Automatic single-symbol optimization is bounded to 7,089 characters.

## Structured Append

`generate_structured_append($text_or_bytes, \%options, $max_symbols=16, $diagnostics=0)` returns `{symbols,total,parity,inputLength,byteLength,diagnostics}`. All symbols share the selected version and ECC; each may select its own mask. The automatic search chooses the smallest version allowing a valid 2..16-symbol set. Text splits on Unicode scalar boundaries; binary splits on byte boundaries. Parity is XOR of original UTF-8 or raw bytes.

`generate_segments_structured_append(\@segments, \%options, $max_symbols=16, $diagnostics=0, $split_units='summary', $symbol_results='')` preserves non-byte segments indivisibly and only subdivides byte segments, respecting character boundaries in text-backed byte segments. Full split-unit diagnostics are available with `full`; `symbol_results` accepts `output` or `diagnostics`.

The high-level SA operation rejects single-symbol inputs, empty data, ECI/FNC1/GS1, an existing SA header, ECC boosting, and incompatible manual mode settings. Low-level SA headers remain available for externally managed sets.

`merge_structured_append_parts(\@parts)` takes decoded mappings `{index,total,parity,data}`, verifies complete unique indices, consistent metadata, homogeneous text/binary data, and XOR parity, then returns `{data,total,parity,parts,diagnostics}`. It does not decode images; decoder metadata must be supplied by the caller. No private decoder extension is assumed.

## GS1 and errors

See [GS1 profile](gs1.md) for the complete supported catalog, validation rules, Digital Link authority profile, and explicit historical reference differences. Unsupported AIs are rejected rather than guessed.

All validation failures throw `SpecQR::Error` with `code` and `message`. GS1 errors additionally provide `detailCode`. Typical codes are `INVALID_INPUT`, `INVALID_MODE`, `INVALID_ECC_LEVEL`, `INVALID_VERSION`, `INVALID_ECI`, `INVALID_COLOR`, `INVALID_OUTPUT`, `INVALID_GS1`, `DATA_TOO_LONG`; CLI I/O failures are reported as `IO_ERROR` and exit 2. Diagnostics warn about quiet zone, contrast, alpha, capacity, physical module size, and overall scan risk; they are not a guarantee that every camera/decoder will read every symbol.
