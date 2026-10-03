<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Why Transient Presentation Uses Profiles

Transient UI shares mechanics without sharing meaning. A marker detail,
completion list, notification, and progress report may all need theme-aware
chrome, bounded geometry, capability fallback, and deterministic teardown, but
they do not have the same interaction policy. Treating them as one generic
popup would hide those differences; implementing each directly in a frontend
would duplicate policy and couple semantic features to terminal mechanics.

## Roles describe interaction families

A presentation role identifies a stable behavioral family. The delivered
`contextual-information` role describes bounded source-related detail that
preserves document focus. It does not imply that future interactive candidates
or feedback should inherit the same dismissal, input, or update policy.

A selected profile supplies the chrome and geometry for one role. This keeps
semantic content with its feature owner while making theme and frontend
lowering reusable.

```text
semantic owner
  -> feature projection
  -> presentation role and selected profile
  -> shared popup or compact fallback
  -> theme resolution
  -> frontend lowering
```

## Semantic slots keep themes authoritative

Profiles map named chrome slots such as title, content, attention, and border
to semantic theme roles. They do not contain colors or terminal escapes. A
theme change can therefore restyle the same profile identity coherently, and a
frontend can degrade the same resolved meaning without knowing which feature
produced it.

The alternative would make the Gutter choose concrete popup roles or make the
terminal infer meaning from marker content. Both directions leak ownership.

## Complete generations protect visible state

Profiles are copied and published as immutable generations. Admission checks
required slots, bounds, capabilities, and fallback graphs before selection.
Replacement is atomic, so a failed personal or package candidate cannot leave
half of the chrome on a new generation and half on the old one.

The profile generation is coordinated with the theme, popup, and UI root
generations. Stale work rejects rather than being reinterpreted against newer
content or a newer source location.

## Fallback is declared, not improvised

Capability and geometry failures follow the selected profile's declared
degradation path. The terminal may substitute a portable border or use compact
non-floating feedback, but it cannot invent a feature-specific alternative.
The semantic owner retains the same detail and action authority throughout the
transition.

## The first consumer is deliberately narrow

The Gutter marker detail proves the complete path with a real existing
consumer: theme selection, popup geometry, source-focus preservation,
replacement, dismissal, compact fallback, inspection, and teardown. The
migration removes fixed-role selection from generic popup lowering without
turning the profile registry into a speculative plugin framework.

Interactive candidates and feedback destinations remain separate delivery
contracts. They may share the registry and renderer machinery, but each must
define its own role, lifecycle, input, refresh, and fallback semantics before
activation.

For exact identities, mappings, limits, and inspection behavior, see the
[Transient Presentation Profile Reference](../../reference/transient-presentation-profiles/index.md).
