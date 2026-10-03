<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Ksawery Reference

Ksawery is a full-canvas, session-scoped interface to one local Git repository.
The current capability observes repository status, presents semantic change
groups, paths, tracked text hunks, and bounded history, visits paths, stages or
unstages exact paths and compatible granular targets, creates checked commits,
discards one complete tracked working-tree path after confirmation, observes
refs and remotes, performs checked fetch and explicitly confirmed single-branch
push, and manages confirmed local branches and lightweight tags.
The same session exposes bounded active and recent operation records without
turning process output into repository authority.
It also observes Git-owned sequences and provides checked merge, rebase,
ordered cherry-pick or revert, manual bisect, conflict-resolution, and explicit
recovery controls.

## Entry, Context, and Exit

`ksawery-status` is available through `M-x`. It requires an active document
with an absolute local target path inside a Git repository. Entry resolves the
repository from that resource, starts one noninteractive observation, retains
the current editor-visible target, and presents the Ksawery UI root.

Ksawery owns the complete visible canvas while active. Ordinary panes, panels,
buffers, and terminal sessions remain retained but do not receive visible or
independent input. `q` leaves a visited resource for Status, then leaves Status
for the retained editor target. A missing retained primary view falls back to
the most recently used live editor target.

## Status Order and Identity

Nonempty groups appear in this fixed order: Unmerged, Untracked, Unstaged, and
Staged. Each group and path has a semantic identity tied to one immutable
observation generation. Empty groups are omitted. A repository without changed
paths reports `Working tree clean`.

Selection, detail, visits, and index actions use semantic group and path
identities. Rendered rows, coordinates, labels, and raw path text are not
mutation authority. Refresh replaces the observation and reconciles the
selection when the same path remains valid.

## Commands and Keys

| Operation | Key | Result |
| --- | --- | --- |
| Move to the previous item | Up or `C-p` | Selects the previous semantic group or path. |
| Move to the next item | Down or `C-n` | Selects the next semantic group or path. |
| Toggle path detail | Tab | Opens or closes bounded read-only detail for the selected path. |
| Visit a path | Enter | Presents the selected file inside the active Ksawery session. |
| Refresh Status | `g` | Starts a fresh repository observation. |
| Mark a target | `*` | Adds the selected path or hunk to the bounded session-local target set. |
| Unmark a target | `-` | Removes the selected path or hunk from the marked set. |
| Clear marks | `0` | Clears the complete marked set. |
| Stage | `s` | Stages the selected path or hunk, or every compatible marked target, then refreshes. |
| Unstage | `u` | Unstages the selected path or hunk, or every compatible marked target, preserves working-tree content, then refreshes. |
| Discard a path | `k` | Opens exact confirmation for one eligible tracked working-tree path. |
| Browse History | `h` | Opens bounded repository History from the checked repository. |
| Browse Refs | `b` | Opens bounded branches, tags, remotes, `HEAD`, and tracking state. |
| Inspect active Sequence | `M-x ksawery-sequence` | Opens the current Git-owned sequence when one is observable. |
| Inspect repository processes | `$` | Opens the active operation and recent terminal outcomes, returning later to this exact source surface. |
| Enter a raw repository command | `!` | Opens the built-in bounded Git or shell command route and requires exact review before execution. |
| Inspect extension providers | `v` | Opens the active contributor generation, provenance, authority, limits, usage, failure, Process, and fallback state. |
| Reload personal providers | `L` | Atomically prepares and activates one valid complete personal generation or retains the last confirmed generation. |
| Disable the personal provider | `M-x ksawery-provider-disable` | Disables it only while every repository and provider workflow is idle and keeps built-in fallback active. |
| Compose a normal commit | `c` | Opens commit-message composition when the checked index has staged content and no unmerged paths. |
| Return or exit | `q` | Returns from a visited resource to Status, or closes Status and restores the prior editor target. |

A primary-button press on a visible Status group or path selects that semantic
item. Pointer presses outside the Ksawery root do not reach hidden editor
surfaces.

## Status Families and Repository Inspection

`?` opens the contextual Status dispatcher. A family key opens its available
actions without executing one. `q`, Escape, or `C-g` returns without an
effect.

