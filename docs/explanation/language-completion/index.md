<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Why Language Completion Separates Provider, Session, and Acceptance

Language completion combines external semantic advice, rapid local
interaction, temporary presentation, and canonical text mutation. Those
responsibilities have different authority and lifetimes, so Odra does not make
the language-service protocol or popup the completion model.

The language-service boundary owns process lifecycle, protocol framing,
capability negotiation, document synchronization, request transport, and
response normalization. The completion controller receives copied candidates
and owns the active query, filtered projection, stable selection, and request
replacement. Shared UI profiles own theme-aware presentation and terminal
degradation. The transaction and history subsystems alone publish accepted
edits.

This split keeps several invariants explicit:

- a server response is advisory and cannot mutate editor text;
- candidates remain bound to the exact document, provider, session, binding,
  request, and revision that produced them;
- typing may filter a complete copied batch without another protocol request;
- the source text view retains focus while transient completion input captures
  only its contextual commands;
- primary and additional edits publish together or not at all; and
- provider failure or cancellation removes derived state without weakening
  ordinary editing.

Provider identity and language-service process identity are deliberately
distinct. The selected completion provider identifies the semantic role that
published the normalized batch. The server session and document binding prove
transport and synchronization authority. Conflating them would prevent a
future provider from using the same completion controller through another
implementation boundary.

The replaceable surface is therefore narrow: provider, declarative policy, and
presentation roles may receive admitted implementations. Session lifecycle,
normalization checks, bounds, stale rejection, and transactional acceptance
remain stable editor infrastructure. This allows later extension without
creating competing owners for selection, focus, text, or history.
