<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Editor Core API

The Odin source comments are the authoritative declaration-level reference.
Render them in source order with:

```sh
odin doc src/text -in-source-order
odin doc src/editor -in-source-order
```

Odin test cases must be public to the test runner. They therefore also appear
in generated package documentation and are documented as verified guarantees,
not as callable production operations.

The cross-language packages are documented separately in
[Racket Runtime Boundary Reference](../racket-runtime-boundary/index.md).

## `editor` package

The `editor` package owns canonical state and the atomic publication boundary.

| Area | Public declarations | Contract |
| --- | --- | --- |
| Identity | `Buffer_ID`, `Revision`, `Byte_Offset`, `Position` | Positions are tied to one buffer revision and a UTF-8 byte boundary. |
| Bounds | `Limits`, `DEFAULT_LIMITS`, `MAX_*` constants | Size, allocation, inspection, reclamation, and work are explicitly bounded. |
| Lifecycle | `Buffer`, `Allocator_Set`, `buffer_init`, `buffer_close`, `buffer_is_live` | Initialization acquires persistent resources; close releases them and invalidates the handle. |
| Inspection | `buffer_position`, `buffer_inspect`, `buffer_stats` | Inspection copies into caller storage and never exposes a rope-owned byte view. |
| Editing | `Splice`, `Validated_Splice`, `Prepared_Splice`, `buffer_validate_splice`, `buffer_prepare_splice`, `buffer_splice` | Validation and preparation leave canonical state unchanged; successful publication advances one revision. |
| Prepared data | `prepared_splice_is_valid`, `prepared_splice_abort`, `prepared_splice_change_set`, `prepared_splice_undo_record`, `prepared_splice_inspect` | A prepared handle owns an unpublished candidate until it is consumed or aborted. |
| Results | `Change_Set`, `Undo_Record`, `Failure_Code`, `Failure_Context` | Committed text views are buffer-owned; expected failures are explicit values. |

`position_make` constructs identity-bound positions without consulting a live
buffer. Normal editor clients should prefer `buffer_position`, which also
checks the current text and UTF-8 boundary.

## `text` package

The `text` package owns immutable persistent rope storage.

| Area | Public declarations | Contract |
| --- | --- | --- |
| Shape | `Layout`, `DEFAULT_LAYOUT`, leaf and internal-node constants | Leaf size, fanout, and tree height have explicit bounds. |
| Summaries | `Byte_Count`, `Line_Feed_Count`, `Node_Count`, `Summary` | Each root carries composable text metrics. |
| Limits and failures | `Storage_Limits`, `Storage_Failure_Code`, `Storage_Failure` | Storage reports expected bound and input failures without partial ownership escaping. |
| Root lifecycle | `Root`, `root_build`, `root_is_valid`, `root_retain`, `root_release` | Every valid root handle owns one reference and must be released exactly once. |
| Root operations | `root_stats`, `root_copy_range`, `root_prepare_splice`, `root_maintain` | Reads do not allocate; splice preparation preserves the base root and may share immutable nodes. |

## Ownership summary

1. The caller owns `Buffer` and `Prepared_Splice` handle storage.
2. A live buffer owns its rope root and committed change and undo text.
3. A valid prepared splice owns its candidate root and candidate records.
4. Every valid `text.Root` handle owns one retained reference.
5. Inspection destinations are always caller-owned.

See [Ownership and Lifetimes](../../explanation/ownership-and-lifetimes/index.md)
for the reasoning behind these boundaries.
