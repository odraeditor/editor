#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/match
         racket/string)

(provide plan-tool-backend
         render-tool-document
         render-calendar)

(define (escape-replace value replacements)
  (for/fold ([result value]) ([replacement (in-list replacements)])
    (string-replace result (car replacement) (cdr replacement))))

(define (latex-escape value)
  (escape-replace
   value
   '(("\\" . "\\textbackslash{}") ("&" . "\\&") ("%" . "\\%")
     ("$" . "\\$") ("#" . "\\#") ("_" . "\\_")
     ("{" . "\\{") ("}" . "\\}") ("~" . "\\textasciitilde{}")
     ("^" . "\\textasciicircum{}"))))

(define (texinfo-escape value)
  (escape-replace value '(("@" . "@@") ("{" . "@{") ("}" . "@}"))))

(define (roff-escape value)
  (string-replace value "\\" "\\e"))

(define (fragments block renderer)
  (apply string-append (map renderer (hash-ref block 'fragments))))

(define (latex-fragment fragment)
  (define text (latex-escape (hash-ref fragment 'text)))
  (match (hash-ref fragment 'kind)
    ['text text]
    ['emphasis (format "\\emph{~a}" text)]
    ['strong (format "\\textbf{~a}" text)]
    ['code (format "\\texttt{~a}" text)]
    ['link (format "\\href{~a}{~a}" (latex-escape (hash-ref fragment 'target)) text)]
    ['image (format "\\includegraphics{~a}" (latex-escape (hash-ref fragment 'target)))]
    ['math (format "$~a$" (hash-ref fragment 'text))]))

(define (texinfo-fragment fragment)
  (define text (texinfo-escape (hash-ref fragment 'text)))
  (match (hash-ref fragment 'kind)
    ['text text]
    ['emphasis (format "@emph{~a}" text)]
    ['strong (format "@strong{~a}" text)]
    ['code (format "@code{~a}" text)]
    ['link (format "@uref{~a,~a}" (texinfo-escape (hash-ref fragment 'target)) text)]
    ['image (format "@image{~a,,,,\"~a\"}" (texinfo-escape (hash-ref fragment 'target)) text)]
    ['math (format "@math{~a}" text)]))

(define (roff-fragment fragment)
  (define text (roff-escape (hash-ref fragment 'text)))
  (match (hash-ref fragment 'kind)
    ['text text]
    ['emphasis (format "\\fI~a\\fP" text)]
    ['strong (format "\\fB~a\\fP" text)]
    ['code (format "\\f(CW~a\\fP" text)]
    ['link (format "~a (~a)" text (roff-escape (hash-ref fragment 'target)))]
    ['image (format "[Image: ~a] (~a)" text (roff-escape (hash-ref fragment 'target)))]
    ['math text]))

(define (plain-fragments block)
  (apply string-append (map (lambda (fragment) (hash-ref fragment 'text))
                            (hash-ref block 'fragments))))

(define (render-latex document beamer?)
  (define frame-open? #f)
  (define body
    (apply
     string-append
     (for/list ([block (in-list (hash-ref document 'blocks))])
       (define text (fragments block latex-fragment))
       (match (hash-ref block 'kind)
         ['heading
          (if beamer?
              (begin0
                (string-append (if frame-open? "\\end{frame}\n" "")
                               "\\begin{frame}[fragile]{" text "}\n")
                (set! frame-open? #t))
              (format "\\~a{~a}\n"
                      (case (hash-ref block 'level) [(1) "section"] [(2) "subsection"]
                        [else "subsubsection"])
                      text))]
         ['paragraph (string-append text "\n\n")]
         ['list-item (string-append "\\begin{itemize}\n\\item " text "\n\\end{itemize}\n")]
         ['quote (string-append "\\begin{quote}\n" text "\n\\end{quote}\n")]
         [(or 'source 'example)
          (string-append "\\begin{verbatim}\n" (plain-fragments block) "\n\\end{verbatim}\n")]
         ['horizontal-rule "\\hrulefill\n"]))))
  (string-append "\\documentclass{" (if beamer? "beamer" "article")
                 "}\n\\usepackage{hyperref}\n\\usepackage{graphicx}\n\\title{"
                 (latex-escape (hash-ref document 'title))
                 "}\n\\begin{document}\n\\maketitle\n"
                 body (if frame-open? "\\end{frame}\n" "") "\\end{document}\n"))

(define (render-texinfo document)
  (string-append
   "\\input texinfo\n@setfilename output.info\n@node Top\n@top "
   (texinfo-escape (hash-ref document 'title)) "\n"
   (apply string-append
          (for/list ([block (in-list (hash-ref document 'blocks))])
            (define text (fragments block texinfo-fragment))
            (match (hash-ref block 'kind)
              ['heading (format "@~a ~a\n"
                                (case (hash-ref block 'level) [(1) "chapter"] [(2) "section"]
                                  [else "subsection"])
                                text)]
              ['paragraph (string-append text "\n\n")]
              [(or 'source 'example)
               (string-append "@example\n" (plain-fragments block) "\n@end example\n")]
              ['list-item (string-append "@itemize @bullet\n@item " text "\n@end itemize\n")]
              ['quote (string-append "@quotation\n" text "\n@end quotation\n")]
              ['horizontal-rule "@center ----------\n"])))
   "@bye\n"))

(define (render-man document)
  (string-append
   ".TH \"" (roff-escape (hash-ref document 'title)) "\" \"1\"\n"
   (apply string-append
          (for/list ([block (in-list (hash-ref document 'blocks))])
            (define text (fragments block roff-fragment))
            (match (hash-ref block 'kind)
              ['heading (string-append ".SH \"" text "\"\n")]
              ['paragraph (string-append ".PP\n" text "\n")]
              [(or 'source 'example)
               (string-append ".nf\n" (plain-fragments block) "\n.fi\n")]
              ['list-item (string-append ".IP \\(bu 2\n" text "\n")]
              ['quote (string-append ".RS\n" text "\n.RE\n")]
              ['horizontal-rule ".sp\n\\l'\\n(.lu'\n.sp\n"])))))

(define (render-tool-document backend document)
  (case backend
    [(latex) (render-latex document #f)]
    [(beamer) (render-latex document #t)]
    [(texinfo) (render-texinfo document)]
    [(man-page) (render-man document)]
    [else #f]))

(define (plan-tool-backend backend tools generation validate?)
  (define identity
    (case backend [(pdf) 'pdflatex] [(odt) 'odra-odt-packager] [(info) 'makeinfo]
      [else #f]))
  (define tool (and identity (hash-ref tools identity #f)))
  (and tool
       (= (hash-ref tool 'generation) generation)
       (hash-ref tool 'available? #f)
       (hash-ref tool 'trusted? #f)
       (let ([steps (+ 1 (if validate? 1 0) (if (eq? backend 'pdf) 1 0))])
         (hasheq 'backend backend 'steps steps 'temporaries (add1 steps)
                 'cleanup (add1 steps) 'complete? #t))))

(define (ical-escape value)
  (escape-replace value '(("\\" . "\\\\") ("," . "\\,") (";" . "\\;")
                           ("\r" . "") ("\n" . "\\n"))))

(define (render-calendar events)
  (string-append
   "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Odra//Jan//EN\r\n"
   (apply string-append
          (for/list ([event (in-list events)])
            (define component (if (hash-ref event 'task? #f) "VTODO" "VEVENT"))
            (string-append
             "BEGIN:" component "\r\nUID:" (ical-escape (hash-ref event 'uid))
             "\r\nDTSTART:" (hash-ref event 'start) "\r\n"
             (if (hash-ref event 'end #f) (string-append "DTEND:" (hash-ref event 'end) "\r\n") "")
             "SUMMARY:" (ical-escape (hash-ref event 'summary)) "\r\n"
             (if (hash-ref event 'description #f)
                 (string-append "DESCRIPTION:" (ical-escape (hash-ref event 'description)) "\r\n") "")
             (if (hash-ref event 'location #f)
                 (string-append "LOCATION:" (ical-escape (hash-ref event 'location)) "\r\n") "")
             (if (hash-ref event 'categories #f)
                 (string-append "CATEGORIES:" (ical-escape (hash-ref event 'categories)) "\r\n") "")
             (if (hash-ref event 'completed? #f) "STATUS:COMPLETED\r\n" "")
             "CLASS:" (if (hash-ref event 'private? #f) "PRIVATE" "PUBLIC")
             "\r\nEND:" component "\r\n")))
   "END:VCALENDAR\r\n"))