| Family | Status sequence | Result |
| --- | --- | --- |
| Stash | `z z` or `z l` | Opens the bounded stash list. |
| Worktree | `Z Z` or `Z l` | Opens the checked linked-worktree list. |
| Reflog | `l r` | Opens bounded reflog entries with complete commit identities. |
| Blame | `B b` | Attributes the selected Status path to exact commits. |
| Clone | `C C`, `C s`, `C b`, or `C m` | Prepares regular, shallow, bare, or mirror clone arguments. |
| Ignore | `i t` or `i p` | Opens `.gitignore` or `.git/info/exclude` as an editor resource. |
| Init | `I I` | Prepares repository initialization with an explicit destination. |
| Submodule | `o` | Prepares add, list, update, synchronize, or deinitialize arguments. |
| Subtree | `O` | Prepares add, merge, pull, push, or split arguments. |
| Notes | `T` | Prepares add, remove, or prune arguments. |
| Apply patches | `w` | Prepares mail or plain-patch application. |
| Format patches | `W` | Prepares format-patch, saved diff, or request-pull output. |
| Sparse checkout | `>` | Prepares enable, disable, reapply, set, or add operations. |

The four inspection surfaces use `n` and `p` to move, Enter to toggle retained
detail, `g` to replace the observation, and `q` to return to Status. Blame and
Reflog use `v` to inspect the selected exact revision.

The Stash surface provides `c` create, `v` inspect, `a` apply, `p` pop, `b`
branch, and `k` drop. The Worktree surface provides `c` create, `v` visit, `L`
lock, `U` unlock, `P` prune, and `k` remove. Every mutation requires explicit
confirmation and refreshes Status before Ksawery reports its result.

Advanced Git families prepare bounded Git arguments in the existing raw
repository-command editor. The prepared prefix remains editable. `C-Enter`
opens exact review, a second `C-Enter` starts the process, and `C-g` cancels
before an effect. Git mode supplies the `git` executable directly and does not
invoke a shell. A started operation uses the same output limits, deadline,
cancellation, cleanup, full compatible refresh, and indeterminate-outcome
rules as an explicitly entered raw command.

Clone and Init require the user to finish the source or destination arguments;
Ksawery does not infer a filesystem target. Subtree reports Git support failure
when `git subtree` is unavailable. Patch and mail workflows operate on explicit
local paths or ranges and do not send mail. Network operations remain subject
to the configured Git transport and the noninteractive process environment.

## Repository Processes and Outcomes

`$` opens Ksawery Processes from Status, History, Refs, Sequence, or Conflict. The Process surface
retains its source mode and list position. `q` returns to that exact source;
opening or closing Process detail does not cancel repository work.

Rows are ordered with the one active operation first and terminal records
newest first. Up, Down, `C-p`, and `C-n` move the semantic selection. Enter
toggles bounded detail for the exact selected record, and `g` reconciles the
selection with the latest immutable generation. Detail may contain the public
phase, outcome message, exit status, standard output, diagnostics, and explicit
truncation state. Native handles, private arguments, environment values, and
credential-bearing remote text are not public record content.

Public phases are `Checking`, `Executing`, `Refreshing`, `Verifying`,
`Cancelling`, and `Cleaning_Up`. Progress remains phase-based unless an
operation supplies one truthful finite measure; elapsed time, polling, and
captured byte counts do not become invented percentages.

| Terminal outcome | Meaning |
| --- | --- |
| `Verified_Success` | The child completed and refreshed Git state proves the requested result. |
| `Known_Failure` | The operation failed and the resulting repository state is known. |
| `Cancelled_Before_Effect` or `Timed_Out_Before_Effect` | Cancellation or timeout completed before a repository effect started. |
| `Cancelled_After_Possible_Effect` or `Timed_Out_After_Possible_Effect` | Interruption occurred after an effect may have started; refreshed state determines what can be claimed. |
| `Verification_Mismatch` | The child result and refreshed repository evidence do not verify the requested result. |
| `Indeterminate` | An effect may have started, but child and refresh evidence cannot prove one final repository outcome. |

