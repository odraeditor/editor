<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Manage a Project Root

## Open the Project

Open its root Dir from Startup, `open-directory`, or the command line. Odra
uses Project scope only when `<dir>/.odra/project.rkt` is valid for that exact
root.

Invoke `describe-project` to inspect the identity, name, generation, trust,
and one-root summary.

## Navigate Project content

Invoke `project-find-file` to select a regular file below the root. Use
`project-switch-buffer`, `project-save-buffers`, and
`project-close-buffers` for Project-scoped buffer operations.

`project-refresh` reconciles the current root observation without changing the
Project identity or adding another root.

## Work with several roots

A Project cannot acquire another root. Promote each ordinary Dir separately,
then create or update a Workspace to retain their order as one reusable
composition.

Opening a different Dir with `open-directory` replaces the current root after
ordinary dirty-buffer and Dir-abandonment decisions. It does not mutate the
Project being left.

## Diagnose scope

If a Project command reports a scope failure:

1. invoke `describe-project`;
2. verify that the opened Dir contains `.odra/project.rkt`;
3. verify that the stored root equals the normalized opened Dir; and
4. reopen the exact Project root.

Invalid metadata is not repaired or overwritten automatically. An ordinary
Dir remains usable for file navigation and editing.
