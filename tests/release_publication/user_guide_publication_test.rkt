#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require json
         rackunit
         racket/file
         racket/list
         "../../scripts/release/user-guide-publication.rkt")

(define snapshot-commit "1111111111111111111111111111111111111111")
(define snapshot-tree "2222222222222222222222222222222222222222")
(define canonical-commit "3333333333333333333333333333333333333333")
(define digest "4444444444444444444444444444444444444444444444444444444444444444")

(define (with-fixture action)
  (define root (make-temporary-file "user-guide-publication-~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     (define guide (build-path root "guide"))
     (define snapshot (build-path root "snapshot"))
     (define output (build-path root "candidate"))
     (make-directory* (build-path guide "scripts"))
     (make-directory snapshot)
     (call-with-output-file
      (build-path guide "scripts" "prepare-release-guide.sh")
      (lambda (port) (display "#!/usr/bin/env bash\n" port)))
     (action root guide snapshot output))
   (lambda () (delete-directory/files root))))

(define (request guide snapshot output)
  (guide-candidate-request
   guide snapshot "odra/editor" snapshot-commit snapshot-tree canonical-commit
   "0.2.0" "0.1.0" 'stable output "/usr/bin/spore"))

(define (write-candidate output [tree snapshot-tree])
  (make-directory output)
  (call-with-output-file
   (build-path output "candidate-manifest.json")
   (lambda (port)
     (write-json
      (hasheq
       'schema_version 1
       'model "odra-user-guide-candidate"
       'candidate_id digest
       'release (hasheq 'version "0.2.0" 'status "candidate")
       'snapshot (hasheq 'repository "odra/editor"
                         'commit snapshot-commit
                         'tree tree)
       'canonical_source (hasheq 'commit canonical-commit)
       'source_manifest_sha256 digest
       'projection_manifest_sha256 digest
       'site (hasheq 'tree_sha256 digest))
      port))))

(test-case "Plans candidate preparation from an exact snapshot commit"
  (with-fixture
   (lambda (_ guide snapshot output)
     (define plan (prepare-guide-candidate-plan (request guide snapshot output)))
     (check-equal?
      (take-right (guide-candidate-plan-command plan) 4)
      (list "--output" (path->string output)
            "--spore-executable" "/usr/bin/spore"))
     (check-not-false
      (member snapshot-commit (guide-candidate-plan-command plan))))))

(test-case "Rejects mutable or malformed candidate inputs"
  (with-fixture
   (lambda (_ guide snapshot output)
     (define invalid
       (struct-copy guide-candidate-request
                    (request guide snapshot output)
                    [snapshot-commit "main"]))
     (check-exn exn:fail:contract?
                (lambda () (prepare-guide-candidate-plan invalid))))))

(test-case "Accepts evidence bound to the requested source and snapshot"
  (with-fixture
   (lambda (_ guide snapshot output)
     (define plan (prepare-guide-candidate-plan (request guide snapshot output)))
     (write-candidate output)
     (define evidence (read-guide-candidate-evidence plan))
     (check-equal? (guide-candidate-evidence-candidate-id evidence) digest)
     (check-equal?
      (take-right (guide-publish-command plan evidence) 4)
      (list "--candidate-id" digest
            "--destination" (path->string (path->complete-path guide)))))))

(test-case "Rejects evidence from a different snapshot tree"
  (with-fixture
   (lambda (_ guide snapshot output)
     (define plan (prepare-guide-candidate-plan (request guide snapshot output)))
     (write-candidate output "5555555555555555555555555555555555555555")
     (check-exn exn:fail?
                (lambda () (read-guide-candidate-evidence plan))))))
