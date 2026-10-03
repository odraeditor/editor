<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Use the Gutter

This chapter follows the complete Gutter workflow: read stable line numbers,
change numbering for one view, inspect semantic markers, invoke marker actions,
and add a personal theme-aware marker that leaves document text unchanged.

## Before You Begin

If you enter this chapter directly, first complete [Prepare the User Guide
Exercises](../getting-started/prepare-exercises.md), then complete
[Read and Configure the Status Bar](status-bar.md). The configuration source
used below is created by the reader from the complete displayed block.

## Read Stable Line Numbers

Open an ordinary text file. The left Gutter shows one-based logical line
numbers. Its number field reserves at least four digits, so moving from line 9
to 10 or from 99 to 100 does not shift the document text.

The Gutter is presentation owned by the active view. Its numbers, separators,
and markers are not part of selection, copying, search, replacement, editing
history, language offsets, or reported text columns. If a pane becomes too
narrow, Gutter lanes hide before they consume the protected text area.

## Change Numbering in the Active View

Run these commands through `M-x` and observe the active pane:

1. Run `gutter-cycle-line-number-mode` to cycle through hidden, absolute,
   relative, and hybrid numbering.
2. Run `gutter-toggle-line-number-side` to move numbers between the left and
   right sides.
3. Run `gutter-inspect-numbering` to read the effective mode, side, scope, and
   whether the policy is the configured default or a view override.
4. Run `gutter-toggle-line-numbers` to hide or restore numbering.

The explicit commands `gutter-set-line-numbers-none`,
`gutter-set-line-numbers-absolute`, `gutter-set-line-numbers-relative`, and
`gutter-set-line-numbers-hybrid` select a mode without cycling. Numbering uses
logical lines. `gutter-set-numbering-visual` reports that visual-line scope is
currently unavailable and preserves the last valid policy.

Split the current pane and change numbering in only one side. Both views share
the same text, but each retains its own Gutter policy.

## Establish the Personal Numbering Default

Open `${XDG_CONFIG_HOME:-$HOME/.config}/odra/init.rkt`. Retain any existing
exports and add `odra-gutter-configuration`:

```racket
#lang racket/base

(provide odra-gutter-configuration)

(define odra-gutter-configuration
  '#hash((mode . hybrid)
          (current-line . zero)
          (minimum-digits . 4)))
```

Run `M-x reload-personal-commands`. New views use hybrid numbering, display
zero on the current line, and reserve at least four digits. Existing explicit
view overrides remain local. An invalid complete configuration is rejected
without replacing the last valid policy.

## Read Semantic Markers

The factory semantic lane appears opposite the number lane only when the
current viewport contains a marker. Its presentation follows the active theme
and terminal capabilities.

Current language diagnostics contribute error, warning, information, and hint
markers. Open a document with live language diagnostics and move to a marked
line. Run `M-x gutter-inspect-markers`; a compact popup anchored to the Gutter
row shows the marker detail. Source, collision, and action metadata remain
internal. Its border and content styles follow
the active theme through the contextual presentation profile. The document
remains focused. Press `C-g` or move the cursor to dismiss the popup.

When several markers share the line, repeat `gutter-inspect-markers` to replace
the popup with the next collision member, including members hidden behind the
visible marker. A terminal without overlap support, or one too narrow for the
minimum popup, shows the same essential detail through the compact shared
feedback region.

The shared placement diagram in
[Use Language Completion](../language-intelligence/language-completion.md#request-candidates-manually)
contrasts a point-anchored candidate surface with this line-anchored marker
detail. Both preserve the surrounding document as context.

Run `M-x gutter-invoke-primary-marker-action` on a diagnostic marker. The
action opens the ordinary diagnostic surface through normal command dispatch.
Run `M-x gutter-refresh-markers` to ask the active buffer's semantic owner for
a current publication.

For the language-service setup that produces diagnostics, follow
[Use Language Services and Diagnostics](../language-intelligence/language-services-and-diagnostics.md).

## Observe Horizontal Clipping

Open a line wider than the active pane and move the cursor far enough across
the line to change the horizontal viewport. The semantic lane indicates when
content is clipped on the left, right, or both sides. These markers belong to
the exact view snapshot: another pane over the same buffer can show a different
clipping state.

## Add a Personal Marker

In `init.rkt`, require the public Gutter API and export one personal provider:

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
     #:style 'ordinary
     #:detail "Review this line"
     #:actions '(cursor-next-line)))))
```

Run `M-x reload-personal-commands`, open a document with at least six lines,
and move to line 5. The right Gutter shows the marker without inserting it into
the document. Inspect it in the anchored popup with
`gutter-inspect-markers`, then run
`gutter-invoke-primary-marker-action`; the admitted `cursor-next-line` action
moves the cursor through ordinary command dispatch.

The primary glyph follows the active theme and terminal capabilities. The
fallback preserves its meaning when the primary glyph cannot be presented.

## Replace or Remove the Personal Provider

Change the marker and publish a newer complete generation:

```racket
(define odra-gutter-provider
  (gutter-provider
   "Personal Notes"
   'personal-notes
   (list notes-lane)
   (list
    (gutter-marker 'review 'notes 5 "▲"
                   #:fallback "*"
                   #:style 'ordinary
                   #:detail "Updated review marker"))
   #:generation 2
   #:marker-generation 2))
```

Run `M-x reload-personal-commands`. The new complete generation replaces the
old marker atomically. A rejected replacement leaves the last valid generation
visible.

To remove only the personal provider, export `#f` and reload:

```racket
(define odra-gutter-provider #f)
```

Factory line numbers, diagnostics, and clipping indicators remain available.

For operational recovery and reload procedures, see
[Configure and Reload a Programmable Gutter](../../../how-to/configure-programmable-gutter/index.md).
For every command, configuration field, marker policy, limit, and lifecycle
rule, see the [Gutter Reference](../../../reference/gutter/index.md). For the
ownership model, see
[Why Programmable Gutters Publish Immutable Generations](../../../explanation/programmable-gutter-ownership/index.md).
For the shared presentation contract, see the
[Transient Presentation Profile Reference](../../../reference/transient-presentation-profiles/index.md).

---

[Previous: Read and Configure the Status Bar](status-bar.md) ·
[User Guide](../index.md) ·
[Next: Read Feedback and Progress](read-feedback-and-progress.md)
