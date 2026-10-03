<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Language Bundle Author Kit Ownership

This map identifies the repository owner for each author-facing contract.

| Concern | Owner |
| --- | --- |
| Racket constructors and immutable bundle values | `src/command/language-bundles.rkt` |
| Canonical manifest encoding and bounded module loading | `src/hosting/language-bundle-bridge.rkt` |
| Catalog records, signatures, and resolution | `src/language_bundle/catalog-*.rkt` |
| Archive verification and immutable content | `src/language_bundle/acquisition.rkt` |
| Installed state, activation, rollback, and removal | `src/language_bundle/state-*.rkt` and `src/language_bundle/lifecycle.rkt` |
| Dynamic grammar validation and loading | `src/language/syntax_provider_*.odin` |
| Generic syntax workflows and injections | `src/syntax_workflow/` |
| Language-service processes and protocol handling | `src/language_service/` |
| Author validation and deterministic archive creation | `scripts/language-bundle-author.rkt` |
| Public manifest schema and starting template | `assets/language-bundles/author-kit/` |
| External conformance fixture | `tests/language_bundle_fixture/` |

The application composition package may consume these contracts but does not
own bundle validation, syntax loading, service transport, or lifecycle state.