`C-g` requests cancellation only when the exact selected active generation
offers that action. The child owner sends graceful termination, waits the
bounded cancellation grace, escalates at most once when required, reaps the
child, closes both streams, and refreshes repository truth whenever an effect
may have occurred. Stale or repeated cancellation requests are rejected.

Output and diagnostics are bounded inspection evidence. They never authorize
a selection, mutation, retry, or success claim. A retry starts a new checked
operation against a current observation; no retained command text is replayed.
Process records persist only for the active Ksawery session.

## History, Revision Inspection, and Commit Actions

History is a bounded immutable observation of ancestry from the checked
repository `HEAD`. Revision selection uses complete Git object identities, not
rendered subjects, abbreviated hashes, graph marks, or row positions. An unborn
repository has an explicit empty History state.

| History operation | Key | Result |
| --- | --- | --- |
| Move | Up, Down, `C-p`, or `C-n` | Selects one semantic revision. |
| Inspect revision | Tab | Opens read-only metadata, parents, changed paths, and a bounded diff for the exact revision. |
| Set range base | `*` | Marks one compatible exact revision as the range base. |
| Inspect range | Enter | Opens the ordered range for the marked base and selected compatible revision. |
| Next page | `f` | Requests another available bounded History page. |
| Refresh History | `g` | Requests a new History observation and reconciles exact surviving selection. |
| Amend `HEAD` | `A` | Opens composition for the exact observed `HEAD`, followed by explicit confirmation. |
| Create fixup | `F` | Opens the derived read-only `fixup!` message for the selected exact revision. |
| Return | `q` | Returns from revision detail or range to History, or from History to Status. |

Commit-message composition accepts ordinary text input. `C-Enter` finalizes a
normal or fixup request. An amend request requires a second `C-Enter` on its
exact confirmation. `C-g` cancels before process start and retains the draft
within the active session.

A normal commit uses only the checked index and never stages working-tree
content implicitly. Amend replaces only the exact observed `HEAD` after its
confirmation. A fixup commit uses staged content and records one exact selected
target, but does not apply autosquash or rewrite history. Git continues to own
author identity, hooks, signing, the commit graph, refs, and remote state.

After every started commit process, Ksawery refreshes Status and compatible
History instead of treating its prior observation as current repository truth.

## Refs and Synchronization

Refs is a bounded immutable observation of complete local branch,
remote-tracking branch, and tag identities, configured remote names, symbolic,
detached, or unborn `HEAD`, and available tracking relationships. Selection and
marks carry complete generation-bound identities; rendered labels,
abbreviations, and row positions are never operation authority.

| Ref operation | Key | Result |
| --- | --- | --- |
| Move | Up, Down, `C-p`, or `C-n` | Selects one exact Ref or Remote identity. |
| Refresh Refs | `g` | Replaces Ref and Status truth and retains only compatible exact selection. |
| Fetch Remote | `&` | Checks and fetches the selected configured Remote, then refreshes. |
| Mark push source | `*` | Marks the selected exact local branch as the push source. |
| Clear push source | `-` | Removes the exact branch mark. |
| Push marked branch | `p` | Checks the selected Remote and opens confirmation for one derived tracked-branch destination. |
| Create local branch | `n` | Names and confirms one branch at the observed `HEAD`. |
| Switch local branch | `S` | Confirms a switch to the selected local branch after worktree, index, and editor checks. |
| Rename local branch | `R` | Names and confirms a rename of the selected local branch. |
| Delete local branch | `D` | Confirms deletion of one selected non-current branch merged into `HEAD`. |
| Create local tag | `t` | Names and confirms one lightweight tag at the selected commit-backed object. |
| Delete local tag | `T` | Confirms deletion of the selected exact local tag. |
| Merge selected Ref | `=`, `i`, or `I` | Prepares fast-forward-only, merge-allowed, or merge-commit-required integration. |
| Rebase onto selected Ref | `e` or `E` | Prepares ordinary rebase or a bounded reviewed autosquash plan. |
| Cancel | `C-g` | Cancels pending configuration, synchronization, naming, or confirmation work when cancellation is available. |
| Return | `q` | Returns to Status when no checked operation is active. |

