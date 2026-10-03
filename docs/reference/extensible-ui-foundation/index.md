<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Extensible UI Foundation Reference

The `ui` package owns one bounded, frontend-independent logical UI generation.
It receives copied presentation records derived from existing semantic models,
validates one complete proposal, publishes that proposal atomically, and copies
an immutable snapshot for a compatible renderer.

The package boundary follows this pipeline:

```text
Model -> Projection -> View -> Surface -> Layout -> Renderer
```

Slice 1 established the records and publication lifecycle. Slice 2 moves every
ordinary single-view and pane-based editor presentation onto shared text
surfaces, split composition, attached pane status, and generic terminal root
lowering. Slices 3 and 4 move Startup, the Buffer Menu, Project inventory,
ambiguous directory resolution, and keymap inspection onto shared list roots.
Slice 5 adds checked input projection and moves every delivered candidate
source onto one shared list-and-input root. Slice 6 moves every non-search
text-entry and fixed-choice prompt onto shared input and root-edge status
presentation. Slice 7 completes built-in feedback migration for incremental
search, query replacement, command diagnostics, and passive status, then
removes direct prompt rendering.

## Entities and ownership

| Entity | Contract |
| --- | --- |
| Model | Remains owned by its existing editor subsystem. `Model_Reference` identifies one exact observation but grants no mutation authority. |
| Projection | Records the copied model-to-view payload size, item count, generation, and read-only policy. The registry owns the logical descriptor, not the semantic model. |
| View | Describes one `Text_View`, `List_View`, or `Input` presentation. List selection is explicitly model-owned or view-local. |
| Surface | Is a logical renderable, visible, and optionally focusable container with input and keymap context. It is not a terminal screen, native window, or physical renderer allocation. |
| Composition | Forms one bounded binary tree from surface leaves and above/below or left/right splits with exact positive weights. |
| Status region | Reserves copied compact content either on one surface or at the root edge. |
| Style and decoration | Preserve semantic presentation roles independently from physical colors, cells, or renderer effects. |
| Renderer profile | States the immutable physical frontend capabilities required by one published generation. The physical frontend owns its output surface. |
| Snapshot | Owns one immutable copied generation until `snapshot_close`; `Snapshot_View` borrows its slices only for that lifetime. |

`Registry`, `Proposal`, and `Snapshot` are non-copyable owners. Public handles
contain registry, object, root-generation, slot, and slot-generation identity;
they contain no borrowed native pointers.

## Initial primitive vocabulary

The initial visual views are text, list, and input. Composition admits only a
surface leaf and a binary split. Status regions, semantic style roles, and
anchored text-range, list-mark, or diagnostic decorations cover the real
presentation needs identified for migration.

`TreeView`, `TableView`, gutters, `Stack`, `Panel`, `Popup`, images, retained
notifications, and retained progress are not part of the foundation. A later
slice may add a primitive only when a real migrated consumer requires it.

## Publication lifecycle

| Operation | Result |
| --- | --- |
| `registry_init` | Creates one empty registry with a validated resource policy. |
| `proposal_begin` | Allocates one private generation against the exact current root, or the empty initial root. Only one proposal may be active. |
| `proposal_add_*` | Copies checked projections, views, surfaces, composition, status, styles, and decorations into bounded proposal storage. |
| `proposal_set_root` | Selects one complete composition root and one visible focusable surface. |
| `proposal_publish` | Validates the complete proposal and atomically replaces the published generation. The previous generation is released only after replacement. |
| `proposal_abort` | Releases an unpublished generation without changing the current root. |
| `registry_snapshot` | Copies the exact expected generation after checking the renderer profile and snapshot limit. |
| `snapshot_close` | Releases every copied snapshot collection exactly once. |
| `registry_close` | Releases the active generation and registry allocation exactly once. An active proposal must first publish or abort. |

Invalid, stale, incompatible, over-limit, or allocation-failed proposals do
not replace the published root. A failed snapshot releases every partial copy.
An immutable snapshot remains unchanged after a later root replacement.

Ordinary focus may move among visible focusable surfaces. An input view may
capture transient focus while retaining a checked return target. Release uses
that target when it is still valid and otherwise selects the first safe
focusable surface in the current generation.

## Delivered text surfaces

`proposal_project_editor_text_view` copies one exact delivered editor-view
generation, including buffer revision, point, mark, selection generation,
viewport, display policy, presentation ownership, and current search state.
It does not borrow the editor registry or buffer and grants no mutation
authority.

`proposal_map_pane_layout` converts one delivered layout snapshot into text
surfaces and split nodes while copying pane identity, geometry, focus, MRU,
history generation, dedication, weights, and separators. The UI root does not
become a second pane tree: every layout mutation still occurs in `layout`, and
a later layout generation requires a new proposal.

`proposal_compose_pane_status` attaches one bounded status region to each pane
surface. It copies at most 512 bytes of compact content, uses the delivered
one-row status geometry, and assigns the semantic `Status_Normal` or
`Status_Active` role.

