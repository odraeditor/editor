#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/file
         racket/list
         racket/match
         racket/port)

(provide
 current-project-record-format-version
 maximum-project-record-bytes
 maximum-project-identity-bytes
 maximum-project-name-bytes
 maximum-project-directories
 maximum-project-path-bytes
 maximum-project-diagnostic-bytes
 (struct-out odra-project-directory)
 (struct-out odra-project-record)
 (struct-out odra-project-provenance)
 (struct-out odra-project-proposal)
 (struct-out odra-project-diagnostic)
 (contract-out
  [project-directory
   (-> #:id string? #:path string? #:trust (or/c 'untrusted 'trusted)
       odra-project-directory?)]
  [project
   (-> #:format-version exact-positive-integer?
       #:id string?
       #:generation exact-positive-integer?
       #:name string?
       #:directories (listof odra-project-directory?)
       odra-project-record?)]
  [project-record->module-bytes (-> odra-project-record? immutable-bytes?)]
  [project-record-module-parse
   (-> bytes? path-string? (or/c odra-project-proposal? odra-project-diagnostic?))]
  [project-record-module-load
   (-> path-string? (or/c odra-project-proposal? odra-project-diagnostic?))]))

(define current-project-record-format-version 1)
(define maximum-project-record-bytes (* 4 1024 1024))
(define maximum-project-identity-bytes 128)
(define maximum-project-name-bytes 1024)
(define maximum-project-directories 256)
(define maximum-project-path-bytes 4096)
(define maximum-project-diagnostic-bytes 4096)
(define module-header #"#lang odra/config\n")
(define allowed-diagnostic-codes
  '(io record-size invalid-language invalid-encoding invalid-syntax
       invalid-schema unsupported-version))

(define (immutable-bytes? value)
  (and (bytes? value) (immutable? value)))

(define (bounded-string? value maximum)
  (and (string? value)
       (positive? (string-length value))
       (not (string-contains-nul? value))
       (<= (bytes-length (string->bytes/utf-8 value)) maximum)))

