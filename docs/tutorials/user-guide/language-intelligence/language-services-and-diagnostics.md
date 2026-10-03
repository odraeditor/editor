<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Use Language Services and Diagnostics

This chapter admits one external language service through an exact trusted
Project, inspects its health, creates and clears a current diagnostic, moves
through diagnostic locations, and verifies that process failure cannot block
ordinary editing.

## Before You Begin

If you enter this chapter directly, first complete [Prepare the User Guide
Exercises](../getting-started/prepare-exercises.md).

Complete [Use Syntax and Structure](syntax-and-structure.md). Confirm that the
installed editor and the maintained factory service executable are available
in the environment used to launch Odra:

```sh
command -v odra
command -v ols
```

The factory definition requests `ols` through controlled executable lookup.
Odra does not download, update, invoke through a shell, or write Project
configuration for that executable.

## Admit the Trusted Project

External Project-scoped processes require explicit trust. Follow
[Manage Project Trust and Refresh](../../../how-to/manage-project-trust/index.md)
to change the exact local record for
`~/odra-guide/work/projects/forecast-engine` from `untrusted` to `trusted`.

The exercise kit supplies this Project and every source file changed below.

Trust increments the local Project generation. Open the exact root through
`Open Dir` rather than reusing an older Workspace or discovery candidate, then
select `main.odin`. The valid local record admits it as the trusted
`Forecast Engine` Project.

A `.odin` suffix selects the factory language, but the same file in an
ordinary Dir, an untrusted Project, or outside the admitted Project root does
not authorize a language-service process.

## Inspect Service Health

Run `M-x describe-language-service`. The read-only list reports the provider,
requested and resolved executable, session and child-process phase, negotiated
protocol capabilities, synchronized document count, current diagnostics,
resource policy, bounded standard-error tail, and latest failure.

A healthy factory session reaches an active phase with a running process and
one binding for the open document. Press `q` or `C-g` to return. Discovery and
initialization never prevent immediate text editing while they progress.

## Create a Current Diagnostic

Inside `main`, insert this incomplete statement on its own line:

```odin
broken :=
```

Wait for a diagnostic marker at that line. Run
`M-x list-language-diagnostics`. The filterable list contains the current
complete active-buffer or Project generation, with severity, path, and
location. Select the new error with `RET` to reopen its source and move point
to the revalidated range.

Use `M-g n` and `M-g p` from an ordinary editor pane to visit the next or
previous current diagnostic. These commands move through document locations;
they never apply server-provided text edits.

## Observe Invalidation

Undo the incomplete statement. The canonical edit invalidates the old
diagnostic generation before the service receives the admitted incremental or
full synchronization update.

After the next publication, the old marker and candidate are gone. Running
`M-x list-language-diagnostics` may report `No current language diagnostics`;
that means no current publication exists, not that editing failed.

If a diagnostic candidate was opened before the edit, invoking it afterward
is rejected as stale rather than navigating to a range from an older document
revision.

## Share Diagnostics Across Views

Press `C-x 3` while `main.odin` is active. Both views share one document
binding and one diagnostic generation while keeping independent point and
viewport state. Reintroduce `broken :=`, observe the marker in both views,
then undo it and keep one pane with `C-x 1`.

## Exercise Failure Containment

Exit the clean editor session. Create a disposable executable that exits
immediately:

```sh
mkdir -p ~/odra-guide/work/tools
printf '#!/bin/sh\nexit 1\n' > ~/odra-guide/work/tools/ols
chmod 700 ~/odra-guide/work/tools/ols
```

This executable is created by the current chapter from the complete shell
commands above; it is not supplied by the exercise kit.

Launch one capability experiment with that directory first in `PATH`, open the
trusted Project through `Open Dir`, and select `main.odin`:

```sh
PATH="$HOME/odra-guide/work/tools:$PATH" odra
```

The `PATH` override belongs only to this provider-failure experiment.

Run `M-x describe-language-service`. The failed child is contained and reaped;
its phase, process state, bounded standard error, and failure code remain
inspectable. Insert, undo, search, save, switch buffers, and arrange panes to
confirm that ordinary editor ownership is unaffected.

## Request the Bounded Restart

Run `M-x restart-language-service` after inspection shows a failed, reaped
session. The command spends one explicit restart attempt and the disposable
server exits again. Another restart is rejected after the bounded allowance is
exhausted.

An active session rejects this command with `Invalid_Session`; it is not a
general refresh action and never creates an automatic retry loop.

Exit Odra and remove the disposable executable:

```sh
rm -r ~/odra-guide/work/tools
```

Resume ordinary guide work with `odra` from the activated guide shell.

## Recover from Service Problems

- If inspection reports `Executable_Not_Found`, correct the launch `PATH` and
  start a new editor session.
- If there is no service session, verify the suffix, active Project root, exact
  local trust generation, and provider availability.
- If a candidate is stale, wait for the next current publication and request a
  new diagnostic list.
- If the restart allowance is exhausted, correct the executable or Project
  configuration and start a fresh editor session.
- Revoking Project trust tears down its synchronized documents and diagnostics
  without closing their editor buffers.

## Verify the Result

You have completed this chapter when an exact trusted Project starts one
service session, inspection reports its health, an induced error appears and
is navigable, undo invalidates its generation, two views share diagnostics,
an exiting provider leaves ordinary editing usable, and restart remains an
explicit bounded recovery action.

For setup and focused recovery, see
[Set Up and Diagnose Language Services](../../../how-to/use-language-services/index.md).
For exact lifecycle, diagnostic, and provider contracts, see the
[Language Service Contract Reference](../../../reference/language-service-contracts/index.md),
[Language Diagnostics Reference](../../../reference/language-diagnostics/index.md),
and
[Programmable Language Service Reference](../../../reference/programmable-language-services/index.md).

---

[Previous: Work with Jan Documents](work-with-jan-documents.md) ·
[User Guide](../index.md) ·
[Next: Use Factory Go Language Support](configure-language-support.md)
