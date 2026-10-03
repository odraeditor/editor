#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         "keymap-model.rkt"
         (only-in "darek.rkt" darek-factory-bindings)
         (only-in "language-interactions.rkt"
                  factory-language-direct-keymap
                  factory-language-modal-keymap)
         (only-in "maksym.rkt" maksym-factory-bindings)
         (only-in "search.rkt" search-factory-bindings))

(provide
 (contract-out
  [factory-interaction-profile-definition (-> odra-interaction-profile?)]
  [factory-modal-interaction-profile-definition (-> odra-interaction-profile?)]))

;; Logical key and modifier values match the fixed-width native interaction ABI.
(define unicode-scalar-key 1)
(define left-key 2)
(define right-key 3)
(define up-key 4)
(define down-key 5)
(define home-key 6)
(define end-key 7)
(define backspace-key 8)
(define delete-key 9)
(define enter-key 10)
(define tab-key 11)
(define insert-key 12)
(define prior-key 13)
(define next-key 14)
(define escape-key 15)
(define f4-key 16)
(define control-modifier #x01)
(define meta-modifier #x02)
(define factory-provenance (odra-provenance "odra" "factory" ""))

(define (key kind [scalar 0] [modifiers 0])
  (odra-key-stroke kind scalar modifiers))

(define (binding command-name . strokes)
  (keymap-bind (apply key-sequence strokes) command-name factory-provenance))

;; factory-interaction-profile-definition is the canonical shipped keymap owner.
(define (factory-interaction-profile-definition)
  (define all-bindings
    (append
     (list
      (binding "cursor-previous-grapheme" (key left-key))
      (binding "cursor-next-grapheme" (key right-key))
      (binding "cursor-previous-line" (key up-key))
      (binding "cursor-next-line" (key down-key))
      (binding "cursor-line-start" (key home-key))
      (binding "cursor-line-end" (key end-key))
      (binding "cursor-previous-grapheme"
               (key unicode-scalar-key (char->integer #\b) control-modifier))
      (binding "cursor-next-grapheme"
               (key unicode-scalar-key (char->integer #\f) control-modifier))
      (binding "cursor-previous-line"
               (key unicode-scalar-key (char->integer #\p) control-modifier))
      (binding "cursor-next-line"
               (key unicode-scalar-key (char->integer #\n) control-modifier))
      (binding "cursor-line-start"
               (key unicode-scalar-key (char->integer #\a) control-modifier))
      (binding "cursor-line-end"
               (key unicode-scalar-key (char->integer #\e) control-modifier))
      (binding "cursor-previous-word"
               (key unicode-scalar-key (char->integer #\b) meta-modifier))
      (binding "cursor-next-word"
               (key unicode-scalar-key (char->integer #\f) meta-modifier))
      (binding "cursor-line-first-non-whitespace"
               (key unicode-scalar-key (char->integer #\m) meta-modifier))
      (binding "cursor-previous-word" (key left-key 0 control-modifier))
      (binding "cursor-previous-word" (key up-key 0 control-modifier))
      (binding "cursor-next-word" (key right-key 0 control-modifier))
      (binding "cursor-next-word" (key down-key 0 control-modifier))
      (binding "cursor-buffer-start"
               (key unicode-scalar-key (char->integer #\<) meta-modifier))
      (binding "cursor-buffer-end"
               (key unicode-scalar-key (char->integer #\>) meta-modifier))
      (binding "cursor-previous-word" (key left-key 0 meta-modifier))
      (binding "cursor-next-word" (key right-key 0 meta-modifier)))
     (list
      (binding "describe-bindings"
               (key unicode-scalar-key (char->integer #\h) control-modifier)
               (key unicode-scalar-key (char->integer #\b)))
      (binding "describe-key"
               (key unicode-scalar-key (char->integer #\h) control-modifier)
               (key unicode-scalar-key (char->integer #\k)))
      (binding "where-is"
               (key unicode-scalar-key (char->integer #\h) control-modifier)
               (key unicode-scalar-key (char->integer #\w)))
      (binding "help-about-help"
               (key unicode-scalar-key (char->integer #\h) control-modifier)
               (key unicode-scalar-key (char->integer #\?)))
      (binding "apropos-command"
               (key unicode-scalar-key (char->integer #\h) control-modifier)
               (key unicode-scalar-key (char->integer #\a)))
      (binding "info"
               (key unicode-scalar-key (char->integer #\h) control-modifier)
               (key unicode-scalar-key (char->integer #\i)))
      (binding "describe-function"
               (key unicode-scalar-key (char->integer #\h) control-modifier)
               (key unicode-scalar-key (char->integer #\f)))
      (binding "describe-variable"
               (key unicode-scalar-key (char->integer #\h) control-modifier)
               (key unicode-scalar-key (char->integer #\v)))
      (binding "describe-keymap-state"
               (key unicode-scalar-key (char->integer #\h) control-modifier)
               (key unicode-scalar-key (char->integer #\m)))
      (binding "describe-syntax-table"
               (key unicode-scalar-key (char->integer #\h) control-modifier)
               (key unicode-scalar-key (char->integer #\s)))
      (binding "open-tutorial"
               (key unicode-scalar-key (char->integer #\h) control-modifier)
               (key unicode-scalar-key (char->integer #\t))))
     (search-factory-bindings)
     (maksym-factory-bindings)
     (darek-factory-bindings)
     (list
      (binding
       "structural-forward"
       (key unicode-scalar-key (char->integer #\f)
            (bitwise-ior control-modifier meta-modifier)))
      (binding
       "structural-backward"
       (key unicode-scalar-key (char->integer #\b)
            (bitwise-ior control-modifier meta-modifier)))
      (binding
       "structural-up"
       (key unicode-scalar-key (char->integer #\u)
            (bitwise-ior control-modifier meta-modifier)))
      (binding
       "structural-down"
       (key unicode-scalar-key (char->integer #\d)
            (bitwise-ior control-modifier meta-modifier)))
      (binding
       "structural-select"
       (key unicode-scalar-key (char->integer #\space)
            (bitwise-ior control-modifier meta-modifier)))
      (binding
       "complete-at-point"
       (key unicode-scalar-key (char->integer #\i)
            (bitwise-ior control-modifier meta-modifier)))
      (binding "insert-indentation" (key tab-key))
      (binding
       "next-location"
       (key unicode-scalar-key (char->integer #\g) meta-modifier)
       (key unicode-scalar-key (char->integer #\n)))
      (binding
       "previous-location"
       (key unicode-scalar-key (char->integer #\g) meta-modifier)
       (key unicode-scalar-key (char->integer #\p)))
      (binding
       "goto-line"
       (key unicode-scalar-key (char->integer #\g) meta-modifier)
       (key unicode-scalar-key (char->integer #\g)))
      (binding
       "goto-char"
       (key unicode-scalar-key (char->integer #\g) meta-modifier)
       (key unicode-scalar-key (char->integer #\c)))
      (binding "delete-previous-grapheme" (key backspace-key))
      (binding "delete-next-grapheme" (key delete-key))
      (binding "toggle-overwrite-mode" (key insert-key))
      (binding "scroll-previous-page" (key prior-key))
      (binding "scroll-next-page" (key next-key))
      (binding "recenter"
               (key unicode-scalar-key (char->integer #\l) control-modifier))
      (binding "shell-command"
               (key unicode-scalar-key (char->integer #\!) meta-modifier))
      (binding "async-shell-command"
               (key unicode-scalar-key (char->integer #\&) meta-modifier))
      (binding "insert-line-break" (key enter-key))
      (binding
       "set-mark-command"
       (key unicode-scalar-key (char->integer #\space) control-modifier))
      (binding
       "pop-selection-location"
       (key unicode-scalar-key (char->integer #\u) control-modifier)
       (key unicode-scalar-key (char->integer #\space) control-modifier))
      (binding
       "save-location"
       (key unicode-scalar-key (char->integer #\x) control-modifier)
       (key unicode-scalar-key (char->integer #\r))
       (key unicode-scalar-key (char->integer #\m)))
      (binding
       "list-locations"
       (key unicode-scalar-key (char->integer #\x) control-modifier)
       (key unicode-scalar-key (char->integer #\r))
       (key unicode-scalar-key (char->integer #\l)))
      (binding
       "visit-location"
       (key unicode-scalar-key (char->integer #\x) control-modifier)
       (key unicode-scalar-key (char->integer #\r))
       (key unicode-scalar-key (char->integer #\b)))
      (binding
       "store-number"
       (key unicode-scalar-key (char->integer #\x) control-modifier)
       (key unicode-scalar-key (char->integer #\r))
       (key unicode-scalar-key (char->integer #\n)))
      (binding
       "increment-number"
       (key unicode-scalar-key (char->integer #\x) control-modifier)
       (key unicode-scalar-key (char->integer #\r))
       (key unicode-scalar-key (char->integer #\+)))
      (binding
       "store-region-text"
       (key unicode-scalar-key (char->integer #\x) control-modifier)
       (key unicode-scalar-key (char->integer #\r))
       (key unicode-scalar-key (char->integer #\s)))
      (binding
       "store-position"
       (key unicode-scalar-key (char->integer #\x) control-modifier)
       (key unicode-scalar-key (char->integer #\r))
       (key unicode-scalar-key (char->integer #\space)))
      (binding
       "insert-slot"
       (key unicode-scalar-key (char->integer #\x) control-modifier)
       (key unicode-scalar-key (char->integer #\r))
       (key unicode-scalar-key (char->integer #\i)))
      (binding
       "store-layout"
       (key unicode-scalar-key (char->integer #\x) control-modifier)
       (key unicode-scalar-key (char->integer #\r))
       (key unicode-scalar-key (char->integer #\w)))
      (binding
       "visit-slot"
       (key unicode-scalar-key (char->integer #\x) control-modifier)
       (key unicode-scalar-key (char->integer #\r))
       (key unicode-scalar-key (char->integer #\j)))
      (binding
       "select-word"
       (key unicode-scalar-key (char->integer #\@) meta-modifier))
      (binding
       "select-paragraph"
       (key unicode-scalar-key (char->integer #\h) meta-modifier))
      (binding
       "select-buffer"
       (key unicode-scalar-key (char->integer #\x) control-modifier)
       (key unicode-scalar-key (char->integer #\h)))
      (binding
       "select-definition"
       (key unicode-scalar-key (char->integer #\h)
            (bitwise-ior control-modifier meta-modifier)))
      (binding
       "narrow-to-region"
       (key unicode-scalar-key (char->integer #\x) control-modifier)
       (key unicode-scalar-key (char->integer #\n))
       (key unicode-scalar-key (char->integer #\n)))
      (binding
       "narrow-to-definition"
       (key unicode-scalar-key (char->integer #\x) control-modifier)
       (key unicode-scalar-key (char->integer #\n))
       (key unicode-scalar-key (char->integer #\d)))
      (binding
       "widen"
       (key unicode-scalar-key (char->integer #\x) control-modifier)
       (key unicode-scalar-key (char->integer #\n))
       (key unicode-scalar-key (char->integer #\w)))
      (binding
       "start-kbd-macro"
       (key unicode-scalar-key (char->integer #\x) control-modifier)
       (key unicode-scalar-key (char->integer #\()))
      (binding
       "end-kbd-macro"
       (key unicode-scalar-key (char->integer #\x) control-modifier)
       (key unicode-scalar-key (char->integer #\))))
      (binding
       "call-last-kbd-macro"
       (key unicode-scalar-key (char->integer #\x) control-modifier)
       (key unicode-scalar-key (char->integer #\e)))
      (binding "kmacro-end-or-call-macro" (key f4-key))
      (binding
       "name-last-kbd-macro"
       (key unicode-scalar-key (char->integer #\x) control-modifier)
       (key unicode-scalar-key (char->integer #\k) control-modifier)
       (key unicode-scalar-key (char->integer #\n)))
      (binding
       "keyboard-quit"
       (key unicode-scalar-key (char->integer #\g) control-modifier))
      (binding
       "kill-region"
       (key unicode-scalar-key (char->integer #\w) control-modifier))
      (binding
       "kill-line"
       (key unicode-scalar-key (char->integer #\k) control-modifier))
      (binding
       "backward-kill-word"
       (key backspace-key 0 meta-modifier))
      (binding
       "kill-word"
       (key unicode-scalar-key (char->integer #\d) meta-modifier))
      (binding
       "delete-blank-lines"
       (key unicode-scalar-key (char->integer #\x) control-modifier)
       (key unicode-scalar-key (char->integer #\o) control-modifier))
      (binding
       "fill-paragraph"
       (key unicode-scalar-key (char->integer #\q) meta-modifier))
      (binding
       "transpose-words"
       (key unicode-scalar-key (char->integer #\t) meta-modifier))
      (binding
       "upcase-word"
       (key unicode-scalar-key (char->integer #\u) meta-modifier))
      (binding
       "downcase-word"
       (key unicode-scalar-key (char->integer #\l) meta-modifier))
      (binding
       "capitalize-word"
       (key unicode-scalar-key (char->integer #\c) meta-modifier))
      (binding
       "comment-dwim"
       (key unicode-scalar-key (char->integer #\;) meta-modifier))
      (binding
       "dabbrev-expand"
       (key unicode-scalar-key (char->integer #\/) meta-modifier))
      (binding
       "indent-lines"
       (key unicode-scalar-key (char->integer #\\)
            (bitwise-ior control-modifier meta-modifier)))
      (binding
       "indent-rigidly"
       (key unicode-scalar-key (char->integer #\x) control-modifier)
       (key tab-key))
      (binding
       "copy-region"
       (key unicode-scalar-key (char->integer #\w) meta-modifier))
      (binding
       "yank"
       (key unicode-scalar-key (char->integer #\y) control-modifier))
      (binding
       "yank-pop"
       (key unicode-scalar-key (char->integer #\y) meta-modifier))
      (binding
       "undo"
       (key unicode-scalar-key (char->integer #\/) control-modifier))
      (binding
       "undo"
       (key unicode-scalar-key (char->integer #\_) control-modifier))
      (binding
       "undo"
       (key unicode-scalar-key (char->integer #\x) control-modifier)
       (key unicode-scalar-key (char->integer #\u)))
      (binding
       "execute-extended-command"
       (key unicode-scalar-key (char->integer #\x) meta-modifier))
      (binding
       "exchange-point-and-mark"
       (key unicode-scalar-key (char->integer #\x) control-modifier)
       (key unicode-scalar-key (char->integer #\x) control-modifier))
      (binding
       "save-associated-document"
       (key unicode-scalar-key (char->integer #\x) control-modifier)
       (key unicode-scalar-key (char->integer #\s) control-modifier))
      (binding
       "find-file"
       (key unicode-scalar-key (char->integer #\x) control-modifier)
       (key unicode-scalar-key (char->integer #\f) control-modifier))
	  (binding
	   "find-alternate-file"
	   (key unicode-scalar-key (char->integer #\x) control-modifier)
	   (key unicode-scalar-key (char->integer #\v) control-modifier))
	  (binding
	   "write-file"
	   (key unicode-scalar-key (char->integer #\x) control-modifier)
	   (key unicode-scalar-key (char->integer #\w) control-modifier))
	  (binding
	   "save-some-buffers"
	   (key unicode-scalar-key (char->integer #\x) control-modifier)
	   (key unicode-scalar-key (char->integer #\s)))
	  (binding
	   "insert-file"
	   (key unicode-scalar-key (char->integer #\x) control-modifier)
	   (key unicode-scalar-key (char->integer #\i)))
	  (binding
	   "toggle-read-only"
	   (key unicode-scalar-key (char->integer #\x) control-modifier)
	   (key unicode-scalar-key (char->integer #\q) control-modifier))
      (binding
       "next-buffer"
       (key unicode-scalar-key (char->integer #\x) control-modifier)
       (key right-key))
      (binding
       "previous-buffer"
       (key unicode-scalar-key (char->integer #\x) control-modifier)
       (key left-key))
      (binding
       "switch-to-buffer"
       (key unicode-scalar-key (char->integer #\x) control-modifier)
       (key unicode-scalar-key (char->integer #\b)))
      (binding
       "find-file-other-pane"
       (key unicode-scalar-key (char->integer #\x) control-modifier)
       (key unicode-scalar-key (char->integer #\4))
       (key unicode-scalar-key (char->integer #\f)))
      (binding
       "switch-to-buffer-other-pane"
       (key unicode-scalar-key (char->integer #\x) control-modifier)
       (key unicode-scalar-key (char->integer #\4))
       (key unicode-scalar-key (char->integer #\b)))
      (binding
       "display-buffer-other-pane"
       (key unicode-scalar-key (char->integer #\x) control-modifier)
       (key unicode-scalar-key (char->integer #\4))
       (key unicode-scalar-key (char->integer #\o) control-modifier))
      (binding
       "kill-buffer"
       (key unicode-scalar-key (char->integer #\x) control-modifier)
       (key unicode-scalar-key (char->integer #\k)))
      (binding
       "list-buffers"
       (key unicode-scalar-key (char->integer #\x) control-modifier)
       (key unicode-scalar-key (char->integer #\b) control-modifier))
      (binding
       "split-pane-below"
       (key unicode-scalar-key (char->integer #\x) control-modifier)
       (key unicode-scalar-key (char->integer #\2)))
      (binding
       "split-pane-right"
       (key unicode-scalar-key (char->integer #\x) control-modifier)
       (key unicode-scalar-key (char->integer #\3)))
      (binding
       "close-pane"
       (key unicode-scalar-key (char->integer #\x) control-modifier)
       (key unicode-scalar-key (char->integer #\0)))
      (binding
       "keep-only-pane"
       (key unicode-scalar-key (char->integer #\x) control-modifier)
       (key unicode-scalar-key (char->integer #\1)))
      (binding
       "focus-next-pane"
       (key unicode-scalar-key (char->integer #\x) control-modifier)
       (key unicode-scalar-key (char->integer #\o)))
      (binding
       "enlarge-pane-vertically"
       (key unicode-scalar-key (char->integer #\x) control-modifier)
       (key unicode-scalar-key (char->integer #\^)))
      (binding
       "enlarge-pane-horizontally"
       (key unicode-scalar-key (char->integer #\x) control-modifier)
       (key unicode-scalar-key (char->integer #\})))
      (binding
       "shrink-pane-horizontally"
       (key unicode-scalar-key (char->integer #\x) control-modifier)
       (key unicode-scalar-key (char->integer #\{)))
      (binding
       "balance-panes"
       (key unicode-scalar-key (char->integer #\x) control-modifier)
       (key unicode-scalar-key (char->integer #\+)))
      (binding
       "project-find-file"
       (key unicode-scalar-key (char->integer #\c) control-modifier)
       (key unicode-scalar-key (char->integer #\p))
       (key unicode-scalar-key (char->integer #\f)))
      (binding
       "project-switch-buffer"
       (key unicode-scalar-key (char->integer #\c) control-modifier)
       (key unicode-scalar-key (char->integer #\p))
       (key unicode-scalar-key (char->integer #\b)))
      (binding
       "project-save-buffers"
       (key unicode-scalar-key (char->integer #\c) control-modifier)
       (key unicode-scalar-key (char->integer #\p))
       (key unicode-scalar-key (char->integer #\S)))
      (binding
       "project-close-buffers"
       (key unicode-scalar-key (char->integer #\c) control-modifier)
       (key unicode-scalar-key (char->integer #\p))
       (key unicode-scalar-key (char->integer #\k)))
      (binding
       "project-refresh"
       (key unicode-scalar-key (char->integer #\c) control-modifier)
       (key unicode-scalar-key (char->integer #\p))
       (key unicode-scalar-key (char->integer #\i)))
      (binding
       "project-command-menu"
       (key unicode-scalar-key (char->integer #\c) control-modifier)
       (key unicode-scalar-key (char->integer #\p))
       (key unicode-scalar-key (char->integer #\m)))
      (binding
       "describe-project-bindings"
       (key unicode-scalar-key (char->integer #\c) control-modifier)
       (key unicode-scalar-key (char->integer #\p))
       (key unicode-scalar-key (char->integer #\h) control-modifier))
      (binding
       "request-editor-exit"
       (key unicode-scalar-key (char->integer #\x) control-modifier)
       (key unicode-scalar-key (char->integer #\c) control-modifier)))))
  ;; Odin owns these protected recovery commands.
  (define protected-command-names '("keyboard-quit" "execute-extended-command"))
  (define project-command-names
    '("project-find-file" "project-switch-buffer"
      "project-save-buffers" "project-close-buffers" "project-refresh"
      "project-command-menu" "describe-project-bindings"))
  (define (command-member? binding names)
    (member (odra-binding-command binding) names))
  (define factory-bindings
    (for/list ([candidate (in-list all-bindings)]
               #:unless (or (command-member? candidate protected-command-names)
                            (command-member? candidate project-command-names)))
      candidate))
  (define project-bindings
    (for/list ([candidate (in-list all-bindings)]
               #:when (command-member? candidate project-command-names))
      candidate))
  (define project-prefix
    (list (key unicode-scalar-key (char->integer #\c) control-modifier)
          (key unicode-scalar-key (char->integer #\p))))
  (define reserved-project-strokes
    (for/list ([scalar (in-list
                        '(#\p #\F #\r #\s #\c #\! #\& #\e #\x #\w #\4 #\5))])
      (key unicode-scalar-key (char->integer scalar))))
  (define reserved-project-bindings
    (for/list ([stroke (in-list reserved-project-strokes)])
      (keymap-mask
       (apply key-sequence (append project-prefix (list stroke)))
       factory-provenance)))
  (odra-interaction-profile
   1 1 "direct"
   (list (odra-interaction-state
          1 1 "direct-editing" #t
          '(buffer view lifecycle text-mutation)
          factory-provenance))
   1
   (list
    (odra-keymap
     1 1 "factory" 0 0 'factory-fallback 0
     0 0 0 0 'text-input factory-bindings '() '() factory-provenance)
    (odra-keymap
     2 1 "project" 0 0 'project 0
     0 0 0 0 'fallthrough
     (append project-bindings reserved-project-bindings)
     '() '() factory-provenance)
    (factory-language-direct-keymap))
   "insert-text"))

;; factory-modal-interaction-profile-definition is the shipped stateful profile.
(define (factory-modal-interaction-profile-definition)
  (define normal (odra-profile-state-selector 2 1))
  (define insert (odra-profile-state-selector 2 2))
  (define visual-character (odra-profile-state-selector 2 3))
  (define visual-line (odra-profile-state-selector 2 4))
  (define replace (odra-profile-state-selector 2 5))
  (define visual-block (odra-profile-state-selector 2 6))
  (define visual-states (list visual-character visual-line visual-block))
  (define linear-visual-states (list visual-character visual-line))
  (define (states-binding selectors command-name . strokes)
    (keymap-for-states
     (apply binding command-name strokes)
     selectors))
  (define (state-binding selector command-name . strokes)
    (apply states-binding (list selector) command-name strokes))
  (define modal-bindings
    (list
     (state-binding normal "cursor-previous-grapheme" (key left-key))
     (state-binding normal "cursor-next-grapheme" (key right-key))
     (state-binding normal "cursor-previous-line" (key up-key))
     (state-binding normal "cursor-next-line" (key down-key))
     (state-binding normal "cursor-line-start" (key home-key))
     (state-binding normal "cursor-line-end" (key end-key))
     (state-binding normal "scroll-previous-page" (key prior-key))
     (state-binding normal "scroll-next-page" (key next-key))
     (states-binding (cons normal visual-states) "recenter"
                     (key unicode-scalar-key (char->integer #\l) control-modifier))
     (states-binding (cons normal visual-states) "help-about-help"
                     (key unicode-scalar-key (char->integer #\h) control-modifier)
                     (key unicode-scalar-key (char->integer #\?)))
     (states-binding (cons normal visual-states) "apropos-command"
                     (key unicode-scalar-key (char->integer #\h) control-modifier)
                     (key unicode-scalar-key (char->integer #\a)))
     (states-binding (cons normal visual-states) "info"
                     (key unicode-scalar-key (char->integer #\h) control-modifier)
                     (key unicode-scalar-key (char->integer #\i)))
     (states-binding (cons normal visual-states) "describe-function"
                     (key unicode-scalar-key (char->integer #\h) control-modifier)
                     (key unicode-scalar-key (char->integer #\f)))
     (states-binding (cons normal visual-states) "describe-variable"
                     (key unicode-scalar-key (char->integer #\h) control-modifier)
                     (key unicode-scalar-key (char->integer #\v)))
     (states-binding (cons normal visual-states) "describe-keymap-state"
                     (key unicode-scalar-key (char->integer #\h) control-modifier)
                     (key unicode-scalar-key (char->integer #\m)))
     (states-binding (cons normal visual-states) "describe-syntax-table"
                     (key unicode-scalar-key (char->integer #\h) control-modifier)
                     (key unicode-scalar-key (char->integer #\s)))
     (states-binding (cons normal visual-states) "open-tutorial"
                     (key unicode-scalar-key (char->integer #\h) control-modifier)
                     (key unicode-scalar-key (char->integer #\t)))
     (state-binding normal "cursor-previous-grapheme"
                    (key unicode-scalar-key (char->integer #\h)))
     (state-binding normal "cursor-next-line"
                    (key unicode-scalar-key (char->integer #\j)))
     (state-binding normal "cursor-previous-line"
                    (key unicode-scalar-key (char->integer #\k)))
     (state-binding normal "cursor-next-grapheme"
                    (key unicode-scalar-key (char->integer #\l)))
     (state-binding normal "cursor-line-start"
                    (key unicode-scalar-key (char->integer #\0)))
     (state-binding normal "cursor-line-end"
                    (key unicode-scalar-key (char->integer #\$)))
     (state-binding normal "cursor-line-first-non-whitespace"
                    (key unicode-scalar-key (char->integer #\^)))
     (state-binding normal "cursor-next-word-start"
                    (key unicode-scalar-key (char->integer #\w)))
     (state-binding normal "cursor-previous-word"
                    (key unicode-scalar-key (char->integer #\b)))
     (state-binding normal "cursor-word-end"
                    (key unicode-scalar-key (char->integer #\e)))
     (state-binding normal "cursor-buffer-start"
                    (key unicode-scalar-key (char->integer #\g))
                    (key unicode-scalar-key (char->integer #\g)))
     (state-binding normal "cursor-buffer-end"
                    (key unicode-scalar-key (char->integer #\G)))
     (state-binding normal "isearch-forward"
                    (key unicode-scalar-key (char->integer #\/)))
     (state-binding normal "isearch-backward"
                    (key unicode-scalar-key (char->integer #\?)))
     (state-binding normal "search-next-occurrence"
                    (key unicode-scalar-key (char->integer #\n)))
     (state-binding normal "search-previous-occurrence"
                    (key unicode-scalar-key (char->integer #\N)))
     (state-binding normal "delete-next-grapheme"
                    (key unicode-scalar-key (char->integer #\x)))
     (state-binding normal "delete-previous-grapheme"
                    (key unicode-scalar-key (char->integer #\X)))
     (state-binding normal "yank-after-point"
                    (key unicode-scalar-key (char->integer #\p)))
     (state-binding normal "yank"
                    (key unicode-scalar-key (char->integer #\P)))
     (state-binding normal "undo"
                    (key unicode-scalar-key (char->integer #\u)))
     (state-binding normal "redo"
                    (key unicode-scalar-key (char->integer #\r) control-modifier))
     (state-binding normal "modal-repeat-last-change"
                    (key unicode-scalar-key (char->integer #\.)))
     (state-binding normal "modal-enter-insert"
                    (key unicode-scalar-key (char->integer #\i)))
     (state-binding normal "modal-enter-insert-after"
                    (key unicode-scalar-key (char->integer #\a)))
     (state-binding normal "modal-enter-insert-line-first"
                    (key unicode-scalar-key (char->integer #\I)))
     (state-binding normal "modal-enter-insert-line-end"
                    (key unicode-scalar-key (char->integer #\A)))
     (state-binding normal "modal-enter-replace"
                    (key unicode-scalar-key (char->integer #\R)))
     (state-binding normal "modal-open-line-below"
                    (key unicode-scalar-key (char->integer #\o)))
     (state-binding normal "modal-open-line-above"
                    (key unicode-scalar-key (char->integer #\O)))
     (state-binding normal "modal-enter-visual-character"
                    (key unicode-scalar-key (char->integer #\v)))
     (state-binding normal "modal-enter-visual-line"
                    (key unicode-scalar-key (char->integer #\V)))
     (state-binding normal "modal-enter-visual-block"
                    (key unicode-scalar-key (char->integer #\v) control-modifier))
     (states-binding (cons normal visual-states) "execute-extended-command"
                     (key unicode-scalar-key (char->integer #\:)))
     (states-binding (cons normal visual-states) "shell-command"
                     (key unicode-scalar-key (char->integer #\!) meta-modifier))
     (states-binding (cons normal visual-states) "async-shell-command"
                     (key unicode-scalar-key (char->integer #\&) meta-modifier))
     (states-binding (cons normal visual-states) "focus-pane-left"
                     (key unicode-scalar-key (char->integer #\w) control-modifier)
                     (key unicode-scalar-key (char->integer #\h)))
     (states-binding (cons normal visual-states) "focus-pane-down"
                     (key unicode-scalar-key (char->integer #\w) control-modifier)
                     (key unicode-scalar-key (char->integer #\j)))
     (states-binding (cons normal visual-states) "focus-pane-up"
                     (key unicode-scalar-key (char->integer #\w) control-modifier)
                     (key unicode-scalar-key (char->integer #\k)))
     (states-binding (cons normal visual-states) "focus-pane-right"
                     (key unicode-scalar-key (char->integer #\w) control-modifier)
                     (key unicode-scalar-key (char->integer #\l)))
     (states-binding (cons normal visual-states) "split-pane-below"
                     (key unicode-scalar-key (char->integer #\w) control-modifier)
                     (key unicode-scalar-key (char->integer #\s)))
     (states-binding (cons normal visual-states) "split-pane-right"
                     (key unicode-scalar-key (char->integer #\w) control-modifier)
                     (key unicode-scalar-key (char->integer #\v)))
     (states-binding (cons normal visual-states) "close-pane"
                     (key unicode-scalar-key (char->integer #\w) control-modifier)
                     (key unicode-scalar-key (char->integer #\c)))
     (states-binding (cons normal visual-states) "keep-only-pane"
                     (key unicode-scalar-key (char->integer #\w) control-modifier)
                     (key unicode-scalar-key (char->integer #\o)))
     (states-binding (cons normal visual-states) "balance-panes"
                     (key unicode-scalar-key (char->integer #\w) control-modifier)
                     (key unicode-scalar-key (char->integer #\=)))
     (state-binding insert "modal-enter-normal"
                    (key escape-key))
     (state-binding insert "modal-enter-normal"
                    (key unicode-scalar-key (char->integer #\[) control-modifier))
     (state-binding replace "modal-enter-normal"
                    (key escape-key))
     (state-binding replace "modal-enter-normal"
                    (key unicode-scalar-key (char->integer #\[) control-modifier))
     (states-binding visual-states "cursor-previous-grapheme" (key left-key))
     (states-binding visual-states "cursor-next-grapheme" (key right-key))
     (states-binding visual-states "cursor-previous-line" (key up-key))
     (states-binding visual-states "cursor-next-line" (key down-key))
     (states-binding visual-states "cursor-line-start" (key home-key))
     (states-binding visual-states "cursor-line-end" (key end-key))
     (states-binding visual-states "scroll-previous-page" (key prior-key))
     (states-binding visual-states "scroll-next-page" (key next-key))
     (states-binding visual-states "cursor-previous-grapheme"
                     (key unicode-scalar-key (char->integer #\h)))
     (states-binding visual-states "cursor-next-line"
                     (key unicode-scalar-key (char->integer #\j)))
     (states-binding visual-states "cursor-previous-line"
                     (key unicode-scalar-key (char->integer #\k)))
     (states-binding visual-states "cursor-next-grapheme"
                     (key unicode-scalar-key (char->integer #\l)))
     (states-binding visual-states "cursor-line-start"
                     (key unicode-scalar-key (char->integer #\0)))
     (states-binding visual-states "cursor-line-end"
                     (key unicode-scalar-key (char->integer #\$)))
     (states-binding visual-states "cursor-line-first-non-whitespace"
                     (key unicode-scalar-key (char->integer #\^)))
     (states-binding visual-states "cursor-next-word-start"
                     (key unicode-scalar-key (char->integer #\w)))
     (states-binding visual-states "cursor-previous-word"
                     (key unicode-scalar-key (char->integer #\b)))
     (states-binding visual-states "cursor-word-end"
                     (key unicode-scalar-key (char->integer #\e)))
     (states-binding visual-states "cursor-buffer-start"
                     (key unicode-scalar-key (char->integer #\g))
                     (key unicode-scalar-key (char->integer #\g)))
     (states-binding visual-states "cursor-buffer-end"
                     (key unicode-scalar-key (char->integer #\G)))
     (states-binding visual-states "isearch-forward"
                     (key unicode-scalar-key (char->integer #\/)))
     (states-binding visual-states "isearch-backward"
                     (key unicode-scalar-key (char->integer #\?)))
     (states-binding visual-states "search-next-occurrence"
                     (key unicode-scalar-key (char->integer #\n)))
     (states-binding visual-states "search-previous-occurrence"
                     (key unicode-scalar-key (char->integer #\N)))
     (states-binding visual-states "kill-region"
                     (key unicode-scalar-key (char->integer #\d)))
     (states-binding visual-states "kill-region"
                     (key unicode-scalar-key (char->integer #\c)))
     (states-binding visual-states "copy-region"
                     (key unicode-scalar-key (char->integer #\y)))
     (states-binding linear-visual-states "indent-lines"
                     (key unicode-scalar-key (char->integer #\>)))
     (states-binding linear-visual-states "outdent-lines"
                     (key unicode-scalar-key (char->integer #\<)))
     (states-binding linear-visual-states "select-word"
                     (key unicode-scalar-key (char->integer #\i))
                     (key unicode-scalar-key (char->integer #\w)))
     (states-binding linear-visual-states "select-word"
                     (key unicode-scalar-key (char->integer #\a))
                     (key unicode-scalar-key (char->integer #\w)))
     (states-binding linear-visual-states "select-paragraph"
                     (key unicode-scalar-key (char->integer #\i))
                     (key unicode-scalar-key (char->integer #\p)))
     (states-binding linear-visual-states "select-paragraph"
                     (key unicode-scalar-key (char->integer #\a))
                     (key unicode-scalar-key (char->integer #\p)))
     (states-binding visual-states "exchange-point-and-mark"
                     (key unicode-scalar-key (char->integer #\o)))
     (state-binding visual-character "modal-enter-normal"
                    (key unicode-scalar-key (char->integer #\v)))
     (state-binding visual-character "modal-enter-visual-line"
                    (key unicode-scalar-key (char->integer #\V)))
     (state-binding visual-line "modal-enter-visual-character"
                    (key unicode-scalar-key (char->integer #\v)))
     (state-binding visual-line "modal-enter-normal"
                    (key unicode-scalar-key (char->integer #\V)))
     (state-binding visual-character "modal-enter-visual-block"
                    (key unicode-scalar-key (char->integer #\v) control-modifier))
     (state-binding visual-line "modal-enter-visual-block"
                    (key unicode-scalar-key (char->integer #\v) control-modifier))
     (state-binding visual-block "modal-enter-visual-character"
                    (key unicode-scalar-key (char->integer #\v)))
     (state-binding visual-block "modal-enter-visual-line"
                    (key unicode-scalar-key (char->integer #\V)))
     (state-binding visual-block "modal-enter-normal"
                    (key unicode-scalar-key (char->integer #\v) control-modifier))
     (states-binding visual-states "modal-enter-normal" (key escape-key))
     (states-binding visual-states "modal-enter-normal"
                     (key unicode-scalar-key (char->integer #\[) control-modifier))))
  (define direct-maps
    (odra-interaction-profile-maps (factory-interaction-profile-definition)))
  (define text-continuity-maps
    (for/list ([source-map (in-list direct-maps)]
               [id (in-list '(2 3))]
               [name (in-list '("modal-text-factory" "modal-text-project"))])
      (struct-copy odra-keymap source-map
                   [id id]
                   [revision 2]
                   [name name]
                   [bindings
                    (for/list ([source-binding
                                (in-list (odra-keymap-bindings source-map))])
                      (keymap-for-states source-binding (list insert replace)))])))
  (define modal-buffer-pane-command-names
    '("save-associated-document" "find-file" "switch-to-buffer"
      "find-file-other-pane" "switch-to-buffer-other-pane"
      "display-buffer-other-pane" "kill-buffer" "list-buffers"
      "split-pane-below" "split-pane-right" "close-pane" "keep-only-pane"
      "focus-next-pane" "enlarge-pane-vertically"
      "enlarge-pane-horizontally" "shrink-pane-horizontally"
      "balance-panes"))
  (define modal-buffer-pane-continuity
    (odra-keymap
     4 1 "modal-buffer-pane-continuity" 0 0 'profile-base 0
     0 0 0 0 'fallthrough
     (for*/list ([source-map (in-list direct-maps)]
                 [source-binding (in-list (odra-keymap-bindings source-map))]
                 #:when (member (odra-binding-command source-binding)
                                modal-buffer-pane-command-names))
       (keymap-for-states source-binding (cons normal visual-states)))
     '() '() factory-provenance))
  (odra-interaction-profile
   2 5 "modal"
   (list
    (odra-interaction-state
     1 1 "Normal" #f
     '(buffer view lifecycle text-mutation)
     factory-provenance)
    (odra-interaction-state
     2 1 "Insert" #t
     '(buffer view lifecycle text-mutation)
     factory-provenance)
    (odra-interaction-state
     3 1 "Visual Character" #f
     '(buffer view lifecycle text-mutation)
     factory-provenance)
    (odra-interaction-state
     4 1 "Visual Line" #f
     '(buffer view lifecycle text-mutation)
     factory-provenance)
    (odra-interaction-state
     5 1 "Replace" #t
     '(buffer view lifecycle text-mutation)
     factory-provenance)
    (odra-interaction-state
     6 1 "Visual Block" #f
     '(buffer view lifecycle text-mutation)
     factory-provenance))
   1
   (append
    (list (odra-keymap
     1 4 "modal-base" 0 0 'profile-base 0
     0 0 0 0 'text-input modal-bindings '() '() factory-provenance))
    text-continuity-maps
    (list modal-buffer-pane-continuity
          (factory-language-modal-keymap)))
   "insert-text"))

(module+ test
  (require rackunit
           (only-in "buffers.rkt" buffer-command-names))

  (define profile (factory-interaction-profile-definition))
  (define maps (odra-interaction-profile-maps profile))
  (define factory-bindings (odra-keymap-bindings (car maps)))
  (define project-bindings (odra-keymap-bindings (cadr maps)))
  (define all-bindings (append factory-bindings project-bindings))
  (define bound-command-names (map odra-binding-command all-bindings))
  (check-equal? (odra-interaction-profile-text-fallback-name profile) "insert-text")
  (check-equal? (length factory-bindings) 144)
  (check-equal? (length project-bindings) 19)
  (define (direct-help-binding scalar)
    (for/first ([candidate (in-list factory-bindings)]
                #:when (equal?
                        (odra-key-sequence-strokes
                         (odra-binding-sequence candidate))
                        (list
                         (key unicode-scalar-key (char->integer #\h) control-modifier)
                         (key unicode-scalar-key (char->integer scalar)))))
      candidate))
  (for ([entry (in-list '((#\? . "help-about-help")
                          (#\a . "apropos-command")
                          (#\b . "describe-bindings")
                          (#\f . "describe-function")
                          (#\i . "info")
                          (#\k . "describe-key")
                          (#\m . "describe-keymap-state")
                          (#\s . "describe-syntax-table")
                          (#\t . "open-tutorial")
                          (#\v . "describe-variable")
                          (#\w . "where-is")))])
    (define candidate (direct-help-binding (car entry)))
    (check-not-false candidate)
    (check-equal? (odra-binding-command candidate) (cdr entry)))
  (for ([entry (in-list '((#\! . "shell-command")
                          (#\& . "async-shell-command")))])
    (define candidate
      (for/first ([binding (in-list factory-bindings)]
                  #:when (equal?
                          (odra-key-sequence-strokes
                           (odra-binding-sequence binding))
                          (list
                           (key unicode-scalar-key
                                (char->integer (car entry))
                                meta-modifier))))
        binding))
    (check-not-false candidate)
    (check-equal? (odra-binding-command candidate) (cdr entry)))
  (define modal (factory-modal-interaction-profile-definition))
  (check-equal? (odra-interaction-profile-name modal) "modal")
  (check-equal? (odra-interaction-profile-revision modal) 5)
  (check-equal? (map odra-interaction-state-name
                     (odra-interaction-profile-states modal))
                '("Normal" "Insert" "Visual Character" "Visual Line" "Replace" "Visual Block"))
  (check-equal? (odra-interaction-profile-initial-state-id modal) 1)
  (check-equal? (length (odra-keymap-bindings
                         (car (odra-interaction-profile-maps modal))))
                111)
  (check-equal? (map odra-keymap-name (odra-interaction-profile-maps modal))
                '("modal-base" "modal-text-factory" "modal-text-project"
                  "modal-buffer-pane-continuity" "modal-language-context"))
  (define modal-pane-bindings
    (odra-keymap-bindings
     (car (odra-interaction-profile-maps modal))))
  (define modal-normal (odra-profile-state-selector 2 1))
  (define modal-replace (odra-profile-state-selector 2 5))
  (check-not-false
   (member
    (keymap-for-states
     (binding "modal-enter-replace"
              (key unicode-scalar-key (char->integer #\R)))
     (list modal-normal))
    modal-pane-bindings))
  (check-not-false
   (member
    (keymap-for-states
     (binding "modal-repeat-last-change"
              (key unicode-scalar-key (char->integer #\.)))
     (list modal-normal))
    modal-pane-bindings))
  (check-not-false
   (member
    (keymap-for-states
     (binding "modal-enter-normal" (key escape-key))
     (list modal-replace))
    modal-pane-bindings))
  (define (modal-pane-binding second)
    (for/first ([candidate (in-list modal-pane-bindings)]
                #:when (equal?
                        (odra-key-sequence-strokes
                         (odra-binding-sequence candidate))
                        (list
                         (key unicode-scalar-key (char->integer #\w)
                              control-modifier)
                         (key unicode-scalar-key (char->integer second)))))
      candidate))
  (for ([entry (in-list '((#\h . "focus-pane-left")
                          (#\j . "focus-pane-down")
                          (#\k . "focus-pane-up")
                          (#\l . "focus-pane-right")
                          (#\s . "split-pane-below")
                          (#\v . "split-pane-right")
                          (#\c . "close-pane")
                          (#\o . "keep-only-pane")
                          (#\= . "balance-panes")))])
    (define candidate (modal-pane-binding (car entry)))
    (check-not-false candidate)
    (check-equal? (odra-binding-command candidate) (cdr entry))
    (check-equal? (odra-binding-selectors candidate)
                  (list (odra-profile-state-selector 2 1)
                        (odra-profile-state-selector 2 3)
                        (odra-profile-state-selector 2 4)
                        (odra-profile-state-selector 2 6))))
  (define modal-buffer-pane-bindings
    (odra-keymap-bindings
     (for/first ([keymap (in-list (odra-interaction-profile-maps modal))]
                 #:when (string=? (odra-keymap-name keymap)
                                  "modal-buffer-pane-continuity"))
       keymap)))
  (define modal-buffer-pane-command-bindings
    (map odra-binding-command modal-buffer-pane-bindings))
  (for ([command-name
         (in-list
          '("save-associated-document" "find-file" "switch-to-buffer"
            "find-file-other-pane" "switch-to-buffer-other-pane"
            "display-buffer-other-pane" "kill-buffer" "list-buffers"
            "split-pane-below" "split-pane-right" "close-pane"
            "keep-only-pane" "focus-next-pane" "enlarge-pane-vertically"
            "enlarge-pane-horizontally" "shrink-pane-horizontally"
            "balance-panes"))])
    (check-not-false (member command-name modal-buffer-pane-command-bindings)))
  (for ([candidate (in-list modal-buffer-pane-bindings)])
    (check-equal? (odra-binding-selectors candidate)
                  (list (odra-profile-state-selector 2 1)
                        (odra-profile-state-selector 2 3)
                        (odra-profile-state-selector 2 4)
                        (odra-profile-state-selector 2 6))))
  (define text-continuity-bindings
    (apply append
           (map odra-keymap-bindings
                (list (cadr (odra-interaction-profile-maps modal))
                      (caddr (odra-interaction-profile-maps modal))))))
  (check-equal? (length text-continuity-bindings) 163)
  (define (modal-help-binding scalar)
    (for/first ([candidate (in-list text-continuity-bindings)]
                #:when (equal?
                        (odra-key-sequence-strokes
                         (odra-binding-sequence candidate))
                        (list
                         (key unicode-scalar-key (char->integer #\h) control-modifier)
                         (key unicode-scalar-key (char->integer scalar)))))
      candidate))
  (for ([entry (in-list '((#\? . "help-about-help")
                          (#\a . "apropos-command")
                          (#\b . "describe-bindings")
                          (#\f . "describe-function")
                          (#\i . "info")
                          (#\k . "describe-key")
                          (#\m . "describe-keymap-state")
                          (#\s . "describe-syntax-table")
                          (#\t . "open-tutorial")
                          (#\v . "describe-variable")
                          (#\w . "where-is")))])
    (define candidate (modal-help-binding (car entry)))
    (check-not-false candidate)
    (check-equal? (odra-binding-command candidate) (cdr entry))
    (check-equal? (odra-binding-selectors candidate)
                  (list (odra-profile-state-selector 2 2)
                        (odra-profile-state-selector 2 5))))
  (define (text-state-binding . strokes)
    (for/first ([candidate (in-list text-continuity-bindings)]
                #:when (equal? (odra-key-sequence-strokes
                                (odra-binding-sequence candidate))
                               strokes))
      candidate))
  (check-equal? (odra-binding-command
                 (text-state-binding
                  (key unicode-scalar-key (char->integer #\w) control-modifier)))
                "kill-region")
  (check-equal? (odra-binding-command
                 (text-state-binding
                  (key unicode-scalar-key (char->integer #\y) control-modifier)))
                "yank")
  (check-equal? (odra-binding-command
                 (text-state-binding
                  (key unicode-scalar-key (char->integer #\r) control-modifier)))
                "isearch-backward")
  (check-equal? (odra-binding-selectors
                 (text-state-binding
                  (key unicode-scalar-key (char->integer #\w) control-modifier)))
                (list (odra-profile-state-selector 2 2)
                      (odra-profile-state-selector 2 5)))
  (define modal-command-names
    (map odra-binding-command
         (odra-keymap-bindings (car (odra-interaction-profile-maps modal)))))
  (define modal-command-entry
    (for/first ([candidate
                 (in-list (odra-keymap-bindings
                           (car (odra-interaction-profile-maps modal))))]
                #:when (equal? (odra-binding-command candidate)
                               "execute-extended-command"))
      candidate))
  (check-not-false modal-command-entry)
  (check-equal? (odra-binding-selectors modal-command-entry)
                (list (odra-profile-state-selector 2 1)
                      (odra-profile-state-selector 2 3)
                      (odra-profile-state-selector 2 4)
                      (odra-profile-state-selector 2 6)))
  (for ([command-name
         (in-list
          '("cursor-previous-grapheme"
            "cursor-next-grapheme"
            "cursor-previous-line"
            "cursor-next-line"
            "cursor-line-start"
            "cursor-line-end"
            "cursor-line-first-non-whitespace"
            "cursor-next-word-start"
            "cursor-previous-word"
            "cursor-word-end"
            "cursor-buffer-start"
            "cursor-buffer-end"
            "scroll-previous-page"
            "scroll-next-page"
            "isearch-forward"
            "isearch-backward"
            "search-next-occurrence"
            "search-previous-occurrence"
            "delete-next-grapheme"
            "delete-previous-grapheme"
            "yank-after-point"
            "yank"
            "undo"
            "redo"))])
    (check-not-false (member command-name modal-command-names)))
  (define direct-movement-bindings
    (list
     (binding "cursor-previous-grapheme" (key left-key))
     (binding "cursor-next-grapheme" (key right-key))
     (binding "cursor-previous-line" (key up-key))
     (binding "cursor-next-line" (key down-key))
     (binding "cursor-line-start" (key home-key))
     (binding "cursor-line-end" (key end-key))
     (binding "toggle-overwrite-mode" (key insert-key))
     (binding "delete-next-grapheme" (key delete-key))
     (binding "scroll-previous-page" (key prior-key))
     (binding "scroll-next-page" (key next-key))
     (binding "cursor-previous-grapheme"
              (key unicode-scalar-key (char->integer #\b) control-modifier))
     (binding "cursor-next-grapheme"
              (key unicode-scalar-key (char->integer #\f) control-modifier))
     (binding "cursor-previous-line"
              (key unicode-scalar-key (char->integer #\p) control-modifier))
     (binding "cursor-next-line"
              (key unicode-scalar-key (char->integer #\n) control-modifier))
     (binding "cursor-line-start"
              (key unicode-scalar-key (char->integer #\a) control-modifier))
     (binding "cursor-line-end"
              (key unicode-scalar-key (char->integer #\e) control-modifier))))
  (for ([direct-binding (in-list direct-movement-bindings)])
    (check-not-false (member direct-binding all-bindings)))
  (define direct-word-bindings
    (list
     (binding "cursor-previous-word"
              (key unicode-scalar-key (char->integer #\b) meta-modifier))
     (binding "cursor-next-word"
              (key unicode-scalar-key (char->integer #\f) meta-modifier))
     (binding "cursor-line-first-non-whitespace"
              (key unicode-scalar-key (char->integer #\m) meta-modifier))
     (binding "cursor-previous-word" (key left-key 0 control-modifier))
     (binding "cursor-previous-word" (key up-key 0 control-modifier))
     (binding "cursor-next-word" (key right-key 0 control-modifier))
     (binding "cursor-next-word" (key down-key 0 control-modifier))))
  (for ([direct-binding (in-list direct-word-bindings)])
    (check-not-false (member direct-binding all-bindings)))
  (define direct-selection-bindings
    (list
     (binding "pop-selection-location"
              (key unicode-scalar-key (char->integer #\u) control-modifier)
              (key unicode-scalar-key (char->integer #\space) control-modifier))
     (binding "select-word"
              (key unicode-scalar-key (char->integer #\@) meta-modifier))
     (binding "select-paragraph"
              (key unicode-scalar-key (char->integer #\h) meta-modifier))
     (binding "select-buffer"
              (key unicode-scalar-key (char->integer #\x) control-modifier)
              (key unicode-scalar-key (char->integer #\h)))
     (binding "select-definition"
              (key unicode-scalar-key (char->integer #\h)
                   (bitwise-ior control-modifier meta-modifier)))))
  (for ([direct-binding (in-list direct-selection-bindings)])
    (check-not-false (member direct-binding all-bindings)))
  (define named-location-bindings
    (list
     (binding "save-location"
              (key unicode-scalar-key (char->integer #\x) control-modifier)
              (key unicode-scalar-key (char->integer #\r))
              (key unicode-scalar-key (char->integer #\m)))
     (binding "list-locations"
              (key unicode-scalar-key (char->integer #\x) control-modifier)
              (key unicode-scalar-key (char->integer #\r))
              (key unicode-scalar-key (char->integer #\l)))
     (binding "visit-location"
              (key unicode-scalar-key (char->integer #\x) control-modifier)
              (key unicode-scalar-key (char->integer #\r))
              (key unicode-scalar-key (char->integer #\b)))
     (binding "store-number"
              (key unicode-scalar-key (char->integer #\x) control-modifier)
              (key unicode-scalar-key (char->integer #\r))
              (key unicode-scalar-key (char->integer #\n)))
     (binding "increment-number"
              (key unicode-scalar-key (char->integer #\x) control-modifier)
              (key unicode-scalar-key (char->integer #\r))
              (key unicode-scalar-key (char->integer #\+)))
     (binding "store-region-text"
              (key unicode-scalar-key (char->integer #\x) control-modifier)
              (key unicode-scalar-key (char->integer #\r))
              (key unicode-scalar-key (char->integer #\s)))
     (binding "store-position"
              (key unicode-scalar-key (char->integer #\x) control-modifier)
              (key unicode-scalar-key (char->integer #\r))
              (key unicode-scalar-key (char->integer #\space)))
     (binding "insert-slot"
              (key unicode-scalar-key (char->integer #\x) control-modifier)
              (key unicode-scalar-key (char->integer #\r))
              (key unicode-scalar-key (char->integer #\i)))
     (binding "store-layout"
              (key unicode-scalar-key (char->integer #\x) control-modifier)
              (key unicode-scalar-key (char->integer #\r))
              (key unicode-scalar-key (char->integer #\w)))
     (binding "visit-slot"
              (key unicode-scalar-key (char->integer #\x) control-modifier)
              (key unicode-scalar-key (char->integer #\r))
              (key unicode-scalar-key (char->integer #\j)))))
  (for ([direct-binding (in-list named-location-bindings)])
    (check-not-false (member direct-binding all-bindings)))
  (for ([command-name (in-list buffer-command-names)])
    (check-not-false (member (symbol->string command-name) bound-command-names)))
  (check-false (member "balance-pane-areas" bound-command-names))
  (for ([search-binding (in-list (search-factory-bindings))])
    (check-not-false (member search-binding all-bindings)))
  (check-not-false
   (member (binding "structural-forward"
                    (key unicode-scalar-key (char->integer #\f)
                         (bitwise-ior control-modifier meta-modifier)))
           all-bindings))
  (check-not-false
   (member (binding "structural-backward"
                    (key unicode-scalar-key (char->integer #\b)
                         (bitwise-ior control-modifier meta-modifier)))
           all-bindings))
  (check-not-false
   (member (binding "structural-up"
                    (key unicode-scalar-key (char->integer #\u)
                         (bitwise-ior control-modifier meta-modifier)))
           all-bindings))
  (check-not-false
   (member (binding "structural-down"
                    (key unicode-scalar-key (char->integer #\d)
                         (bitwise-ior control-modifier meta-modifier)))
           all-bindings))
  (check-not-false
   (member (binding "structural-select"
                    (key unicode-scalar-key (char->integer #\space)
                         (bitwise-ior control-modifier meta-modifier)))
           all-bindings))
  (check-not-false
   (member (binding "complete-at-point"
                    (key unicode-scalar-key (char->integer #\i)
                         (bitwise-ior control-modifier meta-modifier)))
           all-bindings))
  (check-not-false
   (member (binding "insert-indentation" (key tab-key))
           all-bindings))
  (check-not-false
   (member (binding "next-location"
                    (key unicode-scalar-key (char->integer #\g) meta-modifier)
                    (key unicode-scalar-key (char->integer #\n)))
           all-bindings))
  (check-not-false
   (member (binding "previous-location"
                    (key unicode-scalar-key (char->integer #\g) meta-modifier)
                    (key unicode-scalar-key (char->integer #\p)))
           all-bindings))
  (check-not-false
   (member (binding "split-pane-below"
                    (key unicode-scalar-key (char->integer #\x) control-modifier)
                    (key unicode-scalar-key (char->integer #\2)))
           all-bindings))
  (check-not-false
   (member (binding "focus-next-pane"
                    (key unicode-scalar-key (char->integer #\x) control-modifier)
                    (key unicode-scalar-key (char->integer #\o)))
           all-bindings))
  (check-not-false
   (member (binding "enlarge-pane-vertically"
                    (key unicode-scalar-key (char->integer #\x) control-modifier)
                    (key unicode-scalar-key (char->integer #\^)))
           all-bindings))
  (check-not-false
   (member (binding "enlarge-pane-horizontally"
                    (key unicode-scalar-key (char->integer #\x) control-modifier)
                    (key unicode-scalar-key (char->integer #\})))
           all-bindings))
  (check-not-false
   (member (binding "shrink-pane-horizontally"
                    (key unicode-scalar-key (char->integer #\x) control-modifier)
                    (key unicode-scalar-key (char->integer #\{)))
           all-bindings))
  (check-not-false
   (member (binding "balance-panes"
                    (key unicode-scalar-key (char->integer #\x) control-modifier)
                    (key unicode-scalar-key (char->integer #\+)))
           all-bindings))
  (check-not-false
   (member (binding "kill-region"
                    (key unicode-scalar-key (char->integer #\w) control-modifier))
           all-bindings))
  (check-not-false
   (member (binding "copy-region"
                    (key unicode-scalar-key (char->integer #\w) meta-modifier))
           all-bindings))
  (check-not-false
   (member (binding "yank"
                    (key unicode-scalar-key (char->integer #\y) control-modifier))
           all-bindings))
  (check-not-false
   (member (binding "yank-pop"
                    (key unicode-scalar-key (char->integer #\y) meta-modifier))
           all-bindings))
  (check-not-false
   (member (binding "undo"
                    (key unicode-scalar-key (char->integer #\/) control-modifier))
           all-bindings))
  (check-false (member "execute-extended-command" bound-command-names))
  (check-not-false
   (member (binding "find-file"
                    (key unicode-scalar-key (char->integer #\x) control-modifier)
                    (key unicode-scalar-key (char->integer #\f) control-modifier))
           all-bindings))
  (check-not-false
   (member (binding "switch-to-buffer"
                    (key unicode-scalar-key (char->integer #\x) control-modifier)
                    (key unicode-scalar-key (char->integer #\b)))
           all-bindings))
  (check-not-false
   (member (binding "find-file-other-pane"
                    (key unicode-scalar-key (char->integer #\x) control-modifier)
                    (key unicode-scalar-key (char->integer #\4))
                    (key unicode-scalar-key (char->integer #\f)))
           all-bindings))
  (check-not-false
   (member (binding "switch-to-buffer-other-pane"
                    (key unicode-scalar-key (char->integer #\x) control-modifier)
                    (key unicode-scalar-key (char->integer #\4))
                    (key unicode-scalar-key (char->integer #\b)))
           all-bindings))
  (check-not-false
   (member (binding "display-buffer-other-pane"
                    (key unicode-scalar-key (char->integer #\x) control-modifier)
                    (key unicode-scalar-key (char->integer #\4))
                    (key unicode-scalar-key (char->integer #\o) control-modifier))
           all-bindings))
  (check-not-false
   (member (binding "kill-buffer"
                    (key unicode-scalar-key (char->integer #\x) control-modifier)
                    (key unicode-scalar-key (char->integer #\k)))
           all-bindings))
  (check-not-false
   (member (binding "list-buffers"
                    (key unicode-scalar-key (char->integer #\x) control-modifier)
                    (key unicode-scalar-key (char->integer #\b) control-modifier))
           all-bindings))
  (check-not-false
   (member (binding "project-find-file"
                    (key unicode-scalar-key (char->integer #\c) control-modifier)
                    (key unicode-scalar-key (char->integer #\p))
                    (key unicode-scalar-key (char->integer #\f)))
           all-bindings))
  (check-not-false
   (member (binding "describe-project-bindings"
                    (key unicode-scalar-key (char->integer #\c) control-modifier)
                    (key unicode-scalar-key (char->integer #\p))
                    (key unicode-scalar-key (char->integer #\h) control-modifier))
           all-bindings))
  (check-not-false
   (member (binding "undo"
                    (key unicode-scalar-key (char->integer #\_) control-modifier))
           all-bindings))
  (check-not-false
   (member (binding "undo"
                    (key unicode-scalar-key (char->integer #\x) control-modifier)
                    (key unicode-scalar-key (char->integer #\u)))
           all-bindings)))
