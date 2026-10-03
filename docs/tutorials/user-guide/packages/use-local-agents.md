<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Work with Local Agents

Odra exposes installed agents through the same command, candidate, inspection,
and cancellation grammar used elsewhere in the editor. An agent can propose a
capability request, but only the substrate can grant authority, admit the
request, invoke its owner, and publish a checked result.

Complete [Use Package Catalogs](use-package-catalogs.md) first. This chapter
assumes that the agent substrate and at least one agent package are active.
The command names below belong to the substrate package. They appear only
after that package contributes its local interaction surface.

## Discover an Agent

1. Run `M-x agent-list`.
2. Type part of the agent's display name, semantic identity, description,
   package, or capability label.
3. Move through the filtered candidates and inspect one item.
4. Run `M-x agent-describe` for provider requirements, requested capabilities,
   effective grants, limits, provenance, and current availability.

An unavailable agent remains selectable for inspection. Its detail explains
which provider or package state is missing. Read-only list and detail actions
do not ask for confirmation.

## Exercise the ROT13 Canary

The reference canary uses three independent packages:

- `odra.rot13` owns the ordinary `rot13-region` command;
- `odra.rot13-canary-agent` contributes the deterministic agent; and
- `odra.rot13-agent-integration` contributes `odra.rot13.region` and depends
  on both the agent substrate and ROT13.

Install and enable the three packages through `M-x package-discover`. The
package resolver shows required dependencies before installation and keeps
the integration separate from the direct ROT13 command.

1. Open a text buffer containing `Hello from Odra` and select the complete
   text.
2. Run `M-x agent-list`, filter for `ROT13 Canary`, and inspect it.
3. Run `M-x agent-grant`. Select `Apply ROT13 to one exact active non-empty
   region`, restrict the scope to the active buffer and selection, and admit
   `observe` plus `mutate-editor-state` for the displayed limits.
4. Run `M-x agent-task-start`, select `ROT13 Canary`, and enter an objective
   such as `Apply ROT13 to the selected text`.
5. Open the pending request through `M-x agent-request-list`. Verify the
   selected region, effects, limits, package generation, and `Approve once`
   decision class.
6. Approve the request. The selected text becomes `Uryyb sebz Bqen` through
   one editor transaction. Undo restores the original text.
7. Run the same task again to restore the original through ROT13, then revoke
   the grant with `M-x agent-revoke`.
8. Disable `odra.rot13-agent-integration`. Its capability disappears, while
   direct `M-x rot13-region` remains available.

The selection must remain on the same checked buffer revision until the owner
operation begins. A stale revision, empty selection, revoked grant, disabled
integration, or missing ROT13 package produces a checked failure without an
edit.

## Start a Task and Send Text

1. Run `M-x agent-task-start`.
2. Select an available agent by its display name.
3. Enter a bounded objective.
4. Review the selected agent and visible context, then create the task.
5. Run `M-x agent-task-open` to open its ordinary Odra task view.
6. Run `M-x agent-send` and enter a follow-up message.

The task view shows the agent, state, objective, pending attention, driver
state, and ordered interaction history. Questions, proposals, progress,
requests, checked results, failures, and cancellation remain distinct.

Text entered through `agent-send` is interaction data. Odra does not evaluate
it as Racket, shell, Odin, JavaScript, a command name, or a capability request.

## Decide a Capability Request

Run `M-x agent-request-list` to see pending and recent requests. Select one and
run `M-x agent-request-decide`. A pending request shows its agent, task,
capability owner, target summary, requested effects, effective limits, and
decision class before these actions become available:

- `Approve once` records one request-scoped decision;
- `Reject` denies that exact request; and
- `Cancel task` rejects the request and cancels its task.

Approve-once does not create reusable authority and does not trigger another
generic confirmation. A stale request cannot be approved; return to the task
and let the agent issue a new request against current generations.

## Grant, Revoke, and Cancel

Use `M-x agent-grant` to select an agent capability, owner-defined scope,
effect ceiling, resource ceiling, validity, and local policy. Each step can
only narrow the accumulated authority.

Use `M-x agent-revoke` to select an active grant and inspect affected work
before revocation. New admission stops immediately. Work already in progress
moves through cancellation or reconciliation according to its owner contract.

Use `M-x agent-cancel` for a selected task, turn, or operation attempt.
Cancellation can be requested, signalled, reconciling, or terminal. The task
view remains usable while completion is pending.

An `outcome-unknown` result is neither success nor failure. Acknowledging it
records that the user saw the uncertainty; it does not change the result.

## Inspect History

Run `M-x agent-inspect` from an ordinary candidate or task view to follow
related agents, capabilities, grants, tasks, interactions, requests,
decisions, driver sessions, turns, attempts, results, audit events, and
reconciliation markers. Labels and state appear before technical identities.

Run `M-x agent-audit` for bounded attributable history. Redacted events remain
visibly redacted. Audit inspection does not replay an operation or grant
authority.

## Recover an Empty or Stale Surface

An empty list explains the next useful action: activate an agent package,
start a task, or return when a request needs attention. If a selected item
changed generation, refresh the candidate list and select its current entry.

After a process restart, interrupted sessions, turns, and attempts appear as
`Reconciling`. Inspect their reconciliation marker and owner evidence. Odra
does not restart them automatically or infer success from their former
`Running` state.

For the ROT13 canary, inspect these dependencies in order when the agent or
capability is unavailable:

1. `odra.rot13` is installed, enabled, and contributes `rot13-region`;
2. `odra.rot13-agent-integration` is enabled and contributes
   `odra.rot13.region`;
3. `odra.rot13-canary-agent` is enabled and can see
   `odra.agent-driver.deterministic`; and
4. the grant still matches the current agent, capability, buffer, region, and
   package generations.

For focused recovery procedures, use
[Operate and Diagnose Local Agents](../../../how-to/operate-local-agents/index.md).
Exact commands, record fields, limits, and state transitions are in the
[Agent Substrate Reference](../../../reference/agent-substrate/index.md).
Package authors can continue with
[Author and Validate an Agent Package](../../../how-to/author-agent-packages/index.md)
and the complete
[Agent Package Authoring Reference](../../../reference/agent-substrate/authoring.md).

---

[Previous: Use Package Catalogs](use-package-catalogs.md) ·
[User Guide](../index.md) ·
[Next: Build a Linked Knowledge Base with Roman](use-roman-linked-knowledge.md)