The terminal exposes its required capability profile through
`renderer_ui_profile`. `renderer_present_ui` validates one immutable UI
snapshot and one compatible display/logical projection for every text surface,
then lowers text, splits, separators, status, cursor, region, and current-search
roles into one bounded full ANSI frame. It retains no logical UI or physical-row
cache between calls. Insufficient layout geometry uses the existing global
recovery presentation instead of publishing partial pane geometry.

Syntax spans use this same path as exact-revision `Text_Range` decorations.
Styles may carry optional sRGB foreground and background colors, and the
terminal lowers them for true-color, 256-color, 16-color, or monochrome
profiles. See the
[Semantic Syntax Presentation Reference](../semantic-syntax-presentation/index.md)
for role mappings, precedence, degradation, limits, and failure behavior.

## Delivered list roots

`proposal_project_list_view` copies one complete bounded item generation with
stable item identity, text, either a semantic action reference or passive-row
status, an optional mark, explicit selection ownership, current item, viewport,
and read-only policy. The current item must remain actionable. Startup, the
Buffer Menu, Project inventory, ambiguous directory resolution, and keymap
inspection use this contract through `renderer_present_ui`.

Project and Workspace list workflows retain their semantic descriptors outside
the UI registry. Rows expose Project or Workspace identity, root or member
count, trust, availability, and normalized paths as applicable. View-local
selection follows stable identity across refresh. Enter inspects or activates
one exact candidate; `q` and `Control-G` close through the checked UI return
target.

Keymap inspection retains its `Inspection_Result` and `Command_Catalog` until
close. Rows format sequence, binding, remap, conflict, map, snapshot, profile,
pending input, availability, protection, rejection, and provenance fields, but
the semantic records remain authoritative. Up and Down move view-local
selection; `q` and `Control-G` return to the captured primary view; `M-x`
returns first and then opens command navigation.

Project and inspection models use monotonic generations across close and
reopen. Invalid or stale generations, generation exhaustion, item or text
overflow, invalid geometry, incompatible profiles, and allocation faults reject
before root publication. Project batches, inspection results, catalogs,
proposal storage, snapshots, and temporary row text have explicit close or
deallocation paths.

## Delivered candidate roots

Command, session-buffer, Project-buffer, and Project-file candidate sessions
all project through the same composed root. The upper surface is a read-only
`ListView` whose selection owner is `Model`; its current row and viewport are
copied from the exact `Candidate_View` generation. Each row receives a checked
action reference bound to that session generation. Source adapters retain
ownership of command, buffer, document, and Project identities and format
their existing annotations into copied row text.

The lower surface is an `Input` projection bound to the same candidate-session
generation. The candidate session owns the query and every query mutation;
the UI registry owns only copied value bytes, presentation generation, cursor,
UTF-8-safe horizontal viewport, and `Valid` or `Rejected` visual state. The UI
does not match, rank, move selection, update history, or infer an action from
display text.

One root-edge `StatusRegion` reserves the bottom row and reports source, scope,
and selected/result counts. The list and input surfaces are composed above and
below within the remaining checked geometry. The input surface captures focus
after atomic root publication. Closing by acceptance or cancellation releases
the candidate session and restores its recorded primary-view return target;
stale actions and return targets never retarget by label or row position.

A recoverable candidate failure keeps the previous semantic generation and
projects its bounded diagnostic as rejected input for that turn. Invalid UTF-8,
zero or insufficient geometry, stale backing or root generations, input,
choice, list, projection, status, snapshot, or temporary-storage limits,
generation exhaustion, renderer incompatibility, and allocation failure reject
without publishing a partial replacement. Candidate sources remain bounded at
4,096 rows and 32 MiB of copied source text; input is bounded at 4 KiB, and the
prompt label is bounded at 128 bytes.

The candidate migration was the final consumer of component presentation.
`Component_Kind`, component adapters and snapshots, the component visible
target, and `renderer_present_component` are removed. `Component_Tool` and
`component-*` command names remain contextual-keymap vocabulary; they do not
name a retained presentation registry or renderer path.

## Delivered transient input and feedback roots

All 21 non-search prompt modes project through `Input`: save paths, file and
other-pane file opening, buffer switching and killing, Project directory and
registration operations, marked-buffer operations, exit protection, and
keymap inspection. Each mode receives a distinct owner identity and a
monotonic backing generation. A projection accepts only the active mode,
matching prompt kind, exact generation, and active semantic state. A fixed
choice action additionally carries the exact owner, action identifier, and
generation; stale actions do not resolve by visible name or position.

`interaction.Prompt` remains the semantic owner of text-entry and fixed-choice
state. It owns accepted text, active or terminal status, selected choice, and
the mapping from each copied display name to its existing command. The UI
generation owns only copied value bytes, cursor, horizontal viewport,
validation state, choice descriptors, and presentation geometry. Keymap
sequence inspection follows the same input projection contract while retaining
its sequence as the semantic source.

The current editor, pane layout, Startup list, Buffer Menu, Project list, or
keymap list remains the base root. While a prompt is active, the base content
is materialized one row shorter and a focusable `Input` surface occupies the
final row. A root-edge `StatusRegion` carries the prompt label and fixed-choice
names. The label is clipped only at Unicode grapheme boundaries and always
leaves at least one input cell. Closing the prompt releases that row, advances
or clears semantic state as applicable, and restores the base geometry on the
next complete publication.

