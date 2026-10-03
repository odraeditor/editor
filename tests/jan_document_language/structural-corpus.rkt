#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/list
         racket/string)

(provide structural-evidence-kinds
         structural-fixture-family
         structural-fixture-node-type
         structural-fixtures
         structural-fixture-cases)

(struct structural-fixture (family node-type source negative) #:transparent)

(define structural-evidence-kinds
  '(positive negative ambiguous nested malformed unicode line-ending casing
    indentation unknown-form boundary preservation range availability recovery))

(define structural-fixtures
  (list
   (structural-fixture 'document-root "document" "" "")
   (structural-fixture 'zeroth-section "zeroth_section" "Text before headings\n" "")
   (structural-fixture 'heading "heading" "* Heading\n" " * Heading\n")
   (structural-fixture 'section "section" "* Heading\nBody\n" "Body\n")
   (structural-fixture 'center-block "center_block" "#+begin_center\nBody\n#+end_center\n" "#+center: Body\n")
   (structural-fixture 'quote-block "quote_block" "#+begin_quote\nBody\n#+end_quote\n" "> Body\n")
   (structural-fixture 'special-block "special_block" "#+begin_note\nBody\n#+end_note\n" "#+note: Body\n")
   (structural-fixture 'drawer "drawer" ":LOGBOOK:\nentry\n:END:\n" ":LOGBOOK: entry\n")
   (structural-fixture 'property-drawer "property_drawer" ":PROPERTIES:\n:ID: alpha\n:END:\n" ":PROPERTY:\n")
   (structural-fixture 'dynamic-block "dynamic_block" "#+begin: clocktable\nBody\n#+end:\n" "#+begin clocktable\n")
   (structural-fixture 'footnote-definition "footnote_definition" "[fn:note] Definition\n" " [fn:note] Definition\n")
   (structural-fixture 'inline-task "inline_task" "* Parent\n *************** Task\n" "***************Task\n")
   (structural-fixture 'list-item "list_item" "- item\n" "-item\n")
   (structural-fixture 'plain-list "plain_list" "- first\n- second\n" "ordinary text\n")
   (structural-fixture 'pipe-table "pipe_table" "| a | b |\n|---+---|\n" "a | b\n")
   (structural-fixture 'table-provider-form "table_provider_form" "#+begin_table provider\nrow\n#+end_table\n" "#+table: provider\n")
   (structural-fixture 'source-block "source_block" "#+begin_src odin\nmain :: proc() {}\n#+end_src\n" "#+src: odin\n")
   (structural-fixture 'example-block "example_block" "#+begin_example\nvalue\n#+end_example\n" "#+example: value\n")
   (structural-fixture 'export-block "export_block" "#+begin_export html\n<p>x</p>\n#+end_export\n" "#+export: html\n")
   (structural-fixture 'comment-block "comment_block" "#+begin_comment\nhidden\n#+end_comment\n" "# comment\n")
   (structural-fixture 'lesser-block "lesser_block" "#+begin_verse\nline\n#+end_verse\n" "#+verse: line\n")
   (structural-fixture 'clock "clock" "CLOCK: [2026-09-10 Wed 09:00]\n" "CLOCK [2026-09-10]\n")
   (structural-fixture 'diary-expression "diary_expression" "%%(diary-float t 1)\n" "% (diary-float t 1)\n")
   (structural-fixture 'planning-line "planning_line" "* Heading\nSCHEDULED: <2026-09-10 Wed>\n" "SCHEDULED <2026-09-10>\n")
   (structural-fixture 'line-comment "line_comment" "# comment\n" "#+comment: value\n")
   (structural-fixture 'fixed-width-area "fixed_width_area" ": fixed width\n" ":fixed width\n")
   (structural-fixture 'horizontal-rule "horizontal_rule" "-----\n" "----\n")
   (structural-fixture 'keyword "keyword" "#+title: Demo\n" "# title: Demo\n")
   (structural-fixture 'affiliated-keyword "affiliated_keyword" "#+caption: Demo\n| value |\n" "# caption: Demo\n")
   (structural-fixture 'latex-environment "latex_environment" "\\begin{equation}\nx=1\n\\end{equation}\n" "\\begin equation\n")
   (structural-fixture 'node-property "node_property" ":PROPERTIES:\n:ID: alpha\n:END:\n" ":ID alpha\n")
   (structural-fixture 'paragraph "paragraph" "Ordinary paragraph text.\n" "\n")
   (structural-fixture 'table-row "table_row" "| a | b |\n" "a | b\n")
   (structural-fixture 'table-separator-row "table_separator_row" "|---+---|\n" "| a + b |\n")))

(define (replace-line-endings source ending)
  (regexp-replace* #rx"\r\n|\r|\n" source ending))

(define (indent-source source)
  (string-join
   (for/list ([line (in-list (string-split source "\n" #:trim? #f))]
              [index (in-naturals)])
     (cond
       [(and (= index (sub1 (length (string-split source "\n" #:trim? #f))))
             (string=? line ""))
        ""]
       [else (string-append "  " line)]))
   "\n"))

(define (drop-final-byte source)
  (if (zero? (string-length source))
      source
      (substring source 0 (sub1 (string-length source)))))

(define (structural-fixture-cases fixture)
  (define source (structural-fixture-source fixture))
  (define negative (structural-fixture-negative fixture))
  (hasheq
   'positive source
   'negative negative
   'ambiguous (string-append negative source)
   'nested (string-append "* Parent\n" source)
   'malformed (drop-final-byte source)
   'unicode (string-append source "Unicode lambda: λ\n")
   'line-ending (replace-line-endings source "\r\n")
   'casing (string-upcase source)
   'indentation (indent-source source)
   'unknown-form (string-append "#+unknown_form: retained\n" source)
   'boundary (string-trim source "\r\n" #:left? #f)
   'preservation source
   'range source
   'availability (hasheq '.org source '.jan source)
   'recovery (string-append source "#+begin_unterminated\n")))
