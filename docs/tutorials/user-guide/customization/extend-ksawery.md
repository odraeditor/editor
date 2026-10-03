<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Extend Ksawery from Personal Configuration

This chapter adds one personal Ksawery contributor, observes its Status and
Ref presentation, runs core and external actions, uses conflict
guidance, inspects and replaces the provider, and returns to the original
editor canvas.

## Before You Begin

If you enter this chapter directly, first complete [Prepare the User Guide
Exercises](../getting-started/prepare-exercises.md).

Complete [Write and Reload a Personal Command](personal-commands.md). Keep the
isolated configuration root from that chapter and open a changed file inside a
disposable Git repository.

`ksawery-status` remains the only external Ksawery command. A contributor adds
behavior inside that session; it does not create another repository model or
receive direct Git, process, refresh, renderer, or buffer authority.

## Declare One Contributor

Create `~/odra-guide/config/odra/modules/ksawery-tools.rkt` by pasting this
complete chapter-owned file:

```racket
#lang racket/base

(require odra/commands)

(provide odra-ksawery-contributor
         odra-ksawery-command-families)

(define contributions
  (list
   (make-ksawery-contribution
    1 'status.review 'status-section
    #:observations '(status)
    #:authorities '(inspect present))
   (make-ksawery-contribution
    2 'annotation.review 'annotation
    #:observations '(refs)
    #:authorities '(inspect present))
   (make-ksawery-contribution
    3 'family.review 'command-family
    #:observations '(status)
    #:authorities '(inspect request-core-action submit-external-operation))
   (make-ksawery-contribution
    4 'operation.inspect 'external-operation
    #:observations '(status process)
    #:authorities '(inspect submit-external-operation))
   (make-ksawery-contribution
    5 'conflict.guidance 'conflict-assistance
    #:observations '(conflict)
    #:authorities '(inspect present assist-conflict))
   (make-ksawery-contribution
    6 'provider.conflict 'provider-role
    #:provider-role 'conflict-assistance
    #:observations '(status sequence conflict process)
    #:authorities '(inspect present assist-conflict))))

(define (status-provider _observation)
  (list
   (make-ksawery-status-section
    1 'status.review "Repository review"
    (list
     (make-ksawery-status-item
      1 'review.ready "Personal review tools active"
      #:style 'success)))))

(define (annotation-provider observation)
  (define targets (hash-ref observation 'targets))
  (if (or (not (eq? (hash-ref observation 'family) 'refs))
          (null? targets))
      '()
      (list
       (make-ksawery-annotation
        2 1 'annotation.review (car targets)
        #:label "Review this ref"
        #:detail "Personal provider annotation"
        #:severity 'information
        #:style 'information))))

(define (conflict-provider contributor request observation)
  (define provider
    (make-ksawery-conflict-provider
     contributor 6 11 1 'conflict.review "Conflict review helper"
     '(text truncated missing-stage)
     '(present-guidance)
     #:lifecycle 'active))
  (make-ksawery-conflict-guidance
   request provider
   (string-append
    "Inspect "
    (ksawery-conflict-target-path
     (ksawery-conflict-observation-target observation)))))

(define odra-ksawery-contributor
  (make-ksawery-contributor
   'personal.repository-review
   "Repository review tools"
   "modules/ksawery-tools.rkt"
   1
   contributions
   #:status-provider status-provider
   #:annotation-provider annotation-provider
   #:conflict-assistance-provider conflict-provider))

(define stage-action
  (make-ksawery-command-action
   1 'action.stage "Stage selected path"
   'request-core-action '(status)
   #:targets '(path)
   #:operation 'idle
   #:core-operation 'stage
   #:mutates-repository? #t
   #:confirmation-required? #t))

(define inspect-action
  (make-ksawery-command-action
   2 'action.inspect "Inspect repository"
   'submit-external-operation '(status)
   #:operation 'idle
   #:confirmation-required? #t
   #:external-operation
   (lambda (_context _values)
     (make-ksawery-operation-plan
      odra-ksawery-contributor
      4 21 'operation.inspect "Inspect repository" 1
      (make-ksawery-operation-git)
      (list "status" "--short")
      'read-only
      '(status process)
      (make-ksawery-operation-verifier
       'observation-available #:observation 'status)))))

(define review-family
  (make-ksawery-command-family
   odra-ksawery-contributor
   3 11 'family.review "Repository review" 1
   '(status)
   '()
   (list stage-action inspect-action)))

(define odra-ksawery-command-families (list review-family))
```

