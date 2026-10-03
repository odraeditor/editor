#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list
         racket/string
         "native-contracts.rkt")

(provide
 factory-status-bar-configuration
 (struct-out odra-status-bar-configuration)
 (struct-out odra-status-bar-segment)
 (struct-out odra-status-bar-provider)
 (contract-out
  [status-bar-configuration
   (->* ()
        (#:position symbol? #:visible (listof symbol?) #:compact symbol?)
        odra-status-bar-configuration?)]
  [normalize-status-bar-configuration
   (-> any/c odra-status-bar-configuration?)]
  [status-bar-position-code (-> odra-status-bar-configuration? exact-positive-integer?)]
  [status-bar-compact-code (-> odra-status-bar-configuration? exact-positive-integer?)]
  [status-bar-visibility-mask (-> odra-status-bar-configuration? exact-nonnegative-integer?)]
  [status-bar-segment
   (->* (symbol? string?)
        (#:compact string? #:group symbol? #:order exact-nonnegative-integer?
         #:priority exact-nonnegative-integer? #:omittable? boolean?
         #:truncatable? boolean? #:style symbol? #:inspection string?
         #:primary-command (or/c #f symbol? string?)
         #:secondary-command (or/c #f symbol? string?))
        odra-status-bar-segment?)]
  [status-bar-provider
   (-> string? symbol? (listof odra-status-bar-segment?) odra-status-bar-provider?)]))

(define position-variants '(line-column-percentage line-column byte-offset))
(define compact-policies '(automatic prefer-compact essential-only))
(define optional-segments '(encoding pane-state workspace project editing-context))
(define maximum-extension-segments
  (native-contract-value 'status-bar 'maximum-extension-segments))
(define maximum-identity-bytes
  (native-contract-value 'status-bar 'maximum-identity-bytes))
(define maximum-provider-name-bytes
  (native-contract-value 'status-bar 'maximum-provider-name-bytes))
(define maximum-package-name-bytes
  (native-contract-value 'status-bar 'maximum-package-name-bytes))
(define maximum-command-name-bytes
  (native-contract-value 'status-bar 'maximum-command-name-bytes))
(define maximum-segment-text-bytes
  (native-contract-value 'status-bar 'maximum-segment-text-bytes))
(define admitted-segment-styles '(ordinary context editing-context disabled))
(define factory-segment-identities
  '(alert encoding buffer-state pane-state buffer-identity
          buffer-size buffer-context position progress
          workspace project editing-context))
(define machine-identity-pattern #px"^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$")

(struct odra-status-bar-configuration (position visible compact)
  #:transparent
  #:guard
  (lambda (position visible compact _)
    (unless (memq position position-variants)
      (raise-arguments-error 'odra-status-bar-configuration
                             "unsupported position presentation"
                             "position" position))
    (unless (and (list? visible)
                 (andmap (lambda (entry) (memq entry optional-segments)) visible)
                 (= (length visible) (length (remove-duplicates visible))))
      (raise-arguments-error 'odra-status-bar-configuration
                             "visible segments must be a unique admitted list"
                             "visible" visible))
    (unless (memq compact compact-policies)
      (raise-arguments-error 'odra-status-bar-configuration
                             "unsupported compact policy"
                             "compact" compact))
    (values position visible compact)))

(struct odra-status-bar-segment
  (identity kind group order priority full-text compact-text omittable? truncatable?
            style inspection-text primary-command secondary-command)
  #:transparent
  #:guard
  (lambda (identity kind group order priority full-text compact-text
                    omittable? truncatable? style inspection-text
                    primary-command secondary-command _)
    (unless (and (symbol? identity)
                 (machine-identity? (symbol->string identity) maximum-identity-bytes)
                 (not (memq identity factory-segment-identities)))
      (raise-arguments-error 'odra-status-bar-segment
                             "identity must be a non-factory machine identity"
                             "identity" identity))
    (unless (eq? kind 'miscellaneous)
      (raise-arguments-error 'odra-status-bar-segment
                             "unsupported programmable segment kind"
                             "kind" kind))
    (unless (memq group '(left right))
      (raise-arguments-error 'odra-status-bar-segment
                             "group must be left or right"
                             "group" group))
    (unless (and (exact-nonnegative-integer? order) (<= order #xffff)
                 (exact-nonnegative-integer? priority) (<= priority #xffff))
      (raise-arguments-error 'odra-status-bar-segment
                             "order and priority must fit unsigned 16-bit fields"
                             "order" order "priority" priority))
    (for ([field (in-list (list (cons 'full-text full-text)
                                (cons 'compact-text compact-text)
                                (cons 'inspection-text inspection-text)))])
      (unless (bounded-display-text? (cdr field) maximum-segment-text-bytes)
        (raise-arguments-error 'odra-status-bar-segment
                               "segment text must be bounded UTF-8 without control sequences"
                               (symbol->string (car field)) (cdr field))))
    (when (string=? full-text "")
      (raise-arguments-error 'odra-status-bar-segment
                             "full text cannot be empty"
                             "full-text" full-text))
    (unless (or omittable? truncatable?)
      (raise-arguments-error 'odra-status-bar-segment
                             "programmable segments must admit omission or truncation"))
    (unless (memq style admitted-segment-styles)
      (raise-arguments-error 'odra-status-bar-segment
                             "style is not admitted for programmable segments"
                             "style" style))
    (for ([command (in-list (list primary-command secondary-command))])
      (unless (or (not command) (command-identity? command))
        (raise-arguments-error 'odra-status-bar-segment
                               "command must be a bounded registered-command identity"
                               "command" command)))
    (values identity kind group order priority full-text compact-text
            omittable? truncatable? style inspection-text
            (normalize-command primary-command)
            (normalize-command secondary-command))))

(struct odra-status-bar-provider (name package segments)
  #:transparent
  #:guard
  (lambda (name package segments _)
    (unless (and (not (string=? name ""))
                 (bounded-display-text? name maximum-provider-name-bytes))
      (raise-arguments-error 'odra-status-bar-provider
                             "provider name must be bounded UTF-8 without control sequences"
                             "name" name))
    (unless (and (symbol? package)
                 (machine-identity? (symbol->string package) maximum-package-name-bytes))
      (raise-arguments-error 'odra-status-bar-provider
                             "package must be a machine identity"
                             "package" package))
    (unless (and (list? segments)
                 (pair? segments)
                 (<= (length segments) maximum-extension-segments)
                 (andmap odra-status-bar-segment? segments))
      (raise-arguments-error 'odra-status-bar-provider
                             "segments must be a non-empty bounded segment list"
                             "segments" segments))
    (define identities (map odra-status-bar-segment-identity segments))
    (unless (= (length identities) (length (remove-duplicates identities)))
      (raise-arguments-error 'odra-status-bar-provider
                             "segment identities must be unique"
                             "identities" identities))
    (values name package segments)))

(define factory-status-bar-configuration
  (odra-status-bar-configuration
   'line-column-percentage optional-segments 'automatic))

;; status-bar-configuration constructs one complete admitted factory policy.
(define (status-bar-configuration
         #:position [position 'line-column-percentage]
         #:visible [visible optional-segments]
         #:compact [compact 'automatic])
  (odra-status-bar-configuration position visible compact))

;; normalize-status-bar-configuration accepts the public value or its init.rkt hash form.
(define (normalize-status-bar-configuration value)
  (cond
    [(not value) factory-status-bar-configuration]
    [(odra-status-bar-configuration? value) value]
    [(hash? value)
     (status-bar-configuration
      #:position (hash-ref value 'position 'line-column-percentage)
      #:visible (hash-ref value 'visible optional-segments)
      #:compact (hash-ref value 'compact 'automatic))]
    [else
     (raise-arguments-error 'normalize-status-bar-configuration
                            "expected a Status Bar configuration or hash"
                            "value" value)]))

(define (status-bar-position-code configuration)
  (case (odra-status-bar-configuration-position configuration)
    [(line-column-percentage) 1]
    [(line-column) 2]
    [(byte-offset) 3]))

(define (status-bar-compact-code configuration)
  (case (odra-status-bar-configuration-compact configuration)
    [(automatic) 1]
    [(prefer-compact) 2]
    [(essential-only) 3]))

(define (status-bar-visibility-mask configuration)
  (for/fold ([mask 0]) ([segment (in-list (odra-status-bar-configuration-visible configuration))])
    (bitwise-ior
     mask
     (case segment
       [(encoding) #x01]
       [(pane-state) #x02]
       [(workspace) #x04]
       [(project) #x08]
       [(editing-context) #x10]))))

;; status-bar-segment constructs one bounded declarative package contribution.
(define (status-bar-segment
         identity full-text
         #:compact [compact-text ""]
         #:group [group 'right]
         #:order [order 0]
         #:priority [priority 0]
         #:omittable? [omittable? #t]
         #:truncatable? [truncatable? #f]
         #:style [style 'context]
         #:inspection [inspection-text ""]
         #:primary-command [primary-command #f]
         #:secondary-command [secondary-command #f])
  (odra-status-bar-segment
   identity 'miscellaneous group order priority full-text compact-text
   omittable? truncatable? style inspection-text primary-command secondary-command))

;; status-bar-provider constructs one complete replaceable package generation.
(define (status-bar-provider name package segments)
  (odra-status-bar-provider name package segments))

(define (machine-identity? value maximum-bytes)
  (and (string? value)
       (regexp-match? machine-identity-pattern value)
       (<= (bytes-length (string->bytes/utf-8 value)) maximum-bytes)))

(define (bounded-display-text? value maximum-bytes)
  (and (string? value)
       (<= (bytes-length (string->bytes/utf-8 value)) maximum-bytes)
       (for/and ([character (in-string value)])
         (define code (char->integer character))
         (not (or (< code 32) (<= 127 code 159))))))

(define (command-identity? command)
  (define value (if (symbol? command) (symbol->string command) command))
  (machine-identity? value maximum-command-name-bytes))

(define (normalize-command command)
  (cond [(symbol? command) (symbol->string command)]
        [else command]))

(module+ test
  (require rackunit)

  (check-equal? (status-bar-position-code factory-status-bar-configuration) 1)
  (check-equal? (status-bar-compact-code factory-status-bar-configuration) 1)
  (check-equal? (status-bar-visibility-mask factory-status-bar-configuration) #x1f)
  (define compact
    (normalize-status-bar-configuration
     '#hash((position . line-column)
            (visible . (project editing-context))
            (compact . prefer-compact))))
  (check-equal? (status-bar-position-code compact) 2)
  (check-equal? (status-bar-compact-code compact) 2)
  (check-equal? (status-bar-visibility-mask compact) #x18)
  (check-exn exn:fail?
             (lambda ()
               (status-bar-configuration #:visible '(project project))))

  (define task-segment
    (status-bar-segment
     'task-count "3 tasks" #:compact "3" #:order 20
     #:inspection "Three active tasks" #:primary-command 'tasks-open))
  (define provider (status-bar-provider "Tasks" 'tasks-package (list task-segment)))
  (check-equal? (odra-status-bar-provider-package provider) 'tasks-package)
  (check-equal? (odra-status-bar-segment-primary-command task-segment) "tasks-open")
  (check-exn exn:fail?
             (lambda () (status-bar-segment 'position "forged")))
  (check-exn exn:fail?
             (lambda () (status-bar-segment 'unsafe "\u001b[31mred")))
  (check-exn exn:fail?
             (lambda ()
               (status-bar-provider "Duplicate" 'duplicate-package
                                    (list task-segment task-segment)))))
