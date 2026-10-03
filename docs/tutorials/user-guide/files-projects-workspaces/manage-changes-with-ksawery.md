<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Manage Repository Changes with Ksawery

This chapter uses Ksawery to inspect and change a Git repository from a
dedicated editor session. It covers Status, History, staging, commits, refs,
branches, tags, merge, rebase, cherry-pick, revert, bisect, conflict recovery,
and Git process inspection. The session ends by returning to the previous
editor canvas.

## Before You Begin

Open a file inside a local Git repository. The file must have a saved path;
Ksawery resolves the repository from that active resource rather than from
rendered text or the current shell directory.

Make two saved text changes that are not staged. Keep one file open in Odra so
canvas restoration remains visible at the end of the workflow. Save Odra
buffer changes before using discard; Ksawery refuses to discard a path while
its file buffer is modified.

To create commits, configure Git author identity and any required signing or
hook policy for the repository before opening Ksawery. Ksawery uses that Git
policy; it does not ask an interactive Git editor to complete a commit.

Fetch and push use the repository's existing remote, URL, push URL, and
tracking configuration. Ksawery does not create or edit that configuration and
does not bypass Git credential or receiver policy.

Save every Odra buffer associated with the repository before a sequence
operation. Ksawery does not save, stage, stash, or discard content implicitly.

## Open Repository Status

Run `M-x ksawery-status`. Ksawery replaces the complete visible canvas with a
Status session for the resolved repository. Existing panes, Darek, Maksym, and
integrated terminals remain retained but hidden and cannot receive input while
the session is active.

Status shows the repository and branch, then only nonempty groups in this
order: Unmerged, Untracked, Unstaged, and Staged. A clean repository displays
`Working tree clean` instead.

Move with Up and Down or `C-p` and `C-n`. A primary-button click may select a
visible group or path when pointer reporting is available.

## Inspect Repository Processes

While Status, History, or Refs is visible, press `$` to open Ksawery Processes.
The active repository operation appears first, followed by bounded recent
terminal records in newest-first order. Each row identifies the operation, its
safe semantic target, current phase or terminal outcome, and elapsed time.
Press `r` to reconcile the list with the latest immutable record generation.

Move with Up and Down, then press Enter to show the selected record's phase,
outcome message, exit status when available, and bounded Git output or
diagnostics. Explicit truncation labels mean that Ksawery reached a configured
capture or presentation limit; the omitted text is not available through the
Process surface.

An active record may offer `C-g cancel`. Cancellation targets that exact
operation generation, first requests graceful termination, and uses a finite
grace period before escalation. Closing detail or pressing `q` does not imply
cancellation: `q` returns to the exact Status, History, or Refs source and its
retained list position.

Read the terminal outcome separately from the child exit status.
`Verified_Success` means refreshed Git state proves the requested result.
`Known_Failure`, cancellation, timeout, and `Verification_Mismatch` identify
bounded known outcomes. `Indeterminate` means an effect may have started but
the available child and refreshed repository evidence cannot prove the final
state. Inspect current Status, History, or Refs truth before deciding whether
to retry; a retry is always a new checked operation.

## Browse History and Inspect Revisions

Press `h` in Status to open the bounded History surface for the checked
repository. History remains inside the same Ksawery session and shows semantic
revisions in ancestry order. Use Up and Down or `C-p` and `C-n` to select a
revision, `f` to request the next available page, and `g` for a fresh
observation. Press `q` to return to Status.

Press Tab on a revision to inspect its exact metadata, parents, changed paths,
and read-only diff. Press `q` to return to History. Detail is read-only: it
does not stage, unstage, discard, or check out historical content.

To compare a range, press `*` on a revision to set its base, select a
compatible revision, then press Enter. Ksawery presents the exact ordered range
and its bounded change summary. Press `q` to return to History.

## Inspect Stashes, Worktrees, Reflog, and Blame

From Status, press `z z` to list stashes, `Z Z` to list linked worktrees, or
`l r` to inspect the reflog. Select a changed path before pressing `B b` to
open bounded line attribution for that path. Use `n` and `p` to move through
any of these lists, Enter to show retained detail, `g` to refresh, and `q` to
return to Status.

