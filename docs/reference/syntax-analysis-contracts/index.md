<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Syntax Analysis Contract Reference

The `language` package owns Odra's bounded native language catalog,
syntax-analysis identities, provider selection, exact-revision metadata,
resource policy, failure records, inspection shapes, and maintained syntax
providers. Language recognition is independent from parser availability; the
[Language Catalog Reference](../language-catalog/index.md) defines that
boundary.

## Responsibility Map

| Owner | Responsibility |
| --- | --- |
| `editor` | Own canonical text, immutable `Buffer_Snapshot` values, buffer identities, and revisions. |
| `document` | Own optional file-backed document identity and lifecycle. |
| `language` | Own the language catalog, language identities, provider generations, provider selection, Tree-sitter analysis, normalized syntax records, resource policy, failures, and cleanup. |
| `ui` | Maps semantic syntax roles into exact-revision frontend-independent styles and decorations. |
| `terminal` | Lowers validated UI styles to one explicit renderer color capability profile. |

The language boundary stores copied editor and document identities. It owns no
canonical text and grants providers no renderer, terminal, document, or buffer
mutation authority.

## Identities and Generations

`Language_ID` and `Language_Generation` identify one semantic document
language. A language identity names behavior such as `odin` or `racket`; it
does not name a filename suffix, parser library, or language server. Catalog
confirmation assigns stable identities independently from candidate order.

`Registry_ID` and `Registry_Generation` identify one native provider registry
and its exact selection state. `Provider_ID` remains stable for a registry
lifetime, while `Provider_Generation` changes when that provider's lifecycle
state changes. Zero values are invalid.

`Selection_Generation`, `Parser_Generation`, `Tree_Generation`,
`Query_Generation`, and `Syntax_Snapshot_Generation` prevent results from one
analysis owner or source revision from being accepted by another.

## Associations and Selection

`Language_Catalog_Association` copies the catalog generation, selected
language, selector kind and value, contribution source and scope, source
generation, and shadowed-match count. Exact filenames, case-sensitive suffixes,
and explicit identities resolve without consulting a parser registry. Source
precedence is Project, personal, package, then factory; within one source and
scope an exact filename outranks a suffix and the longest suffix wins.

`Provider_Selection` always describes one of four observable states:

1. the maintained factory provider is active;
2. one confirmed native replacement is active;
3. syntax analysis is explicitly disabled; or
4. the factory provider has been restored after an explicit restore or a
   contained replacement failure.

Only one provider handle can be active. Disabled selection uses a zero active
handle while retaining the factory handle as the restoration target.

## Provider Lifecycle

```text
factory: confirmed -> active
                    -> restored
                    -> failed -> disabled

native:  registered -> confirmed -> active replacement
                       |             |-> failed -> factory restored
                       |             \-> closed -> factory restored
                       \-> closed
```

`provider_registry_init` allocates one registry owner and creates the confirmed
factory provider. `provider_registry_register_native` copies an inactive
synthetic provider descriptor. `provider_registry_confirm_native` advances its
generation without selecting it. `provider_registry_replace` accepts only the
exact current selection and one exact confirmed native generation.

`provider_registry_disable` removes active analysis responsibility without
removing the factory descriptor. `provider_registry_restore` selects the
healthy factory provider. `provider_registry_fail_active` marks the active
generation failed, then restores the factory provider or disables selection
when the factory itself is unavailable. `provider_registry_close_native`
removes a native provider and restores factory selection when necessary.

Every mutation is registry-generation checked. A rejected mutation preserves
the complete prior selection. `provider_registry_close` releases the fixed
provider table exactly once and invalidates every outstanding handle.

## Provider Descriptors

`Provider_Descriptor` copies:

1. checked registry, language, provider, and provider-generation identity;
2. factory or native kind and lifecycle state;
3. bounded provider and parser names;
4. grammar ABI;
5. initial, incremental, visible-query, and syntax-role capabilities;
6. query generation; and
7. bounded provenance.

The factory contract currently accepts synthetic native replacements only.
The registry boundary is the seam a later package system can use after it has
separately established package loading, trust, and lifecycle ownership. This
slice does not load external code.

## Exact-Revision Records

`Parse_Snapshot` identifies the buffer, exact source revision, language,
provider generation, selection generation, parser, tree, query, status, and
resource usage for one owned parse result. It contains no Tree-sitter pointer.

