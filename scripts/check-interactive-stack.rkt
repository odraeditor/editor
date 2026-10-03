#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/cmdline
         racket/format
         racket/list
         racket/port
         racket/string
         racket/system)

(struct frame-budget (owner symbol maximum-bytes) #:transparent)
(struct path-budget (owner maximum-bytes symbols) #:transparent)

(define mib (* 1024 1024))
(define minimum-supported-stack-bytes (* 8 mib))
(define interactive-path-maximum-bytes (* 4 mib))

(define run-symbol "main::[app.odin]::run")
(define open-symbol "main::[app.odin]::app_runtime_open")
(define interface-symbol "main::[app.odin]::app_runtime_initialize_interface")
(define loop-symbol "main::[app.odin]::app_runtime_loop")
(define byte-loop-symbol "main::[app.odin]::app_runtime_loop_byte")
(define resize-loop-symbol "main::[app.odin]::app_runtime_loop_resize")
(define idle-loop-symbol "main::[app.odin]::app_runtime_loop_idle")
(define close-symbol "main::[app.odin]::app_runtime_close")
(define session-input-symbol "main::[app.odin]::dispatch_session_input")
(define deferred-command-symbol "main::[app.odin]::dispatch_session_deferred_command")
(define interaction-input-symbol "main::[interaction.odin]::dispatch_input")
(define interaction-result-symbol
  "main::[interaction.odin]::command_context_dispatch_execution_result")
(define darek-route-symbol
  "main::[darek_workflow.odin]::command_context_dispatch_darek_route")
(define product-module-invoke-symbol
  "main::[product_module_workflow.odin]::product_module_workflow_invoke_role")
(define search-prompt-symbol "main::[search_workflow.odin]::dispatch_search_prompt")
(define candidate-input-symbol "main::[candidate_ui.odin]::dispatch_candidate_ui_input")
(define present-session-symbol "main::[app.odin]::present_current_session")
(define present-content-symbol "main::[app.odin]::present_current_session_content")
(define present-layout-symbol "main::[app.odin]::present_current_layout")
(define shutdown-symbol "main::[app.odin]::session_shutdown_close")

;; Increasing these budgets requires an architecture ticket that explains why
;; the editor cannot recover the headroom by changing ownership or call shape.
(define frame-budgets
  (list
   (frame-budget "runtime startup" open-symbol (* 4 mib))
   (frame-budget "runtime interface startup" interface-symbol (* 1 mib))
   (frame-budget "event loop" loop-symbol (* 512 1024))
   (frame-budget "byte input turn" byte-loop-symbol (* 768 1024))
   (frame-budget "resize turn" resize-loop-symbol (* 768 1024))
   (frame-budget "idle turn" idle-loop-symbol (* 768 1024))
   (frame-budget "session input" session-input-symbol (* 768 1024))
   (frame-budget "command dispatch" interaction-input-symbol (* 2 mib))
   (frame-budget "command result dispatch" interaction-result-symbol (* 2 mib))
   (frame-budget "Darek dispatch" darek-route-symbol (* 768 1024))
   (frame-budget "product module dispatch" product-module-invoke-symbol (* 768 1024))
   (frame-budget "search dispatch" search-prompt-symbol (* 768 1024))
   (frame-budget "layout presentation" present-layout-symbol (* 2 mib))))

(define path-budgets
  (list
   (path-budget
    "startup and initial editor presentation"
    (* 6 mib)
    (list run-symbol open-symbol interface-symbol present-session-symbol
          present-content-symbol present-layout-symbol))
   (path-budget
    "interactive Darek command"
    interactive-path-maximum-bytes
    (list run-symbol loop-symbol byte-loop-symbol session-input-symbol interaction-input-symbol
          interaction-result-symbol darek-route-symbol product-module-invoke-symbol))
   (path-budget
    "interactive search command"
    interactive-path-maximum-bytes
    (list run-symbol loop-symbol byte-loop-symbol session-input-symbol interaction-input-symbol
          interaction-result-symbol search-prompt-symbol))
   (path-budget
    "candidate selection and deferred command"
    interactive-path-maximum-bytes
    (list run-symbol loop-symbol byte-loop-symbol session-input-symbol candidate-input-symbol
          deferred-command-symbol session-input-symbol interaction-input-symbol
          interaction-result-symbol))
   (path-budget
    "editor presentation"
    interactive-path-maximum-bytes
    (list run-symbol loop-symbol byte-loop-symbol present-session-symbol present-content-symbol
          present-layout-symbol))
   (path-budget
    "runtime shutdown"
    (* 2 mib)
    (list run-symbol close-symbol shutdown-symbol))))

(define (parse-disassembly input)
  (define frames (make-hash))
  (define current-symbol #f)
  (for ([line (in-lines input)])
    (define symbol-match (regexp-match #px"^[0-9a-f]+ <(.+)>:$" line))
    (cond
      [symbol-match
       (set! current-symbol (cadr symbol-match))]
      [current-symbol
       (define frame-match
         (regexp-match #px"sub[[:space:]]+\\$0x([0-9a-f]+),%rsp" line))
       (when (and frame-match (not (hash-has-key? frames current-symbol)))
         (hash-set! frames current-symbol
                    (string->number (cadr frame-match) 16)))]))
  frames)

(define (bytes-label bytes)
  (format "~a bytes (~a MiB)" bytes (~r (/ bytes mib) #:precision '(= 2))))

(define (missing-symbol-findings frames required-symbols)
  (for/list ([symbol (in-list (remove-duplicates required-symbols))]
             #:unless (hash-has-key? frames symbol))
    (format "missing generated frame evidence for ~a" symbol)))

(define (frame-budget-findings frames budgets)
  (for/list ([budget (in-list budgets)]
             #:when (and (hash-has-key? frames (frame-budget-symbol budget))
                         (> (hash-ref frames (frame-budget-symbol budget))
                            (frame-budget-maximum-bytes budget))))
    (define actual (hash-ref frames (frame-budget-symbol budget)))
    (format "frame ~a exceeds its budget: ~a > ~a; symbol=~a"
            (frame-budget-owner budget)
            (bytes-label actual)
            (bytes-label (frame-budget-maximum-bytes budget))
            (frame-budget-symbol budget))))

(define (path-budget-findings frames budgets)
  (for/list ([budget (in-list budgets)]
             #:when (and (andmap (lambda (symbol) (hash-has-key? frames symbol))
                                  (path-budget-symbols budget))
                         (> (for/sum ([symbol (in-list (path-budget-symbols budget))])
                              (hash-ref frames symbol))
                            (path-budget-maximum-bytes budget))))
    (define contributions
      (for/list ([symbol (in-list (path-budget-symbols budget))])
        (format "~a=~a" symbol (hash-ref frames symbol))))
    (define actual
      (for/sum ([symbol (in-list (path-budget-symbols budget))])
        (hash-ref frames symbol)))
    (format "path ~a exceeds its budget: ~a > ~a; frames: ~a"
            (path-budget-owner budget)
            (bytes-label actual)
            (bytes-label (path-budget-maximum-bytes budget))
            (string-join contributions ", "))))

(define (evaluate-budgets frames [frames-to-check frame-budgets]
                          [paths-to-check path-budgets])
  (define required-symbols
    (append (map frame-budget-symbol frames-to-check)
            (append-map path-budget-symbols paths-to-check)))
  (append (missing-symbol-findings frames required-symbols)
          (frame-budget-findings frames frames-to-check)
          (path-budget-findings frames paths-to-check)))

(define (read-binary-frames binary-path)
  (unless (file-exists? binary-path)
    (raise-user-error 'interactive-stack "binary is unavailable: ~a" binary-path))
  (define machine (system-type 'machine))
  (unless (and (string-contains? machine "Linux")
               (string-contains? machine "x86_64"))
    (raise-user-error
     'interactive-stack
     "generated-frame inspection requires Linux x86_64; found ~a"
     machine))
  (define objdump (find-executable-path "objdump"))
  (unless objdump
    (raise-user-error
     'interactive-stack
     "GNU objdump is required to inspect generated stack frames"))
  (define-values (process output input diagnostics)
    (subprocess #f #f #f objdump "-d" binary-path))
  (close-output-port input)
  (define frames (parse-disassembly output))
  (define diagnostic-text (port->string diagnostics))
  (subprocess-wait process)
  (unless (zero? (subprocess-status process))
    (raise-user-error
     'interactive-stack
     "objdump failed for ~a: ~a"
     binary-path
     (string-trim diagnostic-text)))
  frames)

(define (report-success frames minimum-stack-bytes)
  (printf "interactive-stack: minimum=~a, interactive-budget=~a\n"
          (bytes-label minimum-stack-bytes)
          (bytes-label interactive-path-maximum-bytes))
  (for ([budget (in-list path-budgets)])
    (define actual
      (for/sum ([symbol (in-list (path-budget-symbols budget))])
        (hash-ref frames symbol)))
    (printf "interactive-stack: path=~a measured=~a budget=~a headroom=~a\n"
            (path-budget-owner budget)
            (bytes-label actual)
            (bytes-label (path-budget-maximum-bytes budget))
            (bytes-label (- minimum-stack-bytes actual)))))

(module+ main
  (define binary-path #f)
  (define minimum-stack-kib 8192)
  (command-line
   #:program "check-interactive-stack.rkt"
   #:once-each
   [("--binary") path "Optimized Odra binary to inspect"
                   (set! binary-path path)]
   [("--minimum-stack-kib") value "Minimum supported process stack in KiB"
                                (set! minimum-stack-kib
                                      (or (string->number value)
                                          (raise-user-error
                                           'interactive-stack
                                           "invalid stack size: ~a"
                                           value)))]
   #:args () (void))
  (unless binary-path
    (raise-user-error 'interactive-stack "--binary is required"))
  (define minimum-stack-bytes (* minimum-stack-kib 1024))
  (unless (= minimum-stack-bytes minimum-supported-stack-bytes)
    (raise-user-error
     'interactive-stack
     "the declared minimum stack must remain 8192 KiB; received ~a KiB"
     minimum-stack-kib))
  (define frames (read-binary-frames binary-path))
  (define findings (evaluate-budgets frames))
  (unless (null? findings)
    (for-each (lambda (finding) (eprintf "interactive-stack: ~a\n" finding))
              findings)
    (exit 1))
  (report-success frames minimum-stack-bytes))

(module+ test
  (require rackunit)

  (test-case "generated frames are parsed by owning symbol"
    (define frames
      (parse-disassembly
       (open-input-string
        (string-append
         "0001 <owner::small>:\n"
         "  1: 48 81 ec 00 10 00 00 sub    $0x1000,%rsp\n"
         "0002 <owner::large>:\n"
         "  2: 48 81 ec 00 20 00 00 sub    $0x2000,%rsp\n"))))
    (check-equal? (hash-ref frames "owner::small") #x1000)
    (check-equal? (hash-ref frames "owner::large") #x2000))

  (test-case "over-budget frame names owner and symbol"
    (define budgets (list (frame-budget "input owner" "owner::input" 4096)))
    (define findings (evaluate-budgets (hash "owner::input" 8192) budgets '()))
    (check-equal? (length findings) 1)
    (check-true (string-contains? (car findings) "input owner"))
    (check-true (string-contains? (car findings) "owner::input")))

  (test-case "over-budget path names contributing frames"
    (define paths (list (path-budget "input path" 4096 '("owner::a" "owner::b"))))
    (define findings
      (evaluate-budgets (hash "owner::a" 3072 "owner::b" 2048) '() paths))
    (check-equal? (length findings) 1)
    (check-true (string-contains? (car findings) "input path"))
    (check-true (string-contains? (car findings) "owner::a=3072"))
    (check-true (string-contains? (car findings) "owner::b=2048")))

  (test-case "missing generated evidence fails closed"
    (define budgets (list (frame-budget "input owner" "owner::missing" 4096)))
    (define findings (evaluate-budgets (hash) budgets '()))
    (check-equal? findings
                  '("missing generated frame evidence for owner::missing"))))
