<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Why Embedded Languages Require Explicit Injections

A document may contain regions whose syntax belongs to another language. Odra
models those regions as declared injections from a parent syntax provider to a
specific child language rather than guessing from text or starting one parser
for the whole mixed document.

The parent query identifies bounded byte ranges and names the child language.
The syntax workflow resolves that language through the same effective bundle
registries used for top-level files, parses the copied range with the child
provider, and composes non-overlapping semantic spans back into the parent
revision. Parent ownership, child ownership, resource accounting, and failures
remain attributable separately.

The basic pack uses this for HTML: admitted `<script>` content selects the
JavaScript or TypeScript syntax provider, while admitted `<style>` content
selects CSS. The outer HTML grammar, highlight query, and injection query stay
active even when the HTML language server is absent. A missing or failed child
provider affects only its region and leaves the rest of the document editable.

Explicit declarations avoid surprising authority and ambiguity. Tagged
templates, framework dialects, custom Racket readers, and other embedded forms
are not inferred from incidental text. A bundle must declare the injection,
ship or depend on its query, name the child language, and accept the same ABI,
trust, overlap, generation, cancellation, and resource checks as any other
syntax provider.
