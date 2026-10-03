<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Trace One UI Generation Through the Shared Pipeline

This tutorial follows the presentation of ordinary editor panes and one
interactive candidate list from their semantic owners to terminal output. By
the end, you will be able to identify which layer owns each value and verify
that both workflows use the same frontend-independent UI pipeline.

Run every command from the repository root.

## 1. Start with the independent lifecycle model

Run the model suite:

```sh
make ui-reference-test
```

The model publishes complete generations containing views, surfaces, split
nodes, status regions, and focus. It has no editor buffer, candidate session,
or terminal renderer. This separation is intentional: it proves the UI
lifecycle without borrowing behavior from a current consumer.

## 2. Follow ordinary editor panes

Open `src/odra/app.odin` and locate these calls in the session presentation
path:

```text
proposal_project_editor_text_view
proposal_map_pane_layout
proposal_compose_pane_status
proposal_publish
registry_snapshot
renderer_present_ui
```

The editor view remains the owner of point, mark, viewport, selection, and
search state. The pane layout remains the owner of pane identity, focus,
history, dedication, split weights, and geometry. The UI proposal copies one
compatible presentation generation; it does not become another editor view or
pane tree.

Run the focused package tests:

```sh
odin test src/ui -vet -warnings-as-errors
odin test src/terminal -vet -warnings-as-errors
```

The tests cover atomic publication, stale generations, allocation faults,
layout lowering, style precedence, output failure, and cleanup.

## 3. Follow candidate navigation

Open `src/odra/candidate_ui.odin`. The candidate session supplies stable row
identity, matching, ranking, selection, query, and actions. Its presentation
is composed from:

```text
ListView + Input + Surface + Split + StatusRegion
```

`proposal_project_list_view` copies candidate rows and the model-owned current
item. `proposal_project_input` copies the exact query generation. The input
surface captures focus only after the complete root publishes, and
`renderer_present_ui` lowers the same generic snapshot used by ordinary panes.

Run the focused acceptance target:

```sh
make candidate-navigation-acceptance
```

This exercises command, session-buffer, Project-buffer, and Project-file
sources through native, Racket, and PTY boundaries without adding a
candidate-specific renderer.

## 4. Confirm every current consumer

Run the source migration gate:

```sh
make ui-migration-check
```

The gate verifies ordinary panes, Startup, Buffer Menu, Project inventory,
keymap inspection, candidate navigation, transient input, the terminal
renderer, and the programmable role boundary. It also rejects the superseded
component, prompt, view, layout, compatibility, and feature-kind presentation
entry points.

You have now traced two semantically different workflows through the same
model-to-renderer pipeline. The shared UI owns copied presentation generations;
the editor, layout, candidate, prompt, search, Project, and command subsystems
retain their existing semantic authority.

Continue with [Extensible UI Foundation Reference](../../reference/extensible-ui-foundation/index.md)
for exact records and limits, then use
[Validate the Extensible UI Foundation](../../how-to/validate-extensible-ui-foundation/index.md)
for the complete acceptance and resource gates.
