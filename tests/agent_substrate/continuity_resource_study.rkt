#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         "../../src/agent/continuity.rkt")

(define root
  (make-temporary-file "odra-agent-continuity-resource~a" 'directory))

(dynamic-wind
  void
  (lambda ()
    (define store (open-agent-continuity-store root))
    (define origin (make-agent-task-origin 'local-user 'resource.study))
    (define started (current-inexact-milliseconds))
    (for ([index (in-range maximum-nonterminal-agent-tasks)])
      (define task-id (string->symbol (format "task.resource-~a" index)))
      (define created
        (create-agent-task!
         store task-id "Bounded resource study task." origin index
         #:owner-agent 'example.owner))
      (unless (odra-agent-task? created)
        (error 'continuity-resource-study
               "task ~a was rejected before the hard limit" index)))
    (define rejected
      (create-agent-task!
       store 'task.resource-overflow "Rejected overflow task." origin 1000))
    (unless (and (odra-agent-continuity-denial? rejected)
                 (eq? (odra-agent-continuity-denial-code rejected)
                      'task-limit))
      (error 'continuity-resource-study
             "the nonterminal task hard limit was not enforced"))
    (define participant-task (car (inspect-agent-tasks store)))
    (for ([index (in-range 1 maximum-agent-task-participants)])
      (define joined
        (join-agent-task!
         store
         (odra-agent-task-identity participant-task)
         1
         (string->symbol (format "example.participant-~a" index))
         'observer
         (+ 1000 index)))
      (unless (odra-agent-task-participant? joined)
        (error 'continuity-resource-study
               "participant ~a was rejected before the hard limit" index)))
    (define participant-rejected
      (join-agent-task!
       store
       (odra-agent-task-identity participant-task)
       1 'example.participant-overflow 'observer 2000))
    (unless (and (odra-agent-continuity-denial? participant-rejected)
                 (eq? (odra-agent-continuity-denial-code participant-rejected)
                      'participant-limit))
      (error 'continuity-resource-study
             "the participant hard limit was not enforced"))
    (collect-garbage)
    (printf
     "agent-continuity-resource: tasks=~a participants=~a elapsed-ms=~a memory-bytes=~a database-bytes=~a next-task=~a next-participant=~a\n"
     maximum-nonterminal-agent-tasks
     maximum-agent-task-participants
     (- (current-inexact-milliseconds) started)
     (current-memory-use)
     (file-size (build-path root agent-continuity-database-name))
     (odra-agent-continuity-denial-code rejected)
     (odra-agent-continuity-denial-code participant-rejected))
    (close-agent-continuity-store! store))
  (lambda () (delete-directory/files root)))
