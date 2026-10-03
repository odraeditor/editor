<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Admit Project Configuration Safely

This developer tutorial demonstrates the one-root trust boundary with isolated
storage.

## 1. Create an isolated Project root

From the repository root, start Racket and evaluate:

```racket
(require racket/file
         "src/project/lifecycle-persistence.rkt"
         "src/project/lifecycle-records.rkt")

(define demo-root (make-temporary-file "odra-trust-demo-~a" 'directory))
(file-or-directory-permissions demo-root #o700)

(define untrusted
  (local-project-record
   #:format-version current-local-project-format-version
   #:id "trust-demo"
   #:generation 1
   #:name "Trust Demo"
   #:root (path->string demo-root)
   #:trust 'untrusted))

(local-project-record-persist demo-root untrusted)
```

The local record establishes Project identity but does not admit executable
Project behavior.

## 2. Publish a trusted generation

```racket
(define trusted
  (local-project-record
   #:format-version current-local-project-format-version
   #:id "trust-demo"
   #:generation 2
   #:name "Trust Demo"
   #:root (path->string demo-root)
   #:trust 'trusted))

(local-project-record-persist demo-root trusted)
```

The publication succeeds only as the exact next generation. Reusing generation
`1`, skipping a generation, changing the root, or presenting unsafe metadata
is rejected without replacing the confirmed record.

## 3. Inspect and clean up

```racket
(local-project-record-module-load
 (local-project-record-path demo-root))

(delete-directory/files demo-root)
```

When the same Project is opened in Odra, `describe-project` reports its local
identity and trust. Project configuration and language services still pass
through their own capability and resource checks; trust never bypasses those
contracts.
