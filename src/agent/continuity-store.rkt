#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require db
         racket/contract/base
         racket/file
         racket/path)

(provide
 agent-continuity-schema-version
 agent-continuity-database-name
 odra-agent-continuity-store?
 (contract-out
  [open-agent-continuity-store
   (->* (path-string?)
        (#:transaction-observer procedure?)
        odra-agent-continuity-store?)]
  [close-agent-continuity-store!
   (-> odra-agent-continuity-store? void?)]
  [call-with-agent-continuity-transaction
   (-> odra-agent-continuity-store? symbol? procedure? any/c)]
  [continuity-store-task-record
   (-> odra-agent-continuity-store? string? (or/c #f vector?))]
  [continuity-store-task-records
   (-> odra-agent-continuity-store? (listof vector?))]
  [continuity-store-participant-record
   (-> odra-agent-continuity-store? string? string? (or/c #f vector?))]
  [continuity-store-participant-records
   (-> odra-agent-continuity-store? string? (listof vector?))]
  [continuity-store-interaction-record
   (-> odra-agent-continuity-store? string? (or/c #f vector?))]
  [continuity-store-interaction-records
   (-> odra-agent-continuity-store? string? (listof vector?))]
  [continuity-store-interaction-count
   (-> odra-agent-continuity-store? exact-nonnegative-integer?)]
  [continuity-store-delegation-record
   (-> odra-agent-continuity-store? string? (or/c #f vector?))]
  [continuity-store-delegation-records
   (-> odra-agent-continuity-store? string? (listof vector?))]
  [continuity-store-delegation-count
   (-> odra-agent-continuity-store? exact-nonnegative-integer?)]
  [continuity-store-request-record
   (-> odra-agent-continuity-store? string? (or/c #f vector?))]
  [continuity-store-request-records
   (-> odra-agent-continuity-store? (listof vector?))]
  [continuity-store-request-count
   (-> odra-agent-continuity-store? exact-nonnegative-integer?)]
  [continuity-store-admission-record
   (-> odra-agent-continuity-store? string? (or/c #f vector?))]
  [continuity-store-human-decision-record
   (-> odra-agent-continuity-store? string? (or/c #f vector?))]
  [continuity-store-driver-session-record
   (-> odra-agent-continuity-store? string? (or/c #f vector?))]
  [continuity-store-driver-session-records
   (-> odra-agent-continuity-store? string? (listof vector?))]
  [continuity-store-driver-session-count
   (-> odra-agent-continuity-store? exact-nonnegative-integer?)]
  [continuity-store-turn-record
   (-> odra-agent-continuity-store? string? (or/c #f vector?))]
  [continuity-store-turn-records
   (-> odra-agent-continuity-store? string? (listof vector?))]
  [continuity-store-turn-count
   (-> odra-agent-continuity-store? exact-nonnegative-integer?)]
  [continuity-store-attempt-record
   (-> odra-agent-continuity-store? string? (or/c #f vector?))]
  [continuity-store-request-attempt-records
   (-> odra-agent-continuity-store? string? (listof vector?))]
  [continuity-store-attempt-count
   (-> odra-agent-continuity-store? exact-nonnegative-integer?)]
  [continuity-store-result-record
   (-> odra-agent-continuity-store? string? (or/c #f vector?))]
  [continuity-store-request-result-records
   (-> odra-agent-continuity-store? string? (listof vector?))]
  [continuity-store-result-count
   (-> odra-agent-continuity-store? exact-nonnegative-integer?)]
  [continuity-store-audit-record
   (-> odra-agent-continuity-store? string? (or/c #f vector?))]
  [continuity-store-audit-records
   (-> odra-agent-continuity-store? exact-nonnegative-integer?
       exact-positive-integer? (listof vector?))]
  [continuity-store-audit-count
   (-> odra-agent-continuity-store? exact-nonnegative-integer?)]
  [continuity-store-recovery-session-records
   (-> odra-agent-continuity-store? (listof vector?))]
  [continuity-store-recovery-turn-records
   (-> odra-agent-continuity-store? (listof vector?))]
  [continuity-store-recovery-attempt-records
   (-> odra-agent-continuity-store? (listof vector?))]
  [continuity-store-reconciliation-record
   (-> odra-agent-continuity-store? string? (or/c #f vector?))]
  [continuity-store-reconciliation-records
   (-> odra-agent-continuity-store? (listof vector?))]
  [continuity-store-tombstone-record
   (-> odra-agent-continuity-store? string? (or/c #f vector?))]
  [continuity-store-tombstone-records
   (-> odra-agent-continuity-store? (listof vector?))]
  [continuity-store-tombstone-count
   (-> odra-agent-continuity-store? exact-nonnegative-integer?)]
  [continuity-store-rebuild-indexes!
   (-> odra-agent-continuity-store? void?)]
  [continuity-store-cleanup-reconciliation!
   (-> odra-agent-continuity-store? exact-nonnegative-integer?
       exact-positive-integer? exact-nonnegative-integer?)]))

;; These mutation procedures are intentionally private to the trusted substrate.
(provide continuity-transaction-write-task!
         continuity-transaction-write-participant!
         continuity-transaction-insert-interaction!
         continuity-transaction-write-delegation!
         continuity-transaction-insert-request!
         continuity-transaction-insert-admission!
         continuity-transaction-write-human-decision!
         continuity-transaction-write-driver-session!
         continuity-transaction-write-turn!
         continuity-transaction-write-attempt!
         continuity-transaction-insert-result!
         continuity-transaction-insert-audit!
         continuity-transaction-write-reconciliation!
         continuity-transaction-insert-tombstone!)

(define agent-continuity-schema-version 1)
(define agent-continuity-database-name "agent-substrate.sqlite3")

(struct odra-agent-continuity-store
  (connection path transaction-observer closed?)
  #:mutable)

(define (initialize-schema! connection)
  (call-with-transaction
   connection
   (lambda ()
     (query-exec
      connection
      #<<SQL
CREATE TABLE IF NOT EXISTS agent_substrate_metadata (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
)
SQL
      )
     (query-exec
      connection
      "INSERT OR IGNORE INTO agent_substrate_metadata (key, value) VALUES ('schema-version', '1')")
     (define version
       (query-value
        connection
        "SELECT value FROM agent_substrate_metadata WHERE key = 'schema-version'"))
     (unless (equal? version (number->string agent-continuity-schema-version))
       (error 'open-agent-continuity-store
              "unsupported agent continuity schema version: ~a" version))
     (query-exec
      connection
      #<<SQL
CREATE TABLE IF NOT EXISTS agent_tasks (
  id TEXT PRIMARY KEY,
  generation INTEGER NOT NULL CHECK (generation > 0),
  state TEXT NOT NULL,
  payload TEXT NOT NULL,
  created_at INTEGER NOT NULL CHECK (created_at >= 0),
  updated_at INTEGER NOT NULL CHECK (updated_at >= created_at)
)
SQL
      )
     (query-exec
      connection
      #<<SQL
CREATE TABLE IF NOT EXISTS agent_task_participants (
  task_id TEXT NOT NULL,
  agent_identity TEXT NOT NULL,
  generation INTEGER NOT NULL CHECK (generation > 0),
  active INTEGER NOT NULL CHECK (active IN (0, 1)),
  payload TEXT NOT NULL,
  joined_at INTEGER NOT NULL CHECK (joined_at >= 0),
  left_at INTEGER,
  PRIMARY KEY (task_id, agent_identity),
  FOREIGN KEY (task_id) REFERENCES agent_tasks(id)
)
SQL
      )
     (query-exec
      connection
      #<<SQL
CREATE TABLE IF NOT EXISTS agent_interactions (
  id TEXT PRIMARY KEY,
  task_id TEXT NOT NULL,
  generation INTEGER NOT NULL CHECK (generation > 0),
  kind TEXT NOT NULL,
  payload TEXT NOT NULL,
  created_at INTEGER NOT NULL CHECK (created_at >= 0),
  FOREIGN KEY (task_id) REFERENCES agent_tasks(id)
)
SQL
      )
     (query-exec
      connection
      #<<SQL
CREATE TABLE IF NOT EXISTS agent_delegations (
  id TEXT PRIMARY KEY,
  generation INTEGER NOT NULL CHECK (generation > 0),
  parent_task_id TEXT NOT NULL,
  child_task_id TEXT,
  sender_agent TEXT NOT NULL,
  recipient_agent TEXT NOT NULL,
  state TEXT NOT NULL,
  payload TEXT NOT NULL,
  created_at INTEGER NOT NULL CHECK (created_at >= 0),
  updated_at INTEGER NOT NULL CHECK (updated_at >= created_at),
  FOREIGN KEY (parent_task_id) REFERENCES agent_tasks(id),
  FOREIGN KEY (child_task_id) REFERENCES agent_tasks(id)
)
SQL
      )
     (query-exec
      connection
      #<<SQL
CREATE TABLE IF NOT EXISTS agent_capability_requests (
  id TEXT PRIMARY KEY,
  task_id TEXT NOT NULL,
  task_generation INTEGER NOT NULL CHECK (task_generation > 0),
  agent_identity TEXT NOT NULL,
  capability_identity TEXT NOT NULL,
  payload TEXT NOT NULL,
  created_at INTEGER NOT NULL CHECK (created_at >= 0),
  valid_until INTEGER NOT NULL CHECK (valid_until > created_at),
  FOREIGN KEY (task_id) REFERENCES agent_tasks(id)
)
SQL
      )
     (query-exec
      connection
      #<<SQL
CREATE TABLE IF NOT EXISTS agent_admission_decisions (
  id TEXT PRIMARY KEY,
  request_id TEXT NOT NULL UNIQUE,
  state TEXT NOT NULL,
  payload TEXT NOT NULL,
  decided_at INTEGER NOT NULL CHECK (decided_at >= 0),
  FOREIGN KEY (request_id) REFERENCES agent_capability_requests(id)
)
SQL
      )
     (query-exec
      connection
      #<<SQL
CREATE TABLE IF NOT EXISTS agent_human_decisions (
  id TEXT PRIMARY KEY,
  generation INTEGER NOT NULL CHECK (generation > 0),
  request_id TEXT NOT NULL UNIQUE,
  value TEXT NOT NULL,
  payload TEXT NOT NULL,
  created_at INTEGER NOT NULL CHECK (created_at >= 0),
  valid_until INTEGER NOT NULL CHECK (valid_until > created_at),
  consumed_by TEXT,
  FOREIGN KEY (request_id) REFERENCES agent_capability_requests(id)
)
SQL
      )
     (query-exec
      connection
      #<<SQL
CREATE TABLE IF NOT EXISTS agent_driver_sessions (
  id TEXT PRIMARY KEY,
  generation INTEGER NOT NULL CHECK (generation > 0),
  task_id TEXT NOT NULL,
  task_generation INTEGER NOT NULL CHECK (task_generation > 0),
  agent_identity TEXT NOT NULL,
  driver_identity TEXT NOT NULL,
  driver_generation INTEGER NOT NULL CHECK (driver_generation > 0),
  state TEXT NOT NULL,
  payload TEXT NOT NULL,
  opened_at INTEGER NOT NULL CHECK (opened_at >= 0),
  updated_at INTEGER NOT NULL CHECK (updated_at >= opened_at),
  closed_at INTEGER,
  FOREIGN KEY (task_id) REFERENCES agent_tasks(id)
)
SQL
      )
     (query-exec
      connection
      #<<SQL
CREATE TABLE IF NOT EXISTS agent_turns (
  id TEXT PRIMARY KEY,
  generation INTEGER NOT NULL CHECK (generation > 0),
  task_id TEXT NOT NULL,
  task_generation INTEGER NOT NULL CHECK (task_generation > 0),
  agent_identity TEXT NOT NULL,
  session_id TEXT NOT NULL,
  session_generation INTEGER NOT NULL CHECK (session_generation > 0),
  state TEXT NOT NULL,
  deadline INTEGER NOT NULL CHECK (deadline >= 0),
  payload TEXT NOT NULL,
  started_at INTEGER NOT NULL CHECK (started_at >= 0),
  updated_at INTEGER NOT NULL CHECK (updated_at >= started_at),
  ended_at INTEGER,
  FOREIGN KEY (task_id) REFERENCES agent_tasks(id),
  FOREIGN KEY (session_id) REFERENCES agent_driver_sessions(id)
)
SQL
      )
     (query-exec
      connection
      #<<SQL
CREATE TABLE IF NOT EXISTS agent_operation_attempts (
  id TEXT PRIMARY KEY,
  generation INTEGER NOT NULL CHECK (generation > 0),
  request_id TEXT NOT NULL,
  admission_decision_id TEXT NOT NULL,
  state TEXT NOT NULL,
  lease_id TEXT NOT NULL,
  lease_deadline INTEGER NOT NULL CHECK (lease_deadline >= 0),
  payload TEXT NOT NULL,
  started_at INTEGER NOT NULL CHECK (started_at >= 0),
  updated_at INTEGER NOT NULL CHECK (updated_at >= started_at),
  ended_at INTEGER,
  result_id TEXT,
  FOREIGN KEY (request_id) REFERENCES agent_capability_requests(id),
  FOREIGN KEY (admission_decision_id) REFERENCES agent_admission_decisions(id)
)
SQL
      )
     (query-exec
      connection
      #<<SQL
CREATE TABLE IF NOT EXISTS agent_operation_results (
  id TEXT PRIMARY KEY,
  request_id TEXT NOT NULL,
  attempt_id TEXT NOT NULL UNIQUE,
  state TEXT NOT NULL,
  payload TEXT NOT NULL,
  completed_at INTEGER NOT NULL CHECK (completed_at >= 0),
  FOREIGN KEY (request_id) REFERENCES agent_capability_requests(id),
  FOREIGN KEY (attempt_id) REFERENCES agent_operation_attempts(id)
)
SQL
      )
     (query-exec
      connection
      #<<SQL
CREATE TABLE IF NOT EXISTS agent_audit_events (
  sequence INTEGER PRIMARY KEY AUTOINCREMENT,
  id TEXT NOT NULL UNIQUE,
  occurred_at INTEGER NOT NULL CHECK (occurred_at >= 0),
  kind TEXT NOT NULL,
  actor TEXT NOT NULL,
  task_id TEXT,
  visibility TEXT NOT NULL,
  redaction_class TEXT NOT NULL,
  payload TEXT NOT NULL
)
SQL
      )
     (query-exec
      connection
      #<<SQL
CREATE TABLE IF NOT EXISTS agent_reconciliation_markers (
  id TEXT PRIMARY KEY,
  generation INTEGER NOT NULL CHECK (generation > 0),
  state TEXT NOT NULL,
  subject_kind TEXT NOT NULL,
  subject_id TEXT NOT NULL,
  payload TEXT NOT NULL,
  updated_at INTEGER NOT NULL CHECK (updated_at >= 0)
)
SQL
      )
     (query-exec
      connection
      #<<SQL
CREATE TABLE IF NOT EXISTS agent_definition_tombstones (
  id TEXT PRIMARY KEY,
  definition_identity TEXT NOT NULL,
  definition_generation INTEGER NOT NULL CHECK (definition_generation > 0),
  definition_kind TEXT NOT NULL,
  package_id TEXT NOT NULL,
  package_version TEXT NOT NULL,
  contribution_generation INTEGER NOT NULL CHECK (contribution_generation > 0),
  retired_at INTEGER NOT NULL CHECK (retired_at >= 0),
  payload TEXT NOT NULL,
  UNIQUE(definition_kind, definition_identity, definition_generation)
)
SQL
      )
     (query-exec
      connection
      "CREATE INDEX IF NOT EXISTS agent_participants_task_idx ON agent_task_participants(task_id, active, agent_identity)")
     (query-exec
      connection
      "CREATE INDEX IF NOT EXISTS agent_interactions_task_idx ON agent_interactions(task_id, created_at, id)")
     (query-exec
      connection
      "CREATE INDEX IF NOT EXISTS agent_delegations_task_idx ON agent_delegations(parent_task_id, created_at, id)")
     (query-exec
      connection
      "CREATE INDEX IF NOT EXISTS agent_requests_task_idx ON agent_capability_requests(task_id, created_at, id)")
     (query-exec
      connection
      "CREATE INDEX IF NOT EXISTS agent_driver_sessions_task_idx ON agent_driver_sessions(task_id, state, updated_at, id)")
     (query-exec
      connection
      "CREATE INDEX IF NOT EXISTS agent_turns_task_idx ON agent_turns(task_id, state, updated_at, id)")
     (query-exec
      connection
      "CREATE INDEX IF NOT EXISTS agent_attempts_request_idx ON agent_operation_attempts(request_id, state, updated_at, id)")
     (query-exec
      connection
      "CREATE INDEX IF NOT EXISTS agent_results_request_idx ON agent_operation_results(request_id, completed_at, id)")
     (query-exec
      connection
      "CREATE INDEX IF NOT EXISTS agent_tombstones_definition_idx ON agent_definition_tombstones(definition_kind, definition_identity, definition_generation)"))))

(define (open-agent-continuity-store
         data-root #:transaction-observer [observer void])
  (unless (procedure-arity-includes? observer 2)
    (raise-arguments-error
     'open-agent-continuity-store
     "transaction observer must accept a transaction kind and result"
     "transaction-observer" observer))
  (make-directory* data-root)
  (define database-path (build-path data-root agent-continuity-database-name))
  (define connection
    (sqlite3-connect #:database database-path
                     #:mode 'create
                     #:busy-retry-limit 1000))
  (with-handlers ([exn:fail?
                   (lambda (failure)
                     (disconnect connection)
                     (raise failure))])
    (query-exec connection "PRAGMA foreign_keys = ON")
    (initialize-schema! connection)
    (odra-agent-continuity-store
     connection database-path observer #f)))

(define (store-connection store who)
  (when (odra-agent-continuity-store-closed? store)
    (raise-arguments-error who "agent continuity store is closed"))
  (odra-agent-continuity-store-connection store))

(define (close-agent-continuity-store! store)
  (unless (odra-agent-continuity-store-closed? store)
    (disconnect (odra-agent-continuity-store-connection store))
    (set-odra-agent-continuity-store-closed?! store #t))
  (void))

(define (call-with-agent-continuity-transaction store kind procedure)
  (unless (procedure-arity-includes? procedure 1)
    (raise-arguments-error
     'call-with-agent-continuity-transaction
     "transaction procedure must accept one connection"
     "procedure" procedure))
  (call-with-transaction
   (store-connection store 'call-with-agent-continuity-transaction)
   (lambda ()
     (define result
       (procedure (odra-agent-continuity-store-connection store)))
     ((odra-agent-continuity-store-transaction-observer store) kind result)
     result)))

(define (continuity-store-task-record store identity)
  (query-maybe-row
   (store-connection store 'continuity-store-task-record)
   "SELECT generation, state, payload, created_at, updated_at FROM agent_tasks WHERE id = ?"
   identity))

(define (continuity-store-task-records store)
  (query-rows
   (store-connection store 'continuity-store-task-records)
   "SELECT id, generation, state, payload, created_at, updated_at FROM agent_tasks ORDER BY created_at, id LIMIT 10000"))

(define (continuity-store-participant-record store task-id agent-identity)
  (query-maybe-row
   (store-connection store 'continuity-store-participant-record)
   "SELECT generation, active, payload, joined_at, left_at FROM agent_task_participants WHERE task_id = ? AND agent_identity = ?"
   task-id agent-identity))

(define (continuity-store-participant-records store task-id)
  (query-rows
   (store-connection store 'continuity-store-participant-records)
   "SELECT agent_identity, generation, active, payload, joined_at, left_at FROM agent_task_participants WHERE task_id = ? ORDER BY agent_identity LIMIT 16"
   task-id))

(define (continuity-store-interaction-record store identity)
  (query-maybe-row
   (store-connection store 'continuity-store-interaction-record)
   "SELECT task_id, generation, kind, payload, created_at FROM agent_interactions WHERE id = ?"
   identity))

(define (continuity-store-interaction-records store task-id)
  (query-rows
   (store-connection store 'continuity-store-interaction-records)
   "SELECT id, generation, kind, payload, created_at FROM agent_interactions WHERE task_id = ? ORDER BY created_at, id LIMIT 10000"
   task-id))

(define (continuity-store-interaction-count store)
  (query-value
   (store-connection store 'continuity-store-interaction-count)
   "SELECT COUNT(*) FROM agent_interactions"))

(define (continuity-store-delegation-record store identity)
  (query-maybe-row
   (store-connection store 'continuity-store-delegation-record)
   "SELECT generation, parent_task_id, child_task_id, sender_agent, recipient_agent, state, payload, created_at, updated_at FROM agent_delegations WHERE id = ?"
   identity))

(define (continuity-store-delegation-records store task-id)
  (query-rows
   (store-connection store 'continuity-store-delegation-records)
   "SELECT id, generation, child_task_id, sender_agent, recipient_agent, state, payload, created_at, updated_at FROM agent_delegations WHERE parent_task_id = ? ORDER BY created_at, id LIMIT 10000"
   task-id))

(define (continuity-store-delegation-count store)
  (query-value
   (store-connection store 'continuity-store-delegation-count)
   "SELECT COUNT(*) FROM agent_delegations"))

(define (continuity-store-request-record store identity)
  (query-maybe-row
   (store-connection store 'continuity-store-request-record)
   "SELECT task_id, task_generation, agent_identity, capability_identity, payload, created_at, valid_until FROM agent_capability_requests WHERE id = ?"
   identity))

(define (continuity-store-request-records store)
  (query-rows
   (store-connection store 'continuity-store-request-records)
   "SELECT id, task_id, task_generation, agent_identity, capability_identity, payload, created_at, valid_until FROM agent_capability_requests ORDER BY created_at, id LIMIT 10000"))

(define (continuity-store-request-count store)
  (query-value
   (store-connection store 'continuity-store-request-count)
   "SELECT COUNT(*) FROM agent_capability_requests"))

(define (continuity-store-admission-record store request-id)
  (query-maybe-row
   (store-connection store 'continuity-store-admission-record)
   "SELECT id, state, payload, decided_at FROM agent_admission_decisions WHERE request_id = ?"
   request-id))

(define (continuity-store-human-decision-record store request-id)
  (query-maybe-row
   (store-connection store 'continuity-store-human-decision-record)
   "SELECT id, generation, value, payload, created_at, valid_until, consumed_by FROM agent_human_decisions WHERE request_id = ?"
   request-id))

(define (continuity-store-driver-session-record store identity)
  (query-maybe-row
   (store-connection store 'continuity-store-driver-session-record)
   "SELECT generation, task_id, task_generation, agent_identity, driver_identity, driver_generation, state, payload, opened_at, updated_at, closed_at FROM agent_driver_sessions WHERE id = ?"
   identity))

(define (continuity-store-driver-session-records store task-id)
  (query-rows
   (store-connection store 'continuity-store-driver-session-records)
   "SELECT id, generation, task_generation, agent_identity, driver_identity, driver_generation, state, payload, opened_at, updated_at, closed_at FROM agent_driver_sessions WHERE task_id = ? ORDER BY opened_at, id LIMIT 128"
   task-id))

(define (continuity-store-driver-session-count store)
  (query-value
   (store-connection store 'continuity-store-driver-session-count)
   "SELECT COUNT(*) FROM agent_driver_sessions"))

(define (continuity-store-turn-record store identity)
  (query-maybe-row
   (store-connection store 'continuity-store-turn-record)
   "SELECT generation, task_id, task_generation, agent_identity, session_id, session_generation, state, deadline, payload, started_at, updated_at, ended_at FROM agent_turns WHERE id = ?"
   identity))

(define (continuity-store-turn-records store task-id)
  (query-rows
   (store-connection store 'continuity-store-turn-records)
   "SELECT id, generation, task_generation, agent_identity, session_id, session_generation, state, deadline, payload, started_at, updated_at, ended_at FROM agent_turns WHERE task_id = ? ORDER BY started_at, id LIMIT 8"
   task-id))

(define (continuity-store-turn-count store)
  (query-value
   (store-connection store 'continuity-store-turn-count)
   "SELECT COUNT(*) FROM agent_turns"))

(define (continuity-store-attempt-record store identity)
  (query-maybe-row
   (store-connection store 'continuity-store-attempt-record)
   "SELECT generation, request_id, admission_decision_id, state, lease_id, lease_deadline, payload, started_at, updated_at, ended_at, result_id FROM agent_operation_attempts WHERE id = ?"
   identity))

(define (continuity-store-request-attempt-records store request-id)
  (query-rows
   (store-connection store 'continuity-store-request-attempt-records)
   "SELECT id, generation, admission_decision_id, state, lease_id, lease_deadline, payload, started_at, updated_at, ended_at, result_id FROM agent_operation_attempts WHERE request_id = ? ORDER BY started_at, id LIMIT 16"
   request-id))

(define (continuity-store-attempt-count store)
  (query-value
   (store-connection store 'continuity-store-attempt-count)
   "SELECT COUNT(*) FROM agent_operation_attempts"))

(define (continuity-store-result-record store identity)
  (query-maybe-row
   (store-connection store 'continuity-store-result-record)
   "SELECT request_id, attempt_id, state, payload, completed_at FROM agent_operation_results WHERE id = ?"
   identity))

(define (continuity-store-request-result-records store request-id)
  (query-rows
   (store-connection store 'continuity-store-request-result-records)
   "SELECT id, attempt_id, state, payload, completed_at FROM agent_operation_results WHERE request_id = ? ORDER BY completed_at, id LIMIT 16"
   request-id))

(define (continuity-store-result-count store)
  (query-value
   (store-connection store 'continuity-store-result-count)
   "SELECT COUNT(*) FROM agent_operation_results"))

(define (continuity-store-audit-record store identity)
  (query-maybe-row
   (store-connection store 'continuity-store-audit-record)
   "SELECT sequence, occurred_at, kind, actor, task_id, visibility, redaction_class, payload FROM agent_audit_events WHERE id = ?"
   identity))

(define (continuity-store-audit-records store after-sequence limit)
  (query-rows
   (store-connection store 'continuity-store-audit-records)
   "SELECT id, sequence, occurred_at, kind, actor, task_id, visibility, redaction_class, payload FROM agent_audit_events WHERE sequence > ? ORDER BY sequence LIMIT ?"
   after-sequence limit))

(define (continuity-store-audit-count store)
  (query-value
   (store-connection store 'continuity-store-audit-count)
   "SELECT COUNT(*) FROM agent_audit_events"))

(define (continuity-store-recovery-session-records store)
  (query-rows
   (store-connection store 'continuity-store-recovery-session-records)
   "SELECT id, generation, state FROM agent_driver_sessions WHERE state IN ('opening', 'available', 'busy', 'cancelling') ORDER BY id LIMIT 128"))

(define (continuity-store-recovery-turn-records store)
  (query-rows
   (store-connection store 'continuity-store-recovery-turn-records)
   "SELECT id, generation, state FROM agent_turns WHERE state IN ('prepared', 'running', 'waiting') ORDER BY id LIMIT 1024"))

(define (continuity-store-recovery-attempt-records store)
  (query-rows
   (store-connection store 'continuity-store-recovery-attempt-records)
   "SELECT id, generation, state FROM agent_operation_attempts WHERE state IN ('starting', 'running', 'cancelling') ORDER BY id LIMIT 10000"))

(define (continuity-store-reconciliation-record store identity)
  (query-maybe-row
   (store-connection store 'continuity-store-reconciliation-record)
   "SELECT generation, state, subject_kind, subject_id, payload, updated_at FROM agent_reconciliation_markers WHERE id = ?"
   identity))

(define (continuity-store-reconciliation-records store)
  (query-rows
   (store-connection store 'continuity-store-reconciliation-records)
   "SELECT id, generation, state, subject_kind, subject_id, payload, updated_at FROM agent_reconciliation_markers ORDER BY updated_at, id LIMIT 10000"))

(define (continuity-store-tombstone-record store identity)
  (query-maybe-row
   (store-connection store 'continuity-store-tombstone-record)
   "SELECT definition_identity, definition_generation, definition_kind, package_id, package_version, contribution_generation, retired_at, payload FROM agent_definition_tombstones WHERE id = ?"
   identity))

(define (continuity-store-tombstone-records store)
  (query-rows
   (store-connection store 'continuity-store-tombstone-records)
   "SELECT id, definition_identity, definition_generation, definition_kind, package_id, package_version, contribution_generation, retired_at, payload FROM agent_definition_tombstones ORDER BY retired_at, id LIMIT 10000"))

(define (continuity-store-tombstone-count store)
  (query-value
   (store-connection store 'continuity-store-tombstone-count)
   "SELECT COUNT(*) FROM agent_definition_tombstones"))

(define (continuity-store-rebuild-indexes! store)
  (query-exec
   (store-connection store 'continuity-store-rebuild-indexes!) "REINDEX")
  (void))

(define (continuity-store-cleanup-reconciliation! store before limit)
  (define connection
    (store-connection store 'continuity-store-cleanup-reconciliation!))
  (query-exec
   connection
   "DELETE FROM agent_reconciliation_markers WHERE id IN (SELECT id FROM agent_reconciliation_markers WHERE updated_at < ? ORDER BY updated_at, id LIMIT ?)"
   before limit)
  (query-value connection "SELECT changes()"))

(define (continuity-transaction-write-task!
         connection identity generation state payload created-at updated-at)
  (query-exec
   connection
   #<<SQL
INSERT INTO agent_tasks (id, generation, state, payload, created_at, updated_at)
VALUES (?, ?, ?, ?, ?, ?)
ON CONFLICT(id) DO UPDATE SET
  generation = excluded.generation,
  state = excluded.state,
  payload = excluded.payload,
  updated_at = excluded.updated_at
WHERE agent_tasks.generation = excluded.generation - 1
SQL
   identity generation (symbol->string state) payload created-at updated-at)
  (= 1 (query-value connection "SELECT changes()")))

(define (continuity-transaction-write-participant!
         connection task-id agent-identity generation active? payload
         joined-at left-at)
  (query-exec
   connection
   #<<SQL
INSERT INTO agent_task_participants
  (task_id, agent_identity, generation, active, payload, joined_at, left_at)
VALUES (?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(task_id, agent_identity) DO UPDATE SET
  generation = excluded.generation,
  active = excluded.active,
  payload = excluded.payload,
  left_at = excluded.left_at
WHERE agent_task_participants.generation = excluded.generation - 1
SQL
   task-id agent-identity generation (if active? 1 0) payload joined-at
   (if left-at left-at sql-null))
  (= 1 (query-value connection "SELECT changes()")))

(define (continuity-transaction-insert-interaction!
         connection identity task-id generation kind payload created-at)
  (query-exec
   connection
   "INSERT INTO agent_interactions (id, task_id, generation, kind, payload, created_at) VALUES (?, ?, ?, ?, ?, ?)"
   identity task-id generation (symbol->string kind) payload created-at))

(define (continuity-transaction-write-delegation!
         connection identity generation parent-task-id child-task-id
         sender-agent recipient-agent state payload created-at updated-at)
  (query-exec
   connection
   #<<SQL
INSERT INTO agent_delegations
  (id, generation, parent_task_id, child_task_id, sender_agent, recipient_agent, state, payload, created_at, updated_at)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(id) DO UPDATE SET
  generation = excluded.generation,
  child_task_id = excluded.child_task_id,
  state = excluded.state,
  payload = excluded.payload,
  updated_at = excluded.updated_at
WHERE agent_delegations.generation = excluded.generation - 1
SQL
   identity generation parent-task-id (if child-task-id child-task-id sql-null)
   sender-agent recipient-agent (symbol->string state) payload created-at
   updated-at)
  (= 1 (query-value connection "SELECT changes()")))

(define (continuity-transaction-insert-request!
         connection identity task-id task-generation agent-identity
         capability-identity payload created-at valid-until)
  (query-exec
   connection
   "INSERT INTO agent_capability_requests (id, task_id, task_generation, agent_identity, capability_identity, payload, created_at, valid_until) VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
   identity task-id task-generation agent-identity capability-identity payload
   created-at valid-until))

(define (continuity-transaction-insert-admission!
         connection identity request-id state payload decided-at)
  (query-exec
   connection
   "INSERT INTO agent_admission_decisions (id, request_id, state, payload, decided_at) VALUES (?, ?, ?, ?, ?)"
   identity request-id (symbol->string state) payload decided-at))

(define (continuity-transaction-write-human-decision!
         connection identity generation request-id value payload created-at
         valid-until consumed-by)
  (query-exec
   connection
   #<<SQL
INSERT INTO agent_human_decisions
  (id, generation, request_id, value, payload, created_at, valid_until, consumed_by)
VALUES (?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(id) DO UPDATE SET
  generation = excluded.generation,
  payload = excluded.payload,
  consumed_by = excluded.consumed_by
WHERE agent_human_decisions.generation = excluded.generation - 1
SQL
   identity generation request-id (symbol->string value) payload created-at
   valid-until (if consumed-by consumed-by sql-null))
  (= 1 (query-value connection "SELECT changes()")))

(define (continuity-transaction-write-driver-session!
         connection identity generation task-id task-generation agent-identity
         driver-identity driver-generation state payload opened-at updated-at
         closed-at)
  (query-exec
   connection
   #<<SQL
INSERT INTO agent_driver_sessions
  (id, generation, task_id, task_generation, agent_identity, driver_identity, driver_generation, state, payload, opened_at, updated_at, closed_at)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(id) DO UPDATE SET
  generation = excluded.generation,
  task_generation = excluded.task_generation,
  driver_identity = excluded.driver_identity,
  driver_generation = excluded.driver_generation,
  state = excluded.state,
  payload = excluded.payload,
  updated_at = excluded.updated_at,
  closed_at = excluded.closed_at
WHERE agent_driver_sessions.generation = excluded.generation - 1
SQL
   identity generation task-id task-generation agent-identity driver-identity
   driver-generation (symbol->string state) payload opened-at updated-at
   (if closed-at closed-at sql-null))
  (= 1 (query-value connection "SELECT changes()")))

(define (continuity-transaction-write-turn!
         connection identity generation task-id task-generation
         agent-identity session-id session-generation state deadline payload
         started-at updated-at ended-at)
  (query-exec
   connection
   #<<SQL
INSERT INTO agent_turns
  (id, generation, task_id, task_generation, agent_identity, session_id, session_generation, state, deadline, payload, started_at, updated_at, ended_at)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(id) DO UPDATE SET
  generation = excluded.generation,
  state = excluded.state,
  payload = excluded.payload,
  updated_at = excluded.updated_at,
  ended_at = excluded.ended_at
WHERE agent_turns.generation = excluded.generation - 1
SQL
   identity generation task-id task-generation agent-identity session-id
   session-generation (symbol->string state) deadline payload started-at
   updated-at (if ended-at ended-at sql-null))
  (= 1 (query-value connection "SELECT changes()")))

(define (continuity-transaction-write-attempt!
         connection identity generation request-id admission-decision-id state
         lease-id lease-deadline payload started-at updated-at ended-at
         result-id)
  (query-exec
   connection
   #<<SQL
INSERT INTO agent_operation_attempts
  (id, generation, request_id, admission_decision_id, state, lease_id, lease_deadline, payload, started_at, updated_at, ended_at, result_id)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(id) DO UPDATE SET
  generation = excluded.generation,
  state = excluded.state,
  payload = excluded.payload,
  updated_at = excluded.updated_at,
  ended_at = excluded.ended_at,
  result_id = excluded.result_id
WHERE agent_operation_attempts.generation = excluded.generation - 1
SQL
   identity generation request-id admission-decision-id (symbol->string state)
   lease-id lease-deadline payload started-at updated-at
   (if ended-at ended-at sql-null) (if result-id result-id sql-null))
  (= 1 (query-value connection "SELECT changes()")))

(define (continuity-transaction-insert-result!
         connection identity request-id attempt-id state payload completed-at)
  (query-exec
   connection
   "INSERT INTO agent_operation_results (id, request_id, attempt_id, state, payload, completed_at) VALUES (?, ?, ?, ?, ?, ?)"
   identity request-id attempt-id (symbol->string state) payload completed-at))

(define (continuity-transaction-insert-audit!
         connection identity occurred-at kind actor task-id visibility
         redaction-class payload)
  (query-exec
   connection
   "INSERT INTO agent_audit_events (id, occurred_at, kind, actor, task_id, visibility, redaction_class, payload) VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
   identity occurred-at (symbol->string kind) actor
   (if task-id task-id sql-null) (symbol->string visibility)
   (symbol->string redaction-class) payload)
  (query-value connection "SELECT last_insert_rowid()"))

(define (continuity-transaction-write-reconciliation!
         connection identity generation state subject-kind subject-id payload
         updated-at)
  (query-exec
   connection
   #<<SQL
INSERT INTO agent_reconciliation_markers
  (id, generation, state, subject_kind, subject_id, payload, updated_at)
VALUES (?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(id) DO UPDATE SET
  generation = excluded.generation,
  state = excluded.state,
  payload = excluded.payload,
  updated_at = excluded.updated_at
WHERE agent_reconciliation_markers.generation = excluded.generation - 1
SQL
   identity generation (symbol->string state) (symbol->string subject-kind)
   subject-id payload updated-at)
  (= 1 (query-value connection "SELECT changes()")))

(define (continuity-transaction-insert-tombstone!
         connection identity definition-identity definition-generation
         definition-kind package-id package-version contribution-generation
         retired-at payload)
  (query-exec
   connection
   #<<SQL
INSERT OR IGNORE INTO agent_definition_tombstones
  (id, definition_identity, definition_generation, definition_kind, package_id, package_version, contribution_generation, retired_at, payload)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
SQL
   identity definition-identity definition-generation
   (symbol->string definition-kind) package-id package-version
   contribution-generation retired-at payload)
  (= 1 (query-value connection "SELECT changes()")))
