<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Why Project Identity Is Local and One-Root

A Project represents durable intent attached to one Dir. Keeping its canonical
record inside that Dir makes identity travel with the content and prevents a
global catalog from becoming a competing authority.

One-root identity also separates two different concerns. Project trust,
configuration, tools, and language services belong to one exact root.
Multi-root composition belongs to a Workspace, which preserves order without
merging those capabilities.

The global Project catalog is therefore discovery only. It can enumerate a
bounded set of known identities and last-known roots, but resolution must
validate the matching local record and generation. Stale discovery remains a
diagnostic instead of silently recreating identity.

An ordinary Dir remains intentionally lightweight. Opening it creates no
metadata and grants no executable authority. Promotion is the explicit
transition that publishes local identity; trust remains a separate decision.

This boundary keeps session ownership narrow: the session retains root
projections and buffer scope, the Project owns its local identity and trust,
and the Workspace owns only an ordered set of Project references.
