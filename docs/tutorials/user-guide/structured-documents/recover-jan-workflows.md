<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Recover Jan Workflows

This chapter diagnoses one rejected Jan operation and selects a recovery while
preserving text and exposing any partial external work.

## Start with the Owning Status

Use `jan-language-status` for analysis, `jan-inspect-availability` for
structured editing, `jan-planning-status` for planning and agendas, and
`jan-computation-status` for calculations and execution. Output, provider, and
extension inspection is available through the Jan commands shown by `M-x` in
the current build.

Read the exact scope, revision, configuration and provider generations,
availability, limit, observed usage, partial-outcome counts, and latest
failure. Do not retry against a different target until those values are clear.

## Select the Matching Recovery

| Outcome | Meaning | Recovery |
| --- | --- | --- |
| Unsupported | The active document or operation has no matching Jan route. | Confirm `.org` or `.jan`, the command scope, and explicit language selection. |
| Incomplete | A required analysis, source, configuration, or provider result is not confirmed. | Keep editing ordinary text; retry after the owner reports a complete generation. |
| Stale | The request names an older revision or generation. | Refresh the owning view or status, then issue a new request. |
| Malformed | The retained source cannot produce the requested semantic target. | Inspect or lint the exact range and edit only the intended source. |
| Unavailable | An optional adapter, tool, provider, or capability is absent. | Use a native or offline route, or configure the optional dependency explicitly. |
| Unauthorized | The request exceeds admitted authority. | Reduce the operation or explicitly grant the required scoped authority through its owner. |
| Limited | A count, byte, depth, time, or memory ceiling was reached. | Reduce the scope; do not raise a limit merely to hide the boundary. |
| Cancelled or timed out | The owning workflow stopped before acceptance. | Inspect cleanup and partial outcomes, then start a new request if needed. |
| Conflict or reconciliation required | Multiple resource histories cannot be applied safely. | Preserve both sides and choose an explicit resolution. |
| Provider invalid or failed | A provider returned a mismatched or invalid result. | Keep the last confirmed generation, inspect attribution, and disable only through the checked lifecycle. |

## Confirm No-Effect Guarantees

After rejection, compare the source with ordinary undo history or a saved
checksum. A rejected semantic edit cannot mutate canonical text. A rejected
export cannot publish partial output. A stale resource plan cannot overwrite a
newer revision. Provider failure cannot activate an incomplete generation.

External workflows can report partial effects. A local publication can finish
before a remote upload fails; a synchronization staging area can exist before
application. Inspect the manifest and recovery state instead of assuming that
source preservation also rolls back external systems.

## Verify the Result

You have completed this chapter when you can classify one failure, identify
its owning revision or generation, use the matching recovery, and verify that
canonical source and the last confirmed state remain available.

For exact limits and linked subsystem references, see the
[Jan Product Surface Reference](../../../reference/jan-product-surface/index.md).

---

[Previous: Connect and Extend Jan](connect-and-extend.md) ·
[Structured Documents](index.md) ·
[Next: Packages and Catalogs](../packages/index.md)