Fetch binds one selected Remote to a credential-free digest of its exact URL
and fetch refspec. It uses one closed noninteractive Git command and never
merges, rebases, switches a local branch, or changes remote configuration.

Push requires one marked local branch with an existing observed upstream and
one selected configured Remote. The confirmation identifies the exact source
object, remote, and derived destination. The closed initial form admits one
non-force, non-deletion branch refspec; Git remote policy and receiver state
remain authoritative. Transport success is not presented as completion until
the refreshed local and remote-tracking identities verify publication.

Local branch and tag requests bind one exact Status and Ref generation to a
one-shot confirmation. Branch switching requires a clean index and worktree
and no modified repository-backed Odra resource. Branch deletion excludes the
current or unmerged target and has no force form. Tags are lightweight and
local: signing, annotation, force, and remote mutation are excluded. Every
started fetch, push, branch, or tag operation refreshes Ref and Status truth,
compatible History, and affected resources before retaining its result.

Fetch never performs integration. A pull-like workflow is the explicit
composition of Fetch followed by a separately selected and confirmed Merge or
Rebase. Ksawery does not read or infer an ambiguous pull policy.

## Sequences, Conflicts, and Recovery

Sequence is one immutable bounded observation of Git-owned operation state. It
identifies the repository, operation family, active, conflicted, truncated, or
unsupported state, internal or external origin, current step and revision when
available, and exact unmerged paths. Its fingerprint, not its label or rendered
row, binds a later control to the same sequence.

| Sequence operation | Key | Result |
| --- | --- | --- |
| Inspect selected conflict | Enter | Opens exact path, conflict classification, and available index stages. |
| Continue merge | `>` | Prepares checked continuation after all merge conflicts are resolved. |
| Abort merge | `X` | Prepares restoration of the retained pre-merge state. |
| Continue, skip, or abort rebase | `]`, `;`, or `Z` | Targets the retained exact replay step and rebase lineage. |
| Continue, skip, or abort cherry-pick | `{`, `l`, or `Y` | Targets the retained ordered cherry-pick lineage. |
| Continue, skip, or abort revert | `}`, `j`, or `Q` | Targets the retained ordered revert lineage. |
| Classify bisect candidate | `G` or `B` | Marks the current exact candidate good or bad. |
| Skip bisect candidate | `|` | Skips the current exact candidate after confirmation. |
| Reset bisect | `~` | Restores the checked pre-bisect branch after confirmation. |
| Refresh | `g` | Replaces Status and Sequence truth and reconciles compatible selection. |
| Inspect Processes | `$` | Opens active and recent repository operation records. |
| Return | `q` | Returns from Conflict to Sequence or from Sequence to Status without changing Git state. |

History owns ordered revision and bisect-boundary selection. `a` appends one
exact commit to the cherry-pick or revert set, `U` removes it, and `0` clears
the set; `P` and `V` prepare cherry-pick and revert. `G` toggles a known-good
bisect boundary, `B` selects the known-bad boundary, and `?` prepares bisect
start. A selected merge commit requires an exact parent row to bind its
mainline. Every start action and destructive recovery action uses `C-Enter` on
an exact one-shot confirmation.

Conflict presents Base, Current, and Applied according to the active operation,
not as universal text labels detached from Git index stages. `1`, `2`, or `3`
prepares replacement by one complete available side; `K` prepares a supported
resolved deletion; and `x` verifies and stages the exact saved worktree result.
Resolution never implies Continue. Unsupported, binary, rename, delete,
type-change, submodule, missing-stage, and truncated conflicts remain visible
even when a complete-side action is unavailable.

`H` asks the selected conflict-assistance provider about the exact copied
Conflict. Guidance is presentation only. An editor response uses the ordinary
conflict visit, and an external-tool response enters the existing Process
owner. A missing, disabled, failed, stale, or class-incompatible provider uses
the built-in no-op fallback. Provider output cannot stage a result, mark a path
resolved, or continue, skip, abort, or reset a sequence.

Only one repository operation child is active. While Sequence is active,
ordinary mutations are unavailable except its compatible conflict and control
actions. Process cancellation stops one child but never means skip, abort, or
reset. A Git conflict is a known actionable state, not completion. Every
started mutation refreshes the compatible Status, History, Refs, Sequence, and
repository resources required to verify completion, advancement, recovery, or
an indeterminate outcome.

