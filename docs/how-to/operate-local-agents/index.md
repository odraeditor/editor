<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Operate and Diagnose Local Agents

Use these procedures after the agent substrate and an agent package are active.
The commands are unavailable until the substrate package contributes its local
interaction surface.

## Inspect Availability

1. Run `M-x agent-list` and filter by a human-readable label.
2. Select an unavailable agent instead of retrying task creation.
3. Run `M-x agent-describe`.
4. Inspect the missing provider role, package generation, or failed state.
5. Correct that dependency, refresh the list, and select the current
   generation.

## Resolve Pending Attention

1. Run `M-x agent-request-list`.
2. Select the request by task and operation label.
3. Inspect effects, targets, limits, validity, and decision class.
4. Run `M-x agent-request-decide` and choose `Approve once`, `Reject`, or
   `Cancel task`.
5. Return to the task view and inspect the admission decision separately from
   any later attempt or result.

Do not create a reusable grant merely to approve one request. Use
`M-x agent-grant` only when the same bounded authority should remain available.

## Stop Work

1. Run `M-x agent-cancel`.
2. Select the task, turn, or attempt by its semantic label.
3. Inspect its current generation and state.
4. Request cancellation once.
5. Reopen the task to distinguish signalled, reconciling, and terminal state.

If the selection became stale, refresh and choose the current entry. Repeated
cancellation of a terminal record is rejected without changing history.

## Diagnose Restart State

1. Open the task with `M-x agent-task-open`.
2. Follow its `Reconciling` session, turn, or attempt through
   `M-x agent-inspect`.
3. Inspect the prior state and generation in the reconciliation marker.
4. Inspect owner or external evidence before accepting a later resolution.
5. Treat `Outcome unknown` as unresolved until an owner verification
   capability publishes current evidence.

Restart never replays the operation automatically.

## Check Audit History

1. Run `M-x agent-audit`.
2. Filter by the visible actor, task, event kind, or safe subject label.
3. Open the event detail for exact generations and causal references.
4. Follow related records through `M-x agent-inspect`.

Identity-only events intentionally hide their outcome detail. Missing raw
provider text or credentials is expected, not evidence loss.

## Interpret Common Diagnostics

| Diagnostic | Action |
| --- | --- |
| Stale selection | Refresh the list and select the current generation. |
| Agent unavailable | Inspect provider and package availability. |
| Authority denied | Inspect effective grants, scope, effects, and validity. |
| Request no longer pending | Return to the task and inspect the current request. |
| Task or grant limit reached | Finish or remove retained work before creating more. |
| Outcome unknown | Inspect evidence and use an owner verification capability. |
| Reconciling | Wait for or initiate an explicit owner observation; do not replay. |

## Diagnose the ROT13 Canary

1. Run direct `M-x rot13-region` on a non-empty selection. If it is absent or
   fails, repair `odra.rot13` before inspecting the agent path.
2. Run `M-x agent-describe` for `ROT13 Canary`. Confirm the deterministic
   driver is available and `odra.rot13.region` is visible.
3. Inspect the capability generation and its owner package. A disabled or
   replaced `odra.rot13-agent-integration` generation invalidates older
   requests and grants.
4. Inspect the grant scope. It must contain the exact active buffer and region
   references and admit `observe` plus `mutate-editor-state`.
5. Open the request and compare its captured buffer revision with the current
   buffer. Create a new request after any intervening edit.
6. Inspect the operation result and audit event. A cancelled or stale attempt
   must not publish an edit; an uncertain result requires current owner
   evidence before retry.

Disabling the integration removes only the agent capability. If direct ROT13
also disappears, inspect the `odra.rot13` package state separately.

The complete fields and limits are in the
[Agent Substrate Reference](../../reference/agent-substrate/index.md).