The numeric identities are contributor-local stable identities. Increase the
contributor, family, provider, and operation generations when their respective
definitions change. The source string is logical provenance shown by
inspection; it is not an executable path.

## Export the Contributor

Require the new module from `init.rkt` and add both names to its existing
exports:

```racket
(require "modules/ksawery-tools.rkt")

(provide odra-ksawery-contributor
         odra-ksawery-command-families)
```

Run `M-x reload-personal-commands`. A successful atomic reload reports
`Personal commands reloaded`. Run `M-x ksawery-status`; the final `Extensions`
area now contains `Repository review` and `Personal review tools active` after
all core Status groups.

Press `b` to open Refs. The first compatible Ref carries `Review this ref`
immediately after its core row. The annotation is disposable metadata bound to
that exact Ref observation; refresh, reload, disablement, or target removal
removes stale annotation output.

## Run the Contributed Actions

From Ksawery Status, select one changed path and open `M-x`. Search for these
shared command identities:

```text
personal.repository-review/family.review/action.stage
personal.repository-review/family.review/action.inspect
```

The Stage action opens the family surface and requires an exact confirmation
before delegating to the existing checked core Stage workflow. The Inspect
action also requires confirmation, then submits the declared `git status
--short` plan to Ksawery Process. Native code owns the repository directory,
fixed environment, child lifetime, output limits, refresh, and verifier.

Press `$` to inspect the active or completed Process record. A zero child exit
does not by itself mean verified success; the declared Status refresh must also
produce compatible repository evidence.

## Use the Raw Escape Hatch

Press `!` inside Ksawery to open the distinct raw repository-command route.
Choose Git or shell mode, enter a bounded command, and press `C-Enter` to review
the exact request. Cancel with `C-g` or `q`, or confirm the request explicitly.

Raw execution is built in and higher-authority. It is not ordinary contributor
authority, does not add another external command, and cannot claim verified
success without a compatible typed verifier. Its bounded public output and
terminal outcome appear in Process.

## Ask for Conflict Guidance

Create or open a text merge conflict, open Sequence with `o`, select the
conflict, and press Enter. Press `H` on the Conflict surface. The provider
presents `Conflict review helper` and guidance for the exact copied path.

The declared `truncated` and `missing-stage` classes are important because
bounded Conflict observations may omit index material while retaining its
identity. Unsupported classes select the built-in no-op fallback. Guidance
cannot mark the path resolved, stage content, or continue the sequence; those
remain separate checked core actions.

## Inspect, Disable, and Recover

Press `v` from Ksawery to open provider inspection. It reports contributor and
personal generations, personal provenance, lifecycle, authorities,
contributions, selected limits, resource use, latest failure, active Process,
and the effective provider. Press `q` to return to the exact prior Ksawery
surface and position.

Replace one valid expression in the module with malformed syntax and press
`L`. The reload is rejected, the previous confirmed generation remains active,
and inspection shows the bounded failure. Restore the source, increase the
changed generations, and press `L` again to activate the replacement.

Press `z` in provider inspection while all repository and provider work is
idle. The personal provider becomes disabled and built-in fallback remains
usable. A later valid reload activates a new generation. Reload and disablement
do not leave stale commands, sections, annotations, capabilities, children, or
Racket roots.

## Restore the Editor Canvas

Press `q` until Status closes. Odra restores the exact editor target retained
when Ksawery opened; external filesystem writes made during the session do not
silently replace an already-open buffer.

## Verify the Result

You have completed this chapter when one personal generation loads atomically,
its Status section and Ref annotation appear, both contributed actions run
through their checked owners, raw cancellation causes no effect, conflict
guidance leaves core resolution authority unchanged, inspection exposes
provenance and limits, rejected reload and disablement preserve fallback, and
Ksawery restores the original buffer.

For exact commands, keys, lifecycle, limits, and failure behavior, see the
[Ksawery Reference](../../../reference/ksawery/index.md). For the complete
public Racket surface, see the
[Programmable Command Reference](../../../reference/programmable-commands/index.md).
For the authority model, see
[Why Ksawery Owns a Full-Canvas Session](../../../explanation/ksawery-session-ownership/index.md).

---

[Previous: Write and Reload a Personal Command](personal-commands.md) ·
[User Guide](../index.md) ·
[Next: Configure Supported Surfaces](configure-visible-behavior.md)
