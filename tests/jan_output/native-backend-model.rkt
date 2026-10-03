#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/list
         racket/match
         racket/string)

(provide render-native-document)

(define (html-escape value [attribute? #f])
  (define escaped
    (for/fold ([result value]) ([pair (in-list '(("&" . "&amp;") ("<" . "&lt;") (">" . "&gt;")))])
      (string-replace result (car pair) (cdr pair))))
  (if attribute?
      (string-replace (string-replace escaped "\"" "&quot;") "'" "&#39;")
      escaped))

(define (markdown-escape value)
  (regexp-replace* #px"([\\\\*_\\[\\]`])" value "\\\\\\1"))

(define (plain-fragment fragment)
  (match (hash-ref fragment 'kind)
    [(or 'text 'emphasis 'strong 'code 'math) (hash-ref fragment 'text)]
    ['link (format "~a <~a>" (hash-ref fragment 'text) (hash-ref fragment 'target))]
    ['image (format "[Image: ~a] <~a>" (hash-ref fragment 'text) (hash-ref fragment 'target))]))

(define (html-fragment fragment)
  (define text (html-escape (hash-ref fragment 'text)))
  (match (hash-ref fragment 'kind)
    ['text text]
    ['emphasis (format "<em>~a</em>" text)]
    ['strong (format "<strong>~a</strong>" text)]
    ['code (format "<code>~a</code>" text)]
    ['link (format "<a href=\"~a\">~a</a>"
                   (html-escape (hash-ref fragment 'target) #t) text)]
    ['image (format "<img src=\"~a\" alt=\"~a\">"
                    (html-escape (hash-ref fragment 'target) #t)
                    (html-escape (hash-ref fragment 'text) #t))]
    ['math (format "<span class=\"math\">~a</span>" text)]))

(define (markdown-fragment fragment)
  (define text (markdown-escape (hash-ref fragment 'text)))
  (match (hash-ref fragment 'kind)
    ['text text]
    ['emphasis (format "*~a*" text)]
    ['strong (format "**~a**" text)]
    ['code (format "`~a`" (hash-ref fragment 'text))]
    ['link (format "[~a](~a)" text (hash-ref fragment 'target))]
    ['image (format "![~a](~a)" text (hash-ref fragment 'target))]
    ['math (format "$~a$" (hash-ref fragment 'text))]))

(define (jan-fragment fragment)
  (define text (hash-ref fragment 'text))
  (match (hash-ref fragment 'kind)
    ['text text]
    ['emphasis (format "/~a/" text)]
    ['strong (format "*~a*" text)]
    ['code (format "~~~a~" text)]
    ['link (format "[[~a][~a]]" (hash-ref fragment 'target) text)]
    ['image (format "[[~a][~a]]" (hash-ref fragment 'target) text)]
    ['math (format "\\(~a\\)" text)]))

(define (fragments block renderer)
  (apply string-append (map renderer (hash-ref block 'fragments))))

(define (render-plain document)
  (string-append
   (hash-ref document 'title) "\n\n"
   (apply string-append
          (for/list ([block (in-list (hash-ref document 'blocks))])
            (define text (fragments block plain-fragment))
            (match (hash-ref block 'kind)
              ['heading (string-append text "\n" (make-string (string-length text)
                                                                (if (= (hash-ref block 'level) 1) #\= #\-))
                                       "\n\n")]
              ['paragraph (string-append text "\n\n")]
              ['list-item (string-append "- " text "\n")]
              ['quote (string-append "> " text "\n\n")]
              [(or 'source 'example) (string-append "    " text "\n\n")]
              ['horizontal-rule "----------------------------------------\n\n"])))))

(define (render-html document)
  (string-append
   "<!doctype html>\n<html lang=\"" (html-escape (hash-ref document 'language) #t)
   "\">\n<head>\n<meta charset=\"utf-8\">\n<title>" (html-escape (hash-ref document 'title))
   "</title>\n</head>\n<body>\n"
   (apply string-append
          (for/list ([block (in-list (hash-ref document 'blocks))])
            (define text (fragments block html-fragment))
            (match (hash-ref block 'kind)
              ['heading (format "<h~a>~a</h~a>\n" (hash-ref block 'level) text (hash-ref block 'level))]
              ['paragraph (format "<p>~a</p>\n" text)]
              ['list-item (format "<li>~a</li>\n" text)]
              ['quote (format "<blockquote>~a</blockquote>\n" text)]
              [(or 'source 'example)
               (format "<pre><code class=\"language-~a\">~a</code></pre>\n"
                       (html-escape (hash-ref block 'language "") #t) text)]
              ['horizontal-rule "<hr>\n"])))
   "</body>\n</html>\n"))

(define (render-markdown document)
  (string-append
   "# " (markdown-escape (hash-ref document 'title)) "\n\n"
   (apply string-append
          (for/list ([block (in-list (hash-ref document 'blocks))])
            (define text (fragments block markdown-fragment))
            (match (hash-ref block 'kind)
              ['heading (format "~a ~a\n\n" (make-string (hash-ref block 'level) #\#) text)]
              ['paragraph (string-append text "\n\n")]
              ['list-item (string-append "- " text "\n")]
              ['quote (string-append "> " text "\n\n")]
              [(or 'source 'example)
               (format "```~a\n~a\n```\n\n" (hash-ref block 'language "")
                       (fragments block plain-fragment))]
              ['horizontal-rule "---\n\n"])))))

(define (render-jan document)
  (string-append
   "#+title: " (hash-ref document 'title) "\n\n"
   (apply string-append
          (for/list ([block (in-list (hash-ref document 'blocks))])
            (define text (fragments block jan-fragment))
            (match (hash-ref block 'kind)
              ['heading (format "~a ~a\n\n" (make-string (hash-ref block 'level) #\*) text)]
              ['paragraph (string-append text "\n\n")]
              ['list-item (string-append "- " text "\n")]
              ['quote (format "#+begin_quote\n~a\n#+end_quote\n\n" text)]
              ['source (format "#+begin_src ~a\n~a\n#+end_src\n\n"
                               (hash-ref block 'language "")
                               (fragments block plain-fragment))]
              ['example (format "#+begin_example\n~a\n#+end_example\n\n"
                                (fragments block plain-fragment))]
              ['horizontal-rule "-----\n\n"])))))

(define (render-native-document backend document)
  (case backend
    [(plain-text) (render-plain document)]
    [(html) (render-html document)]
    [(markdown) (render-markdown document)]
    [(normalized-jan normalized-org) (render-jan document)]
    [else #f]))
