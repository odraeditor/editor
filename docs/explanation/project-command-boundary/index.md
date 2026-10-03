<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Why Project Commands Use Bounded Native Candidates

Project navigation needs filesystem traversal, canonical path identity, live
buffer classification, and exact generation checks. Those concerns belong to
the Odin-owned Project and editor-session state. The terminal does not build a
second Project model, and the Racket command layer does not retain canonical
paths or registry pointers.

## Enumeration is incremental before publication

One file-enumeration turn examines at most the configured entry budget. The
enumerator retains private progress across turns and publishes candidates only
after traversal is complete. This keeps partial, unsorted, or duplicate results
out of the candidate session and shared UI root.

Each candidate records the exact Project handle and enumeration generation.
Changing the active Project invalidates the search instead of applying a stale
selection to a different context. Cancellation and failure release the private
walker, candidate paths, and copied batches explicitly.

## Overlap is a relationship, not a duplicate file

Several Project directories may contain the same canonical file. Enumeration
retains one candidate and records how many memberships contain it. Project-wide
save and close operations similarly classify one live entry once, so overlap
does not duplicate an effect.

## Project sources retain specific ownership

Project adapters provide exact file and Project-buffer discovery, while the
Project inventory root provides directory inspection. Candidate adapters reuse
the source-neutral session and shared list-and-input root without transferring
filesystem enumeration, buffer classification, or action ownership into the
UI. That separation avoids making Project traversal policy the accidental
design for every selector.

## Composition preserves ordinary lifecycle rules

Project-wide save delegates each admitted file-backed buffer to the ordinary
document save path. Project-wide close first collects every dirty decision and
then closes one validated set. Refresh advances the existing observation
registry. Command navigation, Project selectors, and binding inspection reuse
shared UI roots.

The Project layer therefore composes existing buffer, document, observation,
and keymap contracts. It does not bypass dirty protection or acquire ownership
of their state.

## The prefix is policy, not command identity

Commands have stable names independently of `Control-C p`. The factory Project
map supplies convenient bindings and explicit reservations, while `Meta-X`
keeps every active command discoverable. Inspection exposes both effective
bindings and masked future policy, so unsupported sequences do not pretend to
work.
