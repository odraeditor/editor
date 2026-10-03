#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/file
         racket/string
         "../configuration/platform-roots.rkt")

(provide
 recovery-root-state?
 (struct-out odra-recovery-root)
 (struct-out odra-recovery-root-inspection)
 (contract-out
  [resolve-recovery-root (-> odra-platform-roots? odra-recovery-root?)]
  [inspect-recovery-root
   (-> odra-recovery-root? odra-recovery-root-inspection?)]
  [recovery-root-admitted? (-> odra-recovery-root-inspection? boolean?)]))

(define recovery-root-states
  '(absent private wrong-kind wrong-owner broad-permissions inaccessible
           platform-protected))

(define (recovery-root-state? value)
  (and (memq value recovery-root-states) #t))

(define (bounded-root? value)
  (and (string? value)
       (positive? (string-length value))
       (<= (bytes-length (string->bytes/utf-8 value)) 4096)
       (not (regexp-match? #px"[\u0000-\u001f\u007f]" value))))

(struct odra-recovery-root
  (platform state-root path private-directory-mode private-file-mode)
  #:transparent
  #:guard
  (lambda (platform state-root path private-directory-mode private-file-mode _)
    (unless (and (memq platform '(linux darwin windows))
                 (bounded-root? state-root)
                 (bounded-root? path)
                 (not (string=? state-root path))
                 (if (eq? platform 'windows)
                     (and (zero? private-directory-mode)
                          (zero? private-file-mode))
                     (and (= private-directory-mode #o700)
                          (= private-file-mode #o600))))
      (raise-arguments-error 'odra-recovery-root
                             "invalid derived private recovery root"))
    (values platform
            (string->immutable-string state-root)
            (string->immutable-string path)
            private-directory-mode
            private-file-mode)))

(struct odra-recovery-root-inspection (state diagnostic)
  #:transparent
  #:guard
  (lambda (state diagnostic _)
    (unless (and (recovery-root-state? state)
                 (string? diagnostic)
                 (<= (bytes-length (string->bytes/utf-8 diagnostic)) 256))
      (raise-arguments-error 'odra-recovery-root-inspection
                             "invalid recovery-root inspection"))
    (values state (string->immutable-string diagnostic))))

(define (root-join platform root . parts)
  (define separator (if (eq? platform 'windows) "\\" "/"))
  (string->immutable-string
   (string-append root
                  (if (string-suffix? root separator) "" separator)
                  (string-join parts separator))))

;; resolve-recovery-root derives the versioned namespace from the platform adapter.
(define (resolve-recovery-root roots)
  (define platform (odra-platform-roots-platform roots))
  (define state-root (odra-platform-roots-state roots))
  (odra-recovery-root
   platform
   state-root
   (root-join platform state-root "recovery" "v1")
   (if (eq? platform 'windows) 0 #o700)
   (if (eq? platform 'windows) 0 #o600)))

;; inspect-recovery-root rejects existing Unix roots with foreign ownership or broad permissions.
(define (inspect-recovery-root root)
  (with-handlers ([exn:fail:filesystem?
                   (lambda (_failure)
                     (odra-recovery-root-inspection
                      'inaccessible "Recovery root metadata is unavailable"))])
    (define path (odra-recovery-root-path root))
    (cond
      [(not (or (file-exists? path)
                (directory-exists? path)
                (link-exists? path)))
       (odra-recovery-root-inspection 'absent "Recovery root is not materialized")]
      [(link-exists? path)
       (odra-recovery-root-inspection
        'wrong-kind "Recovery root must not be a symbolic link")]
      [(not (directory-exists? path))
       (odra-recovery-root-inspection 'wrong-kind "Recovery root is not a directory")]
      [(eq? (odra-recovery-root-platform root) 'windows)
       (odra-recovery-root-inspection
        'platform-protected "Recovery root uses the platform-local application state")]
      [else
       (define state-metadata
         (file-or-directory-stat (odra-recovery-root-state-root root)))
       (define recovery-metadata (file-or-directory-stat path))
       (define state-owner (hash-ref state-metadata 'user-id #f))
       (define recovery-owner (hash-ref recovery-metadata 'user-id #f))
       (define permission-bits (file-or-directory-permissions path 'bits))
       (cond
         [(or (not state-owner) (not recovery-owner)
              (not (= state-owner recovery-owner)))
          (odra-recovery-root-inspection
           'wrong-owner "Recovery root owner differs from the platform state root")]
         [(not (zero? (bitwise-and permission-bits #o077)))
          (odra-recovery-root-inspection
           'broad-permissions "Recovery root grants group or other permissions")]
         [else
          (odra-recovery-root-inspection 'private "Recovery root is private")])])))

;; recovery-root-admitted? permits an absent root to be created privately by persistence.
(define (recovery-root-admitted? inspection)
  (and (memq (odra-recovery-root-inspection-state inspection)
             '(absent private platform-protected))
       #t))

(module+ test
  (require rackunit)

  (define linux
    (resolve-recovery-root
     (resolve-platform-roots
      'linux
      (hash "HOME" "/home/example" "XDG_STATE_HOME" "/state"))))
  (check-equal? (odra-recovery-root-path linux) "/state/odra/recovery/v1")
  (check-equal? (odra-recovery-root-private-directory-mode linux) #o700)

  (define darwin
    (resolve-recovery-root
     (resolve-platform-roots 'darwin (hash "HOME" "/Users/example"))))
  (check-equal?
   (odra-recovery-root-path darwin)
   "/Users/example/Library/Application Support/Odra/State/recovery/v1")

  (define windows
    (resolve-recovery-root
     (resolve-platform-roots
      'windows
      (hash "USERPROFILE" "C:\\Users\\Example"
            "APPDATA" "C:\\Users\\Example\\AppData\\Roaming"
            "LOCALAPPDATA" "C:\\Users\\Example\\AppData\\Local"))))
  (check-equal?
   (odra-recovery-root-path windows)
   "C:\\Users\\Example\\AppData\\Local\\Odra\\State\\recovery\\v1")

  (define root (make-temporary-file "odra-recovery-root-~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     (define state-root (build-path root "state"))
     (define recovery-root (build-path state-root "recovery" "v1"))
     (make-directory* recovery-root)
     (file-or-directory-permissions state-root #o700)
     (file-or-directory-permissions (build-path state-root "recovery") #o700)
     (file-or-directory-permissions recovery-root #o700)
     (define contract
       (odra-recovery-root
        'linux
        (path->string state-root)
        (path->string recovery-root)
        #o700
        #o600))
     (check-eq? (odra-recovery-root-inspection-state
                 (inspect-recovery-root contract))
                'private)
     (file-or-directory-permissions recovery-root #o755)
     (check-eq? (odra-recovery-root-inspection-state
                 (inspect-recovery-root contract))
                'broad-permissions))
   (lambda () (delete-directory/files root))))
