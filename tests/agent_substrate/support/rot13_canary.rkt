#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require (only-in file/sha1 bytes->hex-string)
         (except-in openssl/sha1 sha1)
         racket/file
         racket/list
         "../../../src/command/context.rkt"
         "../../../src/command/transaction.rkt"
         "../../../src/package/acquisition.rkt"
         "../../../src/package/manifest-contracts.rkt"
         "../../../src/package/runtime.rkt"
         "../../../src/package/state-records.rkt")

(provide
 make-rot13-canary-runtime
 test-editor?
 make-test-editor
 test-editor-text
 test-editor-revision
 test-editor-splices
 test-editor-undo!
 test-editor-redo!
 call-with-test-editor-context)

(define (digest character) (make-string 64 character))

(define (sha256 value)
  (bytes->hex-string (sha256-bytes (open-input-bytes value))))

(define (write-content root content)
  (define content-digest (sha256 content))
  (define path (package-content-path root content-digest))
  (make-parent-directory* path)
  (call-with-output-file path
    (lambda (output) (write-bytes content output))
    #:mode 'binary #:permissions #o600)
  content-digest)

(define (make-package-candidate root package-id module-source contributions
                                contribution-generation)
  (define content (string->bytes/utf-8 module-source))
  (define content-digest (write-content root content))
  (define authorities '(racket-extension))
  (define-values (manifest rejection)
    (confirm-package-manifest
     (odra-package-manifest-proposal
      1 package-id 'extension package-id "0.1.0" "ROT13 canary fixture"
      "MIT" #f "adrianpk" (make-string 40 #\a) "1.0.0" "1.0.0"
      (list (odra-package-target 'linux 'x86-64)) '() authorities
      (list
       (odra-package-artifact
        "entrypoint" 'racket-module "entrypoint.rkt" content-digest
        (bytes-length content) #f #f 'racket-extension '()))
      (odra-package-entrypoint "entrypoint.rkt" 'odra-package-contributions)
      contributions '()
      (odra-package-state-compatibility #f #f #f 'none))))
  (when rejection
    (error 'make-package-candidate "manifest rejected: ~s" rejection))
  (define installed
    (odra-installed-package
     package-id 'extension "0.1.0" 1
     (package-manifest-digest manifest) #f (list content-digest) '()
     (odra-package-provenance
      'catalog (digest #\1) (digest #\2) (digest #\3)
      "adrianpk" (make-string 40 #\a))
     'linux 'x86-64 authorities '() ""
     'installed-disabled 0 #f #f #f #f ""))
  (prepare-package-runtime
   root installed manifest
   (odra-package-authority-grant
    package-id "0.1.0" 1 authorities "ROT13 canary fixture grant")
   contribution-generation))

(define rot13-module
  (string-append
   "#lang racket/base\n"
   "(require odra/commands)\n"
   "(provide odra-package-contributions)\n"
   "(define (rot13-character character)\n"
   "  (define codepoint (char->integer character))\n"
   "  (cond\n"
   "    [(<= (char->integer #\\A) codepoint (char->integer #\\Z))\n"
   "     (integer->char (+ (char->integer #\\A)\n"
   "                      (modulo (+ (- codepoint (char->integer #\\A)) 13) 26)))]\n"
   "    [(<= (char->integer #\\a) codepoint (char->integer #\\z))\n"
   "     (integer->char (+ (char->integer #\\a)\n"
   "                      (modulo (+ (- codepoint (char->integer #\\a)) 13) 26)))]\n"
   "    [else character]))\n"
   "(define (rot13 text) (list->string (map rot13-character (string->list text))))\n"
   "(define (run context)\n"
   "  (define region (command-context-active-region context))\n"
   "  (cond\n"
   "    [(not region) (command-reject 'invalid-state \"Select non-empty text.\")]\n"
   "    [else\n"
   "     (define selected (command-context-read context region))\n"
   "     (if (string=? selected \"\")\n"
   "         (command-reject 'invalid-state \"Select non-empty text.\")\n"
   "         (command-context-replace! context region (rot13 selected)))]))\n"
   "(define odra-package-contributions\n"
   "  (list (make-command 'rot13-region run\n"
   "                      #:requirements '(active-buffer active-region)\n"
   "                      #:effects '(buffer text-mutation)\n"
   "                      #:source \"odra.rot13\")))\n"))

(define agent-module
  (string-append
   "#lang racket/base\n"
   "(require odra/agents)\n"
   "(provide odra-package-contributions)\n"
   "(define odra-package-contributions\n"
   "  (list\n"
   "   (make-agent 'odra.rot13-canary\n"
   "               #:display-name \"ROT13 Canary\"\n"
   "               #:interaction-kinds '(progress request result)\n"
   "               #:provider-requirements '(odra.agent-driver)\n"
   "               #:requested-capabilities '(odra.rot13.region)\n"
   "               #:continuation-policy 'none\n"
   "               #:source \"odra.rot13-canary-agent\")))\n"))

(define integration-module
  (string-append
   "#lang racket/base\n"
   "(require odra/agents)\n"
   "(provide odra-package-contributions)\n"
   "(define odra-package-contributions\n"
   "  (list\n"
   "   (make-agent-capability\n"
   "    'odra.rot13.region 'odra.rot13\n"
   "    (lambda (context)\n"
   "      (agent-capability-invoke-operation! context 'rot13-region))\n"
   "    #:purpose \"Apply ROT13 to one exact active non-empty region.\"\n"
   "    #:input-schema\n"
   "    '(record\n"
   "      (buffer required (owner-reference odra.editor.buffer 1))\n"
   "      (region required (owner-reference odra.editor.region 1))\n"
   "      (revision required (integer 1 9223372036854775807)))\n"
   "    #:result-schema\n"
   "    '(record (revision required (integer 1 9223372036854775807)))\n"
   "    #:target-kinds '(odra.editor.buffer odra.editor.region)\n"
   "    #:effects '(mutate-editor-state observe)\n"
   "    #:required-authorities '(racket-extension)\n"
   "    #:default-limits\n"
   "    (make-agent-capability-limits\n"
   "     #:deadline-milliseconds 5000 #:input-bytes 4096\n"
   "     #:result-bytes 4096 #:target-references 2)\n"
   "    #:hard-limits\n"
   "    (make-agent-capability-limits\n"
   "     #:deadline-milliseconds 5000 #:input-bytes 4096\n"
   "     #:result-bytes 4096 #:target-references 2)\n"
   "    #:approval-class 'ask-once\n"
   "    #:idempotency-class 'non-idempotent\n"
   "    #:verification-class 'immediate\n"
   "    #:retirement-policy 'cancel\n"
   "    #:source \"odra.rot13-agent-integration\")))\n"))

(define (make-rot13-canary-runtime root)
  (define runtime (make-package-runtime))
  (define candidates
    (list
     (make-package-candidate
      root "odra.rot13" rot13-module
      (list
       (odra-package-contribution
        "rot13-region" 'command '(active-buffer active-region)
        '(buffer text-mutation)))
      2)
     (make-package-candidate
      root "odra.rot13-canary-agent" agent-module
      (list
       (odra-package-contribution
        "odra.rot13-canary" 'agent '(odra.agent-driver)
        '(odra.rot13.region)))
      3)
     (make-package-candidate
      root "odra.rot13-agent-integration" integration-module
      (list
       (odra-package-contribution
        "odra.rot13.region" 'agent-capability '(racket-extension)
        '(mutate-editor-state observe)))
      4)))
  (for ([candidate (in-list candidates)])
    (define result (package-runtime-activate! runtime candidate))
    (unless (void? result)
      (error 'make-rot13-canary-runtime "activation failed: ~s" result)))
  runtime)

(struct test-editor
  ([bytes #:mutable] [revision #:mutable] [undo #:mutable] [redo #:mutable]
                    [splices #:mutable])
  #:transparent)

(define (make-test-editor text)
  (test-editor (string->bytes/utf-8 text) 1 '() '() 0))

(define (test-editor-text editor)
  (bytes->string/utf-8 (test-editor-bytes editor)))

(define (apply-splice! editor edit)
  (define source (test-editor-bytes editor))
  (define start (transaction-edit-start edit))
  (define end (transaction-edit-end edit))
  (define replacement (transaction-edit-replacement edit))
  (set-test-editor-undo! editor (cons source (test-editor-undo editor)))
  (set-test-editor-redo! editor '())
  (set-test-editor-bytes!
   editor
   (bytes-append (subbytes source 0 start) replacement
                 (subbytes source end)))
  (set-test-editor-revision! editor (add1 (test-editor-revision editor)))
  (set-test-editor-splices! editor (add1 (test-editor-splices editor))))

(define (call-with-test-editor-context editor start end action
                                       #:cancelled? [cancelled? #f])
  (call-with-transaction
   1
   (lambda (_token operation payload)
     (case operation
       [(inspect)
        (list 'ok
              (subbytes (test-editor-bytes editor)
                        (hash-ref payload 'start)
                        (hash-ref payload 'end)))]
       [(splice)
        (apply-splice! editor (hash-ref payload 'edit))
        (list 'ok #t)]
       [(abort) (list 'ok #t)]
       [else (error 'test-editor "unexpected transaction operation: ~s" operation)]))
   (lambda (transaction)
     (call-with-command-context
      transaction (test-editor-revision editor) end start end
      0 (bytes-length (test-editor-bytes editor))
      (bytes-length (test-editor-bytes editor))
      '(buffer text-mutation view) (lambda () cancelled?) action))))

(define (test-editor-undo! editor)
  (define previous (car (test-editor-undo editor)))
  (set-test-editor-undo! editor (cdr (test-editor-undo editor)))
  (set-test-editor-redo! editor (cons (test-editor-bytes editor)
                                      (test-editor-redo editor)))
  (set-test-editor-bytes! editor previous)
  (set-test-editor-revision! editor (add1 (test-editor-revision editor))))

(define (test-editor-redo! editor)
  (define next (car (test-editor-redo editor)))
  (set-test-editor-redo! editor (cdr (test-editor-redo editor)))
  (set-test-editor-undo! editor (cons (test-editor-bytes editor)
                                      (test-editor-undo editor)))
  (set-test-editor-bytes! editor next)
  (set-test-editor-revision! editor (add1 (test-editor-revision editor))))
