<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Validate Pane Layouts

Run commands from the repository root. Use the smallest gate that covers the
change, then run the complete repository gate once at the slice or pull-request
boundary.

## Check a layout change while editing

Run the native layout suite for topology, geometry, focus, history, dedication,
hooks, deferred requests, limits, faults, accounting, and teardown:

```sh
odin test src/layout -vet -warnings-as-errors
```

When the change crosses the checked command or Racket boundary, also run:

```sh
make native-command-test
```

When only the composed runtime lifecycle changed, run the two-process acceptance
probe without repeating the reference, resource, command, or PTY suites:

```sh
make layout-acceptance-runtime
```

Both process runs must report `passed=true`, `runtime_stopped=true`,
`cleanup_complete=true`, and `retained_native_bytes=0`.

## Run the complete focused gate

Before completing a layout task, run:

```sh
make layout-acceptance
```

This target combines the independent multi-view, layout, and pane-buffer
references; the native layout and command suites; the layout resource study;
the pane-layout, pane-buffer, other-pane, and area-balance PTY workflows; and
the two-process acceptance probe.

Use this target instead of manually repeating its component commands.

## Reproduce resource evidence

Run the selected layout and aggregate multi-view profiles with:

```sh
make layout-resource-study
make multi-view-resource-study
```

The layout study must report `status=pass`. Every multi-view profile must report
`valid=true`; measured profiles must also report zero cleanup bytes. The policy
line records the selected pane, depth, view, history, hook, deferred-request,
snapshot, prepared-memory, diagnostic, geometry-work, and latency ceilings.

## Run the repository gate

At the slice or pull-request boundary, run:

```sh
make verify
git diff --check
```

`make verify` composes static checks, the broad test target, hosting tests, and
documentation validation. Its layout components are each executed once; the
acceptance executable alone runs twice to prove clean runtime restart and
teardown in separate processes.

Do not treat an isolated rerun as proof that the repository gate passed. Record
the exact failing command when a PTY or mixed-language failure appears only in
the integrated sequence.

See [Pane Layout Reference](../../reference/pane-layout/index.md) for exact
contracts and [Why Programmable Pane Layouts Use Copied Authority](../../explanation/programmable-pane-layouts/index.md)
for the Racket, hook, and deferred-publication boundaries.
