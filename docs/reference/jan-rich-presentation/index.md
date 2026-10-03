<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Jan Rich Presentation Reference

Jan rich presentation is the Stage 2 package boundary for source-preserving
semantic projection, same-document footnotes, and bounded preview adapters. It
consumes exact copied Jan Document Language analysis. Derived presentation may
change what a capable surface shows, but it never changes canonical `.org` or
`.jan` text.

## Rich source projection

`jan_editing.rich_presentation_prepare` publishes one immutable generation for
an exact visible source range. Copied items include shared syntax roles and may
add:

- composed bold, italic, underline, strike-through, verbatim, and code markup;
- factory entity glyphs for `alpha`, `beta`, `gamma`, `lambda`, `pi`, and
  `nbsp`;
- visual heading indentation; and
- dynamic hierarchical heading numbers.

Each derived item retains its exact source range and optional copied display
text. Markup composition removes delimiters only from the derived display
value. Entity glyphs, indentation, and numbering are also display-only.

The projection always owns an exact copy of the requested source range. A
terminal or otherwise unsupported rich surface selects this source fallback
and retains semantic source roles, so every byte remains visible and editable.
Closing the projection releases copied items, display text, and fallback bytes.

## Local footnotes

Jan distinguishes a definition beginning a logical line from an embedded named
reference. Named, inline, and anonymous footnotes use the same exact Stage 1
node vocabulary.

`footnote_visit_local` moves between a named reference and its definition. An
inline or anonymous footnote resolves to its own source position when it has no
separate destination. `footnote_edit_plan_prepare` supports:

- creating one named definition;
- normalizing one named-inline or anonymous footnote into a reference plus
  definition;
- renumbering all local labels consistently by first occurrence; and
- moving complete definitions up or down.

Each admitted mutation is one checked rewrite plan and one normal
transaction/history unit. Other document bytes and Unicode body content are
preserved. Duplicate definitions, missing local destinations, invalid names,
stale analysis, malformed source, and allocation failures reject atomically.

Cross-resource footnote resolution and rewriting remain unavailable through
`jan-external-resources`, owned by Export, Publishing, and Integration.

## Preview adapters

Stage 2 exposes fixed factory-adapter capabilities for LaTeX fragments and
admitted image links. `preview_request_begin` validates the exact document,
source range, target node, view, adapter, configuration, provider, and resource
generations before retaining a pending identity.

LaTeX requests require no resource authority. Image requests require an
explicit admitted resource generation. The Jan package does not open the
resource, follow the link, access the network, or start a renderer. An adapter
performs any authorized work outside this package and returns bytes through
`preview_result_publish`.

A result becomes visible only when every asynchronous identity still matches.
Stale, cancelled, failed, missing-adapter, and unsupported-surface cases select
source fallback. The canonical editor buffer is never part of preview cache
state and preview publication cannot mutate it.

## Bounds and lifecycle

At most eight preview requests may be pending for one view. One copied result
may retain at most 8 MiB, and the process-wide cache may retain at most 64 MiB.
When a new result would exceed the cache bound, the oldest ready results are
evicted first. Eviction changes presentation and performance only.

`Preview_Cache` owns pending identities and copied result bytes. Inspection
returns copied descriptors; result access borrows bytes until eviction or
close. Closing the cache releases pending state and every copied result.

Rich projections remain bounded by the Stage 2 semantic-target limit and check
cancellation at least every 4,096 examined nodes. Fault tests cover every
retained projection, rewrite-plan, cache, and result allocation.

## Focused validation

Use:

```sh
make jan-structured-editing-focused-test
odin check src/jan_editing -no-entry-point -vet -warnings-as-errors
odin check src/display -no-entry-point -vet -warnings-as-errors
```

These commands validate models and static packages without importing or
building `src/odra`. Public application presentation and terminal source
fallback are covered by `jan-structured-editing-acceptance`.
