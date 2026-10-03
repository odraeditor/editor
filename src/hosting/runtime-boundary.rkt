#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require
 (only-in "runtime.rkt"
          runtime-call
          runtime-start
          runtime-stop)
 (only-in "../command/transform.rkt"
          command-inspection-request
          command-transform
          command-uppercase-current-line)
 (only-in "keymap-profile-bridge.rkt"
          runtime-keymap-profile-batch)
 (only-in "command-catalog-bridge.rkt"
          runtime-command-catalog-batch)
 (only-in "../history/configuration.rkt"
          runtime-history-policy-exchange)
 (only-in "../layout/display-policy-configuration.rkt"
          runtime-display-policy-exchange)
 (only-in "../command/transaction.rkt"
          native-transaction-turn)
 (only-in "../command/catalog.rkt"
          runtime-command-dispatch)
 (only-in "../command/personal-execution.rkt"
          runtime-personal-command-dispatch)
 (only-in "../command/transfer.rkt"
          native-transfer-turn)
 (only-in "../command/search.rkt"
          native-search-turn)
 (only-in "../command/buffers.rkt"
          native-buffer-session-turn)
 (only-in "layout-bridge.rkt"
          native-layout-turn)
 (only-in "ui-role-bridge.rkt"
          native-ui-role-turn)
 (only-in "theme-bridge.rkt"
          native-theme-turn)
 (only-in "../command/structural.rkt"
          native-structural-turn)
 (only-in "language-service-bridge.rkt"
          native-language-service-turn)
 (only-in "../command/results.rkt"
          native-result-turn)
 (only-in "status-bar-bridge.rkt"
          native-status-bar-turn)
 (only-in "terminal-bridge.rkt"
          native-terminal-turn
          native-terminal-delivery-turn)
 (only-in "project-opening-bridge.rkt"
          runtime-project-directory-resolution
          runtime-project-catalog-resolution)
 (only-in "personal-configuration-bridge.rkt"
          runtime-personal-configuration-startup-batch
          runtime-personal-configuration-reload-batch
          runtime-personal-generation-transition)
 (only-in "provider-bridge.rkt"
          runtime-provider-invoke-batch)
 (only-in "project-promotion-bridge.rkt"
          runtime-project-promotion-batch
          runtime-project-rename-batch
          runtime-project-unregister-batch
          runtime-promotion-suppression-batch)
 (only-in "workspace-bridge.rkt"
          runtime-workspace-command-batch)
 (only-in "named-location-bridge.rkt"
          runtime-named-location-command-batch)
 (only-in "named-slot-bridge.rkt"
          runtime-named-slot-command-batch)
 (only-in "candidate-usage-bridge.rkt"
          runtime-candidate-usage-load-batch
          runtime-candidate-usage-publish-batch)
 (only-in "package-catalog-bridge.rkt"
          runtime-package-catalog-command-batch)
 (only-in "../configuration/platform-roots.rkt"
          runtime-platform-roots-batch))

(provide
 runtime-call
 runtime-start
 runtime-stop
 command-inspection-request
 command-transform
 command-uppercase-current-line
 runtime-keymap-profile-batch
 runtime-command-catalog-batch
 runtime-history-policy-exchange
 runtime-display-policy-exchange
 native-transaction-turn
 runtime-command-dispatch
 runtime-personal-command-dispatch
 native-transfer-turn
 native-search-turn
 native-buffer-session-turn
 native-layout-turn
 native-ui-role-turn
 native-theme-turn
 native-structural-turn
 native-language-service-turn
 native-result-turn
 native-status-bar-turn
 native-terminal-turn
 native-terminal-delivery-turn
 runtime-project-directory-resolution
 runtime-project-catalog-resolution
 runtime-personal-configuration-startup-batch
 runtime-personal-configuration-reload-batch
 runtime-personal-generation-transition
 runtime-provider-invoke-batch
 runtime-project-promotion-batch
 runtime-project-rename-batch
 runtime-project-unregister-batch
 runtime-promotion-suppression-batch
 runtime-workspace-command-batch
 runtime-named-location-command-batch
 runtime-named-slot-command-batch
 runtime-candidate-usage-load-batch
 runtime-candidate-usage-publish-batch
 runtime-package-catalog-command-batch
 runtime-platform-roots-batch)

(module+ test
  (require rackunit)

  (for ([boundary-procedure
         (in-list
          (list runtime-call
                runtime-start
                runtime-stop
                command-inspection-request
                command-transform
                command-uppercase-current-line
                runtime-keymap-profile-batch
                runtime-command-catalog-batch
                runtime-history-policy-exchange
                runtime-display-policy-exchange
                native-transaction-turn
                runtime-command-dispatch
                runtime-personal-command-dispatch
                native-transfer-turn
                native-search-turn
                native-buffer-session-turn
                native-layout-turn
                native-ui-role-turn
                native-theme-turn
                native-structural-turn
                native-language-service-turn
                native-result-turn
                native-status-bar-turn
                native-terminal-turn
                native-terminal-delivery-turn
                runtime-project-directory-resolution
                runtime-project-catalog-resolution
                runtime-personal-configuration-startup-batch
                runtime-personal-configuration-reload-batch
                runtime-personal-generation-transition
                runtime-provider-invoke-batch
                runtime-project-promotion-batch
                runtime-project-rename-batch
                runtime-project-unregister-batch
                runtime-promotion-suppression-batch
                runtime-workspace-command-batch
                runtime-named-location-command-batch
                runtime-named-slot-command-batch
                runtime-candidate-usage-load-batch
                runtime-candidate-usage-publish-batch
                runtime-package-catalog-command-batch
                runtime-platform-roots-batch))])
    (check-true (procedure? boundary-procedure))))