In Blame or Reflog, press `v` to inspect the selected exact revision. In
Stash, use `c` to create a stash, `v` to inspect one, `a` to apply, `p` to pop,
`b` to create a branch from it, or `k` to drop it. In Worktree, use `c` to
create, `v` to visit, `L` to lock, `U` to unlock, `P` to prune, or `k` to
remove. Review and confirm every mutation before Ksawery starts Git.

## Use Advanced Repository Families

Press `?` in Status to see the complete dispatcher. The additional familiar
families are `C` Clone, `i` Ignore, `I` Init, `o` Submodule, `O` Subtree, `T`
Notes, `w` Apply patches, `W` Format patches, and `>` Sparse checkout. Open a
family to see its action keys and requirements.

Most actions open a Git-argument editor with the selected operation already
present. Complete the source, destination, path, revision range, or other
required arguments. Press `C-Enter` to inspect the exact command, then press
`C-Enter` again to start it. Press `C-g` during composition or confirmation to
leave without starting Git. Clone and Init deliberately require an explicit
destination.

`i t` opens the repository `.gitignore`; `i p` opens the private
`.git/info/exclude`. Edit and save these files with ordinary Odra commands.
Ksawery does not invent an ignore pattern. Subtree depends on `git subtree`.
Patch and mail actions use local files or ranges and do not configure or send
mail. Transport-dependent operations report Git's noninteractive availability
instead of prompting in the hidden child process.

## Inspect and Synchronize Refs

Press `b` in Status to open Refs. The surface shows complete local branch,
remote-tracking branch, and tag names, configured remote names, the checked
`HEAD`, object identities, and observed ahead or behind tracking state. Use Up
and Down to select one semantic item, `g` to replace the observation with
current Git truth, and `q` to return to Status.

Select a configured Remote and press `&` to fetch it. Ksawery first checks the
remote URL and fetch refspec, then runs one noninteractive fetch. A started
fetch refreshes Refs and Status, plus compatible retained History, before its
result is reported. Fetch updates remote-tracking state; it does not merge,
rebase, switch a local branch, or edit remote configuration. Press `C-g` to
cancel a pending check or fetch.

To publish one tracked branch, select its local branch and press `*`, then
select its configured Remote and press `p`. Review the exact source, remote,
and derived destination on the Push Confirmation surface. Press `C-Enter` to
confirm or `C-g` to cancel. The initial push form publishes only that one
branch, without force or deletion, and reports completion only after refreshed
Ref truth verifies the result.

## Manage Local Branches and Tags

From Refs, press `n` to name a local branch at the observed `HEAD`. On a
selected local branch, press `S` to switch, `R` to rename, or `D` to delete it.
Name entry uses Enter to prepare the exact operation; every branch mutation
requires `C-Enter` on its confirmation surface. Switching requires a clean
worktree and index and no modified Odra buffer in the repository. Deletion
admits only a non-current branch already merged into `HEAD`; no force mode is
available.

Select a commit-backed local branch, remote-tracking branch, or lightweight
tag and press `t` to create a lightweight local tag at that exact object. Select
a local tag and press `T` to delete it. Tag creation and deletion each require
`C-Enter` on an exact confirmation. Ksawery does not sign, annotate, force, or
publish tags.

Every started branch or tag operation refreshes Refs and Status, compatible
History, and affected repository-backed editor resources before reporting the
verified result. A stale target, changed repository state, active sequenced Git
operation, or rejected Git process remains visible as a contained failure.

## Merge or Rebase an Exact Ref

Fetch and integration are separate actions. Select the configured Remote in
Refs and press `&`, then select the refreshed remote-tracking branch. Press
`=` for a fast-forward-only merge, `i` for a merge that may create a merge
commit, or `I` to require a merge commit. Press `e` for an ordinary rebase or
`E` for the bounded reviewed autosquash plan. Review the exact target and
policy, then press `C-Enter` to confirm or `C-g` to cancel.

