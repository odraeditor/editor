#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         racket/format
         racket/list
         racket/match
         racket/path
         racket/string)

(define arguments (current-command-line-arguments))
(unless (= (vector-length arguments) 2)
  (raise-user-error
   'generate-unicode-data
   "usage: racket scripts/generate-unicode-data.rkt <unicode-root> <output>"))

(define unicode-root (simplify-path (path->complete-path (vector-ref arguments 0))))
(define output-path (path->complete-path (vector-ref arguments 1)))

(define (parse-range value)
  (match (string-split value "..")
    [(list first) (cons (string->number first 16) (string->number first 16))]
    [(list first last) (cons (string->number first 16) (string->number last 16))]
    [_ (raise-user-error 'generate-unicode-data "invalid range: ~a" value)]))

(define (parse-property-file path property-index value-index)
  (for/fold ([properties (hash)]) ([line (in-lines (open-input-file path))])
    (define body (string-trim (regexp-replace #px"#.*$" line "")))
    (if (string=? body "")
        properties
        (let ([fields (map string-trim (string-split body ";"))])
          (if (<= (length fields) (max property-index value-index))
              properties
              (let* ([range (parse-range (first fields))]
                     [property (list-ref fields property-index)]
                     [value (list-ref fields value-index)]
                     [key (if (string=? property value)
                              property
                              (string-append property "=" value))])
                (hash-update properties key (lambda (ranges) (cons range ranges)) '())))))))

(define (merge-ranges ranges)
  (reverse
   (for/fold ([merged '()]) ([range (sort ranges < #:key car)])
     (match merged
       ['() (list range)]
       [(cons previous rest)
        (if (<= (car range) (add1 (cdr previous)))
            (cons (cons (car previous) (max (cdr previous) (cdr range))) rest)
            (cons range merged))]))))

(define (property-ranges properties key)
  (merge-ranges (hash-ref properties key '())))

(define grapheme-properties
  (parse-property-file
   (build-path unicode-root "ucd" "auxiliary" "GraphemeBreakProperty.txt")
   1
   1))
(define core-properties
  (parse-property-file
   (build-path unicode-root "ucd" "DerivedCoreProperties.txt")
   1
   2))
(define emoji-properties
  (parse-property-file
   (build-path unicode-root "ucd" "emoji" "emoji-data.txt")
   1
   1))
(define width-properties
  (parse-property-file
   (build-path unicode-root "ucd" "EastAsianWidth.txt")
   1
   1))

(define generated-arrays
  (list
   (cons "unicode17_gcb_cr_ranges" (property-ranges grapheme-properties "CR"))
   (cons "unicode17_gcb_lf_ranges" (property-ranges grapheme-properties "LF"))
   (cons "unicode17_gcb_control_ranges" (property-ranges grapheme-properties "Control"))
   (cons "unicode17_gcb_extend_ranges" (property-ranges grapheme-properties "Extend"))
   (cons "unicode17_gcb_zwj_ranges" (property-ranges grapheme-properties "ZWJ"))
   (cons "unicode17_gcb_regional_indicator_ranges" (property-ranges grapheme-properties "Regional_Indicator"))
   (cons "unicode17_gcb_prepend_ranges" (property-ranges grapheme-properties "Prepend"))
   (cons "unicode17_gcb_spacing_mark_ranges" (property-ranges grapheme-properties "SpacingMark"))
   (cons "unicode17_gcb_l_ranges" (property-ranges grapheme-properties "L"))
   (cons "unicode17_gcb_v_ranges" (property-ranges grapheme-properties "V"))
   (cons "unicode17_gcb_t_ranges" (property-ranges grapheme-properties "T"))
   (cons "unicode17_gcb_lv_ranges" (property-ranges grapheme-properties "LV"))
   (cons "unicode17_gcb_lvt_ranges" (property-ranges grapheme-properties "LVT"))
   (cons "unicode17_incb_consonant_ranges" (property-ranges core-properties "InCB=Consonant"))
   (cons "unicode17_incb_extend_ranges" (property-ranges core-properties "InCB=Extend"))
   (cons "unicode17_incb_linker_ranges" (property-ranges core-properties "InCB=Linker"))
   (cons "unicode17_emoji_ranges" (property-ranges emoji-properties "Emoji"))
   (cons "unicode17_emoji_presentation_ranges" (property-ranges emoji-properties "Emoji_Presentation"))
   (cons "unicode17_extended_pictographic_ranges" (property-ranges emoji-properties "Extended_Pictographic"))
   (cons "unicode17_east_asian_wide_ranges"
         (append (property-ranges width-properties "W")
                 (property-ranges width-properties "F")))
   (cons "unicode17_east_asian_ambiguous_ranges" (property-ranges width-properties "A"))))

(define (hex value)
  (~a "0x" (string-upcase (number->string value 16))))

(define (emit-array output name ranges)
  (fprintf output "@(private)\n~a := [?]u32 {\n" name)
  (for ([range (merge-ranges ranges)])
    (fprintf output "\t~a, ~a,\n" (hex (car range)) (hex (cdr range))))
  (fprintf output "}\n"))

(call-with-output-file
 output-path
 #:exists 'truncate/replace
 (lambda (output)
   (display "// SPDX-FileCopyrightText: 2026 Adrian PK\n" output)
   (display "// SPDX-License-Identifier: GPL-3.0-only\n" output)
   (display "//\n" output)
   (display "// This file is part of Odra. See COPYING for license terms.\n\n" output)
   (display "// Code generated by scripts/generate-unicode-data.rkt; DO NOT EDIT.\n" output)
   (display "// Source: Unicode Character Database 17.0.0.\n" output)
   (display "package display\n\n" output)
   (for ([entry generated-arrays]
         [index (in-naturals)])
     (when (> index 0)
       (newline output))
     (emit-array output (car entry) (cdr entry)))))
