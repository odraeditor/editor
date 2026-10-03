<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Jan Native Output Backends Reference

Jan provides four factory-native deterministic backends over the copied output
tree: plain text, HTML, Markdown, and normalized Jan/Org. They produce bounded
candidate bytes in caller-owned storage. Rendering never mutates source or
publishes a destination.

## Shared input

All native backends consume the same validated document:

- a bounded UTF-8 title and language;
- ordered normalized blocks;
- ordered inline fragments referenced by exact block intervals; and
- explicit backend options and output limits.

Blocks cover headings, paragraphs, list items, quotations, source and example
blocks, horizontal rules, and explicitly governed raw content. Inline fragments
cover text, emphasis, strong text, code, links, images, math, and raw content.
Invalid kinds, ranges, levels, targets, encodings, policies, or output capacity
reject before a complete candidate is returned.

## Plain text

Plain text preserves section structure, paragraphs, list and quotation markers,
source indentation, link destinations, image descriptions, and horizontal
rules. It supports explicit UTF-8, ASCII, and Latin-1 policies.

An unrepresentable character rejects the output unless replacement was
explicitly requested. Replacement writes one `?` per unrepresentable Unicode
scalar; it never truncates or silently corrupts encoded text.

## HTML

HTML supports minimal fragments and complete HTML5 documents. Complete output
contains an explicit doctype, language, UTF-8 metadata, escaped title, optional
escaped CSS content, and body.

Text and attribute contexts escape their relevant HTML characters. Links,
images, math, headings, quotations, code, and examples receive structural
elements. Raw blocks and inline raw fragments reject by default. They pass
through only when raw policy is explicitly enabled; plain-text fallback remains
escaped and produces a diagnostic.

The backend does not fetch links or media, execute scripts, evaluate math,
interpret CSS, or write a resource.

## Markdown

Markdown maps headings, paragraphs, list items, quotations, fenced code,
horizontal rules, emphasis, strong text, code, links, images, and inline math.
Markdown control characters in ordinary text are escaped. Unsupported forms
follow the explicit reject, plain-text-with-warning, or omit-with-warning
policy; they cannot disappear without a diagnostic.

## Normalized Jan and Org

Normalized Jan/Org output emits one compatible structured-text representation
for the selected scope. It writes title keywords, heading stars, compatible
inline markup, links and images, quote blocks, source and example blocks, and
horizontal rules.

Normalized export is distinct from ordinary save. Save preserves canonical
bytes; normalized output intentionally serializes the copied tree into a stable
representation. `.jan` and `.org` goldens are byte-identical.

## Unsupported forms

Each render request selects one policy:

- `Reject` returns an unsupported-node failure and no complete candidate;
- `Plain_Text_With_Warning` preserves inert visible text and increments
  diagnostic accounting; or
- `Omit_With_Warning` omits the unsupported value and increments diagnostic
  accounting.

Raw content additionally requires the explicit raw-content option. An
unsupported policy does not grant raw authority.

## Inspection

Backend inspection reports four stable available factory-native identities,
their capability, complete-document support, raw-content policy requirement,
and encoding count. Inspection performs no rendering and does not imply a
checked destination.

| Backend | Capability | Full document | Encodings |
| --- | --- | --- | ---: |
| Plain text | `Plain_Text` | no | 3 |
| HTML | `Html` | yes | 1 |
| Markdown | `Markdown` | no | 1 |
| Normalized Jan/Org | `Normalized_Jan` | no | 1 |

## Failure and output guarantees

Malformed normalized input, unsupported content, unrepresentable text, invalid
policy, or insufficient destination capacity returns no complete result.
Successful results report exact backend, byte count, diagnostic count, and
completion. The renderer cannot partially publish its caller-owned buffer.

## Focused validation

Use:

```sh
make jan-output-focused-test
```

The target exercises all four Odin renderers, encoding rejection and explicit
replacement, HTML escaping and raw-content policy, bounded output, stable
inspection, and deterministic Racket-generated offline goldens for plain text,
HTML, Markdown, normalized Org, and normalized Jan. It does not build or run
the complete editor or invoke an external tool.