Ksawery checks the selected Ref, current branch, `HEAD`, Status, Sequence,
index, worktree, and repository-backed buffers immediately before starting.
It never chooses merge versus rebase as an implicit pull policy. A completed
operation refreshes Status, Refs, History when retained, Sequence, and affected
resources before it is reported as verified.

If Git stops at a conflict, Ksawery opens Sequence instead of reporting the
whole operation as successful. Press `Z` in a Rebase Sequence to prepare an
abort, `;` to prepare skipping the current replay step, or `]` to continue
after every conflict is resolved. In a Merge Sequence, press `X` to prepare an
abort or `>` to continue after resolution. Each control is rechecked and
requires `C-Enter`; process cancellation with `C-g` is not a sequence abort.

## Inspect and Resolve an Active Sequence

Run `M-x ksawery-sequence` when Git owns an active merge, rebase, cherry-pick,
revert, bisect, or another detectable sequence. Sequence shows its operation
family, state, origin, current step or revision when available, and bounded
conflict paths. An operation started outside Odra remains observable, but only
controls with retained checked authority are offered.

Select a conflict and press Enter. The Conflict surface identifies the exact
path, conflict kind, and available Base, Current, and Applied Git index sides.
Press `1`, `2`, or `3` to prepare a complete-side replacement, or `K` to
prepare a supported deletion. To keep an edited and saved worktree result,
press `x`. Review the exact whole-path confirmation and press `C-Enter`.
Resolution and sequence continuation are separate actions; Ksawery does not
infer resolution from missing conflict-marker text or continue automatically.

Press `$` from Sequence or Conflict to inspect the checked operation record.
Press `q` to return from Conflict to Sequence and from Sequence to Status. The
Git sequence remains active until an explicit Git control completes, aborts,
or resets it; leaving Ksawery does not erase sequencer state.

## Apply Ordered Revisions or Run a Manual Bisect

In History, select an exact commit and press `a` to append it to the bounded
ordered set; press `U` to remove it or `0` to clear the set. For a merge commit,
select the intended parent row before adding it. Press `P` to prepare
cherry-pick or `V` to prepare revert, review the order, and press `C-Enter`.

If cherry-pick stops, `{` continues, `l` skips, and `Y` aborts. If revert
stops, `}` continues, `j` skips, and `Q` aborts. Each action is separately
checked and confirmed; a skipped step or abort is never inferred from process
cancellation.

For manual bisect, select a known-bad History commit and press `B`, then select
one or more known-good commits and press `G`. Press `?` and confirm to start.
In the Bisect Sequence, press `G` or `B` to classify the current candidate,
`|` to skip it, or `~` to reset and restore the pre-bisect branch. Automated
`bisect run` is not part of this workflow.

## Create a Normal Commit

Stage the paths or hunks that belong in the commit, then press `c` from Status.
Ksawery opens its Commit Message surface. Enter a subject and optional body,
then press `C-Enter` to finalize the request. Press `C-g` to cancel before the
Git process starts; the draft remains available within the active session.

A normal commit uses the checked index only. Unstaged working-tree changes are
not added implicitly. Ksawery rechecks the repository state immediately before
starting Git, then refreshes Status and History after a started commit process
so the displayed result reflects Git's current state.

## Amend HEAD or Create a Fixup Commit

From History, press `A` to prepare an amend for the observed `HEAD`. Review or
edit the message, press `C-Enter`, then review the exact amend confirmation.
Press `C-Enter` again to confirm, or `C-g` to return to the retained draft.
Amend replaces the local `HEAD` commit. Ksawery does not infer whether that
commit has been published or whether rewriting it is safe for a remote.

Select a revision in History and press `F` to prepare a fixup commit for that
exact revision. The derived `fixup!` message identifies the target and is
read-only. Press `C-Enter` to create the commit, or `C-g` to cancel. A fixup
commit adds a new local commit; it does not reorder, squash, autosquash, or
otherwise rewrite history.

## Inspect a Path

