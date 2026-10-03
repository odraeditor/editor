#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         "keymap-model.rkt")

(provide
 (contract-out
  [darek-global-command-names (listof symbol?)]
  [darek-context-command-names (listof symbol?)]
  [darek-command-names (listof symbol?)]
  [darek-command-name? (-> any/c boolean?)]
  [darek-bind-key
   (-> odra-key-sequence? symbol? odra-provenance? odra-binding?)]
  [darek-mask-key
   (-> odra-key-sequence? odra-provenance? odra-binding?)]
  [darek-remap-command
   (-> symbol? symbol? odra-provenance? odra-remap?)]
  [darek-factory-bindings (-> (listof odra-binding?))]))

(define unicode-scalar-key 1)
(define control-modifier #x01)
(define provenance (odra-provenance "odra" "darek" ""))

(define darek-global-command-names
  '(darek-toggle
    darek-select
    darek-focus-toggle
    darek-show-directory
    darek-find-current-file
    darek-show-current-project))

(define darek-context-command-names
  '(darek-next-node
    darek-previous-node
    darek-next-sibling
    darek-previous-sibling
    darek-next-project
    darek-previous-project
    darek-move-project-up
    darek-move-project-down
    darek-project-add
    darek-project-remove
    darek-project-rename
    darek-project-collapse
    darek-project-collapse-others
    darek-workspace-switch
    darek-workspace-next
    darek-root-parent
    darek-root-current-directory
    darek-parent-node
    darek-structure-action
    darek-visit-action
    darek-open
    darek-open-split-below
    darek-open-split-right
    darek-open-and-hide
    darek-open-mru-pane
    darek-open-external
    darek-create-file
    darek-create-directory
    darek-rename-node
    darek-move-node
    darek-copy-node
    darek-delete-node
    darek-copy-absolute-path
    darek-copy-project-relative-path
    darek-copy-project-root
    darek-copy-name
    darek-collapse-or-parent
    darek-collapse-parent
    darek-collapse-all-projects
    darek-refresh
    darek-toggle-peek
    darek-other-pane-next-line
    darek-other-pane-previous-line
    darek-other-pane-next-page
    darek-other-pane-previous-page
    darek-toggle-file-follow
    darek-toggle-hidden-files
    darek-toggle-vcs-ignored
    darek-toggle-file-watch
    darek-toggle-vcs-decorations
    darek-toggle-diagnostics
    darek-select-sort
    darek-filter
    darek-panel-left
    darek-panel-right
    darek-decrease-width
    darek-increase-width
    darek-fit-width
    darek-toggle-extra-width
    darek-toggle-width-lock
    darek-toggle-directory-compression
    darek-narrow-current-project
    darek-show-all-projects
    darek-shell-command
    darek-shell-command-project
    darek-bulk-actions
    darek-context-actions
    darek-help
    darek-help-advanced
    darek-hide
    darek-close))

(define darek-command-names
  (append darek-global-command-names darek-context-command-names))

(define (darek-command-name? value)
  (and (symbol? value) (memq value darek-command-names) #t))

(define (require-darek-command who command)
  (unless (darek-command-name? command)
    (raise-argument-error who "a Darek command symbol" command))
  (symbol->string command))

;; darek-bind-key declares one checked user binding for a Darek command.
(define (darek-bind-key sequence command provenance)
  (keymap-bind sequence (require-darek-command 'darek-bind-key command) provenance))

;; darek-mask-key suppresses one inherited Darek-context sequence.
(define (darek-mask-key sequence provenance)
  (keymap-mask sequence provenance))

;; darek-remap-command redirects one Darek command identity to another.
(define (darek-remap-command from-command to-command provenance)
  (keymap-remap
   (require-darek-command 'darek-remap-command from-command)
   (require-darek-command 'darek-remap-command to-command)
   provenance))

(define (stroke scalar [modifiers 0])
  (odra-key-stroke unicode-scalar-key (char->integer scalar) modifiers))

(define (binding command-name . strokes)
  (keymap-bind (apply key-sequence strokes) command-name provenance))

;; Darek owns only its global tree-panel prefix here. The active Darek component
;; publishes contextual navigation bindings through its ordinary keymap scope.
(define (darek-factory-bindings)
  (list
   (binding "darek-toggle"
            (stroke #\x control-modifier)
            (stroke #\t)
            (stroke #\t))
   (binding "darek-focus-toggle"
            (stroke #\x control-modifier)
            (stroke #\t)
            (stroke #\o))))

(module+ test
  (require rackunit)
  (check-equal? (length darek-global-command-names) 6)
  (check-equal? (length darek-context-command-names) 71)
  (check-equal? (length darek-command-names) 77)
  (check-true (darek-command-name? 'darek-toggle))
  (check-false (darek-command-name? 'toggle-tree))
  (define user-provenance (odra-provenance "user" "init.rkt" ""))
  (define user-sequence (key-sequence (stroke #\z)))
  (check-equal? (odra-binding-command (darek-bind-key user-sequence 'darek-toggle user-provenance))
                "darek-toggle")
  (check-equal? (odra-binding-operation (darek-mask-key user-sequence user-provenance)) 'mask)
  (check-equal? (odra-remap-to-command
                 (darek-remap-command 'darek-toggle 'darek-select user-provenance))
                "darek-select")
  (check-exn exn:fail:contract? (lambda () (darek-bind-key user-sequence 'unknown user-provenance)))
  (check-equal? (length (darek-factory-bindings)) 2)
  (check-true (andmap odra-binding? (darek-factory-bindings))))
