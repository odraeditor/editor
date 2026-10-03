<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Language Intelligence

This part teaches syntax presentation, structural editing, diagnostics,
completion, and continued editing when a language provider is unavailable.

Follow these chapters in order:

1. [Use Syntax and Structure](syntax-and-structure.md) observes incremental
   syntax presentation, navigates and selects structural nodes, performs one
   reversible structural indentation, and verifies plain-text fallback.
2. [Work with Jan Documents](work-with-jan-documents.md) opens identical
   `.org` and `.jan` language paths, inspects and lints current syntax, checks
   source-preserving ordinary editing, and prepares the complete structured
   document path.
3. [Use Language Services and Diagnostics](language-services-and-diagnostics.md)
   establishes Project trust, inspects service health, induces and invalidates
   one diagnostic, navigates current results, and exercises contained failure
   and limited restart behavior.
4. [Use Factory Go Language Support](configure-language-support.md) uses a
   third maintained language and external server, then verifies local syntax,
   diagnostics, completion, unavailable state, and recovery.
5. [Use the Basic Language Pack](use-the-basic-language-pack.md) applies the
   common syntax, completion, navigation, diagnostics, formatting, inspection,
   and service-independent editing workflow across the nine shipped languages.
6. [Use Language Completion](language-completion.md) requests candidates by
   command and trigger, filters and inspects them, accepts or cancels one exact
   generation, reverses atomic edits, and configures the admitted policy.
7. [Understand Provider Fallback](provider-fallback.md) distinguishes the
   editor baseline from optional syntax, structure, service, completion, and
   presentation capabilities, then verifies graceful degradation.

Jan, Odin, Racket, Go, Rust, JavaScript, TypeScript, HTML, and CSS ship as the
basic Factory language pack. Every entry uses the same bundle, syntax,
inspection, command, interaction, and recovery contracts; Jan additionally
retains its specialized native document capabilities.

---

[Previous: Apply Filesystem Changes](../files-projects-workspaces/maksym/apply-filesystem-changes.md) ·
[User Guide](../index.md) ·
[Next: Use Syntax and Structure](syntax-and-structure.md)
