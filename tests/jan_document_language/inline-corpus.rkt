#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/string)

(provide inline-evidence-kinds
         inline-fixture-family
         inline-fixture-node-type
         inline-fixtures
         inline-fixture-cases)

(struct inline-fixture (family node-type source negative) #:transparent)

(define inline-evidence-kinds
  '(positive negative ambiguous nested malformed unicode line-ending casing
    indentation unknown-form boundary preservation range availability context
    precedence escape index))

(define inline-fixtures
  (list
   (inline-fixture 'entity "entity" "\\alpha" "\\")
   (inline-fixture 'special-symbol "special_symbol" "---" "-")
   (inline-fixture 'latex-fragment "latex_fragment" "$x+y$" "$x+y")
   (inline-fixture 'export-snippet "export_snippet" "@@html:<b>x</b>@@" "@@html:x")
   (inline-fixture 'named-footnote-reference "named_footnote_reference" "[fn:note]" "[fn:]" )
   (inline-fixture 'inline-footnote-reference "inline_footnote_reference" "[fn:note:body]" "[fn:note:]" )
   (inline-fixture 'anonymous-footnote-reference "anonymous_footnote_reference" "[fn::body]" "[fn::]" )
   (inline-fixture 'citation "citation" "[cite:@doe]" "[cite:]" )
   (inline-fixture 'citation-reference "citation_reference" "[cite:@doe]" "[cite:doe]" )
   (inline-fixture 'inline-call "inline_call" "call_total(1,2)" "call_total(" )
   (inline-fixture 'inline-source "inline_source" "src_odin{value}" "src_odin{" )
   (inline-fixture 'explicit-line-break "explicit_line_break" "\\\\\n" "\\\n" )
   (inline-fixture 'radio-link "radio_link" "<<<focus>>>\nfocus" "focus" )
   (inline-fixture 'plain-link "plain_link" "https://example.test" "https:" )
   (inline-fixture 'angle-link "angle_link" "<https://example.test>" "<https:>" )
   (inline-fixture 'regular-link "regular_link" "[[target][description]]" "[[target]" )
   (inline-fixture 'macro "macro" "{{{name(arg)}}}" "{{{name}}" )
   (inline-fixture 'target "target" "<<target>>" "<<target>" )
   (inline-fixture 'radio-target "radio_target" "<<<focus>>>" "<<<focus>>" )
   (inline-fixture 'percentage-cookie "percentage_cookie" "[50%]" "[50]" )
   (inline-fixture 'fraction-cookie "fraction_cookie" "[1/2]" "[1/]" )
   (inline-fixture 'subscript "subscript" "x_1" "x_" )
   (inline-fixture 'superscript "superscript" "x^{2}" "x^" )
   (inline-fixture 'table-cell "table_cell" "| value |" "value |" )
   (inline-fixture 'active-timestamp "active_timestamp" "<2026-09-10 Wed>" "<2026-09>" )
   (inline-fixture 'inactive-timestamp "inactive_timestamp" "[2026-09-10 Wed]" "[2026-09]" )
   (inline-fixture 'diary-timestamp "diary_timestamp" "<%%(diary-float t 1)>" "<%%()>" )
   (inline-fixture 'point-timestamp "point_timestamp" "<2026-09-10>" "<2026>" )
   (inline-fixture 'timestamp-range "timestamp_range" "<2026-09-10>--<2026-09-11>" "<2026-09-10>-<2026-09-11>" )
   (inline-fixture 'repeating-timestamp "repeating_timestamp" "<2026-09-10 +1w>" "<2026-09-10 +w>" )
   (inline-fixture 'delayed-timestamp "delayed_timestamp" "<2026-09-10 -2d>" "<2026-09-10 -d>" )
   (inline-fixture 'bold-markup "bold_markup" "*bold*" "*bold" )
   (inline-fixture 'italic-markup "italic_markup" "/italic/" "/italic" )
   (inline-fixture 'underline-markup "underline_markup" "_underlined_" "_underlined" )
   (inline-fixture 'verbatim-markup "verbatim_markup" "=verbatim=" "=verbatim" )
   (inline-fixture 'code-markup "code_markup" "~code~" "~code" )
   (inline-fixture 'strike-through-markup "strike_through_markup" "+struck+" "+struck" )
   (inline-fixture 'plain-text "plain_text" "ordinary text" "" )))

(define (replace-line-endings source ending)
  (regexp-replace* #rx"\r\n|\r|\n" source ending))

(define (drop-final-byte source)
  (if (zero? (string-length source))
      source
      (substring source 0 (sub1 (string-length source)))))

(define (inline-fixture-cases fixture)
  (define source (inline-fixture-source fixture))
  (define negative (inline-fixture-negative fixture))
  (hasheq
   'positive source
   'negative negative
   'ambiguous (string-append source negative)
   'nested (string-append "*" source "*")
   'malformed (drop-final-byte source)
   'unicode (string-append "λ " source " 文")
   'line-ending (replace-line-endings (string-append source "\n") "\r\n")
   'casing (string-upcase source)
   'indentation (string-append "  " source)
   'unknown-form (string-append "unknown:" source)
   'boundary (string-append "word" source "word")
   'preservation source
   'range source
   'availability (hasheq '.org source '.jan source)
   'context (string-append "Paragraph " source ".")
   'precedence (string-append source negative source)
   'escape (string-append "\\" source)
   'index (inline-fixture-family fixture)))
