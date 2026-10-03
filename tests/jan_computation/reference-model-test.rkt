#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         racket/runtime-path
         racket/string
         rackunit
         "model.rkt")

(define-runtime-path formulas-plots-org "fixtures/formulas-plots.org")
(define-runtime-path formulas-plots-jan "fixtures/formulas-plots.jan")
(define-runtime-path execution-adapters-org "fixtures/execution-adapters.org")
(define-runtime-path execution-adapters-jan "fixtures/execution-adapters.jan")
(define-runtime-path results-sessions-org "fixtures/results-sessions.org")
(define-runtime-path results-sessions-jan "fixtures/results-sessions.jan")
(define-runtime-path source-extraction-org "fixtures/source-extraction.org")
(define-runtime-path source-extraction-jan "fixtures/source-extraction.jan")
(define-runtime-path computation-domain-org "fixtures/computation-domain.org")
(define-runtime-path computation-domain-jan "fixtures/computation-domain.jan")

(test-case "formula graphs are stable and reject cycles"
  (define graph
    (list (hasheq 'identity 'total 'dependencies '(price tax))
          (hasheq 'identity 'price 'dependencies '())
          (hasheq 'identity 'tax 'dependencies '(price))))
  (check-equal? (order-formula-graph graph) '(price tax total))
  (check-false
   (order-formula-graph
    (list (hasheq 'identity 'a 'dependencies '(b))
          (hasheq 'identity 'b 'dependencies '(a))))))

(define copied-table
  '#hasheq((rows . 3) (columns . 3) (names . (item price tax))
           (cells . #(1 10 2 2 20 4 3 30 6))))

(test-case "table formulas resolve references and expose debug traces"
  (define result
    (evaluate-table-formula
     copied-table
     '((reference (named price)) (reference (named tax)) (add))
     1 1))
  (check-equal? (hash-ref result 'value) 24)
  (check-equal? (length (hash-ref result 'trace)) 3)
  (check-equal?
   (hash-ref (evaluate-table-formula copied-table '((sum 0 1 2 1)) 0 0) 'value)
   60))

(test-case "failed recalculation preserves the prior table"
  (define failed
    (recalculate-table
     copied-table
     (list (hasheq 'target '(0 2) 'instructions '((literal 1) (literal 0) (divide))))))
  (check-false failed)
  (check-equal? (hash-ref copied-table 'cells) '#(1 10 2 2 20 4 3 30 6))
  (define updated
    (recalculate-table
     copied-table
     (list (hasheq 'target '(0 2)
                   'instructions '((reference (named price)) (literal 2) (multiply))))))
  (check-equal? (hash-ref updated 'cells) '#(1 10 20 2 20 4 3 30 6)))

(test-case "lookup families select deterministic copied values"
  (check-equal? (lookup-table-value copied-table 'exact 2 0 1) 20)
  (check-equal? (lookup-table-value copied-table 'relational 2.5 0 1) 20)
  (define ranges '#hasheq((rows . 2) (columns . 3) (names . (low high value))
                          (cells . #(0 10 1 11 20 2))))
  (check-equal? (lookup-table-value ranges 'range 15 0 2 1) 2))

(test-case "text and Gnuplot plots remain bounded handoffs"
  (define text (render-text-plot "Totals" '(("Q1" 10) ("Q2" -20)) 10))
  (check-true (regexp-match? #rx"Q1 \\+#####" text))
  (check-true (regexp-match? #rx"Q2 -##########" text))
  (define snapshot
    '#hasheq((operation . 1) (scope . exact) (digest . digest-a)
             (points . (("Q1" 10) ("Q2" -20)))))
  (define request (prepare-gnuplot-request snapshot 3 'svg "plots/totals.svg" 512))
  (check-equal? (hash-ref request 'terminal) 'svg)
  (check-equal? (hash-ref request 'point-count) 2))

(test-case "formula and plot fixtures preserve Org and Jan source parity"
  (define org-source (file->string formulas-plots-org))
  (define jan-source (file->string formulas-plots-jan))
  (check-equal? org-source jan-source)
  (for ([marker (in-list '("#+TBLFM:" "#+plot:" "#+begin_src racket"
                           "#+begin_src emacs-lisp" "#+RESULTS:"))])
    (check-true (string-contains? org-source marker))))

(test-case "execution adapter fixtures preserve explicit source and prior results"
  (define org-source (file->string execution-adapters-org))
  (define jan-source (file->string execution-adapters-jan))
  (check-equal? org-source jan-source)
  (for ([marker (in-list '("header-args:racket" "#+begin_src racket"
                           "#+begin_src emacs-lisp" "jan-missing-runtime"
                           "#+RESULTS:"))])
    (check-true (string-contains? org-source marker))))

(test-case "execution argument precedence remains inspectable"
  (define resolved
    (resolve-execution-arguments
     (list (list 'factory (hasheq 'session "none" 'var '(a)))
           (list 'project (hasheq 'session "project" 'var '(b)))
           (list 'invocation (hasheq 'session "exact")))
     '(var)))
  (check-equal? (hash-ref (hash-ref resolved 'values) 'session) "exact")
  (check-equal? (hash-ref (hash-ref resolved 'values) 'var) '(a b))
  (check-equal? (hash-ref (hash-ref resolved 'provenance) 'session) 'invocation)
  (check-equal? (length (hash-ref (hash-ref resolved 'shadowed) 'session)) 2))

(test-case "authority is deny-first and batch cannot confirm"
  (define rules
    (list (hasheq 'language 'racket 'origins '(project document)
                  'effects '(read-resource child-process)
                  'interactive 'confirm 'batch 'deny 'export 'deny)))
  (check-equal? (resolve-execution-authority rules 'racket 'project 'interactive
                                             '(read-resource) #t)
                'confirm)
  (check-equal? (resolve-execution-authority rules 'racket 'project 'batch
                                             '(read-resource) #t)
                'deny)
  (check-equal? (resolve-execution-authority rules 'racket 'external 'interactive
                                             '(read-resource) #t)
                'deny))

(test-case "adapter selection never substitutes a different language"
  (define adapters
    (list '#hasheq((identity . racket) (language . racket) (generation . 4)
                   (runtime-required? . #t))))
  (check-equal? (select-execution-adapter adapters 'racket 'racket 4 #f) 'unavailable)
  (check-equal? (hash-ref (select-execution-adapter adapters 'racket 'racket 4 #t)
                          'identity)
                'racket)
  (check-equal? (select-execution-adapter adapters 'emacs-lisp #f 4 #t) 'unavailable)
  (check-equal? (select-execution-adapter adapters 'racket 'racket 3 #t) 'stale))

(test-case "serialization and implicit execution remain inert"
  (define serialized
    (serialize-execution-variables
     (list '#hasheq((name . count) (kind . scalar) (value . "3"))
           '#hasheq((name . literal) (kind . scalar) (value . "$(never-executed)")))))
  (check-true (string-contains? serialized "$(never-executed)"))
  (define rules
    (list '#hasheq((adapter . racket) (language . racket) (origins . (project))
                   (effects . (read-resource)) (interactive . allow)
                   (batch . allow) (export . allow))))
  (check-equal? (resolve-execution-authority rules 'racket 'project 'interactive
                                             '(read-resource) #t
                                             #:adapter 'racket #:trigger 'open)
                'deny)
  (check-equal? (resolve-execution-authority rules 'racket 'project 'interactive
                                             '(read-resource) #t
                                             #:adapter 'racket #:trigger 'command)
                'allow))

(test-case "timeouts quarantine exact adapters until cleanup"
  (check-equal? (transition-execution-process 'prepared 'start) 'starting)
  (check-equal? (transition-execution-process 'starting 'started) 'running)
  (check-equal? (transition-execution-process 'running 'timeout) 'timed-out)
  (check-equal? (transition-execution-process 'timed-out 'quarantine) 'quarantined)
  (check-equal? (transition-execution-process 'quarantined 'reconcile) 'cleaning)
  (check-equal? (transition-execution-process 'cleaning 'cleanup-confirmed) 'closed)
  (define health (update-adapter-health #f 4 9 'timeout))
  (check-true (hash-ref health 'quarantined?))
  (check-false (hash-ref (update-adapter-health health 4 9 'reconcile) 'quarantined?)))

(test-case "typed results enforce row and output limits"
  (define candidate
    '#hasheq((collection . value) (type . table) (format . table)
             (handling . replace) (rows . 3) (bytes . 128) (complete? . #t)))
  (check-equal? (normalize-typed-result candidate) candidate)
  (check-false (normalize-typed-result (hash-set candidate 'rows 16385))))

(test-case "result decoding and publication require complete exact owners"
  (define candidate
    '#hasheq((collection . value) (type . table) (format . table)
             (handling . append) (rows . 2) (bytes . 7) (complete? . #t)
             (exit-status . 0) (owner . block-a)))
  (define decoded (decode-typed-result candidate #"a\tb\n1\t2"))
  (check-true (hash-ref decoded 'decoded?))
  (check-equal?
   (hash-ref (prepare-result-publication decoded 'block-a #"old\n" #"new\n") 'replacement)
   #"old\nnew\n")
  (check-false (prepare-result-publication decoded 'block-b #"old\n" #"new\n"))
  (check-false (decode-typed-result (hash-set candidate 'complete? #f) #"a\tb\n1\t2")))

(test-case "post-processing order rejects cycles"
  (define ordered
    (order-result-processing
     (list (hasheq 'identity 3 'dependencies '(2))
           (hasheq 'identity 1 'dependencies '())
           (hasheq 'identity 2 'dependencies '(1)))))
  (check-equal? ordered '(1 2 3))
  (check-false
   (order-result-processing
    (list (hasheq 'identity 1 'dependencies '(2))
          (hasheq 'identity 2 'dependencies '(1))))))

(test-case "session lifecycle closes failed and quarantined contexts"
  (check-equal? (transition-session 'prepared 'start) 'active)
  (check-equal? (transition-session 'active 'quarantine) 'quarantined)
  (check-equal? (transition-session 'quarantined 'close) 'closed)
  (check-equal? (transition-session 'active 'restart) 'recovery-required)
  (check-equal? (transition-session 'recovery-required 'reconnect) 'active)
  (check-false (transition-session 'closed 'start)))

(test-case "cache keys reject changed policy and environment"
  (define key
    '#hasheq((source . source-a) (arguments . args-a) (inputs . inputs-a)
             (references . refs-a) (adapter . racket) (version . "1")
             (environment . env-a) (policy . policy-a)))
  (check-true (cache-key-current? key key))
  (check-false (cache-key-current? (hash-set key 'policy 'policy-b) key))
  (define entry (hasheq 'key key 'complete? #t 'payload #"answer"))
  (check-equal? (hash-ref (inspect-result-cache (list entry) key) 'state) 'hit)
  (check-equal? (hash-ref (inspect-result-cache (list entry) (hash-set key 'policy 'policy-b)) 'state)
                'invalidated)
  (check-equal? (hash-ref (inspect-result-cache '() key) 'state) 'miss))

(test-case "result and session fixtures preserve source-owned prior results"
  (define org-source (file->string results-sessions-org))
  (define jan-source (file->string results-sessions-jan))
  (check-equal? org-source jan-source)
  (for ([marker (in-list '("session named-racket" "cache yes" "#+RESULTS: block-a"
                           "prior-success" "partial-output-is-not-inserted"))])
    (check-true (string-contains? org-source marker))))

(test-case "extraction plans reject collisions before publication"
  (define first (hasheq 'identity 'a 'resource "out/a.rkt" 'bytes #"a"))
  (define second (hasheq 'identity 'b 'resource "out/a.rkt" 'bytes #"b"))
  (check-false (plan-extraction (list first second) #f))
  (check-equal? (hash-ref (plan-extraction (list first second) #t) 'resources) 2)
  (check-false (plan-extraction (list first second) #t #:cancelled? #t)))

(test-case "focused source editing preserves delimiters and unrelated bytes"
  (define prefix #"#+begin_src racket\n")
  (define body #"  (+ 1 2)\n")
  (define suffix #"#+end_src\nunrelated\n")
  (define source (bytes-append prefix body suffix))
  (define edit (prepare-source-edit source 'block-a (bytes-length prefix)
                                    (+ (bytes-length prefix) (bytes-length body)) #"  "))
  (check-equal? (hash-ref edit 'focused) #"(+ 1 2)\n")
  (check-equal? (publish-source-edit edit source #"(- 8 3)\n")
                (bytes-append prefix #"  (- 8 3)\n" suffix))
  (check-false (publish-source-edit edit (bytes-append prefix #"  changed\n" suffix)
                                    #"(- 8 3)\n")))

(test-case "noweb graphs require admitted acyclic definitions"
  (define definitions
    (list (hasheq 'identity 'root 'references '(helper result) 'admitted? #t)
          (hasheq 'identity 'helper 'references '() 'admitted? #t)
          (hasheq 'identity 'result 'references '() 'admitted? #t)))
  (check-equal? (order-noweb-graph definitions 'root) '(helper result root))
  (check-false
   (order-noweb-graph
    (list (hasheq 'identity 'a 'references '(b) 'admitted? #t)
          (hasheq 'identity 'b 'references '(a) 'admitted? #t))
    'a))
  (check-false
   (order-noweb-graph
    (list (hasheq 'identity 'external 'references '() 'admitted? #f))
    'external)))

(test-case "source extraction fixtures preserve noweb and tangle source"
  (define org-source (file->string source-extraction-org))
  (define jan-source (file->string source-extraction-jan))
  (check-equal? org-source jan-source)
  (for ([marker (in-list '("<<shared-helper(value=7)>>" ":tangle generated/main.rkt"
                           ":comments link" "#+RESULTS: computed-fragment"))])
    (check-true (string-contains? org-source marker))))

(test-case "batch order is deterministic"
  (define ordered
    (order-batch-targets
     (list (hasheq 'identity 'c 'document 2 'start 1)
           (hasheq 'identity 'b 'document 1 'start 9)
           (hasheq 'identity 'a 'document 1 'start 9))))
  (check-equal? (map (lambda (target) (hash-ref target 'identity)) ordered) '(a b c)))

(define admitted-batch-targets
  (list (hasheq 'identity 'c 'document 2 'start 1
                'authority 'allow 'explicit-trigger? #t
                'policy-generation 7 'scope-policy-generation 7
                'adapter-state 'selected 'adapter-generation 9
                'scope-adapter-generation 9 'cache-state 'miss)
        (hasheq 'identity 'a 'document 1 'start 4
                'authority 'allow 'explicit-trigger? #t
                'policy-generation 7 'scope-policy-generation 7
                'adapter-state 'selected 'adapter-generation 9
                'scope-adapter-generation 9 'cache-state 'hit)))

(test-case "batch plans require explicit exact-generation authority"
  (define plan (prepare-execution-batch admitted-batch-targets 'atomic 2))
  (check-true (hash-ref plan 'complete?))
  (check-equal? (map (lambda (target) (hash-ref target 'identity))
                     (hash-ref plan 'targets))
                '(a c))
  (check-equal? (hash-ref plan 'cache-hits) 1)
  (check-false
   (prepare-execution-batch
    (list (hash-set (car admitted-batch-targets) 'explicit-trigger? #f))
    'atomic 1)))

(test-case "batch summaries separate atomic and best-effort publication"
  (define plan (prepare-execution-batch admitted-batch-targets 'atomic 2))
  (define outcomes
    (list '#hasheq((identity . a) (state . cache-hit) (bytes . 8) (rows . 1))
          '#hasheq((identity . c) (state . rejected) (failure . evaluation)
                   (bytes . 0) (rows . 0))))
  (check-equal? (hash-ref (summarize-execution-batch plan outcomes) 'published) 0)
  (define best-effort (hash-set plan 'mode 'best-effort))
  (check-equal? (hash-ref (summarize-execution-batch best-effort outcomes) 'published) 1))

(test-case "capability state follows optional runtime owners"
  (define native (computation-capability-states '#hasheq((language-ready? . #t))))
  (check-true (hash-ref native 'formulas))
  (check-false (hash-ref native 'execution))
  (define complete
    (computation-capability-states
     '#hasheq((language-ready? . #t) (graphical-adapter? . #t)
              (execution-adapter? . #t) (process-owner? . #t)
              (resource-owner? . #t))))
  (for ([(capability available?) (in-hash complete)])
    (check-true available? (symbol->string capability))))

(test-case "domain closure fixture preserves Org and Jan source parity"
  (define org-source (file->string computation-domain-org))
  (define jan-source (file->string computation-domain-jan))
  (check-equal? org-source jan-source)
  (for ([marker (in-list '("#+TBLFM:" "#+plot:" "#+name: shared-helper"
                           "<<shared-helper(value=7)>>" ":tangle generated/report.rkt"
                           ":session closure" ":cache yes" "#+RESULTS:"))])
    (check-true (string-contains? org-source marker))))

(test-case "resource profiles remain within every stable ceiling"
  (for ([profile (in-list computation-resource-profiles)])
    (check-true (validate-computation-resource-profile profile))
    (check-true (positive? (estimate-computation-retained-bytes profile)))
    (check-true (positive? (estimate-computation-temporary-bytes profile)))))
