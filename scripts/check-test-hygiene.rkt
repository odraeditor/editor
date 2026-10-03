#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         racket/list
         racket/path
         racket/string)

(provide check-odin-source
         check-racket-source)

(define maximum-test-name-length 48)
(define odin-test-declaration
  #px"^\\s*([A-Za-z_][A-Za-z0-9_]*)\\s*::\\s*proc\\s*\\(")
(define odin-case-table
  #px"^(\\s*)((?:[A-Za-z_][A-Za-z0-9_]*_)?(?:cases|fixtures|scenarios))\\s*:=\\s*\\[\\?\\]")
(define racket-test-case
  #px"\\(test-case\\s+\"((?:\\\\.|[^\"\\\\])*)\"")

(struct finding (line message) #:transparent)

(define (blank-line? line)
  (string=? (string-trim line) ""))

(define (previous-significant-index lines start)
  (let loop ([index (sub1 start)])
    (cond
      [(negative? index) #f]
      [(blank-line? (list-ref lines index)) (loop (sub1 index))]
      [else index])))

(define (block-comment-before lines annotation-index)
  (define end (previous-significant-index lines annotation-index))
  (and end
       (regexp-match? #px"\\*/\\s*$" (list-ref lines end))
       (let loop ([index end])
         (cond
           [(negative? index) #f]
           [(regexp-match? #px"/\\*" (list-ref lines index))
            (take (drop lines index) (add1 (- end index)))]
           [else (loop (sub1 index))]))))

(define (declaration-after lines annotation-index)
	(let skip ([index (add1 annotation-index)] [comment #f])
    (cond
		[(>= index (length lines)) (values #f #f comment)]
      [else
       (define line (list-ref lines index))
       (cond
		 [(blank-line? line) (skip (add1 index) comment)]
         [(regexp-match? #px"^\\s*/\\*" line)
		  (let consume ([comment-index index] [comment-lines '()])
            (cond
			  [(>= comment-index (length lines)) (values #f #f (reverse comment-lines))]
              [(regexp-match? #px"\\*/\\s*$" (list-ref lines comment-index))
			   (skip (add1 comment-index)
					 (reverse (cons (list-ref lines comment-index) comment-lines)))]
			  [else
			   (consume (add1 comment-index)
						(cons (list-ref lines comment-index) comment-lines))]))]
         [else
          (define matched (regexp-match odin-test-declaration line))
		  (values index (and matched (cadr matched)) comment)])])))

(define (block-comment-text lines)
  (and lines
       (string-trim
        (regexp-replace*
         #px"(^/\\*+|\\*/$|^\\s*\\*\\s?)"
         (string-join (map string-trim lines) " ")
         ""))))

(define (comment-restates-name? comment name)
  (and comment
       name
       (string-prefix? comment (string-append name " "))))

(define (check-odin-test-declarations lines)
  (for/fold ([findings '()]) ([(line index) (in-indexed (in-list lines))]
                              #:when (regexp-match? #px"^\\s*@\\(test\\)\\s*$" line))
	(define-values (declaration-index name comment-after)
      (declaration-after lines index))
	(define comment
	  (block-comment-text (or comment-after (block-comment-before lines index))))
    (define line-number (add1 (or declaration-index index)))
    (define next-findings
      (if name
          findings
          (cons (finding line-number "cannot resolve the Odin test declaration") findings)))
    (define named-findings
      (if (and name (> (string-length name) maximum-test-name-length))
          (cons
           (finding line-number
                    (format "test name has ~a characters: ~a"
                            (string-length name)
                            name))
           next-findings)
          next-findings))
	(cond
	  [(or (not comment) (string=? comment ""))
	   (cons (finding line-number
				  (format "test has no adjacent explanatory comment: ~a"
						  (or name "<unknown>")))
		 named-findings)]
	  [(comment-restates-name? comment name)
	   (cons (finding line-number
				  (format "comment repeats the test identifier: ~a" name))
		 named-findings)]
	  [else named-findings])))

(define (case-table-end lines start indentation)
  (define end-pattern
    (pregexp (format "^~a\\}\\s*$" (regexp-quote indentation))))
  (for/first ([line (in-list (drop lines (add1 start)))]
              [index (in-naturals (add1 start))]
              #:when (regexp-match? end-pattern line))
    index))

(define (check-odin-case-tables lines)
  (for/fold ([findings '()]) ([(line index) (in-indexed (in-list lines))])
    (define matched (regexp-match odin-case-table line))
    (cond
      [(not matched) findings]
      [else
       (define indentation (cadr matched))
       (define name (caddr matched))
       (define end (case-table-end lines index indentation))
       (define table-lines
         (if end
             (take (drop lines index) (add1 (- end index)))
             (list line)))
       (if (regexp-match? #px"\\bname\\s*[:=]" (string-join table-lines "\n"))
           findings
           (cons (finding (add1 index)
                          (format "parameter table has no explicit case names: ~a" name))
                 findings))])))

(define (check-odin-source source)
  (define lines (string-split source "\n" #:trim? #f))
  (append (check-odin-test-declarations lines)
          (check-odin-case-tables lines)))

(define (decode-racket-string contents)
  (with-handlers ([exn:fail? (lambda (_) contents)])
    (read (open-input-string (string-append "\"" contents "\"")))))

(define (check-racket-source source)
  (for/fold ([findings '()]) ([(line index) (in-indexed (in-list (string-split source "\n" #:trim? #f)))])
    (define matched (regexp-match racket-test-case line))
    (cond
      [(not matched) findings]
      [else
       (define title (decode-racket-string (cadr matched)))
       (if (> (string-length title) maximum-test-name-length)
           (cons
            (finding (add1 index)
                     (format "test-case title has ~a characters: ~a"
                             (string-length title)
                             title))
            findings)
           findings)])))

(define (source-file? path extension)
  (equal? (path-get-extension path) extension))

(define (ignored-path? path)
  (define parts (map path->string (explode-path path)))
  (ormap (lambda (part) (member part '(".build" ".git" "third_party" "vendor"))) parts))

(define (repository-files root extension)
  (sort
   (for/list ([path (in-directory root)]
              #:when (and (file-exists? path)
                          (source-file? path extension)
                          (not (ignored-path? (find-relative-path root path)))))
     path)
   path<?))

(define (report-file root path checker)
  (define relative (path->string (find-relative-path root path)))
  (for/list ([entry (in-list (reverse (checker (file->string path))))])
    (format "~a:~a: ~a" relative (finding-line entry) (finding-message entry))))

(module+ main
  (define root (simplify-path (current-directory)))
  (define failures
    (append
     (append-map (lambda (path) (report-file root path check-odin-source))
                 (repository-files root #".odin"))
     (append-map (lambda (path) (report-file root path check-racket-source))
                 (append (repository-files root #".rkt")
                         (repository-files root #".scrbl")))))
  (for-each displayln failures)
  (unless (null? failures) (exit 1))
  (displayln "Test source hygiene is valid."))

(module+ test
  (require rackunit)

  (test-case "Odin checks names and comments"
    (define source
      (string-append
       "/* Protects the short contract. */\n"
       "@(test)\n"
       "short_contract :: proc(t: ^testing.T) {}\n"
       "@(test)\n"
       "/* Explains the second contract. */\n"
       "another_contract :: proc(t: ^testing.T) {}\n"))
    (check-equal? (check-odin-source source) '()))

  (test-case "Odin rejects missing intent"
    (define findings
      (check-odin-source
       "@(test)\ncontract_without_comment :: proc(t: ^testing.T) {}\n"))
    (check-equal? (length findings) 1)
    (check-true (string-contains? (finding-message (car findings)) "no adjacent")))

  (test-case "Odin rejects identifier restatements"
    (define findings
      (check-odin-source
       "/* contract_name checks the contract. */\n@(test)\ncontract_name :: proc(t: ^testing.T) {}\n"))
    (check-equal? (length findings) 1)
    (check-true (string-contains? (finding-message (car findings)) "repeats")))

  (test-case "Odin requires named parameter rows"
    (define findings
      (check-odin-source
       (string-append
        "/* Protects decoding behavior. */\n"
        "@(test)\n"
        "decoding :: proc(t: ^testing.T) {\n"
        "\tcases := [?]string {\n\t\t\"x\",\n\t}\n}\n")))
    (check-equal? (length findings) 1)
    (check-true (string-contains? (finding-message (car findings)) "case names")))

  (test-case "Odin accepts named parameter rows"
    (define findings
      (check-odin-source
       (string-append
        "/* Protects decoding behavior. */\n"
        "@(test)\n"
        "decoding :: proc(t: ^testing.T) {\n"
        "\tcases := [?]struct {name: string, input: string} {\n"
        "\t\t{name = \"ascii\", input = \"x\"},\n\t}\n}\n")))
    (check-equal? findings '()))

  (test-case "RackUnit rejects long titles"
    (define findings
      (check-racket-source
       "(test-case \"this title is deliberately longer than forty eight characters total\" (void))"))
    (check-equal? (length findings) 1)))
