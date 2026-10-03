#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require net/base64
         racket/contract/base
         racket/string
         "records.rkt")

(provide
 (contract-out
  [named-layout->string (-> odra-named-layout? string?)]
  [string->named-layout (-> string? odra-named-layout?)]))

(define wire-header "ODRA-LAYOUT-1")

(define (named-layout->string layout)
  (string->immutable-string
   (string-join
    (cons
     wire-header
     (for/list ([node (in-list (odra-named-layout-nodes layout))])
       (if (eq? (odra-named-layout-node-kind node) 'partition)
           (if (eq? (odra-named-layout-node-arrangement node) 'above-below)
               "P\tA"
               "P\tL")
           (string-append
            "V\t"
            (if (odra-named-layout-node-selected? node) "1" "0")
            "\t"
            (case (odra-named-layout-node-dedication node)
              [(none) "0"] [(soft) "1"] [(hard) "2"])
            "\t"
            (bytes->string/utf-8
             (base64-encode
              (string->bytes/utf-8 (odra-named-layout-node-target node))
              #""))))))
    "\n")))

(define (string->named-layout text)
  (define lines (string-split text "\n" #:trim? #f))
  (unless (and (pair? lines) (string=? (car lines) wire-header)
               (> (length lines) 1))
    (raise-arguments-error 'string->named-layout "invalid layout header"))
  (named-layout
   #:nodes
   (for/list ([line (in-list (cdr lines))])
     (define fields (string-split line "\t" #:trim? #f))
     (cond
       [(equal? fields '("P" "A"))
        (named-layout-node #:kind 'partition #:arrangement 'above-below
                           #:target "" #:selected? #f #:dedication 'none)]
       [(equal? fields '("P" "L"))
        (named-layout-node #:kind 'partition #:arrangement 'left-right
                           #:target "" #:selected? #f #:dedication 'none)]
       [(and (= (length fields) 4)
             (string=? (car fields) "V")
             (member (cadr fields) '("0" "1"))
             (member (caddr fields) '("0" "1" "2")))
        (define target
          (bytes->string/utf-8
           (base64-decode (string->bytes/utf-8 (cadddr fields)))))
        (named-layout-node
         #:kind 'pane
         #:arrangement #f
         #:target target
         #:selected? (string=? (cadr fields) "1")
         #:dedication (case (string-ref (caddr fields) 0)
                        [(#\0) 'none] [(#\1) 'soft] [(#\2) 'hard]))]
       [else (raise-arguments-error 'string->named-layout "invalid layout node")]))))

(module+ test
  (require rackunit)

  (define layout
    (named-layout
     #:nodes
     (list
      (named-layout-node #:kind 'partition #:arrangement 'left-right
                         #:target "" #:selected? #f #:dedication 'none)
      (named-layout-node #:kind 'pane #:arrangement #f
                         #:target "/tmp/left.odin" #:selected? #t #:dedication 'soft)
      (named-layout-node #:kind 'pane #:arrangement #f
                         #:target "/tmp/right.odin" #:selected? #f #:dedication 'none))))
  (check-equal? (string->named-layout (named-layout->string layout)) layout)
  (check-exn exn:fail? (lambda () (string->named-layout "ODRA-LAYOUT-0"))))
