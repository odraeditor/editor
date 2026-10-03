<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Why Ksawery Owns a Full-Canvas Session

Repository work changes the user's interaction grammar for a bounded period.
Status groups, paths, detail, and index actions need one coherent semantic
selection; allowing hidden editor panes or panels to keep independent focus
would make the same key or pointer event ambiguous. Ksawery therefore owns a
distinct UI root instead of pretending that repository status is an ordinary
editable buffer.

The takeover is presentational, not destructive. The editor session retains
the previous visible target and every underlying buffer, pane, Darek or Maksym
surface, and terminal process. Exiting Ksawery restores that target when it is
still live, or a checked most-recently-used editor target when it is not. This
keeps repository interaction app-like without creating a second editor
lifecycle.

Git remains the sole authority for repository state. Each Status observation
is an immutable bounded snapshot, and each path action carries its observation
generation and semantic identity back to the process boundary for
revalidation. A successful process request still triggers a fresh observation;
the intended command and its output are not accepted as repository truth.

One visible repository action may require several native children: a
precondition check, the requested effect, refresh, and verification. Ksawery
therefore gives the high-level action one session-scoped identity that survives
those phases. A PID, command line, output fragment, and rendered row are only
evidence or presentation; none can replace the operation identity or authorize
its next phase.

That separation also explains why a zero child exit status is not always a
successful repository outcome. Ksawery reports verified success only after the
required refreshed observation proves the effect. If an effect may have begun
but refresh or cleanup cannot establish final truth, the retained record is
indeterminate. The user sees uncertainty instead of a false success, while the
last confirmed observation remains distinct from the failed refresh.

History follows the same ownership rule. A selected revision or range carries
the exact Git object identities from one bounded observation, rather than a
subject, abbreviated hash, graph symbol, or list position. Read-only revision
inspection therefore cannot become authority for a current working-tree action,
and a refreshed history can retain selection only when the same exact revision
remains compatible.

Commit composition is also session-owned. Ksawery retains a bounded message
draft, the observed `HEAD`, the checked index, and an explicit operation mode
until Git starts. It revalidates those inputs at the process boundary and then
refreshes Status and History after every started operation. This prevents a
normal commit from silently consuming a newer index and keeps failed hooks or
signing policy visible as Git outcomes instead of editor guesses.

Amend has an additional confirmation because it replaces the observed `HEAD`.
A fixup commit has the opposite shape: it records an exact selected target but
creates a new commit without reordering or applying autosquash. Neither action
authorizes Ksawery to infer remote publication safety, mutate refs directly,
or begin a sequenced history operation.

Refs and synchronization use the same observation boundary for identities that
can change outside Odra. A fetch checks one configured Remote and then replaces
the Ref observation instead of interpreting transport output as repository
truth. A push adds an exact one-shot destination confirmation and is considered
complete only when refreshed tracking identities verify the published object.
Local branch and tag operations likewise revalidate Status, Ref, `HEAD`, and
operation-specific worktree or editor state before Git starts. This is why
selection, marks, naming, and confirmation remain inside the full-canvas
session while Git remains the sole owner of refs, configuration, hooks,
credentials, and receiver policy.

Sequenced operations extend this boundary across pauses. Git owns merge,
rebase, cherry-pick, revert, and bisect metadata, so a conflict may outlive one
child process, one Ksawery visit, or the Odra process itself. Ksawery owns only
a bounded observation and the checked lineage created while starting an
operation. Reopening the session reconstructs current Git state; it never
reuses an old process record or confirmation as authority for Continue, Skip,
Abort, classification, or Reset.

This is also why Fetch and integration remain separate. Fetch can refresh a
remote-tracking identity, but it cannot decide whether the user intended Merge
or Rebase. The next action selects that refreshed exact Ref and creates its own
precondition and confirmation. Conflict resolution follows the same pattern:
choosing a complete Git side or marking an exact saved result resolves one
path, while continuing the sequence is a distinct checked action.

Process cancellation does not cross that ownership boundary. It may stop an
active child and trigger repository refresh, but it cannot mean Git sequence
Abort, Skip, or Reset. A nonzero Git exit that leaves a compatible conflict is
a known actionable state; verified success is reserved for a refreshed graph,
index, worktree, and Sequence observation that prove the requested outcome.

Granular and grouped index actions extend this identity model rather than
treating rendered diff text as executable input. One hunk identifies an exact
bounded part of one tracked path and Git layer. A marked set owns an ordered
collection of compatible semantic targets. Refresh invalidates both because a
new observation may describe different repository content even when the same
labels remain visible.

Discard has a stricter boundary because it destroys working-tree changes. The
confirmation belongs to one exact tracked path and observation, cannot be
reused after refresh, and is checked again immediately before process start.
Odra also refuses the action while its buffer for that path has unsaved edits.
This keeps confirmation meaningful without turning prompts or rendered rows
into mutation authority.

Personal extensions fit inside the same ownership model. Racket authors one
inert contributor generation and synchronous providers over copied
observations. Odin validates the complete declaration, owns native storage,
selects current generations, publishes semantic output, and revokes every
capability after its bounded turn. Git still owns repository truth, and the
existing Process coordinator still owns every external child. A provider can
describe a request or derive presentation; it cannot retain a native pointer,
publish canonical repository state, or advance a workflow by side effect.

This separation is why additive Status sections and annotations do not become
new Git facts. Their identities are bound to an exact contributor and
observation generation and disappear when either changes. They follow the
shared semantic presentation path, so theme roles can alter appearance while
explicit text, ordering, truncation, and core selection remain available
independently from color or provider layout choices.

Contributed command families also enter the ordinary command registry rather
than creating a provider-owned dispatcher. Typed argument editing is inert.
One sealed request may ask an existing core workflow to act or may return a
declarative external-operation plan, but native code rechecks contributor,
target, repository, authority, confirmation, and operation generations before
anything runs. This preserves the same one-operation and post-effect refresh
rules used by built-in actions.

Conflict assistance is a replaceable advisory role, not a replacement
Conflict owner. Guidance is copied presentation, editor assistance delegates
to the ordinary buffer workflow, and a tool proposal delegates to Process.
Resolution, index mutation, Continue, Skip, Abort, and Reset remain separate
core decisions. When the provider is absent, disabled, stale, incompatible,
or failed, a built-in no-op response leaves the Conflict surface usable.

Raw Git or shell execution sits outside ordinary contributor authority for the
same reason. It is an explicit built-in escape hatch with its own bounded
input, exact confirmation, Process evidence, refresh, and verification. A
provider cannot smuggle a shell string through a command family, and raw child
output cannot become a repository success claim.

Atomic reload and idle-only disablement close the lifecycle boundary. Racket
may prepare a replacement, but Odin publishes it only after the whole personal
generation is valid. Rejection leaves the prior generation intact; disablement
revokes contributed routes and projections while retaining built-in Ksawery;
shutdown drains turns and children before releasing native allocations and
Racket roots. Package discovery, installation, trust, and sandboxing remain a
separate extension-ecosystem concern.

The UI root and repository process have separate lifetimes inside the same
workflow owner. A redraw or root replacement cannot create another operation,
and an operation failure cannot expose the retained editor canvas to input.
Closing the session releases observations, detail, process output, action
results, marked targets, confirmation state, and any active child before normal
editor ownership resumes.

The Process surface is session-local for the same reason. It retains a bounded
recent history so active progress, cancellation, output limits, and terminal
evidence remain inspectable without inventing durable process history. Returning
to Status, History, or Refs restores the exact source position; retrying is a
new checked action against current Git truth, never a replay of retained text.
