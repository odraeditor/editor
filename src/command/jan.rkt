#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list)

(provide
 maximum-jan-templates
 maximum-jan-completion-sources
 maximum-jan-completion-candidates
 maximum-jan-configuration-bytes
 factory-jan-editing-configuration
 (struct-out odra-jan-presentation)
 (struct-out odra-jan-template)
 (struct-out odra-jan-completion-source)
 (struct-out odra-jan-preview-selection)
 (struct-out odra-jan-editing-configuration)
 (contract-out
  [jan-presentation
   (->* ()
        (#:compose-markup? boolean?
         #:prettify-entities? boolean?
         #:visual-indent-width exact-nonnegative-integer?
         #:number-headings? boolean?
         #:hard-indent-width exact-positive-integer?)
        odra-jan-presentation?)]
  [jan-template
   (-> symbol? symbol? string? odra-jan-template?)]
  [jan-completion-source
   (-> symbol? symbol? (listof string?) odra-jan-completion-source?)]
  [jan-preview-selection
   (->* ()
        (#:latex symbol? #:image symbol?)
        odra-jan-preview-selection?)]
  [jan-editing-configuration
   (->* ()
        (#:startup-visibility symbol?
         #:presentation odra-jan-presentation?
         #:templates (listof odra-jan-template?)
         #:completion-sources (listof odra-jan-completion-source?)
         #:preview odra-jan-preview-selection?)
        odra-jan-editing-configuration?)]
  [normalize-jan-editing-configuration
   (-> any/c odra-jan-editing-configuration?)]))

(define maximum-jan-templates 256)
(define maximum-jan-completion-sources 256)
(define maximum-jan-completion-candidates 512)
(define maximum-jan-configuration-bytes (* 1024 1024))
(define maximum-jan-name-bytes 96)
(define maximum-jan-template-bytes (* 64 1024))
(define maximum-jan-candidate-bytes (* 16 1024))

(define admitted-startup-visibility '(overview contents show-all))
(define admitted-template-contexts
  '(document heading list drawer block table paragraph))
(define admitted-completion-kinds
  '(keyword task-state tag property link-form target block-name language
            header-argument file-setting))
(define admitted-preview-adapters
  '(source factory-latex factory-image))

(define (immutable-text value)
  (string->immutable-string value))

(define (text-bytes value)
  (bytes-length (string->bytes/utf-8 value)))

(define (bounded-symbol? value)
  (and (symbol? value)
       (positive? (string-length (symbol->string value)))
       (<= (text-bytes (symbol->string value)) maximum-jan-name-bytes)))

(define (bounded-text? value maximum [empty-allowed? #f])
  (and (string? value)
       (or empty-allowed? (positive? (string-length value)))
       (not (for/or ([character (in-string value)]) (char=? character #\nul)))
       (<= (text-bytes value) maximum)))

(struct odra-jan-presentation
  (compose-markup? prettify-entities? visual-indent-width number-headings?
                   hard-indent-width)
  #:transparent
  #:guard
  (lambda (compose-markup? prettify-entities? visual-indent-width number-headings?
                           hard-indent-width _)
    (unless (and (boolean? compose-markup?)
                 (boolean? prettify-entities?)
                 (<= 0 visual-indent-width 16)
                 (boolean? number-headings?)
                 (<= 1 hard-indent-width 16))
      (raise-arguments-error 'odra-jan-presentation
                             "invalid Jan presentation policy"))
    (values compose-markup? prettify-entities? visual-indent-width
            number-headings? hard-indent-width)))

(struct odra-jan-template (key context source)
  #:transparent
  #:guard
  (lambda (key context source _)
    (unless (and (bounded-symbol? key)
                 (memq context admitted-template-contexts)
                 (bounded-text? source maximum-jan-template-bytes))
      (raise-arguments-error 'odra-jan-template
                             "invalid bounded Jan structure template"))
    (values key context (immutable-text source))))

(struct odra-jan-completion-source (name kind candidates)
  #:transparent
  #:guard
  (lambda (name kind candidates _)
    (unless (and (bounded-symbol? name)
                 (memq kind admitted-completion-kinds)
                 (list? candidates)
                 (pair? candidates)
                 (<= (length candidates) maximum-jan-completion-candidates)
                 (andmap (lambda (candidate)
                           (bounded-text? candidate maximum-jan-candidate-bytes))
                         candidates)
                 (= (length candidates) (length (remove-duplicates candidates))))
      (raise-arguments-error 'odra-jan-completion-source
                             "invalid bounded Jan completion source"))
    (values name kind (map immutable-text candidates))))

(struct odra-jan-preview-selection (latex image)
  #:transparent
  #:guard
  (lambda (latex image _)
    (unless (and (memq latex admitted-preview-adapters)
                 (memq image admitted-preview-adapters)
                 (not (eq? latex 'factory-image))
                 (not (eq? image 'factory-latex)))
      (raise-arguments-error 'odra-jan-preview-selection
                             "preview selection cannot acquire undeclared authority"))
    (values latex image)))

(struct odra-jan-editing-configuration
  (startup-visibility presentation templates completion-sources preview)
  #:transparent
  #:guard
  (lambda (startup-visibility presentation templates completion-sources preview _)
    (unless (and (memq startup-visibility admitted-startup-visibility)
                 (odra-jan-presentation? presentation)
                 (list? templates)
                 (<= (length templates) maximum-jan-templates)
                 (andmap odra-jan-template? templates)
                 (list? completion-sources)
                 (<= (length completion-sources) maximum-jan-completion-sources)
                 (andmap odra-jan-completion-source? completion-sources)
                 (odra-jan-preview-selection? preview))
      (raise-arguments-error 'odra-jan-editing-configuration
                             "invalid Jan editing configuration"))
    (define template-keys (map odra-jan-template-key templates))
    (define source-names (map odra-jan-completion-source-name completion-sources))
    (unless (and (= (length template-keys) (length (remove-duplicates template-keys)))
                 (= (length source-names) (length (remove-duplicates source-names))))
      (raise-arguments-error 'odra-jan-editing-configuration
                             "template keys and completion source names must be unique"))
    (define retained-bytes
      (+ (for/sum ([template (in-list templates)])
           (+ (text-bytes (symbol->string (odra-jan-template-key template)))
              (text-bytes (symbol->string
                           (odra-jan-template-context template)))
              (text-bytes (odra-jan-template-source template))))
         (for/sum ([completion-source (in-list completion-sources)])
           (+ (text-bytes
               (symbol->string (odra-jan-completion-source-name completion-source)))
              (text-bytes
               (symbol->string (odra-jan-completion-source-kind completion-source)))
              (for/sum ([candidate (in-list
                                    (odra-jan-completion-source-candidates
                                     completion-source))])
                (text-bytes candidate))))))
    (unless (<= retained-bytes maximum-jan-configuration-bytes)
      (raise-arguments-error 'odra-jan-editing-configuration
                             "Jan configuration exceeds the copied byte limit"
                             "limit" maximum-jan-configuration-bytes
                             "actual" retained-bytes))
    (values startup-visibility presentation (append templates '())
            (append completion-sources '()) preview)))

(define (jan-presentation #:compose-markup? [compose-markup? #t]
                          #:prettify-entities? [prettify-entities? #t]
                          #:visual-indent-width [visual-indent-width 2]
                          #:number-headings? [number-headings? #f]
                          #:hard-indent-width [hard-indent-width 2])
  (odra-jan-presentation compose-markup? prettify-entities? visual-indent-width
                         number-headings? hard-indent-width))

(define (jan-template key context source)
  (odra-jan-template key context source))

(define (jan-completion-source name kind candidates)
  (odra-jan-completion-source name kind candidates))

(define (jan-preview-selection #:latex [latex 'factory-latex]
                               #:image [image 'source])
  (odra-jan-preview-selection latex image))

(define factory-jan-editing-configuration
  (odra-jan-editing-configuration
   'contents
   (jan-presentation)
   '()
   '()
   (jan-preview-selection)))

(define (jan-editing-configuration
         #:startup-visibility [startup-visibility 'contents]
         #:presentation [presentation (jan-presentation)]
         #:templates [templates '()]
         #:completion-sources [completion-sources '()]
         #:preview [preview (jan-preview-selection)])
  (odra-jan-editing-configuration startup-visibility presentation templates
                                  completion-sources preview))

(define (normalize-jan-editing-configuration value)
  (cond
    [(not value) factory-jan-editing-configuration]
    [(odra-jan-editing-configuration? value) value]
    [(hash? value)
     (jan-editing-configuration
      #:startup-visibility (hash-ref value 'startup-visibility 'contents)
      #:presentation (hash-ref value 'presentation (jan-presentation))
      #:templates (hash-ref value 'templates '())
      #:completion-sources (hash-ref value 'completion-sources '())
      #:preview (hash-ref value 'preview (jan-preview-selection)))]
    [else
     (raise-arguments-error 'normalize-jan-editing-configuration
                            "expected a Jan editing configuration or hash"
                            "value" value)]))

(module+ test
  (require rackunit)

  (define configured
    (jan-editing-configuration
     #:startup-visibility 'overview
     #:templates (list (jan-template 'note 'block "#+begin_note\n\n#+end_note\n"))
     #:completion-sources
     (list (jan-completion-source 'team-states 'task-state '("READY" "DONE")))
     #:preview (jan-preview-selection #:image 'factory-image)))
  (check-equal? (odra-jan-editing-configuration-startup-visibility configured)
                'overview)
  (check-true (immutable? (odra-jan-template-source
                           (car (odra-jan-editing-configuration-templates configured)))))
  (check-equal? (normalize-jan-editing-configuration #f)
                factory-jan-editing-configuration)
  (check-exn exn:fail?
             (lambda ()
               (jan-editing-configuration
                #:templates
                (list (jan-template 'same 'block "#+begin_a\n#+end_a\n")
                      (jan-template 'same 'drawer ":A:\n:END:\n")))))
  (check-exn exn:fail?
             (lambda ()
               (jan-preview-selection #:latex 'factory-image))))