## Detail and Change Actions

Unstaged detail compares the working tree with the index. Staged detail
compares the index with the current revision. Supported tracked text detail is
parsed into selectable semantic hunks. Untracked detail may contain a bounded
content preview. Detail remains read-only and is invalidated when its
observation or selected path becomes stale. Incomplete, malformed, binary,
truncated, or otherwise unsupported detail does not admit a partial action.

Stage and unstage use closed Git argument sequences and revalidate the exact
repository, observation generation, semantic path, and action availability
immediately before process start. One selected hunk can be staged or unstaged
without changing unrelated hunks in the same path. An unavailable action has
no adjacent or text-derived fallback. Unmerged paths do not admit either index
action.

Marks form one bounded ordered set. A valid path group contains complete paths
with one action direction. A valid hunk group contains nonoverlapping hunks
from one path and one Git layer. Mixed granularity, mixed direction,
cross-path hunk groups, duplicates, overlap, stale generations, unsupported
members, and limit violations reject the complete action.

Discard admits one complete tracked path with working-tree changes. `k` binds
one confirmation to the exact repository, observation, operation, and path.
`n` cancels it and `y` revalidates and starts the discard. A modified Odra
buffer for the path prevents both preparation and execution. Successful
discard restores the working-tree path from the index without changing the
indexed version. Partial discard, grouped discard, and untracked deletion are
not admitted.

Only one repository operation is active at a time. A completed index action is
not treated as current repository truth; Ksawery obtains a new Status
observation and reports the mutation according to that refreshed state.

## Personal Extension Providers

Personal configuration may export one `odra-ksawery-contributor` and one
`odra-ksawery-command-families` list through `odra/commands`. Import is inert;
Odra copies and validates the complete generation before publishing it. The
initial public contribution kinds are `command`, `keymap`, `status-section`,
`annotation`, `command-family`, `external-operation`,
`conflict-assistance`, and `provider-role`.

Each contribution declares a positive contributor-local identity, a stable
text identity, one kind, copied observation families, and requested
authorities. The observation vocabulary is `status`, `history`, `refs`,
`sequence`, `conflict`, and `process`. Authorities are `inspect`, `present`,
`invoke-declared-command`, `request-core-action`,
`submit-external-operation`, and `assist-conflict`. A `provider-role`
declaration additionally names `conflict-assistance`; other declarations must
use no provider role.

Status providers run once per compatible Status projection and publish
sections inside one deterministic `Extensions` area after the core groups.
Annotation providers run once per compatible observation and bind disposable
labels, details, severity, style, and optional command references to exact
path, diff-unit, revision, revision-range, Ref, Remote, Conflict, Sequence, or
Process targets. Empty output omits the contributed presentation. Refresh,
reload, target removal, provider failure, and disablement remove stale output
without changing core repository truth.

Command families publish each action into the ordinary command navigator under
this stable name:

```text
<contributor>/<family>/<action>
```

Boolean, closed-choice, text, selection, Ref, revision, revision-range, and
opaque arguments remain inert until a request is sealed. A core-action request
can name only a closed built-in operation and still passes its normal
preconditions, confirmation, Process, refresh, and verification. An external-
operation request returns a declarative plan using the built-in Git role or a
personal absolute executable path. Native code owns the fixed repository
directory and environment, closed standard input, child lifetime, output,
deadline, cancellation, refresh, verifier, and Process record.

`v` presents the active or disabled contributor identity, personal provenance,
contributor and personal generations, lifecycle, authorities, contributions,
selected resource policy, current usage, latest bounded failure, active
Process association, and effective fallback. `L` uses the complete personal-
configuration replacement transaction. A rejected generation leaves the
previous generation active. `z` requires idle repository, command, provider,
Process, turn, and conflict-assistance owners; successful disablement revokes
routes and projections while retaining the provider for inspection. A later
valid reload activates a new generation.

The built-in raw route is deliberately separate. `!` accepts bounded Git or
shell input only inside Ksawery, presents the exact mode, authority, repository,
and command for confirmation, and records bounded public evidence in Process.
It is not contributor authority, is not exported as another public command,
and reports verified success only when a typed compatible verifier proves the
refreshed result.

