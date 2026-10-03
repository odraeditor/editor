<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Getting Started

This part establishes the first successful Odra session and the interaction
grammar used throughout the User Guide. By the end, you can install and launch
Odra, complete a protected file-editing lifecycle, invoke named commands, and
cancel an unfinished interaction while preserving your work.

## Before You Begin

Use a Linux x86-64 terminal with UTF-8 support. No source checkout, installed
Racket runtime, or previous Odra knowledge is required for the published
preview path.

## Chapters

1. [Choose an Installation Method](install-odra.md) lists the published,
   verified installation routes currently available to a new reader.
2. [Install and Launch a Linux Preview](install-linux-preview.md) reviews the
   public terms and notices, verifies the archive, and opens the Startup screen.
3. [Prepare the User Guide Exercises](prepare-exercises.md) verifies the
   version-matched kit and initializes isolated, disposable guide state.
4. [Complete the First Editing Session](first-editing-session.md) edits, saves,
   exits, and reopens that file while protecting unsaved changes.
5. [Use Commands and Interactions](commands-and-interactions.md) introduces key
   notation, `M-x`, prompts, candidates, acceptance, cancellation, and command
   discovery.

Follow the chapters in order. Later parts assume the key notation, `M-x`,
candidate navigation, prompt acceptance, and `C-g` cancellation introduced
here.

## When Something Goes Wrong

- For a missing download, failed checksum, missing runtime library, or bundled
  resource failure, return to
  [Install and Launch a Linux Preview](install-linux-preview.md#recover-from-installation-problems).
- For a missing exercise package, failed kit checksum, version mismatch, or
  conflicting guide root, return to
  [Prepare the User Guide Exercises](prepare-exercises.md).
- For a failed save, unassociated buffer, or interrupted exit, return to
  [Complete the First Editing Session](first-editing-session.md#recover-from-save-problems).
- For a prompt, candidate, or pending key sequence that should not continue,
  use the protected cancellation path in
  [Use Commands and Interactions](commands-and-interactions.md#recover-from-an-interaction).

The [Editor Core Terminology](../../../reference/terminology/index.md) defines
the public meanings of Buffer, Document, Project, Workspace, view, position,
and other terms used throughout the guide.

## Related Material

These focused documents provide shorter or more exhaustive paths. They are not
required chapters in the User Guide.

- [Open and Navigate a Dir](../../dir-first-opening/index.md)
- [Open, Edit, and Save a Local Document](../../../how-to/run-terminal-view/index.md)
- [Navigate Commands, Buffers, and Project Files](../../candidate-navigation/index.md)

## Continue

Proceed to [Editing](../editing/index.md) to learn direct movement, selection,
text transfer, reversible history, and saved editor state.

---

[Previous: User Guide](../index.md) ·
[Next: Choose an Installation Method](install-odra.md)
