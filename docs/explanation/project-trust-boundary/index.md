<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Why Project Trust Belongs to Local Identity

Trust decides whether one Project root may contribute executable editor
behavior. It does not decide whether the user may read, edit, search, or save
ordinary files.

Attaching trust to the exact local Project identity, generation, and root keeps
the decision beside the authority it governs. An ordinary Dir has no trust
state, and a global discovery reference cannot grant trust. Opening unfamiliar
content therefore remains separate from executing its configuration, tools,
language services, or extensions.

Revocation is a new atomic Project generation. It does not close buffers,
delete files, remove the root, or mutate any Workspace containing the Project.
The user retains ordinary file access while Project-provided executable
capabilities are no longer admitted.

Workspace composition preserves this isolation. Every member resolves its own
local record and trust; the Workspace stores ordered references but owns no
combined trust decision.

Filesystem observations remain hints. A missing or unreadable root is reported
without silently deleting Project identity or changing trust. Reconciliation
publishes complete observed state, while cancellation or failure preserves the
last confirmed generation.