Default contributor policy admits 8 contributors, 16 contributions per
contributor, 128 total contributions, 1 MiB each for declarations,
observations, and results, 256 KiB per provider value, 4 KiB diagnostics, a
250 ms synchronous turn, 32 MiB Racket custodian memory, 64 callbacks, one
nesting level, and 32 MiB each of retained and temporary native memory.
Compiled ceilings are 32 contributors, 64 contributions per contributor,
2,048 total contributions, 8 MiB declarations, observations, and results,
4 MiB provider values, 64 KiB diagnostics, a 2-second turn, 128 MiB custodian
memory, 256 callbacks, and 32 MiB retained or temporary native memory.

Status output is limited to 16 sections, 256 items per section, 4,096 items,
8 metadata fields per item, and 4 MiB per proposal. Annotation output is
limited to 2,048 annotations, 4,096 observed targets, 1,280 bytes per target,
1,024 bytes per detail, and 4 MiB per proposal. A command family admits 256
arguments, choices, and actions; text or opaque values are limited to 4 KiB
and one encoded family to 8 MiB. An external plan admits 64 arguments of 512
bytes each, an 8 MiB argument vector, 8 MiB output, 64 KiB diagnostics, a
10-minute deadline ceiling, and a 5-second cancellation-grace ceiling.
Conflict assistance limits paths to 4 KiB, guidance to 32 KiB, copied content
to 4 MiB, and the complete copied turn to 8 MiB.

## Process and Resource Limits

The default observation admits 1,024 paths, 256 KiB of aggregate path text,
512 KiB of standard output, 64 KiB of retained diagnostics, and 512 KiB of
expanded detail. A default Ref observation admits 256 refs, 32 remotes, 512
KiB of retained metadata, and 4 MiB of temporary parser storage. Complete ref
names are bounded to 1,024 bytes, configured remote names to 256 bytes, and
user-supplied local branch and tag names to 240 bytes. A request has a
two-second timeout and a 250 ms cancellation grace period.

Immutable ceilings are 16,384 paths, 4 MiB of aggregate path text, 4 MiB of
standard output, 512 KiB of diagnostics, 4 MiB of expanded detail, and a
30-second process timeout. The repository context is an absolute copied path
bounded to 4 KiB; a branch or detached-revision label is bounded to 256 bytes.

Process output, diagnostics, observations, detail, and action results are
owned by the active Ksawery workflow and released on session close. Git remains
the repository authority; Odra does not persist a second repository model.

The Process surface retains at most eight total operation records and 2 MiB by
default. Immutable ceilings are 32 records and 8 MiB. One repository context
admits one active high-level operation, one active child, and two child
streams. At most one coalesced immutable record generation is published per
editor step after at most 64 pending events, with 64 KiB of child-stream reads
per step.

## Failure Behavior

Repository resolution, process start, timeout, output limit, parse, stale
generation, unavailable path, grouped-action, confirmation, modified-buffer,
index-action, discard, contributor, provider, proposal, authority, and resource
failures are contained and reported through the editor. A failed action is
never presented as completed, and an indeterminate effect is never collapsed
into success or ordinary failure. A Racket exception, timeout, invalid result,
or rejected reload cannot partially publish a contribution. The last confirmed
repository observation and contributor generation remain usable after their
respective failures. Root replacement or pointer-capture loss is reconciled to
the active Ksawery root, and shutdown closes any active child process, provider
turn, Racket root, and retained workflow state.

## Excluded Operations

Partial or grouped discard, untracked deletion, cross-path hunk groups, patch
editing, remote configuration, automatic pull, implicit autostash, arbitrary
interactive rebase todo editing, patch-series authoring, automated bisect,
force or deletion push, arbitrary refspec and multi-ref push, signed or
annotated tags, remote tag mutation, unconfirmed raw execution, contributor-
supplied shell strings, package discovery, installation, dependency
resolution, catalogs, signing, sandboxing, persisted package state, and
replacement of core Git observations or Process ownership are not part of the
current Ksawery capability.
