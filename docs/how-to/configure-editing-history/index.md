<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Configure Editing History at Runtime

Use the repository-owned Racket history facade to derive one complete policy
from the current Odin-owned policy. Applying the result does not restart the
Racket runtime or the editor.

## Define the configuration function

Create a `racket/base` module in the embedded Odra configuration environment
and import the history facade:

```racket
#lang racket/base

(require 'configuration)

(reload-history-policy!
 (lambda (current)
   (define inspected (history-policy-inspect current))
   (history-policy-replace
    current
    (hasheq
     'global-retained-bytes (* 1024 1024 1024)
     'buffer-retained-bytes (* 512 1024 1024)
     'inspection-nodes 512
     'pruning-operations 4096))))
```

`history-policy-inspect` returns an immutable hash containing all thirteen
fields. `history-policy-replace` copies the current value and replaces only the
named fields, so the configuration remains valid when fields are added to the
example later.

## Apply the configured policy

After loading or reloading the module in the existing embedded runtime, invoke
the native configuration turn. The command layer calls
`history_policy_apply_racket_configuration`, which performs this sequence:

1. Copy the current native policy and generation through a checked capability.
2. Run the registered Racket configuration function over that copy.
3. Copy the complete candidate back to Odin.
4. Validate every field and relationship.
5. Prove and perform any required bounded pruning.
6. Publish one new policy generation.

Calling `reload-history-policy!` again replaces the configuration function in
the live Racket runtime. Run the native configuration turn again to apply that
new result. `reset-history-policy!` restores the identity function; applying it
retains the current field values as a new complete generation.

Personal configuration discovery and a terminal command that invokes this
turn are not yet part of the current terminal interface. The API is available
to repository-owned embedded Racket modules and native assembly code.

## Check a rejected replacement

The existing policy remains authoritative when the candidate has an unknown or
non-integer Racket field, violates a native range or cross-field relationship,
cannot preserve protected retained history, is cancelled, or uses a stale
generation. A Racket exception is contained at the hosting boundary.

Use the focused validation and resource evidence commands:

```sh
make hosting-test
make history-resource-study
```

The exact field names, ranges, generations, pruning rules, and diagnostics are
listed in the [Reversible Editing History Reference](../../reference/reversible-editing-history/index.md).
