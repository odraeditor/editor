<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Why Agent Interaction Uses One Authority Path

Odra treats the local command surface as a view over the agent substrate. The
surface does not own grants, admission, execution, results, or cancellation.
This keeps keyboard commands, candidate actions, package integrations, and
future remote surfaces from acquiring different security behavior.

An agent proposal is not a capability request. A request is not admission. An
admitted request is not an operation result. The interface preserves these
distinctions because each boundary has different authority and evidence.

Candidate selections carry semantic identity and generation. The substrate
checks both again when the action runs. A stale screen therefore cannot revoke
a replacement grant, approve a changed request, or cancel newer work.

Human-readable labels lead every ordinary list, while technical identities and
generations remain available in detail. This improves navigation without
weakening exact targeting. The user never needs to copy an internal ID into a
prompt to operate the system.

User-entered task text is inert interaction data. Model output is untrusted
driver output. Both must pass their own bounded contracts before any
capability owner receives an admitted request. No surface evaluates message
text or turns presentation markup into authority.

Audit and reconciliation are inspection mechanisms. Reading an audit event
cannot replay it. Acknowledging uncertainty cannot turn it into success. A
restart marker cannot revive runtime ownership. These limits let the interface
explain incomplete work without manufacturing a result.

The same boundary permits direct access to a specialist agent. A coordinator
is useful only when the user chooses coordination; it is not an implicit gate
between the local user and every agent.
