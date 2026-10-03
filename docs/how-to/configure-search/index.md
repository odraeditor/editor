<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Configure Programmable Search Policy

Odra exposes live search policy through `src/command/search.rkt`. Code already
running in the embedded Racket runtime can replace the default transformation
without restarting the runtime. Odin validates the resulting complete policy
before any search or replacement command executes.

## Replace the programmable default

Require the search facade and install a transformation:

```racket
#lang racket/base

(require "src/command/search.rkt")

(reload-search-policy!
 (lambda (current)
   (search-policy-replace
    current
    (hasheq 'case-mode 'sensitive
            'boundary-mode 'word
            'whitespace-mode 'flexible
            'wrap? #f
            'retained-occurrences 512))))
```

The transformation receives the complete current native policy and must return
one `search-policy` value. It applies to later programmable invocations that do
not carry an explicit policy. Reloading replaces the function immediately for
subsequent turns in the same embedded runtime.

The current terminal executable does not yet load a user configuration file.
This API is therefore for built-in modules, tests, and future extension-loading
code executing inside Odra's process; running the example in a separate Racket
process cannot configure a running editor.

## Inspect and replace fields

Within a `call-with-search` dynamic extent, obtain the complete native policy:

```racket
(define current (inspect-search-policy context))
(define fields (search-policy-inspect current))
(hash-ref fields 'scan-window-bytes)
```

`search-policy-inspect` returns an immutable hash containing these stable field
names:

| Concern | Fields |
| --- | --- |
| Matching | `case-mode`, `boundary-mode`, `whitespace-mode`, `wrap?` |
| Search work | `pattern-bytes`, `scan-window-bytes`, `cancellation-bytes`, `retained-occurrences`, `search-temporary-bytes`, `capture-groups`, `match-span-bytes` |
| Expansion | `case-preservation`, `template-bytes`, `expanded-bytes`, `replacement-temporary-bytes` |
| Atomic replacement | `replace-all-matches`, `replace-all-text-bytes`, `replace-all-temporary-bytes`, `replace-all-analysis-bytes` |

`case-mode` accepts `smart`, `sensitive`, or `insensitive`.
`boundary-mode` accepts `unrestricted`, `word`, or `symbol`.
`whitespace-mode` accepts `exact` or `flexible`.
`case-preservation` accepts `smart` or `none`. Resource values are exact
nonnegative integers, but they must also satisfy the validated native ranges
and relationships in the
[Search and Replacement Reference](../../reference/search-and-replacement/index.md).

Unknown fields and invalid symbolic values fail in Racket. Out-of-range or
internally inconsistent numeric policies are rejected by Odin before command
effects.

## Override one command

Pass a policy directly when composing a command to avoid changing the live
default:

```racket
(define exact-policy
  (search-policy-replace
   current
   (hasheq 'case-mode 'sensitive 'wrap? #f)))

(define request
  (make-search-command
   'replace-string
   (make-search-pattern 'literal #"Odra")
   #:replacement (make-replacement-template #"ODRA")
   #:query-id 41
   #:search-generation 41
   #:scope (make-search-range buffer-id revision start end)
   #:policy exact-policy))

(invoke-search-command! context request)
```

The command receives copied pattern, replacement, scope, and policy values.
The native side checks the exact editor, view, buffer, revision, interaction,
command-registry, and policy generations before using them.

## Restore factory behavior

Reset the live transformation to identity:

```racket
(reset-search-policy!)
```

Later programmable commands again use the complete native factory policy.

## Validate a change

Run the focused facade and boundary checks:

```sh
raco make src/command/search-bridge.rkt src/command/search.rkt
raco test src/command/search-bridge.rkt src/command/search.rkt
make native-command-test
make search-command-benchmark
```

Then run the repository gate:

```sh
make verify
```
