#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/list
         racket/file
         racket/runtime-path
         rackunit
         "model.rkt")

(define-runtime-path task-metadata-org "fixtures/task-metadata.org")
(define-runtime-path task-metadata-jan "fixtures/task-metadata.jan")
(define-runtime-path time-workflows-org "fixtures/time-workflows.org")
(define-runtime-path time-workflows-jan "fixtures/time-workflows.jan")
(define-runtime-path refile-archive-org "fixtures/refile-archive.org")
(define-runtime-path refile-archive-jan "fixtures/refile-archive.jan")
(define-runtime-path capture-intake-org "fixtures/capture-intake.org")
(define-runtime-path capture-intake-jan "fixtures/capture-intake.jan")
(define-runtime-path agenda-queries-org "fixtures/agenda-queries.org")
(define-runtime-path agenda-queries-jan "fixtures/agenda-queries.jan")
(define-runtime-path planning-closure-org "fixtures/planning-closure.org")
(define-runtime-path planning-closure-jan "fixtures/planning-closure.jan")

(test-case "workflows stay ordered and block atomically"
  (define workflow
    (normalize-workflow 'default
                        '((todo #f #\t state)
                          (next #f #\n none)
                          (done #t #\d time))))
  (check-equal? (workflow-next-state workflow 'todo 'forward #f) 'next)
  (check-equal? (workflow-next-state workflow 'todo 'backward #f) 'done)
  (check-false (workflow-next-state workflow 'todo 'forward #t))
  (check-false (normalize-workflow 'bad '((todo #f #f none)))))

(test-case "tasks derive progress habits and priorities"
  (check-equal? (derive-task-statistics '(checked unchecked intermediate checked))
                '#hasheq((completed . 2) (total . 4) (percent . 50)))
  (check-equal? (summarize-habit '(#t #f #t #t))
                '#hasheq((completed . 3) (missed . 1) (current-streak . 2)))
  (check-equal? (normalize-priority "B" 1 9 5) 2)
  (check-equal? (normalize-priority "7" 1 9 5) 7)
  (check-equal? (normalize-priority "" 1 9 5) 5))

(test-case "tags preserve origins groups exceptions and Boolean search"
  (define records
    (resolve-effective-tags
     '((project local heading-1 #t)
       (work inherited heading-0 #t)
       (backend computed provider #t)
       (Blocked file document #t))
     '((project members (planning delivery))
       (work regexp "^(back|front)end$"))
     '(delivery)))
  (check-equal? (assoc 'project records) '(project local heading-1))
  (check-equal? (assoc 'planning records) '(planning grouped project))
  (check-equal? (assoc 'backend records) '(backend computed provider))
  (check-false (assoc 'blocked records))
  (check-true
   (match-tag-query records '((tag planning) (tag Blocked) and (tag missing) not and))))

(test-case "properties and column captures retain canonical owners"
  (define properties
    '((OWNER "Ada" stored #f heading-1)
      (OWNER "Team" inherited #f heading-0)
      (LABELS "editor" stored #t heading-1)
      (LABELS "jan" inherited #t heading-0)
      (LEVEL "1" derived #f heading-1)))
  (define owner (resolve-property 'OWNER properties 23))
  (check-equal? (hash-ref owner 'value) "Ada")
  (check-equal? (hash-ref owner 'owner) 'heading-1)
  (check-true (hash-ref owner 'editable?))
  (check-equal? (hash-ref (resolve-property 'LABELS properties 23) 'components)
                '(("editor" stored) ("jan" inherited)))
  (check-false (hash-ref (resolve-property 'LEVEL properties 23) 'editable?))
  (check-equal? (capture-column-view '((OWNER "Owner") (LEVEL "Level"))
                                      (list properties)
                                      23)
                "Owner\tLevel\nAda\t1\n"))

(test-case "org and jan task metadata fixtures stay byte-identical"
  (check-equal? (file->bytes task-metadata-org)
                (file->bytes task-metadata-jan)))

(test-case "org and jan time workflow fixtures stay byte-identical"
  (check-equal? (file->bytes time-workflows-org)
                (file->bytes time-workflows-jan)))

(test-case "org and jan refile archive fixtures stay byte-identical"
  (check-equal? (file->bytes refile-archive-org)
                (file->bytes refile-archive-jan)))

(test-case "org and jan capture intake fixtures stay byte-identical"
  (check-equal? (file->bytes capture-intake-org)
                (file->bytes capture-intake-jan)))

(test-case "org and jan agenda query fixtures stay byte-identical"
  (check-equal? (file->bytes agenda-queries-org)
                (file->bytes agenda-queries-jan)))

(test-case "org and jan planning closure fixtures stay byte-identical"
  (define source (file->bytes planning-closure-org))
  (check-equal? source (file->bytes planning-closure-jan))
  (for ([marker (in-list '(#"TODO" #"SCHEDULED:" #"DEADLINE:" #":EFFORT:"
                           #"CLOCK:" #"[ ]" #"JAN_ARCHIVE_SOURCE"
                           #"JAN_FEED_URL" #"REMOTE_EDIT_OUTCOME"))])
    (check-not-false (regexp-match? (byte-regexp (regexp-quote marker)) source))))

(test-case "capture expansion preserves one explicit cursor"
  (check-equal?
   (expand-capture-template "** TODO %{title}\n%{selection}%?"
                            '(("title" . "Review") ("selection" . "Context\n"))
                            'cursor 64 128)
   '#hasheq((cursor . 23) (text . "** TODO Review\nContext\n")))
  (check-false (expand-capture-template "%{missing}" '() 'end 64 128))
  (check-false (expand-capture-template "%? twice %?" '() 'cursor 64 128)))

(test-case "attachment publication exposes recovery before document links"
  (define prepared
    '#hasheq((state . prepared) (document-change? . #t) (repository? . #f)
             (reversible? . #t) (resource-committed? . #f)
             (document-committed? . #f)))
  (check-false (attachment-publication-step prepared 'document-commit))
  (define resource (attachment-publication-step prepared 'resource-commit))
  (check-equal? (hash-ref resource 'state) 'resource-committed)
  (define recovery (attachment-publication-step resource 'document-fail))
  (check-equal? (hash-ref recovery 'state) 'recovery-required)
  (check-equal? (hash-ref (attachment-publication-step recovery 'rollback-resource) 'state)
                'rolled-back))

(test-case "feed intake is explicit deduplicated retained and bounded"
  (define result
    (deduplicate-feed-entries
     'explicit
     '((old "Old") (one "One") (one "Duplicate") (two "Two"))
     '(old)
     1
     3))
  (check-equal? (hash-ref result 'entries) '((one "One")))
  (check-equal? (hash-ref result 'duplicates) 2)
  (check-true (hash-ref result 'truncated?))
  (check-equal? (hash-ref result 'retained) '(one old))
  (check-false (deduplicate-feed-entries 'document-open '((one "One")) '() 1 1)))

(test-case "agenda indexes retain unhealthy sources and confirmed rows"
  (define entries
    (list '#hasheq((identity . review) (kind . document) (task . TODO)
                   (finished? . #f) (tags . (work urgent))
                   (properties . #hasheq((OWNER . "Ada")))
                   (timestamp . 1000) (priority . 2) (text . "Review release task")
                   (project . alpha) (stuck? . #t) (clock . 3600)
                   (effort . 7200) (column . "Ada\t2h"))
          '#hasheq((identity . done) (kind . document) (task . DONE)
                   (finished? . #t) (tags . (home)) (priority . 5)
                   (text . "Finished home task") (archived? . #t))))
  (define sources
    (list (hasheq 'state 'confirmed 'configuration 23 'entries entries)
          (hasheq 'state 'stale 'configuration 22 'entries '())
          (hasheq 'state 'unavailable 'configuration 23 'entries '())))
  (define index (index-agenda-sources sources 77 23 64))
  (check-equal? (hash-ref index 'confirmed) 1)
  (check-equal? (hash-ref index 'stale) 1)
  (check-equal? (hash-ref index 'unavailable) 1)
  (check-equal? (length (hash-ref index 'entries)) 2)
  (check-equal? (map (lambda (entry) (hash-ref entry 'identity))
                     (query-agenda-entries index 'unfinished #f #f 0 0 #f))
                '(review))
  (check-equal? (map (lambda (entry) (hash-ref entry 'identity))
                     (query-agenda-entries index 'tag 'urgent #f 0 0 #f))
                '(review))
  (check-equal? (map (lambda (entry) (hash-ref entry 'identity))
                     (query-agenda-entries index 'property 'OWNER "Ada" 0 0 #f))
                '(review))
  (check-equal? (map (lambda (entry) (hash-ref entry 'identity))
                     (query-agenda-entries index 'daily #f #f 900 1100 #f))
                '(review))
  (check-true (agenda-cache-current? '#hasheq((generation . 77) (configuration . 23)) index))
  (check-false (agenda-cache-current? '#hasheq((generation . 78) (configuration . 23)) index)))

(test-case "agenda presentation sorts stably and reports truncation"
  (define entries
    (list '#hasheq((identity . first) (priority . 2))
          '#hasheq((identity . second) (priority . 5))
          '#hasheq((identity . third) (priority . 5))))
  (define result (present-agenda-entries entries 'priority #t 2))
  (check-equal? (map (lambda (entry) (hash-ref entry 'identity))
                     (hash-ref result 'rows))
                '(second third))
  (check-equal? (hash-ref result 'matched) 3)
  (check-true (hash-ref result 'truncated?)))

(test-case "time zones resolve gaps and folds explicitly"
  (check-equal?
   (resolve-zone-precedence '#hasheq((system . "UTC") (workspace . "Europe/Warsaw")))
   '(workspace . "Europe/Warsaw"))
  (check-false (resolve-local-time 'gap #f 100 200))
  (check-false (resolve-local-time 'fold #f 100 200))
  (check-equal? (resolve-local-time 'fold 'later 100 200) 200))

(test-case "timestamps remain canonical across locales"
  (define english
    (canonical-timestamp 2026 9 16 #:time '(10 30)
                         #:repeater '("++" 1 "w") #:warning '(2 "d")
                         #:locale "en-US"))
  (define polish
    (canonical-timestamp 2026 9 16 #:time '(10 30)
                         #:repeater '("++" 1 "w") #:warning '(2 "d")
                         #:locale "pl-PL"))
  (check-equal? english "<2026-09-16 Wed 10:30 ++1w -2d>")
  (check-equal? polish english))

(test-case "repeaters distinguish stored catch-up and completion bases"
  (check-equal? (advance-recurrence 1 16 16 'stored-base 1 'week) '(8 . 1))
  (check-equal? (advance-recurrence 1 16 16 'catch-up 1 'week) '(22 . 3))
  (check-equal? (advance-recurrence 1 16 16 'completion-base 1 'week) '(23 . 1)))

(test-case "clocks reject overlap and preserve explicit exclusions"
  (define active (clock-start #f 'heading-1 1000))
  (check-false (clock-start active 'heading-2 1200))
  (define closed (clock-stop active 4600 #:excluded 300))
  (check-equal? (hash-ref closed 'elapsed) 3300)
  (check-equal? (hash-ref closed 'target) 'heading-1))

(test-case "timer notification failure remains isolated"
  (define timer '#hasheq((mode . countdown) (state . running)
                         (started . 100) (target . 60) (notified? . #f)))
  (define completed (timer-tick timer 160 #f))
  (check-equal? (hash-ref completed 'state) 'completed)
  (check-equal? (hash-ref completed 'notification) 'unavailable))

(test-case "refile candidates compose every configured constraint"
  (define candidates
    '((projects 2 "notes/projects.jan" project-a workspace-a "notes/projects.jan" 1 #t)
      (archive 3 "notes/archive.jan" project-a workspace-a "notes/archive.jan" 2 #t)
      (private 2 "private.jan" project-b workspace-a "private.jan" 1 #f)))
  (check-equal?
   (select-refile-candidates
    candidates
    '#hasheq((minimum-level . 2)
             (maximum-level . 2)
             (file . "notes/projects.jan")
             (project . project-a)
             (workspace . workspace-a)
             (path-prefix . "notes/")
             (recent-limit . 1)
             (require-predicate? . #t)))
   (list (car candidates))))

(test-case "refile publication exposes duplicates until explicit recovery"
  (define prepared
    '#hasheq((mode . move) (state . prepared)
             (destination-committed? . #f) (source-removed? . #f)))
  (define destination (refile-publication-step prepared 'destination-commit))
  (check-equal? (hash-ref destination 'state) 'destination-committed)
  (define recovery (refile-publication-step destination 'source-fail))
  (check-equal? (hash-ref recovery 'state) 'recovery-required)
  (check-true (hash-ref recovery 'destination-committed?))
  (check-false (hash-ref recovery 'source-removed?))
  (check-equal? (hash-ref (refile-publication-step recovery 'rollback-destination) 'state)
                'rolled-back)
  (define copy (hash-set prepared 'mode 'copy))
  (check-equal? (hash-ref (refile-publication-step copy 'destination-commit) 'state)
                'completed))

(test-case "archive origins remain inspectable and visibility is explicit"
  (define properties
    (archive-origin-properties 7 "notes/projects.jan" 42 7 11 3))
  (check-equal? (cdr (assoc 'JAN_ARCHIVE_SOURCE properties)) "notes/projects.jan")
  (check-false (archive-visible? #t #f))
  (check-true (archive-visible? #t #t))
  (check-true (archive-visible? #f #f)))

(test-case "agenda source failures remain visible"
  (define summary
    (summarize-agenda-sources
     '((one confirmed 6) (two stale 0) (three unavailable 0))
     4))
  (check-equal? (hash-ref summary 'entries) 4)
  (check-true (hash-ref summary 'truncated?))
  (check-false (hash-ref summary 'complete?))
  (check-equal? (hash-ref summary 'stale) 1)
  (check-equal? (hash-ref summary 'unavailable) 1))

(test-case "multi-resource outcomes stay attributable"
  (check-equal?
   (plan-multi-resource-outcomes 'atomic '((a ready) (b ready)))
   '((a committed) (b committed)))
  (check-equal?
   (plan-multi-resource-outcomes 'atomic '((a ready) (b rejected)))
   '((a rejected) (b rejected)))
  (define recovery
    (plan-multi-resource-outcomes 'recoverable '((a committed) (b rejected))))
  (check-equal? (hash-ref recovery 'state) 'reconciliation-required)
  (check-equal?
   (plan-multi-resource-outcomes 'best-effort '((a committed) (b cancelled) (c unattempted)))
   '((a committed) (b cancelled) (c unattempted))))

(test-case "active clocks preserve unresolved recovery"
  (define active '#hasheq((schema . 1) (state . active)))
  (check-equal? (recover-active-clock active #t) 'active)
  (check-equal? (recover-active-clock active #f) 'recovery-required)
  (check-equal? (recover-active-clock '#hasheq((schema . 2) (state . active)) #t)
                'quarantined))

(test-case "planning profiles fit independent limits"
  (for ([profile (in-list planning-resource-profiles)])
    (check-true (validate-planning-resource-profile profile))
    (check-true (positive? (estimate-planning-retained-bytes profile)))
    (check-true (positive? (estimate-planning-temporary-bytes profile)))))

(test-case "planning dimensions reject one-unit overflow"
  (define boundary (last planning-resource-profiles))
  (for ([(key limit) (in-hash planning-limits)]
        #:unless (eq? key 'cancellation-entries))
    (check-false
     (validate-planning-resource-profile (hash-set boundary key (add1 limit))))))