Move from the Unstaged group to a changed path and press Tab. Ksawery opens
bounded read-only detail for that exact semantic path. Supported tracked text
detail contains selectable semantic hunks. Move with Up and Down to select a
hunk, and press Tab on the path again to collapse its detail.

Detail follows the path state: unstaged content is compared with the index,
staged content is compared with the current revision, and an untracked path
may show a bounded preview. A truncation row is explicit when output reaches
the configured limit.

Press Enter on a path to visit its current file content. This resource view is
still inside the Ksawery session. Press `q` to return to Status.

## Stage and Unstage Paths or Hunks

Select an Untracked or Unstaged path and press `s`. After Git completes,
Ksawery reports `Index action Stage completed`, refreshes Status, and
reconciles the same path into the Staged group when it remains observable.

Press `u` on the staged path. Ksawery reports
`Index action Unstage completed` and refreshes again. Unstaging removes the
complete path from the index; it does not discard the working-tree content.

Only the action valid for the selected state is available. Unmerged paths are
never admitted for stage or unstage.

Expand a supported tracked text path, select one hunk, and press `s` to stage
only that hunk. The other working-tree changes in the path remain unstaged.
Select a staged hunk and press `u` to remove only that hunk from the index.

Binary, malformed, truncated, or otherwise unsupported detail remains visible
when possible, but it never becomes authority for a partial action.

## Operate on Compatible Marked Changes

Press `*` on a path or hunk to add it to the session-local marked set. Press
`-` on that item to remove its mark, or `0` to clear every mark. The Status
surface shows marked rows, the target count, the granularity, and whether `s`
or `u` applies.

A group may contain complete paths that share one stage or unstage direction,
or multiple nonoverlapping hunks from one path and one Git layer. Press `s` or
`u` to apply the displayed action to the complete marked set. Ksawery rejects
mixed granularities, mixed directions, duplicate or overlapping hunks,
cross-path hunk groups, stale observations, unsupported members, and groups
that exceed their configured bounds. It never drops an incompatible member
silently.

Refreshing clears generation-bound marks because they no longer identify the
current repository observation.

## Discard One Tracked Working-Tree Path

Select an eligible tracked path in Unstaged and press `k`. Ksawery asks
`Discard working-tree changes in <path>?` for that exact complete path. Press
`n` to cancel without changing the file, or `y` to confirm.

Confirmation is not reusable for another target or observation. Before Git
starts, Ksawery revalidates the repository state and checks again that no Odra
buffer for the path contains unsaved changes. A successful discard restores
the selected working-tree path from the index, preserves indexed content, and
refreshes Status from Git.

Discard is limited to one complete tracked working-tree path. It does not
discard individual hunks or groups and does not delete untracked files.

## Refresh or Leave the Session

Press `g` to request a fresh repository observation. Selection is retained
when the same semantic path survives; stale detail is not kept as current.

Press `q` from Status to close Ksawery and restore the exact editor target that
was visible before entry. If that target no longer exists, Odra restores the
most recently used live editor target instead. Closing Ksawery does not close
the retained buffers, panes, panels, or terminal sessions beneath it.

## Understand Failures and Current Boundaries

Repository discovery, Git process, output-limit, timeout, stale-selection,
group-admission, index-action, confirmation, and discard failures remain
contained in the Ksawery session and are reported as editor diagnostics. An
active operation rejects another operation until it completes; it does not run
a second Git mutation concurrently. Process output is inspection evidence, not
repository truth or reusable command input. Retained process records are
session-local and disappear when Ksawery closes.

The current workflow intentionally stops before partial or grouped discard,
untracked deletion, cross-path hunk groups, editable patches, remote
configuration, automatic pull, implicit autostash, arbitrary interactive
rebase todo editing, automatic bisect, force or deletion push, remote tag
publication, unreviewed process execution, and automatic patch-mail delivery.

For exact commands, state transitions, limits, and process behavior, read the
[Ksawery Reference](../../../reference/ksawery/index.md).

---

[Previous: Manage a Workspace](manage-a-workspace.md) ·
[User Guide](../index.md) ·
[Next: Darek](darek/index.md)
