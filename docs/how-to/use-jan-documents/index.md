<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Use and Diagnose Jan Documents

## Open a Jan document

Open a well-formed UTF-8 file whose suffix is exactly `.org` or `.jan`. Both
suffixes select the bundled `jan` language identity and
`factory-jan-tree-sitter` provider. Suffix matching is case-sensitive.

For another suffix, use the checked explicit language-selection workflow. The
selection changes derived analysis, not source bytes.

## Inspect the current analysis

Run these commands through `M-x`:

| Command | Use |
| --- | --- |
| `jan-language-status` | Confirm recognition, provider, baseline, generations, limits, capability counts, and latest rejection. |
| `jan-inspect-syntax` | Inspect the deepest syntax path and exact byte range at point. |
| `jan-lint` | Produce bounded diagnostics from the current confirmed analysis. |
| `jan-lint-refresh` | Recompute diagnostics after an ordinary edit. |

The factory profile assigns no mandatory physical bindings to these commands.

## Preserve source while editing

Use ordinary text insertion, deletion, undo, redo, and save commands. Jan
analysis follows the canonical buffer revision. It does not regenerate the
document during save.

Before testing no-edit fidelity, record a checksum:

```sh
sha256sum document.org
```

Open and save without editing, exit, and run the same command again. Matching
digests establish byte identity for that file.

## Diagnose unavailable or stale state

Run `jan-language-status` and distinguish these outcomes:

| Outcome | Meaning | Action |
| --- | --- | --- |
| `Unsupported` | The active buffer does not select Jan. | Check the exact suffix or explicit selection. |
| `Incomplete` | No current confirmed analysis is available. | Continue ordinary editing and allow maintenance to complete. |
| `Stale` | The requested scope does not match the current revision or generation. | Retry after current analysis is confirmed. |
| `Malformed` | Recovery syntax exists in the retained source. | Inspect or lint the reported range; repair only when intended. |
| `Limited` or `Allocation_Failed` | A bounded candidate was rejected. | Preserve the document and inspect the reported limit and usage. |
| `Unavailable` | The selected command, adapter, tool, or provider is not operational in this build or configuration. | Continue ordinary editing, inspect the owning status, and configure only the required optional dependency. |

Failures preserve editable text and cannot authorize work against stale
analysis. Parsing and inspection never follow links, execute code, access the
network, or publish external changes.

## Run focused repository checks

From the repository root:

```sh
make jan-document-language-focused-test
make jan-document-language-acceptance
```

The first target verifies the offline corpus, parser boundary, resource model,
revision and failure behavior, and focused native package. The second builds
the application when necessary and drives `.org` and `.jan` through a bounded
real-terminal workflow.

See the [Jan Capability Ledger](../../reference/jan-stage-1-capabilities/)
for package-complete and linked-application state and the
[Jan Product Surface Reference](../../reference/jan-product-surface/)
for commands, providers, backends, limits, and extensions. See the
[Jan Inspection and Lint Reference](../../reference/jan-inspection-and-lint/)
for copied records, limits, and rejection behavior.
