<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Why Language Support Uses Bundles

A language feature is useful only when recognition, syntax, intelligence,
formatting, commands, bindings, artifacts, trust, and recovery describe one
coherent capability. Odra groups those contributions into an immutable
language support bundle instead of scattering them across unrelated startup
hooks.

The bundle is declarative. Racket constructs and validates copied values;
Odin owns runtime registries, buffers, parsers, processes, transactions, and
publication. Loading an entrypoint therefore discovers data without granting
the extension direct control over editor state.

Factory and installed bundles use the same semantic records. Factory bundles
ship with Odra and are immediately discoverable. Installed bundles pass
catalog resolution, signature and digest checks, target and API compatibility,
authority review, staging, and atomic activation. A third-party language can
therefore become available after installation and restart without recompiling
Odra, while built-in languages do not need a separate configuration path.

Lifecycle states separate possession from authority. Installation can retain
a disabled, inspectable candidate. Enablement reviews authority and prepares a
complete next generation. Update retains a confirmed predecessor. Rollback,
disablement, and removal remain factory-owned even if extension code cannot
load. A failed candidate never partially mutates live registries; the last
confirmed generation remains usable.

This boundary also makes support explainable. One inspection can attribute
each language, provider, service, formatter, command, and keymap to a bundle
identity, version, origin, and generation. The same attribution supports
conflict resolution, health diagnostics, recovery, and future distribution
without making Project data or personal configuration disposable.
