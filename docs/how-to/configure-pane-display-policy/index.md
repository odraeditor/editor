<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Configure Other-Pane Display Policy

Use the repository-owned Racket display-policy facade to derive one complete
destination strategy from the current Odin-owned policy. Applying the result
does not restart the Racket runtime or the editor.

## Define the configuration function

Create a `racket/base` module in the embedded Odra configuration environment
and import the display-policy facade:

```racket
#lang racket/base

(require 'display-policy-configuration)

(reload-display-policy!
 (lambda (current)
   (define inspected (display-policy-inspect current))
   (display-policy-replace
    current
    (hasheq
     'actions '(reuse-same-buffer split-right reuse-least-recent)
     'split-height-threshold 16
     'split-width-threshold 60))))
```

`display-policy-inspect` returns an immutable hash with `actions`,
`split-height-threshold`, and `split-width-threshold`.
`display-policy-replace` copies the current value and replaces only the named
fields. Actions must be a nonempty unique list of at most 32 values chosen
from:

- `reuse-same-buffer`;
- `split-below`;
- `split-right`;
- `reuse-least-recent`; and
- `reuse-most-recent`.

Each threshold must be a positive integer that fits the native 32-bit range
after crossing the hosting boundary. A threshold permits an automatic split
attempt; layout geometry and capacity checks must still accept the resulting
tree.

## Apply the configured policy

After loading or reloading the module in the existing embedded runtime, invoke
the native configuration turn. The command layer calls
`display_policy_apply_racket_configuration`, which performs this sequence:

1. Acquire a checked capability and copy the current policy and generation.
2. Run the registered Racket configuration function over that copy.
3. Copy one complete fixed-width candidate back through hosting.
4. Validate action count, uniqueness, action values, thresholds, capability,
   layout identity, and expected policy generation in Odin.
5. Atomically publish one new policy generation.

Calling `reload-display-policy!` again replaces the configuration function in
the live Racket runtime. Run the native configuration turn again to apply the
new result. `reset-display-policy!` restores the identity function; applying
it retains the current field values as a new generation.

Personal configuration discovery and a terminal command that invokes this
turn are not yet part of the current terminal interface. The API is available
to repository-owned embedded Racket modules and native assembly code.

## Check a rejected replacement

The current policy remains authoritative when Racket raises an exception,
returns a malformed envelope, changes the expected generation, duplicates or
misnames an action, supplies too many actions, uses an invalid threshold, or
invokes a stale, wrong-thread, or reentrant capability.

Run the focused boundary and command tests:

```sh
make hosting-test
make native-command-test
```

See [Pane Layout Reference](../../reference/pane-layout/index.md) for the
factory ordering, command focus behavior, limits, and native failure codes.
