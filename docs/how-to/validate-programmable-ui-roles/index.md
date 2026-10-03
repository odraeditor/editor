<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Validate Programmable UI Roles

Run these commands from the repository root.

## Check schemas and Racket contracts

```sh
odin test src/bridge -vet -warnings-as-errors
raco test src/command/native-contracts.rkt
raco test src/hosting/ui-role-bridge.rkt
make hosting-runtime-check
```

These checks detect record-width or schema drift, unsupported role and
renderer values, malformed request sizes, invalid Racket contracts, and a
runtime module that cannot expose the checked role capability.

## Run the mixed-language role fixture

```sh
odin test src/command \
  -vet -warnings-as-errors \
  -define:ODRA_RACKET_RUNTIME_LIBRARY="../../.build/hosting/libodra_racket_runtime.a" \
  -extra-linker-flags:"/usr/lib/racket/../libracketcs.a -lm -lncursesw -lz -llz4 -ldl -lpthread -Wl,--export-dynamic-symbol=odra_racket_scoped_capability_call"
```

The package test inspects all seven roles, runs one complete package provider
proposal, activation, inspection, admitted command, rollback, and teardown,
and checks stale scope, requested and active exceptions, callback-budget
containment, clean session-generation restart, fallback selection, provider
accounting, and cleanup.

## Reproduce the resource study

```sh
make ui-role-resource-study
```

The policy line must report `valid=true`, seven roles, 64 providers, an 8 MiB
proposal and snapshot limit, a 256-callback budget, session scope, built-in
fallback, and measured turn completion.

The ordinary, demanding, and stress lines must each report `valid=true` and
`teardown_bytes=0`. The profiles exercise 16, 1,024, and 4,096 copied list
items; 4 KiB, 1 MiB, and maximum-size package content; scalar crossings;
all-role snapshots; proposal, activation, and admitted callbacks; retained
memory; and exact teardown.

## Exercise the complete hosting regressions

```sh
make hosting-test
make hosting-benchmark
```

These targets retain the runtime lifecycle, wrong-thread, reentrancy,
exception, scoped-capability, layout-hook, display-policy, keymap-profile,
buffer-session, Project, search, transfer, transaction, and command regression
coverage around the new role capability.

## Check package documentation and integration

```sh
make docs-check
make verify
git diff --check
```

`make verify` invokes `ui-acceptance`, which includes the role resource study
and mixed-language hosting regressions, then adds static and documentation
checks. A successful result must preserve the built-in fallback after
contained package failure and finish without retained native role-registry
storage.

## Minimal package fixture

The host supplies `control` during one admitted role turn. Package code can
prepare and activate a provider as follows:

```racket
#lang racket/base

(require "ui-role-bridge.rkt")

(define (install-startup-provider control)
  (define proposed
    (ui-role-propose
     control
     (ui-role-proposal
      'startup
      "compact startup"
      "example/ui"
      '(cell-geometry clipping unicode-profile atomic-generation)
      #"bounded package presentation"
      #"open"
      32)))
  (if (ui-role-failure? proposed)
      proposed
      (ui-role-activate control (ui-role-outcome-provider proposed))))
```

Keep the returned provider handle only as copied identity. A later native turn
must acquire a fresh role control and scope before inspection, replacement,
rollback, or teardown. Do not retain the control itself.

See [Programmable UI Roles Reference](../../reference/programmable-ui-roles/index.md)
for value shapes, limits, and failure behavior.
