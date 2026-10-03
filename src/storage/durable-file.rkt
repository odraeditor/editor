#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require (prefix-in ffi: ffi/unsafe)
         ffi/unsafe/port
         racket/contract/base
         racket/file
         racket/list
         racket/path)

(provide
 (struct-out odra-durable-file-publication)
 (struct-out odra-durable-file-failure)
 (contract-out
  [durable-file-publish
   (->* (path-string? bytes?)
        (#:private-directories (listof path-string?)
         #:validate-stage procedure?
         #:recover-visible (or/c #f procedure?))
        (or/c odra-durable-file-publication? odra-durable-file-failure?))]
  [durable-file-publish-existing
   (->* (path-string? path-string?)
        (#:private-directories (listof path-string?)
         #:validate-stage procedure?)
        (or/c odra-durable-file-publication? odra-durable-file-failure?))]
  [durable-directory-synchronize
   (-> path-string? exact-nonnegative-integer?)]
  [durable-file-check
   (-> path-string? (or/c #f odra-durable-file-failure?))]))

(define maximum-diagnostic-bytes 4096)
(define staging-attempts 16)
(define owner-file-permissions #o600)
(define owner-directory-permissions #o700)
(define linux-open-directory-flags (bitwise-ior #x10000 #x80000))
(define allowed-publications
  '(published-durable published-recovered published-durability-uncertain))
(define allowed-failure-codes
  '(invalid-root invalid-target unsafe-permissions temporary-name-limit
                 create-failed write-failed file-sync-failed validation-failed
                 rename-failed directory-sync-failed cleanup-failed))

(define fsync*
  (ffi:get-ffi-obj "fsync" #f
                   (ffi:_fun #:save-errno 'posix ffi:_int ffi:-> ffi:_int)))
(define open-directory*
  (ffi:get-ffi-obj "open" #f
                   (ffi:_fun #:save-errno 'posix ffi:_path ffi:_int ffi:-> ffi:_int)))
(define close*
  (ffi:get-ffi-obj "close" #f
                   (ffi:_fun #:save-errno 'posix ffi:_int ffi:-> ffi:_int)))
(define getuid* (ffi:get-ffi-obj "getuid" #f (ffi:_fun ffi:-> ffi:_uint)))

(define current-durable-file-open
  (make-parameter
   (lambda (stage)
     (open-output-file stage #:exists 'error #:mode 'binary
                       #:permissions owner-file-permissions))))
(define current-durable-file-write
  (make-parameter (lambda (bytes output) (write-bytes bytes output))))
(define current-durable-file-flush
  (make-parameter (lambda (output) (flush-output output))))
(define current-durable-file-sync
  (make-parameter
   (lambda (output)
     (define result (fsync* (unsafe-port->file-descriptor output)))
     (and (not (zero? result)) (ffi:saved-errno)))))
(define current-durable-file-rename
  (make-parameter
   (lambda (source target)
     (rename-file-or-directory source target #t)
     #f)))
(define current-durable-directory-sync
  (make-parameter (lambda (directory) (sync-directory directory))))
(define current-durable-file-delete
  (make-parameter (lambda (path) (delete-file path))))

(struct odra-durable-file-publication
  (publication target file-synced? directory-synced? platform-code)
  #:transparent
  #:guard
  (lambda (publication target file-synced? directory-synced? platform-code _)
    (unless (and (memq publication allowed-publications)
                 (path-string? target)
                 (boolean? file-synced?)
                 (boolean? directory-synced?)
                 (exact-nonnegative-integer? platform-code))
      (raise-arguments-error 'odra-durable-file-publication
                             "invalid durable file publication"))
    (values publication
            (copied-path target)
            file-synced?
            directory-synced?
            platform-code)))

(struct odra-durable-file-failure
  (code message target recovery-path publication platform-code)
  #:transparent
  #:guard
  (lambda (code message target recovery-path publication platform-code _)
    (unless (and (memq code allowed-failure-codes)
                 (string? message)
                 (positive? (string-length message))
                 (path-string? target)
                 (or (string=? recovery-path "") (path-string? recovery-path))
                 (or (eq? publication 'not-published)
                     (memq publication allowed-publications))
                 (exact-nonnegative-integer? platform-code))
      (raise-arguments-error 'odra-durable-file-failure
                             "invalid durable file failure"))
    (values code
            (bounded-message message)
            (copied-path target)
            (if (string=? recovery-path "") "" (copied-path recovery-path))
            publication
            platform-code)))

(struct exn:fail:durable-file exn:fail
  (code target recovery-path publication platform-code)
  #:transparent)

(define (durable-file-publish target module-bytes
                              #:private-directories [private-directories '()]
                              #:validate-stage [validate-stage (lambda (_) #t)]
                              #:recover-visible [recover-visible #f])
  (define complete-target (path->complete-path target))
  (define parent (path-only complete-target))
  (define directories
    (remove-duplicates
     (append (map path->complete-path private-directories) (list parent))
     equal?))
  (define stage #f)
  (define rename-started? #f)
  (with-handlers
      ([exn:fail:durable-file?
        (lambda (failure)
          (define recovered
            (and rename-started?
                 recover-visible
                 (recover-visible? recover-visible complete-target)))
          (cond
            [recovered
             (odra-durable-file-publication
              'published-recovered complete-target #t #f
              (exn:fail:durable-file-platform-code failure))]
            [else (failure-with-cleanup failure stage)]))]
       [exn:fail?
        (lambda (failure)
          (failure-with-cleanup
           (durable-exception 'validation-failed (exn-message failure)
                              complete-target stage)
           stage))])
    (for ([directory (in-list directories)])
      (ensure-private-directory directory complete-target))
    (when (or (file-exists? complete-target) (link-exists? complete-target))
      (define target-failure (durable-file-check complete-target))
      (when target-failure
        (raise-from-failure target-failure)))
    (define-values (created-stage output) (create-stage parent complete-target))
    (set! stage created-stage)
    (write-stage stage complete-target module-bytes output)
    (validate-staged-file validate-stage stage complete-target)
    (set! rename-started? #t)
    (define rename-error
      (with-handlers ([exn:fail?
                       (lambda (failure)
                         (raise-durable 'rename-failed (exn-message failure)
                                        complete-target stage))])
        ((current-durable-file-rename) stage complete-target)))
    (when rename-error
      (raise-durable 'rename-failed "Could not replace the durable file"
                     complete-target stage 'not-published rename-error))
    (set! stage #f)
    (define directory-sync-error (durable-directory-synchronize parent))
    (if (positive? directory-sync-error)
        (odra-durable-file-publication
         'published-durability-uncertain complete-target #t #f
         directory-sync-error)
        (odra-durable-file-publication
         'published-durable complete-target #t #t 0))))

(define (durable-file-publish-existing stage target
                                       #:private-directories [private-directories '()]
                                       #:validate-stage [validate-stage (lambda (_) #t)])
  (define complete-stage (path->complete-path stage))
  (define complete-target (path->complete-path target))
  (define stage-parent (path-only complete-stage))
  (define target-parent (path-only complete-target))
  (with-handlers
      ([exn:fail:durable-file?
        (lambda (failure) (failure-with-cleanup failure complete-stage))]
       [exn:fail?
        (lambda (observed)
          (failure-with-cleanup
           (durable-exception 'validation-failed (exn-message observed)
                              complete-target complete-stage)
           complete-stage))])
    (for ([directory
           (in-list
            (remove-duplicates
             (append (map path->complete-path private-directories)
                     (list stage-parent target-parent))
             equal?))])
      (ensure-private-directory directory complete-target))
    (define stage-failure (durable-file-check complete-stage))
    (when stage-failure (raise-from-failure stage-failure))
    (when (or (file-exists? complete-target) (link-exists? complete-target))
      (raise-durable 'invalid-target "Durable target already exists"
                     complete-target complete-stage))
    (define sync-error
      (or (with-handlers ([exn:fail? (lambda (_) 5)])
            (call-with-input-file complete-stage
              (lambda (input) ((current-durable-file-sync) input))
              #:mode 'binary))
          0))
    (when (positive? sync-error)
      (raise-durable 'file-sync-failed
                     "Could not synchronize the durable staging file"
                     complete-target complete-stage 'not-published sync-error))
    (validate-staged-file validate-stage complete-stage complete-target)
    (define rename-error
      (with-handlers ([exn:fail?
                       (lambda (observed)
                         (raise-durable 'rename-failed (exn-message observed)
                                        complete-target complete-stage))])
        ((current-durable-file-rename) complete-stage complete-target)))
    (when rename-error
      (raise-durable 'rename-failed "Could not publish the durable staging file"
                     complete-target complete-stage 'not-published rename-error))
    (define target-sync-error (durable-directory-synchronize target-parent))
    (define stage-sync-error
      (if (equal? stage-parent target-parent)
          0
          (durable-directory-synchronize stage-parent)))
    (define directory-sync-error (or (and (positive? target-sync-error) target-sync-error)
                                     (and (positive? stage-sync-error) stage-sync-error)
                                     0))
    (if (positive? directory-sync-error)
        (odra-durable-file-publication
         'published-durability-uncertain complete-target #t #f
         directory-sync-error)
        (odra-durable-file-publication
         'published-durable complete-target #t #t 0))))

(define (durable-directory-synchronize directory)
  (with-handlers ([exn:fail? (lambda (_) 5)])
    (or ((current-durable-directory-sync) (path->complete-path directory)) 0)))

(define (durable-file-check target)
  (define complete-target (path->complete-path target))
  (cond
    [(link-exists? complete-target)
     (failure 'invalid-target "Durable file cannot be a symbolic link"
              complete-target)]
    [(not (file-exists? complete-target))
     (failure 'invalid-target "Durable target is not a regular file"
              complete-target)]
    [else
     (with-handlers ([exn:fail:filesystem?
                      (lambda (observed)
                        (failure 'invalid-target (exn-message observed)
                                 complete-target))])
       (define stat (file-or-directory-stat complete-target #f))
       (if (and (= (hash-ref stat 'user-id) (getuid*))
                (= (bitwise-and (hash-ref stat 'mode) #o777)
                   owner-file-permissions))
           #f
           (failure 'unsafe-permissions "Durable file must be private and owner-only"
                    complete-target)))]))

(define (ensure-private-directory directory target)
  (when (link-exists? directory)
    (raise-durable 'invalid-root "Durable directory cannot be a symbolic link" target))
  (unless (directory-exists? directory)
    (with-handlers ([exn:fail:filesystem?
                     (lambda (failure)
                       (raise-durable 'invalid-root (exn-message failure) target))])
      (make-directory* directory)
      (file-or-directory-permissions directory owner-directory-permissions)))
  (with-handlers ([exn:fail:filesystem?
                   (lambda (failure)
                     (raise-durable 'invalid-root (exn-message failure) target))])
    (define stat (file-or-directory-stat directory #f))
    (unless (and (= (hash-ref stat 'user-id) (getuid*))
                 (zero? (bitwise-and (hash-ref stat 'mode) #o077)))
      (raise-durable 'unsafe-permissions
                     "Durable directory must be private and owner-only"
                     target))))

(define (create-stage parent target)
  (let loop ([attempt 0])
    (when (= attempt staging-attempts)
      (raise-durable 'temporary-name-limit
                     "Could not reserve a durable staging file" target))
    (define stage
      (build-path parent
                  (format ".odra-stage-~a-~a.tmp"
                          (current-process-milliseconds)
                          (random 4294967087))))
    (define output #f)
    (with-handlers ([exn:fail:filesystem:exists?
                     (lambda (_) (loop (add1 attempt)))]
                    [exn:fail?
                     (lambda (failure)
                       (close-output-safely output)
                       (define cleanup-error (cleanup-stage stage))
                       (if cleanup-error
                           (raise-durable
                            'cleanup-failed
                            (format "~a; staging cleanup failed: ~a"
                                    (exn-message failure)
                                    (exn-message cleanup-error))
                            target stage)
                           (raise-durable 'create-failed (exn-message failure)
                                          target stage)))])
      (set! output ((current-durable-file-open) stage))
      (file-or-directory-permissions stage owner-file-permissions)
      (values stage output))))

(define (write-stage stage target module-bytes output)
  (with-handlers ([exn:fail:durable-file? raise]
                  [exn:fail?
                   (lambda (failure)
                     (close-output-safely output)
                     (raise-durable 'write-failed (exn-message failure)
                                    target stage))])
    (define written ((current-durable-file-write) module-bytes output))
    (unless (and (exact-nonnegative-integer? written)
                 (= written (bytes-length module-bytes)))
      (close-output-safely output)
      (raise-durable 'write-failed "Durable staging write was incomplete"
                     target stage))
    ((current-durable-file-flush) output)
    (define sync-error ((current-durable-file-sync) output))
    (if sync-error
        (begin
          (close-output-safely output)
          (raise-durable 'file-sync-failed
                         "Could not synchronize the durable staging file"
                         target stage 'not-published sync-error))
        (close-output-port output))))

(define (validate-staged-file validate-stage stage target)
  (define valid?
    (with-handlers ([exn:fail?
                     (lambda (failure)
                       (raise-durable 'validation-failed (exn-message failure)
                                      target stage))])
      (validate-stage stage)))
  (unless valid?
    (raise-durable 'validation-failed "Durable staging validation failed"
                   target stage)))

(define (recover-visible? recover-visible target)
  (with-handlers ([exn:fail? (lambda (_) #f)])
    (and (recover-visible target) #t)))

(define (failure-with-cleanup failure stage)
  (define cleanup-error (and stage (cleanup-stage stage)))
  (if cleanup-error
      (odra-durable-file-failure
       'cleanup-failed
       (format "~a; staging cleanup failed: ~a"
               (exn-message failure)
               (exn-message cleanup-error))
       (exn:fail:durable-file-target failure)
       (path->string stage)
       (exn:fail:durable-file-publication failure)
       (exn:fail:durable-file-platform-code failure))
      (failure-from-exception failure)))

(define (cleanup-stage stage)
  (and (or (file-exists? stage) (link-exists? stage))
       (with-handlers ([exn:fail? values])
         ((current-durable-file-delete) stage)
         #f)))

(define (close-output-safely output)
  (when (and output (not (port-closed? output)))
    (with-handlers ([exn:fail? void])
      (close-output-port output))))

(define (sync-directory directory)
  (define descriptor (open-directory* directory linux-open-directory-flags))
  (cond
    [(negative? descriptor) (ffi:saved-errno)]
    [else
     (define sync-result (fsync* descriptor))
     (define sync-error (and (not (zero? sync-result)) (ffi:saved-errno)))
     (define close-result (close* descriptor))
     (or sync-error (and (not (zero? close-result)) (ffi:saved-errno)))]))

(define (raise-from-failure observed)
  (raise-durable
   (odra-durable-file-failure-code observed)
   (odra-durable-file-failure-message observed)
   (odra-durable-file-failure-target observed)
   (and (not (string=? (odra-durable-file-failure-recovery-path observed) ""))
        (odra-durable-file-failure-recovery-path observed))
   (odra-durable-file-failure-publication observed)
   (odra-durable-file-failure-platform-code observed)))

(define (raise-durable code message target
                       [recovery-path #f]
                       [publication 'not-published]
                       [platform-code 0])
  (raise (durable-exception code message target recovery-path
                            publication platform-code)))

(define (durable-exception code message target
                           [recovery-path #f]
                           [publication 'not-published]
                           [platform-code 0])
  (exn:fail:durable-file
   message
   (current-continuation-marks)
   code
   (path->string (path->complete-path target))
   (if recovery-path (path->string (path->complete-path recovery-path)) "")
   publication
   (or platform-code 0)))

(define (failure-from-exception observed)
  (odra-durable-file-failure
   (exn:fail:durable-file-code observed)
   (exn-message observed)
   (exn:fail:durable-file-target observed)
   (exn:fail:durable-file-recovery-path observed)
   (exn:fail:durable-file-publication observed)
   (exn:fail:durable-file-platform-code observed)))

(define (failure code message target
                 [recovery-path ""]
                 [publication 'not-published]
                 [platform-code 0])
  (odra-durable-file-failure
   code message (path->string (path->complete-path target))
   recovery-path publication platform-code))

(define (copied-path value)
  (string->immutable-string
   (if (path? value) (path->string value) value)))

(define (bounded-message message)
  (define bytes (string->bytes/utf-8 message))
  (if (<= (bytes-length bytes) maximum-diagnostic-bytes)
      (string->immutable-string message)
      (bytes->string/utf-8
       (subbytes bytes 0 maximum-diagnostic-bytes)
       #\uFFFD)))

(module+ test-support
  (provide current-durable-file-open
           current-durable-file-write
           current-durable-file-flush
           current-durable-file-sync
           current-durable-file-rename
           current-durable-directory-sync
           current-durable-file-delete))
