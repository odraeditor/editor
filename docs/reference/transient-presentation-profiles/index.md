<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Transient Presentation Profile Reference

Transient presentation profiles define theme-aware chrome for bounded UI that
appears near editor content. A profile describes presentation; it does not own
the content, command authority, source location, or frontend resources.

The delivered presentation role is `contextual-information`. The Gutter marker
detail is its current consumer.

## Profile Contract

One immutable profile generation contains:

- a stable profile identity, role, and nonzero generation;
- semantic chrome-slot mappings;
- independent row and column margin and padding;
- border, dimensions, clipping, and degradation policy;
- frontend capability requirements;
- a bounded fallback; and
- copied provenance and inspection metadata.

The contextual profile defines mappings for background, border, title,
content, annotation, separator, action, unavailable, attention, and selection.
Background, border, content, unavailable, and attention are required.

Profiles contain semantic role mappings rather than terminal colors or escape
sequences. The active theme resolves those roles, and the frontend lowers the
resolved profile according to its capabilities.

## Selection and Generations

The shared UI registry owns copied profile definitions and one selection for
each presentation role. Registration validates identities, role compatibility,
slot completeness, geometry, capability requirements, and fallback chains
before publishing one immutable generation.

Replacement, restoration, and selection name exact generations. A stale,
incomplete, cyclic, excessive, or incompatible candidate is rejected without
replacing the last confirmed selection. Factory restoration and disabling a
role are distinct operations.

## Contextual Factory Profile

The factory contextual profile uses one horizontal outer-margin cell, no
mandatory inner padding, and a single border when supported. Its dimensions,
placement attempts, clipping, and compact fallback are bounded. A frontend
without the required border or overlap capability uses the declared portable
or non-floating fallback without changing semantic content or source focus.

Terminal rows and columns are independent logical units. The renderer does not
attempt pixel-level symmetry.

## Theme and Frontend Behavior

Every maintained theme resolves the required contextual slots. Theme changes
alter resolved styles without changing profile identity. Reduced-color and
monochrome lowering preserve distinctions without relying on color alone.

The terminal renderer consumes the selected profile, resolved theme values,
popup geometry, and root generation. It does not select profiles, interpret
Gutter semantics, call Racket, or retain marker state. Unchanged generations
do not require a feature-driven redraw.

## Inspection

Run `M-x describe-theme` to inspect the selected contextual profile. The copied
inspection includes:

- role, selected profile, factory identity, and generations;
- provenance and registry usage;
- spacing, dimensions, border, clipping, and fallback;
- frontend capabilities and degradation state;
- every slot mapping and required-slot status; and
- the latest bounded rejection.

Inspection excludes terminal handles, pointers, private paths, environment
values, and feature-owned unbounded content.

## Current Extension Boundary

The current Racket boundary does not expose arbitrary profile construction or
render-time callbacks. Odin owns admission, generations, selection, fallback,
theme resolution, UI publication, resource enforcement, and frontend lowering.
Future extension may select admitted profiles only through an explicit public
contract.

## Limits and Failure Behavior

One registry admits at most 16 profiles, 16 mappings per profile, 96 bytes for
each bounded identity or provenance value, fallback depth 4, and 8 logical
cells per margin or padding axis. Invalid admission, unavailable theme roles,
stale generations, allocation failure, and renderer failure preserve the last
confirmed profile and root generation. Teardown releases registry,
presentation, snapshot, and temporary lowering storage exactly once.

For the first consumer, see the [Gutter Reference](../gutter/index.md). For the
design rationale, see [Why Transient Presentation Uses Profiles](../../explanation/transient-presentation-profiles/index.md).
