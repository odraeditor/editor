<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Read Feedback and Progress

Odra reports command outcomes and ongoing work in the shared feedback region at
the bottom of the editor. This chapter identifies ordinary messages, required
attention, progress, replacement, and recovery behavior.

## Before You Begin

Complete [Read and Configure the Status Bar](status-bar.md), then open one file
from the maintained User Guide Project.

## Read an Ordinary Outcome

Edit the file and save it. The feedback region reports the save outcome in
plain language. It does not expose internal operation names or error enums.

Run another command that reports an outcome. The newest Command-channel
message replaces the prior Command-channel message. Save, Project, package,
recovery, and language-service feedback have independent source identities, so
one producer cannot replace another producer's record accidentally.

## Observe Long Work

Open the Buffer Menu, mark more than one eligible buffer, and execute the
marked operation. While work is active, the feedback region presents its phase
and measured count. Completion, cancellation, or failure publishes a final
generation for the same operation.

`C-g` requests cancellation through the operation's registered command. Hiding
or replacing the visible message does not cancel the operation.

## Read Warnings and Failures

Warnings and failures use the active theme's alert role. On a frontend that
cannot display a floating or diagnostic surface, Odra presents compact text in
the feedback region. The fallback changes location and detail density, not the
meaning or severity of the record.

Messages intended for ordinary use stay human-readable. Technical failure
detail is retained as diagnostic metadata when the producer supplies it.

## Understand Actions and Stale Results

Feedback may carry Inspect, Retry, Cancel, Open Source, or Show Log actions.
An action is accepted only from its exact feedback generation and source
generation while its named command remains registered. Current presentation
uses the latest channel generation. A retained history action must still pass
the source workflow's operation-specific checks.

The compact Status fallback does not invent action controls. A destination
that presents actions must use the same checked authority before dispatching
the ordinary command.

## Recover from Feedback Problems

- If feedback appears in the bottom region instead of a floating surface, the
  current frontend selected the declared Status fallback.
- If an action is rejected as stale, repeat the source operation and use its
  current feedback generation.
- If a routing update is invalid, Odra keeps the last valid complete route
  table.
- If work continues after a message disappears, use the operation's ordinary
  cancellation command; dismissal is presentation-only.
- Feedback history is bounded and session-local. Restarting the editor does
  not restore it.

## Verify the Result

You have completed this chapter when you can distinguish ordinary feedback,
attention feedback, and progress; recognize replacement by a newer source
generation; and explain why dismissal, cancellation, and retained history are
separate operations.

For the complete contracts, destinations, action checks, and bounds, see the
[Feedback and Progress Reference](../../../reference/feedback-and-progress/index.md).

---

[Previous: Use the Gutter](gutter-and-transient-details.md) ·
[User Guide](../index.md) ·
[Next: Customization](../customization/index.md)
