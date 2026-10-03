#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/cmdline
         racket/list
         racket/path
         "../src/configuration/root.rkt"
         "../src/migration/executor.rkt"
         "../src/migration/legacy-inventory.rkt"
         "../src/migration/planner.rkt")

(provide run-legacy-migration)

(define (run-legacy-migration legacy-root configuration-root apply?
                              #:out [out (current-output-port)]
                              #:err [err (current-error-port)])
  (with-handlers ([exn:fail?
                   (lambda (failure)
                     (fprintf err "Legacy migration failed: ~a\n"
                              (exn-message failure))
                     1)])
    (define inventory
      (legacy-migration-inventory-load (path->complete-path legacy-root)))
    (define plan
      (legacy-migration-plan-compose
       (path->complete-path configuration-root)
       inventory))
    (fprintf out
             "Legacy migration plan: sources=~a projects=~a workspaces=~a states=~a rejected=~a\n"
             (length (odra-legacy-migration-plan-sources plan))
             (length (odra-legacy-migration-plan-projects plan))
             (length (odra-legacy-migration-plan-workspaces plan))
             (length (odra-legacy-migration-plan-states plan))
             (length (odra-legacy-migration-plan-rejections plan)))
    (write-plan-rejections plan out)
    (cond
      [(not apply?)
       (displayln "Preview only; pass --apply to publish this plan." out)
       (if (null? (odra-legacy-migration-plan-rejections plan)) 0 2)]
      [else
       (define result
         (legacy-migration-execute
          (path->complete-path configuration-root)
          plan))
       (fprintf out
                "Legacy migration result: published=~a already-published=~a rejected=~a failures=~a\n"
                (length (odra-legacy-migration-result-published result))
                (length (odra-legacy-migration-result-already-published result))
                (length (odra-legacy-migration-result-rejected result))
                (length (odra-legacy-migration-result-failures result)))
       (write-execution-failures result err)
       (cond
         [(pair? (odra-legacy-migration-result-failures result)) 1]
         [(pair? (odra-legacy-migration-result-rejected result)) 2]
         [else 0])])))

(define (write-plan-rejections plan out)
  (for ([rejection
         (in-list (odra-legacy-migration-plan-rejections plan))])
    (fprintf out "Rejected ~a [~a]: ~a\n"
             (odra-legacy-migration-rejection-source-path rejection)
             (odra-legacy-migration-rejection-code rejection)
             (odra-legacy-migration-rejection-message rejection))))

(define (write-execution-failures result err)
  (for ([failure
         (in-list (odra-legacy-migration-result-failures result))])
    (fprintf err "Failed ~a [~a, ~a]: ~a\n"
             (odra-legacy-migration-failure-source-id failure)
             (odra-legacy-migration-failure-code failure)
             (odra-legacy-migration-failure-publication failure)
             (odra-legacy-migration-failure-message failure))))

(module+ main
  (define legacy-root #f)
  (define configuration-root #f)
  (define apply? #f)
  (command-line
   #:program "migrate-project-workspaces.rkt"
   #:once-each
   [("--legacy-root") root
    "Read legacy Project state from root"
    (set! legacy-root root)]
   [("--configuration-root") root
    "Publish target state under root"
    (set! configuration-root root)]
   [("--apply")
    "Publish the inspected migration plan"
    (set! apply? #t)])
  (define home (getenv "HOME"))
  (unless (or legacy-root home)
    (raise-user-error 'migrate-project-workspaces.rkt
                      "HOME or --legacy-root is required"))
  (exit
   (run-legacy-migration
    (or legacy-root (build-path home ".odra"))
    (or configuration-root (odra-configuration-root))
    apply?)))
