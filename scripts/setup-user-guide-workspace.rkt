#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/cmdline
         racket/list
         racket/path
         "../src/workspace/management.rkt"
         "../src/workspace/persistence.rkt"
         "../src/workspace/records.rkt")

(provide setup-user-guide-workspace)

(define (canonical-root-text root)
  (path->string (simplify-path (path->complete-path root) #f)))

(define (workspace-root-texts record)
  (map odra-workspace-project-reference-root
       (odra-workspace-record-projects record)))

(define (setup-user-guide-workspace configuration-root workspace-root name
                                    #:out [out (current-output-port)]
                                    #:err [err (current-error-port)])
  (with-handlers ([exn:fail?
                   (lambda (failure)
                     (fprintf err "User Guide Workspace setup failed: ~a\n"
                              (exn-message failure))
                     1)])
    (define roots
      (for/list ([child (in-list '("forecast-engine" "report-console"))])
        (canonical-root-text (build-path workspace-root child))))
    (define catalog (workspace-list configuration-root))
    (define existing
      (findf (lambda (record)
               (string=? name (odra-workspace-record-name record)))
             (odra-record-catalog-records catalog)))
    (cond
      [existing
       (if (equal? roots (workspace-root-texts existing))
           (begin
             (fprintf out "Workspace already available: ~a\n" name)
             0)
           (begin
             (fprintf err
                      "User Guide Workspace setup failed: ~a uses a different Project order\n"
                      name)
             1))]
      [else
       (define proposal
         (workspace-create-compose configuration-root name roots))
       (cond
         [(odra-workspace-failure? proposal)
          (fprintf err "User Guide Workspace setup failed: ~a\n"
                   (odra-workspace-failure-message proposal))
          1]
         [else
          (define publication (workspace-publish configuration-root proposal))
          (if (odra-workspace-publication? publication)
              (begin
                (fprintf out "Workspace available: ~a\n" name)
                0)
              (begin
                (fprintf err "User Guide Workspace setup failed: ~a\n"
                         (odra-workspace-failure-message publication))
                1))])])))

(module+ main
  (define configuration-root #f)
  (define workspace-root #f)
  (define workspace-name "User Guide")
  (command-line
   #:program "setup-user-guide-workspace.rkt"
   #:once-each
   [("--configuration-root") root
    "Use the exact Odra configuration root"
    (set! configuration-root root)]
   [("--workspace-root") root
    "Use the disposable User Guide workspace root"
    (set! workspace-root root)]
   [("--name") name
    "Use this Workspace display name"
    (set! workspace-name name)])
  (unless configuration-root
    (raise-user-error 'setup-user-guide-workspace.rkt
                      "--configuration-root is required"))
  (unless workspace-root
    (raise-user-error 'setup-user-guide-workspace.rkt
                      "--workspace-root is required"))
  (exit
   (setup-user-guide-workspace
    configuration-root workspace-root workspace-name)))

(module+ test
  (require racket/file
           rackunit
           "../src/project/persistence.rkt"
           "../src/project/records.rkt")

  (define root (make-temporary-file "odra-user-guide-workspace-~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     (define configuration-root (build-path root "configuration" "odra"))
     (define workspace-root (build-path root "workspace"))
     (make-directory* workspace-root)
     (for ([entry (in-list '(("forecast-engine" "forecast" "Forecast Engine")
                             ("report-console" "report" "Report Console")))])
       (define project-root (build-path workspace-root (car entry)))
       (make-directory project-root)
       (check-true
        (odra-record-publication?
         (local-project-record-persist
          project-root
          (local-project-record
           #:format-version current-local-project-format-version
           #:id (cadr entry)
           #:generation 1
           #:name (caddr entry)
           #:root (canonical-root-text project-root)
           #:trust 'untrusted)))))
     (check-equal?
      (setup-user-guide-workspace
       configuration-root workspace-root "User Guide"
       #:out (open-output-bytes)
       #:err (open-output-bytes))
      0)
     (check-equal?
      (setup-user-guide-workspace
       configuration-root workspace-root "User Guide"
       #:out (open-output-bytes)
       #:err (open-output-bytes))
      0)
     (define records
       (odra-record-catalog-records (workspace-list configuration-root)))
     (check-equal? (length records) 1)
     (check-equal? (workspace-root-texts (car records))
                   (map canonical-root-text
                        (list (build-path workspace-root "forecast-engine")
                              (build-path workspace-root "report-console")))))
   (lambda ()
     (when (directory-exists? root)
       (delete-directory/files root)))))
