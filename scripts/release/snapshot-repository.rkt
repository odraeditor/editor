#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require json
         racket/cmdline
         racket/file
         racket/list
         racket/path
         racket/port
         racket/string
         racket/system)

(provide (struct-out prepared-snapshot)
         (struct-out transfer-result)
         (struct-out snapshot-target-state)
         snapshot-candidate-reference
         inspect-snapshot-target
         prepare-snapshot-commit!
         transfer-snapshot-candidate!
         verify-snapshot-candidate!
         publish-snapshot-release!)

(struct prepared-snapshot
  (workspace version candidate-ref commit tree parent source-date-epoch)
  #:transparent)

(struct transfer-result (state ref commit tree checkout) #:transparent)
(struct snapshot-target-state (candidate main tag) #:transparent)

(define semver-pattern
  #px"^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$")
(define commit-pattern #px"^[0-9a-f]{40}$")
(define credential-url-pattern #px"^[a-z][a-z0-9+.-]*://[^/@[:space:]]+@")
(define credential-scp-pattern #px"^[^/@:[:space:]]+@[^/:[:space:]]+:")
(define authorization-name-pattern #px"^[A-Z][A-Z0-9_]*$")

(define (snapshot-candidate-reference version)
  (unless (and (string? version) (regexp-match? semver-pattern version))
    (raise-arguments-error 'snapshot-candidate-reference
                           "version must use canonical MAJOR.MINOR.PATCH form"
                           "version" version))
  (string-append "refs/heads/candidates/v" version))

(define (release-tag-reference version)
  (string-append "refs/tags/v" version))

(define (safe-target? target)
  (and (string? target)
       (not (string=? target ""))
       (not (regexp-match? #px"[[:cntrl:]]" target))
       (not (regexp-match? credential-url-pattern target))
       (not (regexp-match? credential-scp-pattern target))))

(define (authorization-value name)
  (cond
    [(not name) #f]
    [(not (and (string? name) (regexp-match? authorization-name-pattern name)))
     (raise-arguments-error 'snapshot-repository
                            "authorization environment name is invalid"
                            "name" name)]
    [else
     (define value (getenv name))
     (unless (and value (not (string=? value "")))
       (raise-user-error 'snapshot-repository
                         "authorization environment variable is unavailable: ~a"
                         name))
     value]))

(define (git-environment authorization-name [identity-epoch #f])
  (define environment
    (environment-variables-copy (current-environment-variables)))
  (environment-variables-set! environment #"GIT_TERMINAL_PROMPT" #"0")
  (define authorization (authorization-value authorization-name))
  (when authorization
    (environment-variables-set! environment #"GIT_CONFIG_COUNT" #"1")
    (environment-variables-set! environment #"GIT_CONFIG_KEY_0"
                                #"http.extraHeader")
    (environment-variables-set! environment #"GIT_CONFIG_VALUE_0"
                                (string->bytes/utf-8
                                 (string-append "Authorization: " authorization))))
  (when identity-epoch
    (define date-value (format "@~a +0000" identity-epoch))
    (define identity-environment
      (list (cons #"GIT_AUTHOR_NAME" #"Odra Release")
            (cons #"GIT_AUTHOR_EMAIL" #"release@odraeditor.org")
            (cons #"GIT_COMMITTER_NAME" #"Odra Release")
            (cons #"GIT_COMMITTER_EMAIL" #"release@odraeditor.org")
            (cons #"GIT_AUTHOR_DATE" (string->bytes/utf-8 date-value))
            (cons #"GIT_COMMITTER_DATE" (string->bytes/utf-8 date-value))))
    (for ([entry (in-list identity-environment)])
      (environment-variables-set! environment (car entry) (cdr entry))))
  environment)

(define (required-git)
  (or (find-executable-path "git")
      (raise-user-error 'snapshot-repository "git is unavailable")))

(define (redact value secret)
  (if (and secret (not (string=? secret "")))
      (string-replace value secret "<redacted>")
      value))

(define (run-git repository arguments
                 #:authorization-env [authorization-name #f]
                 #:identity-epoch [identity-epoch #f]
                 #:allow-failure? [allow-failure? #f])
  (define authorization (and authorization-name (authorization-value authorization-name)))
  (define prefix
    (if repository
        (list "-C" (path->string (path->complete-path repository)))
        '()))
  (define-values (process output input errors)
    (parameterize ([current-environment-variables
                    (git-environment authorization-name identity-epoch)])
      (apply subprocess #f #f #f (required-git) (append prefix arguments))))
  (close-output-port input)
  (define standard-output (port->string output))
  (define standard-error (port->string errors))
  (subprocess-wait process)
  (define status (subprocess-status process))
  (unless (or (zero? status) allow-failure?)
    (raise-user-error 'snapshot-repository
                      "git command failed: ~a"
                      (string-trim (redact standard-error authorization))))
  (values status (string-trim standard-output) (string-trim standard-error)))

(define (git-output repository arguments
                    #:authorization-env [authorization-name #f]
                    #:identity-epoch [identity-epoch #f])
  (define-values (_status output _error)
    (run-git repository arguments
             #:authorization-env authorization-name
             #:identity-epoch identity-epoch))
  output)

(define (ensure-absent path who field)
  (when (file-or-directory-type path #f)
    (raise-arguments-error who
                           "destination must be absent"
                           field path)))

(define (remote-ref target reference authorization-name)
  (unless (safe-target? target)
    (raise-arguments-error 'snapshot-repository
                           "target must not contain credentials or control characters"
                           "target" target))
  (define output
    (git-output #f
                (list "ls-remote" "--refs" target reference)
                #:authorization-env authorization-name))
  (cond
    [(string=? output "") #f]
    [else
     (define fields (string-split output))
     (unless (and (= (length fields) 2)
                  (regexp-match? commit-pattern (car fields))
                  (string=? (cadr fields) reference))
       (raise-user-error 'snapshot-repository
                         "target returned an invalid ref result: ~a"
                         reference))
     (car fields)]))

(define (inspect-snapshot-target target version
                                 #:authorization-env [authorization-name #f])
  (define candidate-ref (snapshot-candidate-reference version))
  (define tag-ref (release-tag-reference version))
  (snapshot-target-state
   (remote-ref target candidate-ref authorization-name)
   (remote-ref target "refs/heads/main" authorization-name)
   (remote-ref target tag-ref authorization-name)))

(define (fetch-main-parent! workspace target authorization-name)
  (define reference "refs/heads/main")
  (define commit (remote-ref target reference authorization-name))
  (and commit
       (let* ([_ (git-output workspace
                             (list "fetch" "--no-tags" target reference)
                             #:authorization-env authorization-name)]
              [fetched
               (git-output workspace (list "rev-parse" "FETCH_HEAD^{commit}"))])
         (unless (string=? fetched commit)
           (raise-user-error 'snapshot-repository
                             "fetched main identity differs from target"))
         commit)))

(define (prepare-snapshot-commit! snapshot-tree workspace version source-date-epoch
                                  #:target [target #f]
                                  #:authorization-env [authorization-name #f])
  (snapshot-candidate-reference version)
  (unless (and (exact-nonnegative-integer? source-date-epoch)
               (< source-date-epoch (expt 2 63)))
    (raise-arguments-error 'prepare-snapshot-commit!
                           "source date epoch must be an unsigned 63-bit integer"
                           "source-date-epoch" source-date-epoch))
  (define source (path->complete-path snapshot-tree))
  (unless (directory-exists? source)
    (raise-arguments-error 'prepare-snapshot-commit!
                           "snapshot tree must exist"
                           "snapshot-tree" source))
  (define destination (path->complete-path workspace))
  (ensure-absent destination 'prepare-snapshot-commit! "workspace")
  (copy-directory/files source destination)
  (git-output destination (list "init" "--quiet" "--initial-branch=main"))
  (define parent
    (and target (fetch-main-parent! destination target authorization-name)))
  (git-output destination (list "add" "--all"))
  (define tree (git-output destination (list "write-tree")))
  (define commit-arguments
    (append (list "commit-tree" tree)
            (if parent (list "-p" parent) '())
            (list "-m" (format "Odra v~a source snapshot" version))))
  (define commit
    (git-output destination commit-arguments #:identity-epoch source-date-epoch))
  (define candidate-ref (snapshot-candidate-reference version))
  (git-output destination (list "update-ref" candidate-ref commit))
  (prepared-snapshot destination version candidate-ref commit tree parent
                     source-date-epoch))

(define (transfer-snapshot-candidate! prepared target
                                     #:authorization-env [authorization-name #f])
  (define reference (prepared-snapshot-candidate-ref prepared))
  (define commit (prepared-snapshot-commit prepared))
  (define existing
    (snapshot-target-state-candidate
     (inspect-snapshot-target
      target
      (prepared-snapshot-version prepared)
      #:authorization-env authorization-name)))
  (cond
    [(and existing (string=? existing commit))
     (transfer-result 'identical reference commit
                      (prepared-snapshot-tree prepared) #f)]
    [existing
     (raise-user-error 'transfer-snapshot-candidate!
                       "candidate ref conflicts with prepared snapshot: ~a"
                       reference)]
    [else
     (git-output (prepared-snapshot-workspace prepared)
                 (list "push" target (string-append commit ":" reference))
                 #:authorization-env authorization-name)
     (define resolved (remote-ref target reference authorization-name))
     (unless (and resolved (string=? resolved commit))
       (raise-user-error 'transfer-snapshot-candidate!
                         "candidate ref was not transferred exactly: ~a"
                         reference))
     (transfer-result 'created reference commit
                      (prepared-snapshot-tree prepared) #f)]))

(define (verify-snapshot-candidate! target reference expected-commit expected-tree
                                   checkout
                                   #:authorization-env [authorization-name #f])
  (unless (and (regexp-match? #px"^refs/heads/candidates/v" reference)
               (regexp-match? commit-pattern expected-commit)
               (regexp-match? commit-pattern expected-tree))
    (raise-arguments-error 'verify-snapshot-candidate!
                           "candidate identity is invalid"
                           "reference" reference))
  (define destination (path->complete-path checkout))
  (ensure-absent destination 'verify-snapshot-candidate! "checkout")
  (make-directory destination)
  (git-output destination (list "init" "--quiet" "--initial-branch=main"))
  (git-output destination
              (list "fetch" "--no-tags" "--depth=1" target reference)
              #:authorization-env authorization-name)
  (define fetched (git-output destination (list "rev-parse" "FETCH_HEAD^{commit}")))
  (define tree (git-output destination (list "rev-parse" "FETCH_HEAD^{tree}")))
  (unless (and (string=? fetched expected-commit)
               (string=? tree expected-tree))
    (raise-user-error 'verify-snapshot-candidate!
                      "fresh checkout identity differs from prepared snapshot"))
  (git-output destination (list "checkout" "--quiet" "--detach" fetched))
  (transfer-result 'verified reference fetched tree destination))

(define (local-tag-object! prepared)
  (define workspace (prepared-snapshot-workspace prepared))
  (define tag-ref (release-tag-reference (prepared-snapshot-version prepared)))
  (define commit (prepared-snapshot-commit prepared))
  (git-output workspace
              (list "tag" "--annotate" "--force"
                    "--message" (format "Odra v~a" (prepared-snapshot-version prepared))
                    (substring tag-ref (string-length "refs/tags/"))
                    commit)
              #:identity-epoch (prepared-snapshot-source-date-epoch prepared))
  (values tag-ref (git-output workspace (list "rev-parse" tag-ref))))

(define (publish-snapshot-release! prepared target
                                  #:authorization-env [authorization-name #f])
  (define commit (prepared-snapshot-commit prepared))
  (define parent (prepared-snapshot-parent prepared))
  (define main-ref "refs/heads/main")
  (define-values (tag-ref tag-object) (local-tag-object! prepared))
  (define target-state
    (inspect-snapshot-target target
                             (prepared-snapshot-version prepared)
                             #:authorization-env authorization-name))
  (define remote-main (snapshot-target-state-main target-state))
  (define remote-tag (snapshot-target-state-tag target-state))
  (unless (or (not remote-main)
              (string=? remote-main commit)
              (and parent (string=? remote-main parent)))
    (raise-user-error 'publish-snapshot-release!
                      "release main ref conflicts with prepared snapshot"))
  (when (and remote-tag (not (string=? remote-tag tag-object)))
    (raise-user-error 'publish-snapshot-release!
                      "release tag conflicts with prepared snapshot: ~a"
                      tag-ref))
  (define specifications
    (append
     (if (and remote-main (string=? remote-main commit))
         '()
         (list (string-append commit ":" main-ref)))
     (if remote-tag '() (list (string-append tag-ref ":" tag-ref)))))
  (unless (null? specifications)
    (git-output (prepared-snapshot-workspace prepared)
                (append (list "push" "--atomic" target) specifications)
                #:authorization-env authorization-name))
  (unless (and (equal? (remote-ref target main-ref authorization-name) commit)
               (equal? (remote-ref target tag-ref authorization-name) tag-object))
    (raise-user-error 'publish-snapshot-release!
                      "release identities were not transferred exactly"))
  (transfer-result (if (null? specifications) 'identical 'created)
                   tag-ref commit (prepared-snapshot-tree prepared) #f))

(module+ main
  (define command #f)
  (define snapshot #f)
  (define workspace #f)
  (define version #f)
  (define epoch #f)
  (define target #f)
  (define authorization-name #f)
  (define checkout #f)
  (command-line
   #:program "snapshot-repository.rkt"
   #:once-each
   [("--snapshot") path "Audited exported tree" (set! snapshot path)]
   [("--workspace") path "Fresh snapshot repository workspace"
                         (set! workspace path)]
   [("--version") value "Canonical release version" (set! version value)]
   [("--source-date-epoch") value "Snapshot timestamp"
                                   (set! epoch (string->number value))]
   [("--target") value "Credential-free target URL or path"
                        (set! target value)]
   [("--authorization-env") name "Environment variable containing authorization"
                                  (set! authorization-name name)]
   [("--checkout") path "Fresh verification checkout" (set! checkout path)]
   #:args (action)
   (set! command action))
  (unless (and (member command '("candidate" "publish"))
               snapshot workspace version epoch target
               (or (equal? command "publish") checkout))
    (raise-user-error
     'snapshot-repository
     "candidate or publish requires snapshot, workspace, version, source-date-epoch, target, and candidate checkout"))
  (define prepared
    (prepare-snapshot-commit! snapshot workspace version epoch
                              #:target target
                              #:authorization-env authorization-name))
  (define result
    (cond
      [(equal? command "candidate")
       (define transfer
         (transfer-snapshot-candidate! prepared target
                                       #:authorization-env authorization-name))
       (define verification
         (verify-snapshot-candidate! target
                                     (prepared-snapshot-candidate-ref prepared)
                                     (prepared-snapshot-commit prepared)
                                     (prepared-snapshot-tree prepared)
                                     checkout
                                     #:authorization-env authorization-name))
       (hasheq 'state (symbol->string (transfer-result-state transfer))
               'candidate_ref (prepared-snapshot-candidate-ref prepared)
               'snapshot_commit (prepared-snapshot-commit prepared)
               'snapshot_tree (prepared-snapshot-tree prepared)
               'verification
               (symbol->string (transfer-result-state verification)))]
      [else
       (define published
         (publish-snapshot-release! prepared target
                                    #:authorization-env authorization-name))
       (hasheq 'state (symbol->string (transfer-result-state published))
               'release_ref (transfer-result-ref published)
               'snapshot_commit (transfer-result-commit published)
               'snapshot_tree (transfer-result-tree published))]))
  (write-json result)
  (newline))
