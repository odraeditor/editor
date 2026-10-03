# Tree-sitter Jan jan-org-9.8.10-v1

This directory is the repository-owned concrete grammar boundary for Jan
Document Language Stage 1. It is not an imported Org parser and does not define
compatibility independently of the accepted Odra specifications.

## Baseline

- Jan baseline: `jan-org-9.8.10-v1`
- Org syntax reference: `Org Syntax v2`
- Stable specification commit:
  `a0d1feaa414a0236f4fafc035cb890109d76c00a`
- Tree-sitter runtime: `v0.26.12`, ABI 15
- Generator: Tree-sitter CLI `0.26.9`, ABI 15

The Slice 3 grammar recognizes the structural family and the context-free
inline object family, including links, citations, footnote references,
timestamps, markup, targets, macros, scripts, cookies, entities, export
snippets, calls, source snippets, and table cells. Its external scanner
distinguishes blank lines from preserved `LF`, `CRLF`, and `CR` terminators and
preserves a final inline line without a terminator. Odin owns contextual
classification, configured syntax, and semantic indexes. In particular, radio
links require a confirmed configuration and declared radio targets, so they are
classified by Odin instead of represented as a raw grammar node. The parser is
not registered as an application provider; that remains a later delivery
slice.

## Reproduction

Run the repository-owned vendor check to verify source and generated digests,
ABI, baseline metadata, and generator identity. Normal build and validation use
the committed generated C source and do not invoke Node.js, npm, the generator,
the network, Emacs, or another Org implementation.

To regenerate intentionally after changing `grammar.js`, use the pinned CLI:

```sh
tree-sitter generate --abi 15
```

Regeneration must update `SHA256SUMS` in the same change and pass the vendor
check before the generated parser becomes a build input.

## Ownership and licenses

The grammar, metadata, and generated parser tables are Odra repository-owned
source. No external grammar source is copied into this directory. Generated
support headers originate from Tree-sitter templates and remain covered by the
MIT terms copied in `TREE_SITTER_LICENSE`. The separate Tree-sitter runtime
retains the same license at `third_party/tree-sitter/0.26.12/LICENSE`.
