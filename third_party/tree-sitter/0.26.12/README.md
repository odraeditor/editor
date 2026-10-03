# Tree-sitter 0.26.12

Odra vendors the minimal Tree-sitter C runtime required by the factory Odin
syntax provider.

## Source

- Repository: `https://github.com/tree-sitter/tree-sitter`
- Revision: `v0.26.12`
- Commit: `808e4b1fc06e269a107c4bd8bd936cc6fde18b00`
- Retrieved: 2026-08-19

The checked-in files are the upstream `LICENSE`, public C header, and complete
`lib/src` implementation required by the amalgamated `lib.c` translation unit.

## Integrity and License

Run `make syntax-vendor-check` from the repository root to verify every
vendored file against `SHA256SUMS` and confirm runtime ABI 15 with minimum
compatible grammar ABI 13. The source is distributed under the included MIT
license.

## Update Policy

Vendor a new version in a new directory. Update the companion Odin grammar pin,
provenance, digests, ABI checks, and offline build probe before selecting it.