(define (string-contains-nul? value)
  (for/or ([character (in-string value)]) (char=? character #\nul)))

(define (identity-string? value)
  (and (bounded-string? value maximum-project-identity-bytes)
       (regexp-match? #px"^[a-z0-9]+(?:-[a-z0-9]+)*$" value)))

(define (immutable-text value)
  (string->immutable-string value))

(struct odra-project-directory (id path trust)
  #:transparent
  #:guard
  (lambda (id path trust _)
    (unless (identity-string? id)
      (raise-argument-error 'project-directory "a bounded canonical identity" id))
    (unless (bounded-string? path maximum-project-path-bytes)
      (raise-argument-error 'project-directory "a bounded nonempty UTF-8 path" path))
    (unless (memq trust '(untrusted trusted))
      (raise-argument-error 'project-directory "'untrusted or 'trusted" trust))
    (values (immutable-text id) (immutable-text path) trust)))

(struct odra-project-record (format-version id generation name directories)
  #:transparent
  #:guard
  (lambda (format-version id generation name directories _)
    (unless (= format-version current-project-record-format-version)
      (raise-arguments-error 'project
                             "unsupported Project record format"
                             "format-version" format-version))
    (unless (identity-string? id)
      (raise-argument-error 'project "a bounded canonical identity" id))
    (unless (and (exact-positive-integer? generation)
                 (<= generation (sub1 (expt 2 64))))
      (raise-argument-error 'project "an unsigned nonzero 64-bit generation" generation))
    (unless (bounded-string? name maximum-project-name-bytes)
      (raise-argument-error 'project "a bounded nonempty UTF-8 name" name))
    (unless (and (list? directories)
                 (<= 1 (length directories) maximum-project-directories)
                 (andmap odra-project-directory? directories))
      (raise-argument-error 'project "a bounded nonempty directory list" directories))
    (define ids (map odra-project-directory-id directories))
    (define paths (map odra-project-directory-path directories))
    (unless (= (length ids) (length (remove-duplicates ids)))
      (raise-arguments-error 'project "duplicate directory identity" "ids" ids))
    (unless (= (length paths) (length (remove-duplicates paths)))
      (raise-arguments-error 'project "duplicate directory path" "paths" paths))
    (values format-version
            (immutable-text id)
            generation
            (immutable-text name)
            (for/list ([directory (in-list directories)]) directory))))

(struct odra-project-provenance (source line column position span)
  #:transparent
  #:guard
  (lambda (source line column position span _)
    (unless (and (string? source)
                 (exact-nonnegative-integer? line)
                 (exact-nonnegative-integer? column)
                 (exact-nonnegative-integer? position)
                 (exact-nonnegative-integer? span))
      (raise-arguments-error 'odra-project-provenance
                             "invalid copied source provenance"
                             "source" source
                             "line" line
                             "column" column))
    (values (immutable-text source) line column position span)))

(struct odra-project-proposal (record provenance module-bytes)
  #:transparent
  #:guard
  (lambda (record provenance module-bytes _)
    (unless (and (odra-project-record? record)
                 (odra-project-provenance? provenance)
                 (bytes? module-bytes)
                 (<= (bytes-length module-bytes) maximum-project-record-bytes))
      (raise-arguments-error 'odra-project-proposal "invalid bounded Project proposal"))
    (values record provenance (bytes->immutable-bytes module-bytes))))

(struct odra-project-diagnostic (code message provenance limit actual)
  #:transparent
  #:guard
  (lambda (code message provenance limit actual _)
    (unless (and (memq code allowed-diagnostic-codes)
                 (string? message)
                 (<= (bytes-length (string->bytes/utf-8 message))
                     maximum-project-diagnostic-bytes)
                 (odra-project-provenance? provenance)
                 (exact-nonnegative-integer? limit)
                 (exact-nonnegative-integer? actual))
      (raise-arguments-error 'odra-project-diagnostic "invalid bounded diagnostic"))
    (values code (immutable-text message) provenance limit actual)))

(define (project-directory #:id id #:path path #:trust trust)
  (odra-project-directory id path trust))

(define (project #:format-version format-version
                 #:id id
                 #:generation generation
                 #:name name
                 #:directories directories)
  (odra-project-record format-version id generation name directories))

;; project-record->module-bytes emits the sole canonical editor-managed module shape.
(define (project-record->module-bytes record)
  (define output (open-output-bytes))
  (write-bytes module-header output)
  (display "\n(project\n  #:format-version " output)
  (display (odra-project-record-format-version record) output)
  (display "\n  #:id " output)
  (write (odra-project-record-id record) output)
  (display "\n  #:generation " output)
  (display (odra-project-record-generation record) output)
  (display "\n  #:name " output)
  (write (odra-project-record-name record) output)
  (display "\n  #:directories\n  (list" output)
  (for ([directory (in-list (odra-project-record-directories record))])
    (display "\n    (project-directory\n      #:id " output)
    (write (odra-project-directory-id directory) output)
    (display "\n      #:path " output)
    (write (odra-project-directory-path directory) output)
    (display "\n      #:trust '" output)
    (display (odra-project-directory-trust directory) output)
    (display ")" output))
  (display "))\n" output)
  (bytes->immutable-bytes (get-output-bytes output)))

;; project-record-module-parse reads data through a closed declarative grammar.
(define (project-record-module-parse module-bytes source)
  (define source-text (source->string source))
  (define base-provenance (odra-project-provenance source-text 0 0 0 0))
  (cond
    [(> (bytes-length module-bytes) maximum-project-record-bytes)
     (diagnostic 'record-size
                 "Project record exceeds the module byte limit"
                 base-provenance
                 maximum-project-record-bytes
                 (bytes-length module-bytes))]
    [(not (bytes-prefix? module-bytes module-header))
     (diagnostic 'invalid-language
                 "Project record must begin with #lang odra/config"
                 base-provenance)]
    [else
     (define body-bytes (subbytes module-bytes (bytes-length module-header)))
     (define body
       (with-handlers ([exn:fail?
                        (lambda (failure)
                          (diagnostic 'invalid-encoding
                                      (exn-message failure)
                                      base-provenance))])
         (bytes->string/utf-8 body-bytes #f)))
     (if (odra-project-diagnostic? body)
         body
         (parse-module-body module-bytes source-text body base-provenance))]))

;; project-record-module-load bounds the file before and during its copied read.
(define (project-record-module-load path)
  (define source (source->string path))
  (define provenance (odra-project-provenance source 0 0 0 0))
  (with-handlers ([exn:fail:filesystem?
                   (lambda (failure)
                     (diagnostic 'io (exn-message failure) provenance))])
    (define observed-size (file-size path))
    (if (> observed-size maximum-project-record-bytes)
        (diagnostic 'record-size
                    "Project record exceeds the module byte limit"
                    provenance
                    maximum-project-record-bytes
                    observed-size)
        (call-with-input-file path
          (lambda (input)
            (define bytes (read-bytes (add1 maximum-project-record-bytes) input))
            (project-record-module-parse
             (if (eof-object? bytes) #"" bytes)
             source))
          #:mode 'binary))))

(define (parse-module-body module-bytes source body base-provenance)
  (with-handlers ([exn:fail:project-record?
                   (lambda (failure)
                     (diagnostic (exn:fail:project-record-code failure)
                                 (exn-message failure)
                                 base-provenance))]
                  [exn:fail:read?
                   (lambda (failure)
                     (diagnostic 'invalid-syntax
                                 (exn-message failure)
                                 base-provenance))]
                  [exn:fail?
                   (lambda (failure)
                     (diagnostic 'invalid-schema
                                 (exn-message failure)
                                 base-provenance))])
    (define input (open-input-string body source))
    (port-count-lines! input)
    (set-port-next-location! input 2 0 (add1 (bytes-length module-header)))
    (parameterize ([read-accept-reader #f]
                   [read-accept-lang #f])
      (define form (read-syntax source input))
      (when (eof-object? form)
        (error 'project-record-module "missing Project form"))
      (define trailing (read-syntax source input))
      (unless (eof-object? trailing)
        (error 'project-record-module "unexpected form after Project record"))
      (define provenance (syntax->provenance source form))
      (define fields (parse-keyword-fields 'project (syntax->datum form)
                                           '(#:format-version #:id #:generation
                                             #:name #:directories)))
      (define format-version (hash-ref fields '#:format-version))
      (unless (= format-version current-project-record-format-version)
        (return-unsupported-version format-version))
      (define record
        (project
         #:format-version format-version
         #:id (hash-ref fields '#:id)
         #:generation (hash-ref fields '#:generation)
         #:name (hash-ref fields '#:name)
         #:directories (parse-directory-list (hash-ref fields '#:directories))))
      (odra-project-proposal record provenance module-bytes))))

(define (parse-directory-list datum)
  (match datum
    [(list 'list directory-data ...)
     (for/list ([directory-datum (in-list directory-data)])
       (define fields
         (parse-keyword-fields 'project-directory directory-datum
                               '(#:id #:path #:trust)))
       (project-directory
        #:id (hash-ref fields '#:id)
        #:path (hash-ref fields '#:path)
        #:trust (parse-trust (hash-ref fields '#:trust))))]
    [_ (error 'project "directories must use one literal list")]))

(define (parse-trust datum)
  (match datum
    [(list 'quote (? symbol? trust))
     (unless (memq trust '(untrusted trusted))
       (error 'project-directory "unknown trust value: ~a" trust))
     trust]
    [_ (error 'project-directory "trust must be 'untrusted or 'trusted")]))

(define (parse-keyword-fields expected-head datum required-keywords)
  (unless (and (list? datum) (pair? datum) (eq? (car datum) expected-head))
    (error expected-head "expected one ~a form" expected-head))
  (define parts (cdr datum))
  (unless (even? (length parts))
    (error expected-head "keyword fields must have values"))
  (define fields
    (let loop ([remaining parts] [result (hash)])
      (if (null? remaining)
          result
          (let ([keyword (car remaining)] [value (cadr remaining)])
            (unless (keyword? keyword)
              (error expected-head "expected a keyword, received ~e" keyword))
            (unless (memq keyword required-keywords)
              (error expected-head "unknown field ~a" keyword))
            (when (hash-has-key? result keyword)
              (error expected-head "duplicate field ~a" keyword))
            (loop (cddr remaining) (hash-set result keyword value))))))
  (for ([keyword (in-list required-keywords)])
    (unless (hash-has-key? fields keyword)
      (error expected-head "missing field ~a" keyword)))
  fields)

(define (return-unsupported-version version)
  (raise
   (exn:fail:project-record
    (format "unsupported Project record format version: ~a" version)
    (current-continuation-marks)
    'unsupported-version)))

(struct exn:fail:project-record exn:fail (code) #:transparent)

(define (syntax->provenance source syntax)
  (odra-project-provenance
   source
   (or (syntax-line syntax) 0)
   (or (syntax-column syntax) 0)
   (or (syntax-position syntax) 0)
   (or (syntax-span syntax) 0)))

(define (source->string source)
  (immutable-text (if (path? source) (path->string source) source)))

(define (bytes-prefix? bytes prefix)
  (and (>= (bytes-length bytes) (bytes-length prefix))
       (bytes=? (subbytes bytes 0 (bytes-length prefix)) prefix)))

(define (diagnostic code message provenance [limit 0] [actual 0])
  (define encoded (string->bytes/utf-8 message))
  (define bounded-message
    (if (<= (bytes-length encoded) maximum-project-diagnostic-bytes)
        message
        "Project record diagnostic exceeded the message byte limit"))
  (odra-project-diagnostic code bounded-message provenance limit actual))

(module+ test
  (require rackunit)

  (define first-directory
    (project-directory #:id "dir-1" #:path "/tmp/odra/λ" #:trust 'trusted))
  (define second-directory
    (project-directory #:id "dir-2" #:path "/tmp/notes" #:trust 'untrusted))
  (define record
    (project #:format-version 1
             #:id "project-1"
             #:generation 7
             #:name "Odra λ"
             #:directories (list first-directory second-directory)))
  (define rendered (project-record->module-bytes record))
  (define parsed (project-record-module-parse rendered "/tmp/project-1.rkt"))

  (test-case "Project modules round-trip copied fields"
    (check-true (immutable? rendered))
    (check-true (odra-project-proposal? parsed))
    (check-equal? (odra-project-proposal-record parsed) record)
    (check-equal? (odra-project-proposal-module-bytes parsed) rendered)
    (check-equal? (odra-project-provenance-source
                   (odra-project-proposal-provenance parsed))
                  "/tmp/project-1.rkt")
    (check-equal? (odra-project-provenance-line
                   (odra-project-proposal-provenance parsed))
                  3))

  (test-case "loader bounds proposal from a real module"
    (define path (make-temporary-file "odra-project-record-~a.rkt"))
    (dynamic-wind
     (lambda () (call-with-output-file path #:exists 'truncate/replace
                  (lambda (output) (write-bytes rendered output))
                  #:mode 'binary))
     (lambda ()
       (define loaded (project-record-module-load path))
       (check-true (odra-project-proposal? loaded))
       (check-equal? (odra-project-proposal-record loaded) record))
     (lambda () (delete-file path))))

  (test-case "schema rejects malformed field sets"
    (for ([bytes (in-list
                  (list
                   #"#lang odra/config\n\n(project #:format-version 1)\n"
                   #"#lang odra/config\n\n(project #:format-version 1 #:format-version 1 #:id \"p\" #:generation 1 #:name \"P\" #:directories (list (project-directory #:id \"d\" #:path \"/tmp\" #:trust 'untrusted)))\n"
                   #"#lang odra/config\n\n(project #:format-version 1 #:id \"p\" #:generation 1 #:name \"P\" #:unknown 1 #:directories (list (project-directory #:id \"d\" #:path \"/tmp\" #:trust 'untrusted)))\n"
                   (bytes-append rendered #"(displayln \"executed\")\n")))])
      (define result (project-record-module-parse bytes "/tmp/rejected.rkt"))
      (check-true (odra-project-diagnostic? result))
      (check-eq? (odra-project-diagnostic-code result) 'invalid-schema)))

  (test-case "encoding and size failures are explicit"
    (define invalid-language
      (project-record-module-parse #"#lang racket/base\n(project)" "bad.rkt"))
    (check-eq? (odra-project-diagnostic-code invalid-language) 'invalid-language)
    (define invalid-encoding
      (project-record-module-parse
       (bytes-append module-header #"\377")
       "bad-encoding.rkt"))
    (check-eq? (odra-project-diagnostic-code invalid-encoding) 'invalid-encoding)
    (define invalid-syntax
      (project-record-module-parse
       (bytes-append module-header #"\n(project")
       "bad-syntax.rkt"))
    (check-eq? (odra-project-diagnostic-code invalid-syntax) 'invalid-syntax)
    (define unsupported
      (project-record-module-parse
       #"#lang odra/config\n\n(project #:format-version 2 #:id \"p\" #:generation 1 #:name \"P\" #:directories (list (project-directory #:id \"d\" #:path \"/tmp\" #:trust 'untrusted)))\n"
       "future.rkt"))
    (check-eq? (odra-project-diagnostic-code unsupported) 'unsupported-version)
    (define oversized
      (project-record-module-parse
       (make-bytes (add1 maximum-project-record-bytes))
       "large.rkt"))
    (check-eq? (odra-project-diagnostic-code oversized) 'record-size))

  (test-case "constructor rejects ambiguous records"
    (check-exn exn:fail:contract?
               (lambda ()
                 (project-directory #:id "../escape" #:path "/tmp" #:trust 'trusted)))
    (check-exn exn:fail:contract?
               (lambda ()
                 (project #:format-version 1
                          #:id "project-1"
                          #:generation 1
                          #:name "Project"
                          #:directories (list first-directory first-directory))))
    (check-exn exn:fail:contract?
               (lambda ()
                 (project #:format-version 2
                          #:id "project-1"
                          #:generation 1
                          #:name "Project"
                          #:directories (list first-directory)))))

  (test-case "filesystem failure remains one copied diagnostic"
    (define missing (project-record-module-load "/tmp/odra-missing-project-record.rkt"))
    (check-true (odra-project-diagnostic? missing))
    (check-eq? (odra-project-diagnostic-code missing) 'io)))
