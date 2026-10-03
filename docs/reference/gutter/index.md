<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Gutter Reference

The Gutter is view-local presentation beside ordinary buffer text. The factory
provider displays logical line numbers without inserting characters into the
buffer or changing text coordinates.

The factory semantic lane also presents current language diagnostics and
horizontal-clipping indicators. It appears only when one of those markers is
visible and occupies the side opposite the configured number lane.

One personal Racket provider may contribute an additional immutable lane and
bounded logical-line marker generation. Programmable markers use the same
geometry, collision, theme, inspection, and command paths as factory markers.

## Numbering Modes

| Mode | Non-current lines | Current line |
| --- | --- | --- |
| `none` | hidden | hidden |
| `absolute` | one-based logical line | configured current-line form |
| `relative` | logical distance from the cursor | configured current-line form |
| `hybrid` | logical distance from the cursor | configured current-line form |

The current-line form is independently configurable as `absolute`, `zero`, or
`hidden`. Relative and hybrid numbering use the logical line index and bounded
visible-row work. Cursor movement and scrolling do not scan the complete
buffer or change the reserved number width.

The available numbering scope is `logical`. `visual` is reserved and rejected
without changing the last valid policy.

## View-Local Policy

Personal configuration establishes the default policy. Each editor view may
retain an explicit override for visibility, side, mode, scope, current-line
form, digit bounds, padding, order, and separator. A split view initially
inherits its source view's policy and may then diverge. Rebinding a view to a
different buffer retains its presentation policy; closing the view invalidates
that policy with the rest of the view state.

Two views over one buffer share canonical text while retaining independent
Gutter policies. Gutter text is not part of selection, copying, search,
replacement, editing history, language offsets, or reported text columns.

## Commands

The following commands are available through `M-x` and affect only the active
view:

| Command | Behavior |
| --- | --- |
| `gutter-toggle-line-numbers` | Show or hide line numbers. |
| `gutter-cycle-line-number-mode` | Cycle through none, absolute, relative, and hybrid modes. |
| `gutter-set-line-numbers-none` | Disable numbering. |
| `gutter-set-line-numbers-absolute` | Use absolute logical line numbers. |
| `gutter-set-line-numbers-relative` | Use relative logical line numbers. |
| `gutter-set-line-numbers-hybrid` | Use hybrid logical line numbers. |
| `gutter-set-numbering-logical` | Select logical numbering scope. |
| `gutter-set-numbering-visual` | Report that reserved visual numbering is unavailable. |
| `gutter-toggle-line-number-side` | Move numbers between the left and right Gutter. |
| `gutter-inspect-numbering` | Report the effective policy and whether it comes from the default or the active view. |
| `gutter-inspect-markers` | Open an anchored marker-detail popup at the active line, replacing it with hidden collision members on repetition. |
| `gutter-refresh-markers` | Refresh the active buffer's current semantic owner. |
| `gutter-invoke-primary-marker-action` | Invoke the primary marker's admitted action. |

These commands have no factory keybindings. Personal keymaps may bind their
ordinary command names without introducing a second execution path.

## Personal Configuration

`init.rkt` may export one `odra-gutter-configuration` hash. Omitted fields keep
their factory values.

| Key | Admitted values | Factory value |
| --- | --- | --- |
| `visible?` | Boolean | `#t` |
| `side` | `left`, `right` | `left` |
| `order` | signed 16-bit integer | `100` |
| `mode` | `none`, `absolute`, `relative`, `hybrid` | `absolute` |
| `scope` | `logical`; `visual` is rejected | `logical` |
| `current-line` | `absolute`, `zero`, `hidden` | `absolute` |
| `minimum-digits` | positive integer up to 20 | `4` |
| `maximum-digits` | positive integer up to 20 | `20` |
| `left-padding` | integer from 0 through 255 | `0` |
| `right-padding` | integer from 0 through 255 | `1` |
| `separator` | bounded display text | `│` |
| `separator-fallback` | bounded display text | `\|` |

Example:

```racket
#lang racket/base

(provide odra-gutter-configuration)

(define odra-gutter-configuration
  '#hash((mode . hybrid)
          (current-line . zero)
          (minimum-digits . 4)))
```

Configuration is normalized and copied across the runtime boundary. Invalid
values, unavailable visual scope, evaluation failure, or an oversized result
reject the complete candidate and preserve the last valid policy.

## Programmable Provider API

`init.rkt` may require `odra/gutters` and export `odra-gutter-provider`. The
module provides three constructors:

| Procedure | Result |
| --- | --- |
| `gutter-lane` | One immutable logical-line lane declaration. |
| `gutter-marker` | One immutable marker attached to a one-based logical line. |
| `gutter-provider` | One complete replaceable provider generation. |

Example:

```racket
#lang racket/base

(require odra/gutters)

(provide odra-gutter-provider)

(define review-lane
  (gutter-lane
   'review
   #:side 'right
   #:order 20
   #:width 'content-presence
   #:collision 'highest-priority
   #:style 'ordinary))

(define odra-gutter-provider
  (gutter-provider
   "Review Notes"
   'review-notes
   (list review-lane)
   (list
    (gutter-marker
     'pending-review
     'review
     5
     "◆"
     #:fallback "*"
     #:style 'diagnostic-information
     #:detail "Review this line"
     #:actions '(gutter-inspect-markers)))
   #:generation 1
   #:marker-generation 1))
```

