#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list
         racket/path
         "platform-roots.rkt")

(provide
 configuration-root-input?
 (contract-out
  [odra-configuration-root
   (->* ()
        (#:xdg-config-home configuration-root-input?
         #:home configuration-root-input?)
        path?)]
  [configuration-init-path (-> path-string? path?)]
  [configuration-settings-root (-> path-string? path?)]
  [configuration-themes-root (-> path-string? path?)]
  [configuration-workspaces-root (-> path-string? path?)]
  [configuration-sessions-root (-> path-string? path?)]
  [configuration-modules-root (-> path-string? path?)]
  [configuration-repos-root (-> path-string? path?)]
  [configuration-projects-root (-> path-string? path?)]
  [configuration-state-root (-> path-string? path?)]
  [configuration-named-locations-path (-> path-string? path?)]
  [configuration-promotion-suppressions-path (-> path-string? path?)]
  [configuration-migration-journal-path (-> path-string? path?)]
  [configuration-path-kind (-> path-string? path-string? symbol?)]))

(define root-file-kinds
  (hash
   "init.rkt" 'personal-entrypoint
   "promotion-suppressions.rkt" 'operational-promotion-suppressions
   "migration.rkt" 'operational-migration-state))

(define root-directory-kinds
  (hash
   "settings" 'functional-configuration
   "themes" 'theme-namespace
   "workspaces" 'operational-workspace-state
   "sessions" 'operational-session-state
   "modules" 'extension-module-namespace
   "repos" 'extension-repo-configuration
   "projects" 'operational-project-discovery
   "state" 'operational-generic-state))

(define (configuration-root-input? value)
  (or (not value)
      (path-string? value)
      (and (string? value) (zero? (string-length value)))))

(define current-environment-input (gensym 'current-environment-input))

;; odra-configuration-root delegates user-level root policy to the platform adapter.
(define (odra-configuration-root
         #:xdg-config-home [xdg-config-home current-environment-input]
         #:home [home current-environment-input])
  (define roots
    (if (and (eq? xdg-config-home current-environment-input)
             (eq? home current-environment-input))
        (resolve-current-platform-roots)
        (resolve-platform-roots
         'linux
         (for/hash ([entry
                     (in-list
                      (list (cons "XDG_CONFIG_HOME" xdg-config-home)
                            (cons "HOME" home)))]
                    #:when (and (not (eq? (cdr entry) current-environment-input))
                                (cdr entry)))
           (values (car entry) (cdr entry))))))
  (string->path (odra-platform-roots-configuration roots)))

(define (configuration-init-path root)
  (build-path (path->complete-path root) "init.rkt"))

(define (configuration-settings-root root)
  (build-path (path->complete-path root) "settings"))

(define (configuration-themes-root root)
  (build-path (path->complete-path root) "themes"))

(define (configuration-workspaces-root root)
  (build-path (path->complete-path root) "workspaces"))

(define (configuration-sessions-root root)
  (build-path (path->complete-path root) "sessions"))

(define (configuration-modules-root root)
  (build-path (path->complete-path root) "modules"))

(define (configuration-repos-root root)
  (build-path (path->complete-path root) "repos"))

(define (configuration-projects-root root)
  (build-path (path->complete-path root) "projects"))

(define (configuration-state-root root)
  (build-path (path->complete-path root) "state"))

(define (configuration-named-locations-path root)
  (build-path (configuration-state-root root) "named-locations.rkt"))

(define (configuration-promotion-suppressions-path root)
  (build-path (path->complete-path root) "promotion-suppressions.rkt"))

(define (configuration-migration-journal-path root)
  (build-path (path->complete-path root) "migration.rkt"))

;; configuration-path-kind classifies a path by ownership within one root.
(define (configuration-path-kind root candidate)
  (define complete-root (simplify-path (path->complete-path root)))
  (define complete-candidate (simplify-path (path->complete-path candidate)))
  (cond
    [(equal? complete-root complete-candidate) 'configuration-root]
    [else
     (define relative (find-relative-path complete-root complete-candidate))
     (define elements (explode-path relative))
     (cond
       [(or (null? elements) (member 'up elements))
        'outside-configuration-root]
       [else
        (define first (path->string (car elements)))
        (cond
          [(= (length elements) 1)
           (hash-ref root-file-kinds first
                     (lambda ()
                       (hash-ref root-directory-kinds first
                                 'unclassified-configuration-root-entry)))]
          [else
           (hash-ref root-directory-kinds first
                     'unclassified-configuration-root-entry)])])]))

(module+ test
  (require rackunit)

  (define root (string->path "/tmp/config/odra"))

  (check-equal?
   (odra-configuration-root #:xdg-config-home "/tmp/config" #:home "/tmp/home")
   (string->path "/tmp/config/odra"))
  (check-equal?
   (odra-configuration-root #:xdg-config-home #f #:home "/tmp/home")
   (string->path "/tmp/home/.config/odra"))
  (check-exn exn:fail?
             (lambda ()
               (odra-configuration-root #:xdg-config-home #f #:home #f)))

  (check-equal? (configuration-init-path root)
                (string->path "/tmp/config/odra/init.rkt"))
  (check-equal? (configuration-projects-root root)
                (string->path "/tmp/config/odra/projects"))
  (check-equal? (configuration-workspaces-root root)
                (string->path "/tmp/config/odra/workspaces"))
  (check-equal? (configuration-named-locations-path root)
                (string->path "/tmp/config/odra/state/named-locations.rkt"))

  (check-eq? (configuration-path-kind root root) 'configuration-root)
  (check-eq? (configuration-path-kind root "/tmp/config/odra/init.rkt")
             'personal-entrypoint)
  (check-eq? (configuration-path-kind root "/tmp/config/odra/settings/keys.rkt")
             'functional-configuration)
  (check-eq? (configuration-path-kind root "/tmp/config/odra/projects/alpha.rkt")
             'operational-project-discovery)
  (check-eq? (configuration-path-kind root "/tmp/config/odra/workspaces/main.rkt")
             'operational-workspace-state)
  (check-eq? (configuration-path-kind root "/tmp/config/odra/promotion-suppressions.rkt")
             'operational-promotion-suppressions)
  (check-eq? (configuration-path-kind root "/tmp/config/odra/migration.rkt")
             'operational-migration-state)
  (check-eq? (configuration-path-kind root "/tmp/config/odra/state/projects/alpha/candidates.rkt")
             'operational-generic-state)
  (check-eq? (configuration-path-kind root "/tmp/config/odra/themes/wroclaw/theme.rkt")
             'theme-namespace)
  (check-eq? (configuration-path-kind root "/tmp/config/odra/modules/foo/main.rkt")
             'extension-module-namespace)
  (check-eq? (configuration-path-kind root "/tmp/config/odra/repos/sources/main.rkt")
             'extension-repo-configuration)
  (check-eq? (configuration-path-kind root "/tmp/config/odra/unknown.rkt")
             'unclassified-configuration-root-entry)
  (check-eq? (configuration-path-kind root "/tmp/config/other/init.rkt")
             'outside-configuration-root))
