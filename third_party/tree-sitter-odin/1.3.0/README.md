# Tree-sitter Odin 1.3.0

Odra vendors the generated Odin grammar and factory highlight query used by
the native syntax-analysis boundary.

## Source

- Repository: `https://github.com/tree-sitter-grammars/tree-sitter-odin`
- Revision: `v1.3.0`
- Commit: `e8adc739b78409a99f8c31313f0bb54cc538cf73`
- Retrieved: 2026-08-19

The generated parser, grammar metadata, node types, scanner, generated support
headers, C binding header, and highlight query are unmodified upstream files.
`grammar.js`, `tree-sitter.json`, `package.json`, and `package-lock.json` retain
their generation provenance. The upstream lock selects Tree-sitter CLI
`0.24.5`.

## Integrity and License

Run `make syntax-vendor-check` from the repository root to verify every
vendored file against `SHA256SUMS`, confirm grammar ABI 14, and check the exact
generation-tool record. Run `make syntax-vendor-build` to compile and link the
runtime and grammar without network access. The source is distributed under
the included MIT license.

## Regeneration and Update Policy

Regeneration uses Tree-sitter CLI `0.24.5` and the checked-in generation inputs.
Generated outputs must remain byte-identical to the selected upstream commit or
the revision, provenance, and digest manifest must be updated together. Vendor
a new grammar version in a new directory rather than replacing this pin.