Provider, lane, marker, and package identities are bounded machine names.
Marker and provider text is immutable copied UTF-8 without control characters.
The admitted sides are `left` and `right`. Width policy may be `fixed`,
`automatic`, `bounded-automatic`, or `content-presence`; alignment may be
`left`, `center`, or `right`; visibility may be `always`, `when-content`, or
`configured`; and collision may be `highest-priority`, `stack`, `aggregate`,
or `primary-with-details`.

Programmable style roles are `ordinary`, `background`, `separator`,
`diagnostic-error`, `diagnostic-warning`, `diagnostic-information`,
`diagnostic-hint`, `continuation`, `clipping`, `stale`, `aggregate`, and
`unavailable`. The active theme selects their concrete colors and terminal
attributes. Primary and fallback representations preserve marker meaning when
glyph or color capability is reduced.

An action is the symbol or string identity of an existing admitted command.
It is not a Racket callback. `gutter-invoke-primary-marker-action` resolves the
current marker's first action against the active command generation and then
uses ordinary command dispatch.

Export `#f` to remove the personal provider on the next successful reload:

```racket
(provide odra-gutter-provider)
(define odra-gutter-provider #f)
```

Run `M-x reload-personal-commands` after changing the provider. A complete
candidate replaces the active generation atomically. A malformed provider,
unknown action, stale generation, incomplete publication, or exceeded bound
rejects the candidate and preserves the last valid provider.

## Geometry and Presentation

The factory number width is derived from the complete logical line count,
bounded by the configured minimum and maximum. Padding and the separator are
included in Gutter geometry before the text width is finalized. When a pane is
too narrow, the lane hides before consuming the protected minimum text width.

Line numbers and the current line use separate semantic theme roles. A right
Gutter uses the same policy and composition model as a left Gutter. Capability
fallback changes the separator representation without changing ownership or
text geometry.

## Semantic Markers

Current language diagnostics retain their source revision and map error,
warning, information, and hint severities to semantic theme roles. The Gutter
copies their messages for bounded inspection; the language service remains the
canonical diagnostic owner. A marker action opens the ordinary diagnostic
surface rather than creating a Gutter-specific result view.

Horizontal-clipping markers are derived from one exact display snapshot and
cannot survive that view and projection generation. Left, right, and
both-sided clipping use distinct glyphs with ASCII fallbacks. The current
display policy projects one logical line per viewport row; the shared marker
contract retains the continuation role for a display policy that emits wrapped
continuation rows.

When diagnostic and viewport markers share a row, deterministic priority and
stable marker identity select the visible representation. Every collision
member remains available through repeated `gutter-inspect-markers` calls.
Semantic markers do not reserve cells when the active viewport contains none.

## Anchored Marker Details

`gutter-inspect-markers` projects one copied bounded marker into the shared
popup component through the selected `contextual-information` presentation
profile. The popup presents only the marker detail while retaining provider,
collision, stale-state, and action metadata internally. It is anchored to the
exact Gutter row and lane generation in the active view; it does not copy
semantic ownership out of the marker provider.

The profile supplies semantic background, border, title, content, action,
unavailable, and attention slots together with bounded spacing and degradation
policy. The active theme resolves those slots. Run `M-x describe-theme` to
inspect the selected profile, exact generation, mappings, geometry,
capabilities, fallback, and latest rejection.

The popup is informational. Document focus remains active. `C-g` dismisses it
before ordinary cancellation, cursor movement invalidates it, source closure
removes it, and repeated inspection atomically replaces it with the next
collision member. The action remains available through
`gutter-invoke-primary-marker-action` and ordinary command dispatch.

The normal detail path uses overlap without resizing panes or replacing the
document. Frontends without overlap support and geometries below the popup
minimum use the shared compact feedback region. Pointer hover, pointer hit
testing, autocomplete popups, and a public programmable popup API are outside
the Gutter contract.

## Failures and Lifecycle

Unsupported scope, stale view identity, closed view state, invalid policy,
insufficient geometry, resource overflow, and allocation failure are explicit
rejections. A failed command or configuration reload does not mutate the
active view. A valid view override remains local until another Gutter command
changes it or the view closes.

Marker publications are immutable and bounded. Stale, late, cancelled,
incomplete, duplicate, malformed, and excessive publications are rejected
without replacing the last valid generation. Display-attached markers require
an exact buffer revision, view identity, view generation, and projection
generation.

The initial programmable boundary admits one personal provider, one lane, 256
markers, and four actions per marker. Identities are limited to 64 UTF-8 bytes,
provider names to 128 bytes, package names to 64 bytes, command names to 128
bytes, representations to 64 bytes, marker detail to 512 bytes, and complete
provider text storage to 128 KiB. Native composition admits 80 visible rows,
64 KiB of copied Gutter view text, and 64 Ki work units for one dense
programmable publication.

Registration, replacement, removal, and shutdown occur outside presentation
turns. Rendering borrows one immutable native snapshot and never calls Racket
per marker or per row. The borrow drains before replacement or teardown can
release retained provider storage.

For a guided example, see [Add a Personal Gutter Provider](../../tutorials/programmable-gutter/index.md).
For direct operational steps, see [Configure and Reload a Programmable Gutter](../../how-to/configure-programmable-gutter/index.md).
For the shared chrome contract, see the
[Transient Presentation Profile Reference](../transient-presentation-profiles/index.md).
