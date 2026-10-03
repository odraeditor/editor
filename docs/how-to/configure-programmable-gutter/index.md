<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Configure and Reload a Programmable Gutter

Use the public `odra/gutters` module from personal configuration to publish one
bounded logical-line marker provider.

## Define a Provider

In `${XDG_CONFIG_HOME:-$HOME/.config}/odra/init.rkt`, require `odra/gutters`,
export `odra-gutter-provider`, and construct one provider from one lane and up
to 256 markers:

```racket
#lang racket/base

(require odra/gutters)

(provide odra-gutter-provider)

(define odra-gutter-provider
  (gutter-provider
   "Bookmarks"
   'bookmarks
   (list (gutter-lane 'bookmark #:side 'left #:order 10))
   (list
    (gutter-marker 'chapter 'bookmark 24 "●"
                   #:fallback "o"
                   #:detail "Chapter boundary"))))
```

Lines are one-based. Marker identities must be unique within the provider, and
each marker must reference the declared lane.

## Reload a Replacement

Publish a complete new definition, increasing `#:generation` and
`#:marker-generation` when the provider or marker publication changes. Run:

```text
M-x reload-personal-commands
```

The reload replaces the provider atomically. It also reloads the other
personal configuration exports as one candidate.

## Inspect or Invoke a Marker

Move the cursor to a marked line and use:

```text
M-x gutter-inspect-markers
M-x gutter-invoke-primary-marker-action
```

The inspection command opens a read-only popup anchored to the marked Gutter
row. Repeat it to cycle colliding markers. Use `C-g` or cursor movement to
dismiss the popup. A frontend without overlap support uses the shared compact
feedback region instead.

Actions must name commands already present in the active command registry.
Use `M-x` to confirm that an intended action is discoverable before adding its
identity to `#:actions`.

## Remove the Provider

Keep the export and set it to `#f`, then reload:

```racket
(define odra-gutter-provider #f)
```

Removal affects only the personal provider. Factory Gutter owners remain
active.

## Diagnose Rejection

`Programmable Gutter provider rejected` means the complete candidate failed
native admission. Check, in order:

1. provider, package, lane, and marker identities use lowercase machine names;
2. the provider declares exactly one lane;
3. every marker line is positive and every marker names that lane;
4. marker identities are unique and there are no more than 256 markers;
5. glyph, fallback, detail, and separator text remain within their bounds; and
6. every action names an admitted command.

A rejected reload preserves the last valid provider. Correct the definition
and run `M-x reload-personal-commands` again.

For exact values and limits, see the [Gutter Reference](../../reference/gutter/index.md).
