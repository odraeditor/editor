<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Navigate Live Language Diagnostics

This tutorial follows the complete factory language-service workflow in one
trusted Project. You will open an Odin document, inspect the external service,
edit while diagnostics remain advisory, and move through current diagnostic
locations without giving the server ownership of the document.

## Before You Start

Build Odra and confirm that an `ols` executable is available on `PATH`:

```sh
make odra
command -v ols
```

Use a local Project whose one root is trusted. Project trust is the boundary
that admits external language-service processes; opening the same file through
an ordinary Dir or an untrusted Project keeps editing available but
does not start OLS. See [Manage Project Trust and Refresh](../../how-to/manage-project-trust/index.md)
for the trust workflow.

Create or open an Odin file containing a temporary syntax error, for example:

```odin
package main

main :: proc() {
```

## Open the Trusted Project

Start the editor:

```sh
./.build/odra
```

Choose `Open directory`, enter the local Project path, select the Odin
file, and press `RET`. Odra associates the `.odin` document with the factory
language identity and starts at most one matching service session for the
trusted Project.

The document remains immediately editable. Service discovery, initialization,
or failure never blocks ordinary buffer, pane, history, search, save, or exit
workflows.

## Inspect the Service

Run `M-x describe-language-service`. The read-only list reports the selected
provider, requested and resolved executable, session phase, child-process
state, negotiated capabilities, synchronized document count, current
diagnostic count, resource use, and the latest bounded failure.

Use `C-g` to return to the document. A healthy factory session reports an
active phase and running process. If OLS is missing, the inspection reports
`Executable_Not_Found`; the document remains usable.

## List and Visit Diagnostics

Run `M-x list-language-diagnostics`. The candidate list contains one complete
current generation for the active buffer or Project. Each row exposes severity
and location and can be filtered with ordinary candidate input.

Select a row with `RET`. Odra revalidates the Project root, service session,
document revision, diagnostic generation, and byte range before it opens the
document and moves point.

From an ordinary editor view, use:

- `M-g n` to move to the next current diagnostic; and
- `M-g p` to move to the previous current diagnostic.

These commands move through existing documents, panes, and points. They never
apply an edit from the server.

## Edit and Observe Invalidation

Close the missing brace and save the file. The canonical edit invalidates the
previous diagnostic generation before newer text can display it. Odra sends
the admitted incremental or full synchronization update, and only a later
publication matching the current document state becomes visible.

Open another pane with `C-x 3` or switch buffers. Views of the same buffer share
one document binding and one diagnostic generation while retaining independent
view positions.

## Inspect Failure and Restart

Run `M-x describe-language-service` again after an external server failure.
The inspection preserves copied process state, bounded standard error,
resource use, and the exact failure code.

`M-x restart-language-service` is accepted only for a failed session whose
child has already been reaped. It spends one explicit bounded restart attempt.
It does not create an automatic retry loop, and it is rejected for an active
session.

## Finish

Exit with `C-x C-c`. Odra closes synchronized documents, requests protocol
shutdown, terminates when required, reaps the child process, and restores the
terminal. Unsaved-buffer confirmation remains the ordinary editor workflow,
independent of service health.

You have now exercised the complete factory path while keeping language-
specific values in provider data and canonical editor ownership in Odin.
