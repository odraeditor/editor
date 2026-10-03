#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list
         racket/string)

(provide
 platform-root-environment?
 (struct-out odra-platform-roots)
 (contract-out
  [resolve-platform-roots
   (-> symbol? platform-root-environment? odra-platform-roots?)]
  [resolve-current-platform-roots (-> odra-platform-roots?)]
  [runtime-platform-roots-current (-> (or/c #f odra-platform-roots?))]
  [runtime-platform-roots-reset! (-> void?)]
  [platform-roots->bytes (-> odra-platform-roots? immutable-bytes?)]
  [runtime-platform-roots-batch (-> list?)]))

(define platform-roots-schema-version 1)
(define admitted-platforms '(linux darwin windows))
(define environment-keys
  '("HOME" "XDG_CONFIG_HOME" "XDG_STATE_HOME" "XDG_CACHE_HOME"
           "XDG_DATA_HOME" "USERPROFILE" "APPDATA" "LOCALAPPDATA"))
(define active-platform-roots #f)

(define (immutable-bytes? value)
  (and (bytes? value) (immutable? value)))

(define (platform-root-environment? value)
  (and (hash? value)
       (for/and ([(key entry) (in-hash value)])
         (and (string? key) (string? entry)))))

(define (clean-root? value)
  (and (string? value)
       (positive? (string-length value))
       (<= (bytes-length (string->bytes/utf-8 value)) 4096)
       (not (regexp-match? #px"[\u0000-\u001f\u007f]" value))))

(define (unix-absolute-root? value)
  (and (clean-root? value)
       (string-prefix? value "/")
       (for/and ([part (in-list (string-split value "/" #:trim? #f))]
                 #:when (not (string=? part "")))
         (not (member part '("." "..") string=?)))))

(define (windows-normalize value)
  (regexp-replace* #px"/" value (lambda (_) "\\")))

(define (windows-absolute-root? value)
  (and (clean-root? value)
       (or (regexp-match? #px"^[A-Za-z]:[\\\\/]" value)
           (regexp-match? #px"^[\\\\]{2}[^\\\\/]+[\\\\/][^\\\\/]+" value))
       (for/and ([part (in-list (regexp-split #px"[\\\\/]+" value))]
                 #:when (not (string=? part "")))
         (not (member part '("." "..") string=?)))))

(define (strip-trailing-separators platform value)
  (define normalized
    (if (eq? platform 'windows) (windows-normalize value) value))
  (define minimum
    (cond
      [(eq? platform 'windows)
       (if (regexp-match? #px"^[A-Za-z]:\\\\$" normalized) 3 1)]
      [else 1]))
  (let loop ([result normalized])
    (if (and (> (string-length result) minimum)
             (or (string-suffix? result "/")
                 (string-suffix? result "\\")))
        (loop (substring result 0 (sub1 (string-length result))))
        result)))

(define (validated-root platform variable value)
  (define valid?
    (if (eq? platform 'windows)
        (windows-absolute-root? value)
        (unix-absolute-root? value)))
  (unless valid?
    (raise-arguments-error
     'resolve-platform-roots
     (format "~a must contain an absolute ~a path without control or parent segments"
             variable platform)
     variable value))
  (string->immutable-string (strip-trailing-separators platform value)))

(define (required-root platform environment variable)
  (define value (hash-ref environment variable #f))
  (cond
    [(not value)
     (raise-arguments-error
      'resolve-platform-roots
      (format "~a is required for ~a platform roots" variable platform))]
    [(string=? value "")
     (raise-arguments-error
      'resolve-platform-roots
      (format "~a must not be empty for ~a platform roots" variable platform))]
    [else (validated-root platform variable value)]))

(define (optional-root platform environment variable fallback)
  (define value (hash-ref environment variable #f))
  (if (or (not value) (string=? value ""))
      fallback
      (validated-root platform variable value)))

(define (root-join platform root . elements)
  (define separator (if (eq? platform 'windows) "\\" "/"))
  (string->immutable-string
   (string-append root
                  (if (string-suffix? root separator) "" separator)
                  (string-join elements separator))))

(struct odra-platform-roots
  (platform home configuration state cache package-data project-catalog
            legacy-projects)
  #:transparent
  #:guard
  (lambda (platform home configuration state cache package-data project-catalog
                    legacy-projects _)
    (define root-valid?
      (if (eq? platform 'windows) windows-absolute-root? unix-absolute-root?))
    (unless (and (memq platform admitted-platforms)
                 (andmap root-valid?
                         (list home configuration state cache package-data
                               project-catalog legacy-projects)))
      (raise-arguments-error 'odra-platform-roots
                             "invalid resolved platform roots"))
    (values platform home configuration state cache package-data project-catalog
            legacy-projects)))

;; resolve-platform-roots applies one deterministic platform path policy.
(define (resolve-platform-roots platform environment)
  (unless (memq platform admitted-platforms)
    (raise-arguments-error 'resolve-platform-roots
                           "unsupported platform" "platform" platform))
  (case platform
    [(linux)
     (define home (required-root platform environment "HOME"))
     (define configuration-base
       (optional-root platform environment "XDG_CONFIG_HOME"
                      (root-join platform home ".config")))
     (define state-base
       (optional-root platform environment "XDG_STATE_HOME"
                      (root-join platform home ".local" "state")))
     (define cache-base
       (optional-root platform environment "XDG_CACHE_HOME"
                      (root-join platform home ".cache")))
     (define data-base
       (optional-root platform environment "XDG_DATA_HOME"
                      (root-join platform home ".local" "share")))
     (define configuration (root-join platform configuration-base "odra"))
     (odra-platform-roots
      platform home configuration
      (root-join platform state-base "odra")
      (root-join platform cache-base "odra")
      (root-join platform data-base "odra")
      configuration
      (root-join platform home ".odra" "projects"))]
    [(darwin)
     (define home (required-root platform environment "HOME"))
     (define support
       (root-join platform home "Library" "Application Support" "Odra"))
     (odra-platform-roots
      platform home support
      (root-join platform support "State")
      (root-join platform home "Library" "Caches" "Odra")
      support support
      (root-join platform home ".odra" "projects"))]
    [(windows)
     (define home (required-root platform environment "USERPROFILE"))
     (define roaming (required-root platform environment "APPDATA"))
     (define local (required-root platform environment "LOCALAPPDATA"))
     (define configuration (root-join platform roaming "Odra"))
     (define data (root-join platform local "Odra"))
     (odra-platform-roots
      platform home configuration
      (root-join platform data "State")
      (root-join platform data "Cache")
      data configuration
      (root-join platform home ".odra" "projects"))]))

(define (current-platform)
  (case (system-type 'os)
    [(unix)
     (if (regexp-match? #px"^Linux" (system-type 'machine))
         'linux
         (raise-arguments-error 'resolve-current-platform-roots
                                "unsupported Unix host platform"))]
    [(macosx) 'darwin]
    [(windows) 'windows]
    [else
     (raise-arguments-error 'resolve-current-platform-roots
                            "unsupported host platform")]))

(define (current-environment)
  (for/hash ([key (in-list environment-keys)]
             #:do [(define value (getenv key))]
             #:when value)
    (values key value)))

;; resolve-current-platform-roots resolves the live host environment once.
(define (resolve-current-platform-roots)
  (resolve-platform-roots (current-platform) (current-environment)))

;; runtime-platform-roots-current returns the startup-confirmed root record.
(define (runtime-platform-roots-current)
  active-platform-roots)

;; runtime-platform-roots-reset! releases the startup record on runtime stop.
(define (runtime-platform-roots-reset!)
  (set! active-platform-roots #f))

(define (word value)
  (integer->integer-bytes value 8 #f #f))

;; platform-roots->bytes encodes the complete native startup root record.
(define (platform-roots->bytes roots)
  (define platform
    (case (odra-platform-roots-platform roots)
      [(linux) 1] [(darwin) 2] [(windows) 3]))
  (define values
    (map string->bytes/utf-8
         (list (odra-platform-roots-home roots)
               (odra-platform-roots-configuration roots)
               (odra-platform-roots-state roots)
               (odra-platform-roots-cache roots)
               (odra-platform-roots-package-data roots)
               (odra-platform-roots-project-catalog roots)
               (odra-platform-roots-legacy-projects roots))))
  (bytes->immutable-bytes
   (apply bytes-append
          (append
           (list (word platform-roots-schema-version) (word platform))
           (map (lambda (value) (word (bytes-length value))) values)
           values))))

;; runtime-platform-roots-batch exposes one checked startup transfer envelope.
(define (runtime-platform-roots-batch)
  (with-handlers ([exn?
                   (lambda (failure)
                     (list #f #"" (string->bytes/utf-8 (exn-message failure))))])
    (set! active-platform-roots #f)
    (define roots (resolve-current-platform-roots))
    (set! active-platform-roots roots)
    (list #t (platform-roots->bytes roots) #"")))

(module+ test
  (require rackunit)

  (define linux
    (resolve-platform-roots
     'linux
     (hash "HOME" "/home/example"
           "XDG_CONFIG_HOME" "/config"
           "XDG_STATE_HOME" "/state"
           "XDG_CACHE_HOME" "/cache"
           "XDG_DATA_HOME" "/data")))
  (check-equal? (odra-platform-roots-configuration linux) "/config/odra")
  (check-equal? (odra-platform-roots-state linux) "/state/odra")
  (check-equal? (odra-platform-roots-cache linux) "/cache/odra")
  (check-equal? (odra-platform-roots-package-data linux) "/data/odra")
  (check-equal? (odra-platform-roots-legacy-projects linux)
                "/home/example/.odra/projects")

  (define root-home-linux
    (resolve-platform-roots 'linux (hash "HOME" "/")))
  (check-equal? (odra-platform-roots-configuration root-home-linux)
                "/.config/odra")

  (define darwin
    (resolve-platform-roots 'darwin (hash "HOME" "/Users/example")))
  (check-equal? (odra-platform-roots-configuration darwin)
                "/Users/example/Library/Application Support/Odra")
  (check-equal? (odra-platform-roots-cache darwin)
                "/Users/example/Library/Caches/Odra")

  (define windows
    (resolve-platform-roots
     'windows
     (hash "USERPROFILE" "C:\\Users\\Example"
           "APPDATA" "C:\\Users\\Example\\AppData\\Roaming"
           "LOCALAPPDATA" "C:\\Users\\Example\\AppData\\Local")))
  (check-equal? (odra-platform-roots-configuration windows)
                "C:\\Users\\Example\\AppData\\Roaming\\Odra")
  (check-equal? (odra-platform-roots-package-data windows)
                "C:\\Users\\Example\\AppData\\Local\\Odra")

  (define drive-root-windows
    (resolve-platform-roots
     'windows
     (hash "USERPROFILE" "C:\\"
           "APPDATA" "R:\\"
           "LOCALAPPDATA" "L:\\")))
  (check-equal? (odra-platform-roots-configuration drive-root-windows)
                "R:\\Odra")

  (check-exn #rx"invalid resolved platform roots"
             (lambda ()
               (odra-platform-roots
                'linux "relative" "/configuration" "/state" "/cache"
                "/data" "/catalog" "/legacy")))

  (check-exn #rx"HOME is required"
             (lambda () (resolve-platform-roots 'linux (hash))))
  (check-exn #rx"USERPROFILE must not be empty"
             (lambda ()
               (resolve-platform-roots
                'windows
                (hash "USERPROFILE" "" "APPDATA" "C:\\Roaming"
                      "LOCALAPPDATA" "C:\\Local"))))
  (check-exn #rx"XDG_CONFIG_HOME must contain an absolute linux path"
             (lambda ()
               (resolve-platform-roots
                'linux (hash "HOME" "/home/example"
                             "XDG_CONFIG_HOME" "relative/config"))))
  (check-exn #rx"HOME must contain an absolute linux path"
             (lambda ()
               (resolve-platform-roots
                'linux (hash "HOME" "/home/example\u0000hidden"))))
  (check-exn #rx"HOME must contain an absolute linux path"
             (lambda ()
               (resolve-platform-roots
                'linux (hash "HOME" (string-append "/" (make-string 4096 #\a))))))
  (check-exn #rx"APPDATA must contain an absolute windows path"
             (lambda ()
               (resolve-platform-roots
                'windows
                (hash "USERPROFILE" "C:\\Users\\Example"
                      "APPDATA" "C:\\Users\\..\\Roaming"
                      "LOCALAPPDATA" "C:\\Local"))))
  (check-equal? (bytes-length (platform-roots->bytes linux))
                (+ 72
                   (for/sum ([value
                              (in-list
                               (list (odra-platform-roots-home linux)
                                     (odra-platform-roots-configuration linux)
                                     (odra-platform-roots-state linux)
                                     (odra-platform-roots-cache linux)
                                     (odra-platform-roots-package-data linux)
                                     (odra-platform-roots-project-catalog linux)
                                     (odra-platform-roots-legacy-projects linux)))])
                     (bytes-length (string->bytes/utf-8 value))))))
