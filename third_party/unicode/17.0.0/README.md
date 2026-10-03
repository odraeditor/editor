# Unicode 17.0.0 Data

Odra vendors the minimal official Unicode Character Database inputs required
to generate its deterministic terminal display profile and run the official
extended-grapheme conformance suite.

## Source

All files are unmodified downloads from the Unicode Consortium's versioned
Unicode 17.0.0 distribution:

- `https://www.unicode.org/Public/17.0.0/ucd/DerivedCoreProperties.txt`
- `https://www.unicode.org/Public/17.0.0/ucd/EastAsianWidth.txt`
- `https://www.unicode.org/Public/17.0.0/ucd/auxiliary/GraphemeBreakProperty.txt`
- `https://www.unicode.org/Public/17.0.0/ucd/auxiliary/GraphemeBreakTest.txt`
- `https://www.unicode.org/Public/17.0.0/ucd/emoji/emoji-data.txt`

The files were retrieved on 2026-08-12.

## Integrity

| File | SHA-256 |
| --- | --- |
| `ucd/DerivedCoreProperties.txt` | `24c7fed1195c482faaefd5c1e7eb821c5ee1fb6de07ecdbaa64b56a99da22c08` |
| `ucd/EastAsianWidth.txt` | `ea7ce50f3444a050333448dffef1cadd9325af55cbb764b4a2280faf52170a33` |
| `ucd/auxiliary/GraphemeBreakProperty.txt` | `d6b51d1d2ae5c33b451b7ed994b48f1f4dc62b2272a5831e7fd418514a6bae89` |
| `ucd/auxiliary/GraphemeBreakTest.txt` | `e2d134d2c52919bace503ebb6a551c1855fe1a1faec18478c78fff254a1793ec` |
| `ucd/emoji/emoji-data.txt` | `2cb2bb9455cda83e8481541ecf5b6dfda66a3bb89efa3fa7c5297eccf607b72b` |

## License

The data is governed by the included Unicode Data Files and Software License
and the terms identified in each source-file header. The canonical license is
published at `https://www.unicode.org/license.txt`.

## Generation and Update Policy

Run `make unicode-data` from the repository root to regenerate
`src/display/unicode17_data.odin`. Generated output is committed and must be
reproducible from these inputs.

A Unicode update uses a new version directory and profile identity. It must
not replace this directory in place. Update the source URLs, hashes, license
record, conformance fixture, project width cases, and alternate-profile test
before selecting the new profile.

## Odin Standard-Library Audit

The reference toolchain was Odin `dev-2026-07:301c287de`. Its
`core:unicode` tables explicitly identify Unicode 15.1.0, and its grapheme
helpers reference Unicode Text Segmentation revision 43. Those facilities are
useful but cannot prove Odra's pinned Unicode 17.0.0 contract. Odra therefore
uses the Odin standard library for UTF-8 encoding and validation while owning
only the missing generated Unicode property tables and segmentation policy.
