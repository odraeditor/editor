#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require json
         racket/cmdline
         racket/file
         racket/format
         racket/path
         racket/port
         racket/string
         racket/system)

(provide docker-smoke-arguments
         make-smoke-temporary-directory
         validation-image-reference?)

(define image-reference-pattern
  #px"^[^[:space:]@]+@sha256:[0-9a-f]{64}$")
(define local-validation-image-pattern
  #px"^odra-snapshot-validation:[0-9a-f]{12}$")
(define process-timeout-seconds 20)
(define transcript-tail-limit 8192)
(define restoration-sequence #"\33[?25h\33[0m\r\n")
(define terminal-output-marker #"\316\250")

(define (validation-image-reference? value)
  (and (string? value)
       (or (regexp-match? image-reference-pattern value)
           (regexp-match? local-validation-image-pattern value))))

(define (path-string value)
  (path->string (simple-form-path value)))

(define (regular-file? path)
  (eq? (file-or-directory-type path #f) 'file))

(define (mount-safe-path value)
  (define text (path-string value))
  (when (regexp-match? #rx"[,\r\n]" text)
    (raise-arguments-error 'docker-smoke-arguments
                           "mount path contains an unsupported character"
                           "path" text))
  text)

(define (docker-smoke-arguments image bundle-root working-directory)
  (unless (validation-image-reference? image)
    (raise-arguments-error 'docker-smoke-arguments
                           "validation image is not pinned by digest"
                           "image" image))
  (define bundle (mount-safe-path bundle-root))
  (define working (mount-safe-path working-directory))
  (list
   "run" "--rm" "--interactive"
   "--network" "none"
   "--cpus" "2"
   "--memory" "1073741824"
   "--pids-limit" "128"
   "--read-only"
   "--security-opt" "no-new-privileges"
   "--cap-drop" "ALL"
   "--user" "65532:65532"
   "--env" "HOME=/home/preview"
   "--env" "XDG_CONFIG_HOME=/home/preview/.config"
   "--env" "TERM=xterm-256color"
   "--env" "COLORTERM=truecolor"
   "--env" "SHELL=/bin/sh"
   "--tmpfs" "/tmp:rw,nosuid,nodev,size=67108864,mode=1777"
   "--tmpfs" "/home/preview:rw,nosuid,nodev,size=67108864,mode=700,uid=65532,gid=65532"
   "--mount" (format "type=bind,src=~a,dst=/opt/preview,readonly" bundle)
   "--mount" (format "type=bind,src=~a,dst=/work" working)
   "--workdir" "/work"
   image
   "/bin/bash" "-lc"
   (string-append
    "test ! -e /workspace && "
    "! command -v racket >/dev/null 2>&1 && "
    "exec /usr/sbin/script -qfec \""
    "/usr/sbin/stty rows 24 cols 100; "
    "exec /opt/preview/bin/odra /work/smoke.txt"
    "\" /dev/null")))

(define (bounded-tail value)
  (define count (bytes-length value))
  (if (<= count transcript-tail-limit)
      value
      (subbytes value (- count transcript-tail-limit))))

(define (transcript-contains? transcript value)
  (regexp-match? (byte-regexp (regexp-quote value))
                 (get-output-bytes transcript)))

(define (stop-process! process)
  (when (eq? (subprocess-status process) 'running)
    (subprocess-kill process #f)
    (unless (sync/timeout 1 process)
      (subprocess-kill process #t)))
  (subprocess-wait process))

(define (wait-for-output! owner process output error-output transcript value
                          [timeout 10])
  (define read-buffer (make-bytes 4096))
  (define deadline (+ (current-inexact-milliseconds) (* timeout 1000)))
  (let loop ()
    (cond
      [(transcript-contains? transcript value) #t]
      [(or (not (eq? (subprocess-status process) 'running))
           (<= deadline (current-inexact-milliseconds)))
       (stop-process! process)
       (define error-bytes (port->bytes error-output))
       (raise-user-error
        owner
        "output timeout; marker=~s; output-tail=~s; error-tail=~s"
        value
        (bounded-tail (get-output-bytes transcript))
        (bounded-tail error-bytes))]
      [else
       (define remaining
         (/ (- deadline (current-inexact-milliseconds)) 1000.0))
       (when (sync/timeout (min 0.25 remaining) output)
         (define count (read-bytes-avail!* read-buffer output))
         (when (exact-positive-integer? count)
           (write-bytes read-buffer transcript 0 count)))
       (loop)])))

(define (send! input value [pause 0.25])
  (write-bytes value input)
  (flush-output input)
  (sleep pause))

(define (write-json-file path value)
  (call-with-output-file path
    (lambda (output)
      (write-json value output)
      (newline output))
    #:exists 'truncate/replace))

(define (make-smoke-temporary-directory parent-directory)
  (unless (directory-exists? parent-directory)
    (raise-arguments-error 'make-smoke-temporary-directory
                           "temporary parent directory is unavailable"
                           "parent-directory" parent-directory))
  (make-temporary-file
   "preview-artifact-smoke-~a"
   'directory
   parent-directory))

(define (smoke-preview-artifact! docker image bundle-root evidence-directory
                                 temporary-parent)
  (unless (regular-file? (build-path bundle-root "bin" "odra"))
    (raise-user-error 'preview-smoke "preview executable is unavailable"))
  (define transcript #f)
  (define temporary-directory
    (make-smoke-temporary-directory temporary-parent))
  (with-handlers
      ([exn:fail?
        (lambda (failure)
          (make-directory* evidence-directory)
          (when transcript
            (call-with-output-file
             (build-path evidence-directory "failure-transcript.ansi")
             (lambda (output) (write-bytes (get-output-bytes transcript) output))
             #:exists 'truncate/replace))
          (raise failure))])
    (dynamic-wind
      void
      (lambda ()
        (file-or-directory-permissions temporary-directory #o777)
        (define document (build-path temporary-directory "smoke.txt"))
        (call-with-output-file document
          (lambda (output) (display "preview runtime\n" output)))
        (file-or-directory-permissions document #o666)
        (define arguments
          (docker-smoke-arguments image bundle-root temporary-directory))
        (define-values (process output input error-output)
          (apply subprocess #f #f #f docker arguments))
        (set! transcript (open-output-bytes))
        (wait-for-output! 'preview-smoke process output error-output transcript
                          #"smoke.txt"
                          process-timeout-seconds)
        (send! input #"\33xuppercase-current-line\r")
        (sleep 0.5)
        (send! input (bytes 24 19))
        (send! input #"\33xterminal-open-here\r" 0.5)
        (wait-for-output! 'preview-smoke process output error-output transcript
                          #"\33[2 q")
        (sleep 0.5)
        (send! input #"printf '\\316\\250\\n'\r" 0.5)
        (wait-for-output! 'preview-smoke process output error-output transcript
                          terminal-output-marker)
        (send! input #"\33xrequest-editor-exit\r" 0.3)
        (wait-for-output! 'preview-smoke process output error-output transcript
                          #"Exit and terminate 1 live terminal?")
        (send! input #"y" 0)
        (define exited? (sync/timeout process-timeout-seconds process))
        (unless exited? (stop-process! process))
        (subprocess-wait process)
        (copy-port output transcript)
        (define output-bytes (get-output-bytes transcript))
        (define error-bytes (port->bytes error-output))
        (close-output-port input)
        (close-input-port output)
        (close-input-port error-output)
        (unless (and exited?
                     (zero? (subprocess-status process))
                     (equal? error-bytes #"")
                     (equal? (file->string document) "PREVIEW RUNTIME\n")
                     (transcript-contains? transcript terminal-output-marker)
                     (transcript-contains? transcript restoration-sequence))
          (raise-user-error
           'preview-smoke
           "isolated workflow failed; status=~a; document=~s; output-tail=~s; error-tail=~s"
           (subprocess-status process)
           (file->string document)
           (bounded-tail output-bytes)
           (bounded-tail error-bytes)))
        (make-directory* evidence-directory)
        (define failure-transcript
          (build-path evidence-directory "failure-transcript.ansi"))
        (when (file-exists? failure-transcript) (delete-file failure-transcript))
        (call-with-output-file (build-path evidence-directory "transcript.ansi")
          (lambda (transcript-output) (write-bytes output-bytes transcript-output))
          #:exists 'truncate/replace)
        (write-json-file
         (build-path evidence-directory "summary.json")
         (hasheq 'schema 1
                 'validation_image image
                 'network "none"
                 'repository_mounted #f
                 'racket_executable_available #f
                 'non_source_working_directory #t
                 'writable_user_state #t
                 'file_lifecycle #t
                 'embedded_command #t
                 'integrated_terminal #t
                 'clean_exit #t))
        (printf "preview_smoke=valid image=~a evidence=~a\n"
                image evidence-directory))
      (lambda () (delete-directory/files temporary-directory)))))

(module+ main
  (define bundle-root #f)
  (define image #f)
  (define evidence-directory #f)
  (define temporary-parent #f)
  (command-line
   #:program "smoke-preview-artifact.rkt"
   #:once-each
   [("--tree") path "Extracted preview tree" (set! bundle-root path)]
   [("--validation-image") reference "Pinned validation image"
    (set! image reference)]
   [("--evidence") path "Smoke evidence directory"
    (set! evidence-directory path)]
   [("--temporary-parent") path "Docker-visible temporary parent directory"
    (set! temporary-parent path)])
  (for ([required (in-list (list bundle-root
                                 image
                                 evidence-directory
                                 temporary-parent))])
    (unless required
      (raise-user-error 'preview-smoke "all values are required")))
  (define docker (find-executable-path "docker"))
  (unless docker
    (raise-user-error 'preview-smoke "docker is unavailable"))
  (smoke-preview-artifact! docker
                           image
                           bundle-root
                           evidence-directory
                           temporary-parent))

(module+ test
  (require rackunit)

  (define image
    "docker.io/library/archlinux:base@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef")
  (define arguments
    (docker-smoke-arguments image "/tmp/preview-tree" "/tmp/preview-work"))

  (test-case "isolates the extracted bundle on the pinned baseline"
    (check-not-false (member "none" arguments))
    (check-not-false (member "--read-only" arguments))
    (check-not-false (member "65532:65532" arguments))
    (check-not-false
     (member "type=bind,src=/tmp/preview-tree,dst=/opt/preview,readonly"
             arguments))
    (check-not-false
     (member "type=bind,src=/tmp/preview-work,dst=/work" arguments)))

  (test-case "rejects a movable validation image"
    (check-exn exn:fail:contract?
               (lambda ()
                 (docker-smoke-arguments
                  "docker.io/library/archlinux:base"
                  "/tmp/preview-tree"
                  "/tmp/preview-work"))))

  (test-case "accepts the deterministic local validation image"
    (check-true
     (validation-image-reference?
      "odra-snapshot-validation:0123456789ab"))
    (check-false
     (validation-image-reference?
      "odra-snapshot-validation:latest")))

  (test-case "creates smoke storage below the explicit shared parent"
    (define parent (make-temporary-file "preview-smoke-parent-~a" 'directory))
    (dynamic-wind
      void
      (lambda ()
        (define child (make-smoke-temporary-directory parent))
        (check-equal? (path-only child)
                      (path->directory-path (simple-form-path parent)))
        (delete-directory/files child))
      (lambda () (delete-directory/files parent))))

  (test-case "rejects an unavailable shared parent"
    (define parent (make-temporary-file "missing-preview-smoke-parent-~a"))
    (delete-file parent)
    (check-exn exn:fail:contract?
               (lambda () (make-smoke-temporary-directory parent)))))
