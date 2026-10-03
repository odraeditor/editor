<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Open and Inspect a Project

This tutorial starts with an ordinary Dir, promotes it, and reopens the same
one-root Project.

## Create a sample Dir

```sh
mkdir -p /tmp/odra-project-demo
printf 'package demo\n' > /tmp/odra-project-demo/main.odin
.build/odra /tmp/odra-project-demo
```

The root initially behaves as an ordinary Dir and no `.odra/` metadata is
created by opening it.

## Promote the Dir

1. Invoke `project-promote` through `Meta-X`.
2. Accept or edit the proposed display name.
3. Press Enter.

Odra writes one local Project record and one global discovery reference. Open
buffers, views, and text remain unchanged. The Project begins untrusted.

## Inspect Project scope

Invoke `describe-project`. The result identifies one local Project and one
root. Then invoke `project-find-file` and open `main.odin`.

Create or open a path outside the root. Project status classifies that buffer
as external; Project-wide buffer operations do not adopt it.

## Reopen the Project

Exit Odra and open the same root again:

```sh
.build/odra /tmp/odra-project-demo
```

The exact local record restores Project identity. No global path scan or
repository-marker inference is required.

Continue with [Manage a Project Root](../../how-to/manage-project-directories/)
for scoped commands and Workspace composition.
