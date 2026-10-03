#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/file
         racket/list
         racket/runtime-path
         racket/string
         "../src/package/authority-contract.rkt")

(provide
 (contract-out
  [check-package-authority-parity (-> path-string? exact-nonnegative-integer?)]))

(define-runtime-path repository-root "..")

(define racket-consumers
  '("src/package/manifest-contracts.rkt"
    "src/package/state-records.rkt"
    "src/package/runtime.rkt"
    "src/agent/authority.rkt"
    "src/language_bundle/catalog-contracts.rkt"
    "src/language_bundle/catalog-resolution.rkt"
    "src/command/language-bundles.rkt"))

(define (fail message . arguments)
  (raise-user-error 'package-authority-parity (apply format message arguments)))

(define (source-lines root relative-path)
  (file->lines (build-path root relative-path)))

(define (section-lines lines marker)
  (define tail
    (member marker lines string=?))
  (unless tail
    (fail "missing schema section: ~a" marker))
  (for/list ([line (in-list (cdr tail))]
             #:break (string=? (string-trim line) "}"))
    line))

(define (odin-authority-name authority)
  (string-join
   (for/list ([part (in-list (string-split (symbol->string authority) "-"))])
     (string-titlecase part))
   "_"))

(define (enum-authorities root)
  (define lines
    (section-lines
     (source-lines root "src/language_bundle/contracts.odin")
     "Bundle_Authority :: enum u8 {"))
  (for/list ([line (in-list lines)]
             #:do [(define match
                     (regexp-match #px"^\\s*([A-Za-z][A-Za-z0-9_]*)\\s*," line))]
             #:when match)
    (cadr match)))

(define (bridge-authorities root)
  (define lines
    (section-lines
     (source-lines root "src/language_bundle/bridge.odin")
     "decode_authority :: proc(value: string) -> (Bundle_Authority, bool) {"))
  (for/list ([line (in-list lines)]
             #:do [(define match
                     (regexp-match
                      #px"^\\s*case \\\"([^\\\"]+)\\\": return \\.([A-Za-z][A-Za-z0-9_]*), true"
                      line))]
             #:when match)
    (cons (cadr match) (caddr match))))

(define (check-racket-consumers root)
  (for ([relative-path (in-list racket-consumers)])
    (define source (file->string (build-path root relative-path)))
    (unless (string-contains? source "authority-contract.rkt")
      (fail "Racket consumer does not import the canonical contract: ~a"
            relative-path))
    (unless (regexp-match? #px"package-authority(?:[?]|-set[?])" source)
      (fail "Racket consumer does not delegate authority validation: ~a"
            relative-path))))

;; check-package-authority-parity verifies every consumer and native mapping.
(define (check-package-authority-parity root)
  (check-racket-consumers root)
  (define expected-names
    (map odin-authority-name package-authority-symbols))
  (define enum-names (enum-authorities root))
  (unless (equal? enum-names (cons "Invalid" expected-names))
    (fail "Odin authority enum mismatch: expected ~s, found ~s"
          (cons "Invalid" expected-names) enum-names))
  (define expected-bridge
    (for/list ([authority (in-list package-authority-symbols)]
               [name (in-list expected-names)])
      (cons (package-authority->string authority) name)))
  (define actual-bridge (bridge-authorities root))
  (unless (equal? actual-bridge expected-bridge)
    (fail "Odin authority decoder mismatch: expected ~s, found ~s"
          expected-bridge actual-bridge))
  (+ (length racket-consumers) 2))

(module+ test
  (require rackunit)

  (check-equal? (check-package-authority-parity repository-root) 9))

(module+ main
  (define checks (check-package-authority-parity repository-root))
  (printf "package-authority-parity: pass authorities=~a consumers=~a checks=~a\n"
          (length package-authority-symbols) (length racket-consumers) checks))
