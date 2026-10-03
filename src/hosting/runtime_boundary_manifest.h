// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

#ifndef ODRA_RUNTIME_BOUNDARY_MANIFEST_H
#define ODRA_RUNTIME_BOUNDARY_MANIFEST_H

/*
ODRA_RUNTIME_BOUNDARY_PROCEDURES is the canonical rooted-procedure inventory.
Each entry declares its C slot, embedded module, exported procedure, and scope.
*/
#define ODRA_RUNTIME_BOUNDARY_PROCEDURES(X) \
    X(call, "runtime-boundary", "runtime-call", 0) \
    X(command_request, "runtime-boundary", "command-inspection-request", 0) \
    X(command_transform, "runtime-boundary", "command-transform", 0) \
    X(keymap_profile, "runtime-boundary", "runtime-keymap-profile-batch", 0) \
    X(command_catalog, "runtime-boundary", "runtime-command-catalog-batch", 0) \
    X(history_policy, "runtime-boundary", "runtime-history-policy-exchange", 0) \
    X(display_policy, "runtime-boundary", "runtime-display-policy-exchange", 0) \
    X(uppercase, "runtime-boundary", "command-uppercase-current-line", 0) \
    X(transaction_turn, "runtime-boundary", "native-transaction-turn", 0) \
    X(transaction_command, "runtime-boundary", "runtime-command-dispatch", 0) \
    X(personal_command, "runtime-boundary", "runtime-personal-command-dispatch", 0) \
    X(transfer_turn, "runtime-boundary", "native-transfer-turn", 0) \
    X(search_turn, "runtime-boundary", "native-search-turn", 0) \
    X(buffer_session_turn, "runtime-boundary", "native-buffer-session-turn", 0) \
    X(layout_turn, "runtime-boundary", "native-layout-turn", 0) \
    X(ui_role_turn, "runtime-boundary", "native-ui-role-turn", 0) \
    X(theme_turn, "runtime-boundary", "native-theme-turn", 0) \
    X(structural_turn, "runtime-boundary", "native-structural-turn", 0) \
    X(language_service_turn, "runtime-boundary", "native-language-service-turn", 0) \
    X(result_turn, "runtime-boundary", "native-result-turn", 0) \
    X(status_bar_turn, "runtime-boundary", "native-status-bar-turn", 0) \
    X(terminal_turn, "runtime-boundary", "native-terminal-turn", 0) \
    X(terminal_delivery_turn, "runtime-boundary", "native-terminal-delivery-turn", 0) \
    X(project_directory_resolution, "runtime-boundary", "runtime-project-directory-resolution", 0) \
    X(project_catalog_resolution, "runtime-boundary", "runtime-project-catalog-resolution", 0) \
    X(personal_configuration_startup, "runtime-boundary", "runtime-personal-configuration-startup-batch", 0) \
    X(personal_configuration_reload, "runtime-boundary", "runtime-personal-configuration-reload-batch", 0) \
    X(personal_generation_transition, "runtime-boundary", "runtime-personal-generation-transition", 0) \
    X(provider_invoke, "runtime-boundary", "runtime-provider-invoke-batch", 0) \
    X(project_promotion, "runtime-boundary", "runtime-project-promotion-batch", 0) \
    X(project_rename, "runtime-boundary", "runtime-project-rename-batch", 0) \
    X(project_unregister, "runtime-boundary", "runtime-project-unregister-batch", 0) \
    X(promotion_suppression, "runtime-boundary", "runtime-promotion-suppression-batch", 0) \
    X(workspace_command, "runtime-boundary", "runtime-workspace-command-batch", 0) \
    X(named_location_command, "runtime-boundary", "runtime-named-location-command-batch", 0) \
    X(named_slot_command, "runtime-boundary", "runtime-named-slot-command-batch", 0) \
    X(candidate_usage_load, "runtime-boundary", "runtime-candidate-usage-load-batch", 0) \
    X(candidate_usage_publish, "runtime-boundary", "runtime-candidate-usage-publish-batch", 0) \
    X(package_catalog_command, "runtime-boundary", "runtime-package-catalog-command-batch", 0) \
    X(platform_roots, "runtime-boundary", "runtime-platform-roots-batch", 0) \
    X(call_probe, "runtime-call-probe", "runtime-call-probe", 1) \
    X(command_request_probe, "transform-probe", "command-inspection-request-probe", 1) \
    X(command_transform_probe, "transform-probe", "command-transform-probe", 1) \
    X(keymap_profile_probe, "keymap-profile-probe", "runtime-keymap-profile-batch-probe", 1) \
    X(command_catalog_probe, "command-catalog-probe", "runtime-command-catalog-batch-probe", 1) \
    X(history_policy_probe, "history-policy-probe", "runtime-history-policy-exchange-probe", 1) \
    X(display_policy_probe, "display-policy-probe", "runtime-display-policy-exchange-probe", 1) \
    X(uppercase_probe, "transform-probe", "command-uppercase-current-line-probe", 1) \
    X(transaction_probe, "transaction-probe", "native-transaction-probe", 1) \
    X(transaction_command_probe, "transaction-probe", "native-transaction-command-probe", 1) \
    X(transfer_probe, "transfer-probe", "native-transfer-probe", 1) \
    X(search_probe, "search-probe", "native-search-probe", 1) \
    X(buffer_session_probe, "buffer-session-probe", "native-buffer-session-probe", 1) \
    X(layout_probe, "layout-probe", "native-layout-probe", 1) \
    X(ui_role_probe, "ui-role-probe", "native-ui-role-probe", 1) \
    X(theme_probe, "theme-probe", "native-theme-probe", 1) \
    X(structural_probe, "structural-probe", "native-structural-probe", 1) \
    X(language_service_probe, "language-service-probe", "native-language-service-probe", 1)

#endif
