<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Why Curation and Trust Stay Separate

Package ecosystems often compress several independent claims into one badge:
the source exists, somebody reviewed it, a build completed, a signature is
valid, a catalog lists it, and the user may run it. Odra keeps those claims
separate so each decision remains attributable and reversible.

A signature proves that a holder of an authorized key signed exact bytes. It
does not prove that the software is benign. An assessment records bounded
evidence and limitations. It does not admit a release. A human curation
decision applies one policy generation to one exact release. Installation
possesses verified content but grants no runtime authority. Activation is the
local decision to expose declared capabilities.

The official catalog is an opinionated default, not an exclusive namespace.
Only its compiled catalog and root identities receive the official
designation. Independent curators use the same public profile, policy,
submission, assessment, decision, assertion, advisory, snapshot, and mirror
contracts without asking the Odra maintainer for permission.

This asymmetry is deliberate: official curation authority is restricted, but
the curation protocol is open. Users explicitly choose which additional trust
roots to enroll, while local verification, advisory response, capability
consent, and activation remain under local control.

AI and automated tools fit as assessors. They can inspect changes, reproduce
builds, detect suspicious behavior, and produce attributable findings. They
cannot silently become curators, change policy, or sign a publication. The
initial official catalog therefore has one human curator even when a large
automated assessment system assists that person.

Manual acquisition completes the model. A user can inspect and install an
exact directory, artifact, or Git revision without pretending it was curated.
If an exact catalog assertion matches, Odra reports that relationship while
retaining manual provenance. The source path and the trust claim remain facts
with different owners.