`Syntax_Snapshot` identifies the same ownership chain plus one normalized span
count. `Syntax_Span` contains a non-empty half-open byte range, semantic role,
precedence, provider identity, and exact source revision. A span must remain
within the source byte count and use one of the stable roles:

- attribute, boolean, comment, constant, and constructor;
- function and built-in function;
- keyword, label, number, operator, punctuation, and string;
- type, variable, and variable parameter.

Providers emit no color values, palette indexes, or terminal sequences. The
maintained Tree-sitter query rejects unknown capture names before publication;
its exact mapping is documented in the
[Tree-sitter Odin Analysis Reference](../tree-sitter-odin-analysis/index.md).
UI projection, factory styles, color degradation, and presentation precedence
are documented in the
[Semantic Syntax Presentation Reference](../semantic-syntax-presentation/index.md).

## Selected Limits

| Resource | Limit |
| --- | ---: |
| Semantic languages | 32 |
| Selectors per language definition | 16 |
| Exact filenames per definition | 8 |
| Suffixes per definition | 8 |
| Selectors in one confirmed catalog | 512 |
| Factory and native providers | 64 |
| Live selections | 128 |
| Retained parse trees | 256 |
| Analyzed source per selection | 64 MiB |
| Query source per provider | 1 MiB |
| Captures per query pass | 131,072 |
| Normalized spans per syntax snapshot | 65,536 |
| Visible-query spans | 16,384 |
| Aggregate retained analysis storage | 512 MiB |
| Temporary storage per job | 128 MiB |
| Pending jobs | 128 |
| Retained stale jobs per selection | 1 |
| Pending refresh requests per selection | 1 |

The tree ceiling accounts for one confirmed and one candidate tree per live
selection, so incremental replacement never depends on releasing the confirmed
tree before the candidate can be validated. Initial parsing admits 8 MiB of
input work before a progress decision.
Incremental parsing admits 2 MiB, full refresh admits the complete 64 MiB
source ceiling, maintenance processes eight items per step, and cancellation
is checked at least every 64 KiB of parser input.

`make syntax-resource-study` reproduces ordinary, demanding, stress, and
rejection profiles with allocation peaks, selection and snapshot-validation
latency, cancellation checks, and zero-byte teardown verification.
`make tree-sitter-resource-study` exercises the integrated production parser
and its initial, incremental, visible-query, cancellation, accounting, and
teardown gates.

## Dependency Selection

The dependency study selects Tree-sitter `v0.26.12` at commit
`808e4b1fc06e269a107c4bd8bd936cc6fde18b00` and the Odin grammar `v1.3.0` at
commit `e8adc739b78409a99f8c31313f0bb54cc538cf73`. Runtime ABI 15 admits grammar
ABI 14 because its minimum compatible ABI is 13.

`make syntax-dependency-study` downloads both release tags into a temporary
directory, verifies exact commits, licenses, ABI values, and selected SHA-256
digests, then removes the inputs. The accepted sources are vendored and built
offline; no ambient Tree-sitter library participates in the production build.

## Failures and Preservation

`Failure` copies the operation, failure code, language and provider context,
selection generation, source revision, applicable limit, actual value, and a
bounded diagnostic. Expected failures distinguish invalid or stale identities,
provider lifecycle rejection, ABI or query incompatibility, cancellation,
timeouts, malformed ranges, resource limits, generation exhaustion,
allocation, and teardown.

A rejected registration, confirmation, replacement, disable, restore, or
close operation publishes no partial selection. A failed active replacement
leaves exactly one factory provider active when recovery succeeds. Registry
allocation failure leaves no owner, and registry teardown releases all owned
storage.

## Inspection

`Language_Selection_Inspection` is the copied pointer-free shape used by the
delivered `describe-language-state` command. It records optional document identity,
association, provider selection, exact confirmed revision, parser lifecycle,
analysis status, parse and syntax snapshot metadata, usage, pending work, and
the latest contained failure. The application presents these records through
the shared list UI without borrowing parser, buffer, UI, or renderer memory.

The factory catalog recognizes case-sensitive `.odin`, `.org`, `.jan`, and
`.rkt` suffixes plus the exact `info.rkt` filename. Odin and Jan associations
may open their maintained syntax workflows. Racket is recognized as a distinct
language and remains eligible for later language-service resolution without
opening a parser. One buffer-owned analysis lifecycle is shared by every view;
unsupported or unassociated buffers inspect as plain text. Provider disable,
replacement, failure recovery, and factory restoration reconcile this same
selection without retaining duplicate owners.
