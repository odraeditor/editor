#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         racket/list
         racket/path
         racket/string)

(define required-consumer-markers
  '(("src/odra/app.odin"
     "proposal_project_editor_text_view"
     "proposal_map_pane_layout"
     "proposal_project_pane_status"
     "renderer_present_ui")
    ("src/odra/startup_workflow.odin"
     "proposal_project_list_view"
     "renderer_present_ui")
    ("src/odra/buffer_inventory_ui.odin"
     "proposal_project_list_view"
     "renderer_present_ui")
    ("src/odra/project_inventory_ui.odin"
     "proposal_project_list_view"
     "renderer_present_ui")
    ("src/odra/keymap_inspection_ui.odin"
     "proposal_project_list_view"
     "renderer_present_ui")
    ("src/odra/candidate_ui.odin"
     "proposal_project_list_view"
     "proposal_project_input"
     "registry_capture_focus"
     "renderer_present_ui")
    ("src/odra/transient_input_ui.odin"
     "proposal_project_input"
     "registry_capture_focus"
     "registry_release_focus")
    ("src/terminal/ui_renderer.odin"
     "renderer_present_ui")
    ("src/command/racket_ui_roles.odin"
     "racket_ui_role_turn")
    ("src/hosting/ui-role-bridge.rkt"
     "ui-role-propose"
     "ui-role-activate"
     "ui-role-teardown")))

(define forbidden-presentation-symbols
  '("Component_Kind"
    "Component_Snapshot"
    "renderer_present_component"
    "renderer_present_prompt"
    "renderer_present_view"
    "renderer_present_layout"
    "compatibility_adapter"
    "Feature_Kind"
    "feature_kind"))

(define (production-source? path)
  (and (file-exists? path)
       (member (path-get-extension path) '(#".odin" #".rkt"))))

(define production-sources
  (for/list ([path (in-directory "src")]
             #:when (production-source? path))
    path))

(define failures '())
(define (fail! message)
  (set! failures (cons message failures)))

(for ([requirement (in-list required-consumer-markers)])
  (define path (car requirement))
  (cond
    [(not (file-exists? path))
     (fail! (format "~a: migrated consumer source is missing" path))]
    [else
     (define content (file->string path))
     (for ([marker (in-list (cdr requirement))]
           #:unless (string-contains? content marker))
       (fail! (format "~a: missing shared UI marker ~a" path marker)))]))

(for* ([path (in-list production-sources)]
       [symbol (in-list forbidden-presentation-symbols)]
       #:when (string-contains? (file->string path) symbol))
  (fail! (format "~a: superseded presentation symbol remains: ~a" path symbol)))

(define renderer-entry-points
  (sort
   (remove-duplicates
    (for*/list ([path (in-list (for/list ([candidate (in-directory "src/terminal")]
                                         #:when (production-source? candidate))
                                candidate))]
                [line (in-list (file->lines path))]
                [match (in-value
                        (regexp-match #px"^(renderer_present_[A-Za-z0-9_]+) :: proc\\(" line))]
                #:when match)
      (cadr match)))
   string<?))

(define expected-renderer-entry-points
  '("renderer_present_recovery" "renderer_present_ui"))

(unless (equal? renderer-entry-points expected-renderer-entry-points)
  (fail! (format "src/terminal: expected renderer entry points ~a, found ~a"
                 expected-renderer-entry-points
                 renderer-entry-points)))

(unless (null? failures)
  (for-each displayln (reverse failures))
  (exit 1))

(printf
 "Verified ~a migrated UI consumers, ~a production sources, and no superseded presentation entry points.\n"
 (length required-consumer-markers)
 (length production-sources))
