<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Add a Personal Gutter Provider

This tutorial adds one theme-aware marker lane from personal Racket
configuration, inspects its marker, invokes its action, and reloads a changed
generation.

## Create the Provider

Open `${XDG_CONFIG_HOME:-$HOME/.config}/odra/init.rkt` and add:

```racket
#lang racket/base

(require odra/gutters)

(provide odra-gutter-provider)

(define notes-lane
  (gutter-lane 'notes #:side 'right #:style 'ordinary))

(define odra-gutter-provider
  (gutter-provider
   "Personal Notes"
   'personal-notes
   (list notes-lane)
   (list
    (gutter-marker
     'review
     'notes
     5
     "◆"
     #:fallback "*"
     #:style 'diagnostic-information
     #:detail "Review this line"
     #:actions '(gutter-inspect-numbering)))))
```

If the file already exports personal commands, a keymap profile, or factory
presentation settings, retain those exports and add
`odra-gutter-provider` to the existing `provide` form.

## See and Inspect the Marker

Build and open a document with at least five lines:

```sh
make odra
.build/odra /path/to/document
```

Move to line 5. The right Gutter shows `◆`, or `*` when the terminal cannot
present the primary glyph.

Run `M-x gutter-inspect-markers`. A compact popup anchored to the marked Gutter
row shows the `Review this line` detail. Provider, collision, and action
metadata remain internal. Repeating the command replaces the popup with each
retained collision member when several markers share the location. Press
`C-g`, or move the cursor, to dismiss it without moving document focus.

When the frontend cannot overlap content or the available geometry is too
narrow, the same detail appears in the shared compact feedback region.

Run `M-x gutter-invoke-primary-marker-action`. The registered
`gutter-inspect-numbering` command runs through ordinary command dispatch.

## Replace the Generation

Change the marker glyph and detail, and increase both generation values:

```racket
(define odra-gutter-provider
  (gutter-provider
   "Personal Notes"
   'personal-notes
   (list notes-lane)
   (list
    (gutter-marker 'review 'notes 5 "▲"
                   #:fallback "*"
                   #:style 'diagnostic-information
                   #:detail "Updated review marker"))
   #:generation 2
   #:marker-generation 2))
```

Run `M-x reload-personal-commands`. The complete replacement appears without
restarting the editor. A rejected replacement leaves the previous visible
generation intact and reports a bounded diagnostic.

## Remove the Provider

Replace the exported value with:

```racket
(define odra-gutter-provider #f)
```

Run `M-x reload-personal-commands` again. The personal lane disappears while
factory line numbers, diagnostics, and clipping markers remain available.

See the [Gutter Reference](../../reference/gutter/index.md) for the complete
constructor values and limits.
