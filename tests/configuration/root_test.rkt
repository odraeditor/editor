#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         racket/file
         racket/list
         "../../src/configuration/root.rkt"
         (prefix-in migration: "../../src/migration/persistence.rkt")
         (prefix-in project: "../../src/project/persistence.rkt")
         (prefix-in workspace: "../../src/workspace/persistence.rkt"))

(define (with-root action)
  (define root (make-temporary-file "odra-configuration-root-~a" 'directory))
  (dynamic-wind void (lambda () (action root))
                (lambda () (delete-directory/files root))))

(test-case "configuration root follows XDG before HOME"
  (check-equal?
   (odra-configuration-root #:xdg-config-home "/tmp/xdg" #:home "/tmp/home")
   (string->path "/tmp/xdg/odra"))
  (check-equal?
   (odra-configuration-root #:xdg-config-home "" #:home "/tmp/home")
   (string->path "/tmp/home/.config/odra"))
  (check-exn exn:fail?
             (lambda ()
               (odra-configuration-root #:xdg-config-home #f #:home #f))))

  (test-case "state uses shared root resolver"
  (check-equal?
   (odra-configuration-root #:xdg-config-home "/tmp/xdg" #:home "/tmp/home")
   (project:odra-configuration-root
    #:xdg-config-home "/tmp/xdg"
    #:home "/tmp/home")))

  (test-case "path helpers produce accepted layout"
  (with-root
   (lambda (root)
     (define configuration-root (build-path root "config" "odra"))
     (check-equal? (configuration-init-path configuration-root)
                   (build-path configuration-root "init.rkt"))
     (check-equal? (configuration-settings-root configuration-root)
                   (build-path configuration-root "settings"))
     (check-equal? (configuration-themes-root configuration-root)
                   (build-path configuration-root "themes"))
     (check-equal? (configuration-workspaces-root configuration-root)
                   (build-path configuration-root "workspaces"))
     (check-equal? (workspace:workspace-record-path configuration-root "workspace-one")
                   (build-path configuration-root "workspaces" "workspace-one.rkt"))
     (check-equal? (configuration-projects-root configuration-root)
                   (build-path configuration-root "projects"))
     (check-equal? (configuration-state-root configuration-root)
                   (project:project-state-root configuration-root))
     (check-equal? (configuration-promotion-suppressions-path configuration-root)
                   (project:promotion-suppressions-record-path configuration-root))
     (check-equal? (configuration-migration-journal-path configuration-root)
                   (migration:migration-journal-record-path configuration-root)))))

  (test-case "path classes separate config and state"
  (with-root
   (lambda (root)
     (define configuration-root (build-path root "config" "odra"))
     (define cases
       (list
        (list configuration-root 'configuration-root)
        (list (build-path configuration-root "init.rkt")
              'personal-entrypoint)
        (list (build-path configuration-root "settings" "keys.rkt")
              'functional-configuration)
        (list (build-path configuration-root "projects" "project-one.rkt")
              'operational-project-discovery)
        (list (build-path configuration-root "workspaces" "workspace-one.rkt")
              'operational-workspace-state)
        (list (build-path configuration-root "promotion-suppressions.rkt")
              'operational-promotion-suppressions)
        (list (build-path configuration-root "migration.rkt")
              'operational-migration-state)
        (list (build-path configuration-root "state" "projects" "project-one" "usage.rkt")
              'operational-generic-state)
        (list (build-path configuration-root "sessions" "last.rkt")
              'operational-session-state)
        (list (build-path configuration-root "themes" "wroclaw-night" "theme.rkt")
              'theme-namespace)
        (list (build-path configuration-root "modules" "example" "main.rkt")
              'extension-module-namespace)
        (list (build-path configuration-root "repos" "sources" "official.rkt")
              'extension-repo-configuration)
        (list (build-path configuration-root "scratch.rkt")
              'unclassified-configuration-root-entry)
        (list (build-path root "outside" "init.rkt")
              'outside-configuration-root)))
     (for ([case (in-list cases)])
       (check-eq? (configuration-path-kind configuration-root (first case))
                  (second case))))))
