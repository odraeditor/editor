<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Why Feedback Separates Meaning from Presentation

An editor operation knows what happened, but it should not decide whether the
result belongs in a Status row, a floating surface, a diagnostic area, or a
history view. That decision depends on frontend capability, geometry, theme,
attention policy, and current presentation capacity.

Odra therefore uses three boundaries:

1. the source workflow publishes one semantic record;
2. the feedback registry owns its active and retained lifecycle; and
3. the routing layer produces a bounded presentation for an available
   destination.

The source retains operational authority. A language service owns its process,
a package workflow owns catalog mutation, and a marked-buffer operation owns
its cancellation state. The feedback system can report those operations and
carry checked actions, but it cannot mutate source state by dismissal.

## Public Text and Diagnostic Detail

Ordinary feedback must explain the user-visible outcome. Internal enum names,
transport states, and owner codes help diagnose a failure but make poor Status
messages. Keeping that material in explicit diagnostic metadata lets compact
presentation remain readable while preserving evidence for inspection.

This split also prevents a frontend from parsing prose to recover operation
state. Severity, attention, lifecycle, progress, and action availability are
typed fields.

## Exact Action Authority

An action displayed beside feedback may outlive the state that created it. A
retry can become irrelevant, a source can close, or a newer generation can
replace the record. Command names alone are insufficient authority.

Odra resolves an action from the exact record generation and source generation,
then confirms that the named command remains registered. Frontends receive
matching command authority or a rejection. They cannot reuse one row to invoke
an action from another generation. The source workflow performs the final
operation-specific authority check.

## Capability-Aware Degradation

Semantic feedback remains the same when a frontend lacks floating overlap or a
dedicated history surface. Routing follows a declared fallback chain and
projects the record for the selected destination. Monochrome projection adds
textual severity where color cannot carry it. Narrow presentation truncates at
the destination bound.

Degradation is presentation policy. It does not alter retention, cancel work,
clear diagnostics, or grant an action.