Input focus is captured only after the composed generation publishes. The
previous focus surface is the checked return target. Acceptance, cancellation,
owner closure, or command-context teardown releases capture exactly once;
invalid return targets use the registry's safe focus fallback. A second
projectable prompt cannot replace an already active prompt generation.

Prompt text is bounded at 4 KiB. One semantic prompt admits at most three
fixed choices, and each visible choice name is bounded at 64 bytes. The shared
UI policy independently bounds copied input at 4 KiB and admits at most 64
fixed-choice descriptors across one generation. Empty input follows the
semantic prompt's `allow_empty` policy. Malformed UTF-8, text or choice
overflow, stale generations, wrong owners, invalid prompt kinds, insufficient
height, incompatible profiles, generation exhaustion, and allocation faults
reject without publishing a partial root. Rejected semantic turns publish the
same checked input with `Diagnostic_Rejected` validation when recovery remains
possible.

Incremental literal and regular-expression search use the same `Input` and
root-edge `StatusRegion`. The input remains a projection of the bounded search
prompt; direction, effective case, active, failing, pending, wrapped, and
parser-diagnostic state remain owned by the search workflow and view session.
Query replacement projects pattern and replacement entry as text input. Its
response state projects the checked `pattern -> replacement` value plus five
named actions for replace, skip, replace remaining, replace and exit, and quit.
Every stage transition advances the projection generation.

When no input workflow is active, a bounded command diagnostic or passive
Project status may reserve the same final row without adding an input surface.
Diagnostics use `Diagnostic_Normal`; passive information uses `Status_Normal`.
Rejected input uses `Diagnostic_Rejected`, and active input uses
`Status_Active`. The base root is materialized one row shorter in each case and
restored by the next complete publication.

The terminal applies semantic style roles rather than feature names. Current
search styling overrides active-region styling only on overlapping cells;
region styling remains visible around the match. List-current styling and save
or kill mark styling occupy independent roles. Status and diagnostic regions
are lowered from their recorded role. `renderer_present_prompt` and its
physical prompt-output limit are removed; every ordinary built-in prompt,
search, replacement, diagnostic, and passive status frame now passes through
`renderer_present_ui`.

## Selected resource limits

The independent resource study compares contiguous generational slots with
linear lookup and packed snapshots with expanded snapshots under ordinary,
demanding, and stress profiles. It selected direct indexed lookup and the
following initial policy:

| Resource | Limit |
| --- | ---: |
| Live surfaces and views | 128 each |
| Split depth | 32 |
| Composition nodes | 255 |
| Status regions | 129 |
| List items | 4,096 |
| Input bytes | 4 KiB |
| Fixed choices | 64 |
| Projection bytes | 32 MiB |
| Styles | 64 |
| Decorations | 65,536 |
| Compact-region bytes | 64 KiB |
| Event subscriptions, queued events, and deferred work | 256 each |
| Callback depth | 64 |
| Snapshot bytes | 8 MiB |
| Temporary bytes | 64 MiB |
| Diagnostic bytes | 4 KiB |
| Geometry work | 1,048,576 units |

`Registry_Stats` reports occupancy, focus generation, and exact retained or
peak accounting. Limit relationships are validated as one policy at registry
initialization; callers cannot raise them beyond the compiled ceilings.

## Failures and preservation

`Failure` records the operation, precise failure code, current root, relevant
object, selected limit and actual value, and required renderer profile. Failure
codes distinguish invalid or stale identities, wrong ownership, focus state,
each resource ceiling, renderer incompatibility, generation exhaustion,
checked integer overflow, allocation, and a busy registry.
`failure_code_diagnostic` maps every nonzero code to one stable human-readable
diagnostic. `role_failure_code_diagnostic` and the Racket
`ui-role-failure-diagnostic` procedure provide the same exhaustive contract for
UI role failures.

Expected rejection preserves the active root, focus, logical records, and
renderer contract. Failures never expose native pointers or partially
published collections.

## Evidence boundary

`tests/ui_reference` is an implementation-independent fixed-array lifecycle
model. `tests/ui_equivalence` compares the production registry with that model
over generated valid and invalid sequences. `tests/ui_resource_study` records
representation selection, resource ceilings, timing, rejection, and complete
cleanup evidence.

The Racket runtime can inspect the complete copied logical generation and
select checked session-scoped providers for the seven current UI roles.
Existing semantic owners remain authoritative. Candidate, prompt, search,
replacement, diagnostic, and passive status presentation use shared UI roots.
See [Programmable UI Roles Reference](../programmable-ui-roles/index.md) for the
provider and capability boundary.

`make ui-migration-check` verifies the production consumer matrix and rejects
superseded presentation entry points. `make ui-resource-gates` runs the final
ordinary, demanding, and stress profiles across every current consumer and
programmable role. `make ui-acceptance` runs the independent, generated,
fault, native, Racket, integration, PTY, resize, output, end-to-end, and
teardown matrix.
