#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/list
         racket/match
         racket/string)

(provide resolve-citations
         render-citations
         render-bibliography
         complete-citation-keys)

(define (source-valid? source)
  (and (exact-positive-integer? (hash-ref source 'resource #f))
       (exact-positive-integer? (hash-ref source 'revision #f))
       (memq (hash-ref source 'format #f) '(csl-json bibtex))
       (bytes? (hash-ref source 'digest #f))
       (positive? (bytes-length (hash-ref source 'digest)))))

(define (entry-valid? entry source-count)
  (and (hash-ref entry 'valid? #f)
       (symbol? (hash-ref entry 'key #f))
       (string? (hash-ref entry 'author #f))
       (string? (hash-ref entry 'title #f))
       (exact-positive-integer? (hash-ref entry 'year #f))
       (exact-nonnegative-integer? (hash-ref entry 'source #f))
       (< (hash-ref entry 'source) source-count)))

(define (resolve-citations processor sources entries references)
  (define source-ids (map (lambda (source) (hash-ref source 'resource #f)) sources))
  (define keys (map (lambda (entry) (hash-ref entry 'key #f)) entries))
  (and (hash-ref processor 'available? #f)
       (hash-ref processor 'trusted? #f)
       (exact-positive-integer? (hash-ref processor 'generation #f))
       (pair? sources)
       (andmap source-valid? sources)
       (= (length source-ids) (length (remove-duplicates source-ids)))
       (pair? entries)
       (andmap (lambda (entry) (entry-valid? entry (length sources))) entries)
       (= (length keys) (length (remove-duplicates keys)))
       (let ([table (for/hasheq ([entry (in-list entries)] [index (in-naturals)])
                      (values (hash-ref entry 'key) index))])
         (and (andmap (lambda (reference) (hash-has-key? table (hash-ref reference 'key #f))) references)
              (for/list ([reference (in-list references)] [index (in-naturals)])
                (hasheq 'reference index 'entry (hash-ref table (hash-ref reference 'key))))))))

(define (escape-html value attribute?)
  (define escaped (string-replace (string-replace (string-replace value "&" "&amp;") "<" "&lt;") ">" "&gt;"))
  (if attribute? (string-replace escaped "\"" "&quot;") escaped))

(define (escape-latex value)
  (apply string-append
         (for/list ([character (in-string value)])
           (case character
             [(#\\) "\\textbackslash{}"]
             [(#\& #\% #\$ #\# #\_ #\{ #\}) (string #\\ character)]
             [(#\~) "\\textasciitilde{}"]
             [(#\^) "\\textasciicircum{}"]
             [else (string character)]))))

(define (render-text backend value [attribute? #f])
  (case backend
    [(html) (escape-html value attribute?)]
    [(latex) (escape-latex value)]
    [else value]))

(define (render-citation backend processor reference entry)
  (define variant (hash-ref reference 'variant))
  (define author (hash-ref entry 'author))
  (define year (number->string (hash-ref entry 'year)))
  (define locator (hash-ref reference 'locator ""))
  (cond
    [(eq? processor 'latex)
     (define command
       (case variant [(narrative) "textcite"] [(author-only) "citeauthor"]
         [(suppress-author) "citeyear"] [else "cite"]))
     (string-append "\\" command
                    (if (string=? locator "") "" (format "[~a]" (escape-latex locator)))
                    "{" (escape-latex (symbol->string (hash-ref reference 'key))) "}")]
    [else
     (define rendered-author
       (if (and (eq? backend 'html) (hash-ref entry 'url #f))
           (format "<a href=\"~a\">~a</a>"
                   (escape-html (hash-ref entry 'url) #t) (escape-html author #f))
           (render-text backend author)))
     (case variant
       [(narrative) (format "~a (~a~a)" rendered-author year
                            (if (string=? locator "") "" (string-append ", " (render-text backend locator))))]
       [(author-only) rendered-author]
       [(suppress-author) (format "(~a~a)" year
                                  (if (string=? locator "") "" (string-append ", " (render-text backend locator))))]
       [else (format "(~a, ~a~a)" rendered-author year
                     (if (string=? locator "") "" (string-append ", " (render-text backend locator))))])]))

(define (render-citations backend processor entries references resolutions)
  (string-join
   (for/list ([resolution (in-list resolutions)])
     (define reference (list-ref references (hash-ref resolution 'reference)))
     (define entry (list-ref entries (hash-ref resolution 'entry)))
     (string-append (render-text backend (hash-ref reference 'prefix ""))
                    (render-citation backend processor reference entry)
                    (render-text backend (hash-ref reference 'suffix ""))))
   "; "))

(define (render-bibliography backend entries #:minimum-year [minimum-year 0])
  (define selected
    (sort (filter (lambda (entry) (>= (hash-ref entry 'year) minimum-year)) entries)
          string<? #:key (lambda (entry) (hash-ref entry 'author))))
  (apply string-append
         (for/list ([entry (in-list selected)])
           (case backend
             [(markdown) (format "- ~a. *~a*. ~a.\n" (hash-ref entry 'author)
                                 (hash-ref entry 'title) (hash-ref entry 'year))]
             [(html) (format "<li id=\"ref-~a\">~a. <cite>~a</cite>. ~a</li>\n"
                             (hash-ref entry 'key) (escape-html (hash-ref entry 'author) #f)
                             (escape-html (hash-ref entry 'title) #f) (hash-ref entry 'year))]
             [else (format "~a. ~a. ~a.\n" (hash-ref entry 'author)
                           (hash-ref entry 'title) (hash-ref entry 'year))]))))

(define (complete-citation-keys prefix sources entries)
  (sort
   (for/list ([entry (in-list entries)]
              #:when (string-prefix? (symbol->string (hash-ref entry 'key)) prefix))
     (define source (list-ref sources (hash-ref entry 'source)))
     (hasheq 'key (hash-ref entry 'key) 'title (hash-ref entry 'title)
             'resource (hash-ref source 'resource) 'revision (hash-ref source 'revision)))
   symbol<? #:key (lambda (completion) (hash-ref completion 'key))))
