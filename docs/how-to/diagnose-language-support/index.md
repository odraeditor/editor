<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Diagnose Language Support

Use the inspection commands in this order to locate recognition, syntax,
service, formatter, trust, or bundle failures without disabling ordinary
editing.

## Inspect the Active Document

Open the affected file and run `M-x describe-language-support`. Check:

1. detected and explicitly selected language;
2. selector source and competing selectors;
3. active bundle identity, version, origin, and generation;
4. syntax provider, grammar, queries, injections, parse revision, and failure;
5. selected service, resolved root, executable provenance, and availability;
6. formatter and negotiated capabilities.

If no language is selected, compare the filename with the selectors in the
[Language Support Reference](../../reference/language-support/index.md). A
complete Personal or trusted Project definition may replace a Factory
definition; it does not patch individual Factory fields.

## Distinguish Syntax from Service Failure

Local Tree-sitter syntax is in-process and does not need an LSP executable.
If syntax remains but completion, diagnostics, navigation, or formatting is
unavailable, inspect the service rather than the grammar.

Run `M-x describe-language-service`. Confirm the Project is trusted, the root
marker is correct, the executable is resolved, the process is active, the
document revision is synchronized, and the required feature was negotiated.

Correct the documented prerequisite or Project root first. For a failed,
reaped session, run `M-x restart-language-service` once. Repeated automatic
restart loops are intentionally bounded.

## Run the Doctor

Run `M-x language-support-doctor` for copied diagnostics across selectors,
providers, artifacts, executables, trust, capabilities, lifecycle state, and
resource limits. Read the issue code, bundle and version, evidence generation,
actual and allowed resources, and the exact recovery action.

Use `M-x describe-language-bundle` when the issue names a bundle. Verify its
artifacts, authorities, dependency state, contribution generation, active
state, predecessor, and last failure before enabling or rolling it back.

## Common Recoveries

| Symptom | Recovery |
| --- | --- |
| File is plain text | Correct the suffix or complete replacement definition; reopen and inspect. |
| Syntax unavailable | Inspect grammar ABI, query validity, artifact digest, authority, and resource failure. |
| Service executable missing | Install the version documented by the language page and restart from an environment with that executable on `PATH`. |
| Service root is wrong | Open and trust the intended Project; add the language's real root marker to the Project rather than inventing a Personal override. |
| Capability unavailable | Inspect server negotiation; use only commands admitted by both the bundle and the active service. |
| Installed bundle disabled | Review its authorities and run `M-x language-bundle-enable`. |
| Update failed | Preserve the last confirmed generation; inspect, then use explicit rollback if a predecessor exists. |
| Bundle remains unwanted | Disable, verify dependents, then remove it with the management workflow. |

Do not treat a service failure as a reason to remove the language bundle. The
document must remain editable, and local syntax should remain available when
only the external process is unavailable.
