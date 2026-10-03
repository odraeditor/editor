# SPDX-FileCopyrightText: 2026 Adrian PK
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Odra. See COPYING for license terms.

ODIN ?= odin
ODIN_VET_FLAGS ?= -no-entry-point -vet -warnings-as-errors
RACKET ?= racket
RACO ?= raco
RACKET_TEST ?= bash scripts/run-racket-tests.sh "$(RACO)" "$(BUILD_DIR)"
ISOLATED_RACKET_TEST ?= bash scripts/run-isolated-racket-tests.sh bash scripts/run-racket-tests.sh "$(RACO)" "$(BUILD_DIR)"
PTY_RACKET_TEST ?= $(ISOLATED_RACKET_TEST)
GO ?= go
CC ?= cc
AR ?= ar
STRIP ?= strip

BUILD_DIR ?= .build
HOSTING_BUILD_DIR := $(BUILD_DIR)/hosting
RACKET_INCLUDE_DIR ?= $(shell $(RACKET) -e '(require setup/dirs) (display (find-include-dir))')
RACKET_BOOT_DIR ?= $(shell $(RACKET) -e '(require setup/dirs) (display (find-lib-dir))')
RACKET_COLLECTS_DIR ?= $(shell $(RACKET) -e '(require setup/dirs) (display (find-collects-dir))')
RACKET_CONFIG_DIR ?= $(shell $(RACKET) -e '(require setup/dirs) (display (find-config-dir))')
RACKET_CS_LIBRARY ?= $(shell $(RACKET) -e '(require setup/dirs) (display (build-path (find-lib-dir) ".." "libracketcs.a"))')
RACKET_CS_LINK_LIBS ?= -lm -lncursesw -lz -llz4 -ldl -lpthread -Wl,--export-dynamic-symbol=odra_racket_scoped_capability_call

HOSTING_MODULE_C := $(HOSTING_BUILD_DIR)/probe_module.c
ODIN_HOST_ADAPTER_OBJECT := $(HOSTING_BUILD_DIR)/odin_host_adapter.o
ODIN_HOST_ADAPTER_LIBRARY := $(HOSTING_BUILD_DIR)/libodin_host_adapter.a
ODIN_HOST_PROBE := $(HOSTING_BUILD_DIR)/odin-host-probe
RACKET_HOST_LIBRARY := $(HOSTING_BUILD_DIR)/libodra-racket-host-probe.so
RUNTIME_MODULE_C := $(HOSTING_BUILD_DIR)/runtime_module.c
RUNTIME_TEST_MODULE_C := $(HOSTING_BUILD_DIR)/runtime_test_module.c
RUNTIME_ADAPTER_OBJECT := $(HOSTING_BUILD_DIR)/runtime_adapter.o
RUNTIME_ADAPTER_LIBRARY := $(HOSTING_BUILD_DIR)/libodra_racket_runtime.a
RUNTIME_TEST_ADAPTER_OBJECT := $(HOSTING_BUILD_DIR)/runtime_test_adapter.o
RUNTIME_TEST_ADAPTER_LIBRARY := $(HOSTING_BUILD_DIR)/libodra_racket_runtime_test.a
RUNTIME_LIFECYCLE_TEST := $(HOSTING_BUILD_DIR)/runtime-lifecycle-test
RUNTIME_MISSING_BOOT_ADAPTER_OBJECT := $(HOSTING_BUILD_DIR)/runtime_missing_boot_adapter.o
RUNTIME_MISSING_BOOT_ADAPTER_LIBRARY := $(HOSTING_BUILD_DIR)/libodra_racket_runtime_missing_boot.a
RUNTIME_MISSING_BOOT_TEST := $(HOSTING_BUILD_DIR)/runtime-missing-boot-test
RUNTIME_INVALID_MODULE_ADAPTER_OBJECT := $(HOSTING_BUILD_DIR)/runtime_invalid_module_adapter.o
RUNTIME_INVALID_MODULE_ADAPTER_LIBRARY := $(HOSTING_BUILD_DIR)/libodra_racket_runtime_invalid_module.a
RUNTIME_INVALID_MODULE_TEST := $(HOSTING_BUILD_DIR)/runtime-invalid-module-test
RUNTIME_MISSING_BOUNDARY_ADAPTER_OBJECT := $(HOSTING_BUILD_DIR)/runtime_missing_boundary_adapter.o
RUNTIME_MISSING_BOUNDARY_ADAPTER_LIBRARY := $(HOSTING_BUILD_DIR)/libodra_racket_runtime_missing_boundary.a
RUNTIME_MISSING_BOUNDARY_TEST := $(HOSTING_BUILD_DIR)/runtime-missing-boundary-test
RUNTIME_INVALID_SHUTDOWN_ADAPTER_OBJECT := $(HOSTING_BUILD_DIR)/runtime_invalid_shutdown_adapter.o
RUNTIME_INVALID_SHUTDOWN_ADAPTER_LIBRARY := $(HOSTING_BUILD_DIR)/libodra_racket_runtime_invalid_shutdown.a
RUNTIME_INVALID_SHUTDOWN_TEST := $(HOSTING_BUILD_DIR)/runtime-invalid-shutdown-test
RUNTIME_CONTRACT_MISMATCH_TEST := $(HOSTING_BUILD_DIR)/runtime-contract-mismatch-test
RUNTIME_COMMAND_BENCHMARK := $(HOSTING_BUILD_DIR)/runtime-command-benchmark
RUNTIME_COMMAND_GC_BENCHMARK := $(HOSTING_BUILD_DIR)/runtime-command-gc-benchmark
RUNTIME_VIEW_COMMAND_BENCHMARK := $(HOSTING_BUILD_DIR)/runtime-view-command-benchmark
RUNTIME_TRANSACTION_COMMAND_BENCHMARK := $(HOSTING_BUILD_DIR)/runtime-transaction-command-benchmark
RUNTIME_TRANSFER_COMMAND_BENCHMARK := $(HOSTING_BUILD_DIR)/runtime-transfer-command-benchmark
RUNTIME_SEARCH_COMMAND_BENCHMARK := $(HOSTING_BUILD_DIR)/runtime-search-command-benchmark
RUNTIME_BUFFER_SESSION_COMMAND_BENCHMARK := $(HOSTING_BUILD_DIR)/runtime-buffer-session-command-benchmark
LAYOUT_ACCEPTANCE := $(HOSTING_BUILD_DIR)/layout-acceptance
VIEW_BENCHMARK := $(BUILD_DIR)/view-benchmark
INTERACTION_BENCHMARK := $(BUILD_DIR)/interaction-benchmark
KEYMAP_RESOURCE_STUDY := $(BUILD_DIR)/keymap-resource-study
PROFILE_COMPATIBILITY_RESOURCE_STUDY := $(BUILD_DIR)/profile-compatibility-resource-study
LANGUAGE_SERVICE_RESOURCE_STUDY := $(BUILD_DIR)/language-service-resource-study
LANGUAGE_SERVICE_OLS_ACCEPTANCE := $(BUILD_DIR)/language-service-ols-acceptance
RACKET_LANGSERVER_HOME ?= $(BUILD_DIR)/racket-langserver-home
RACKET_LANGSERVER_CHECKSUM := 93efe35dcc07a7cc86c958f00497280744f0e75c
RACKET_LANGSERVER_STAMP := $(RACKET_LANGSERVER_HOME)/.installed-$(RACKET_LANGSERVER_CHECKSUM)
GOPLS_VERSION := v0.23.0
GOPLS_BUILD_DIR := $(BUILD_DIR)/gopls/$(GOPLS_VERSION)
GOPLS_EXECUTABLE ?= $(GOPLS_BUILD_DIR)/gopls
RUST_ANALYZER_RELEASE := 2026-09-14
RUST_ANALYZER_BUILD_DIR := $(BUILD_DIR)/rust-analyzer/$(RUST_ANALYZER_RELEASE)
RUST_ANALYZER_ARCHIVE := $(RUST_ANALYZER_BUILD_DIR)/rust-analyzer-x86_64-unknown-linux-gnu.gz
RUST_ANALYZER_EXECUTABLE ?= $(RUST_ANALYZER_BUILD_DIR)/rust-analyzer
RUST_ANALYZER_SHA256 := 7609ba53f85cd80a3bde77a4b2e94e304d0f94650e4f4cffc061b9bca454ba75
TYPESCRIPT_LANGUAGE_SERVER_VERSION := 6.0.0
TYPESCRIPT_VERSION := 6.0.3
VSCODE_LANGSERVERS_VERSION := 4.10.0
WEB_LANGUAGE_SERVERS_DIR := $(BUILD_DIR)/web-language-servers
WEB_LANGUAGE_SERVERS_STAMP := $(WEB_LANGUAGE_SERVERS_DIR)/.installed-$(TYPESCRIPT_LANGUAGE_SERVER_VERSION)-$(TYPESCRIPT_VERSION)-$(VSCODE_LANGSERVERS_VERSION)
TYPESCRIPT_LANGUAGE_SERVER_EXECUTABLE := $(WEB_LANGUAGE_SERVERS_DIR)/node_modules/.bin/typescript-language-server
HTML_LANGUAGE_SERVER_EXECUTABLE := $(WEB_LANGUAGE_SERVERS_DIR)/node_modules/.bin/vscode-html-language-server
CSS_LANGUAGE_SERVER_EXECUTABLE := $(WEB_LANGUAGE_SERVERS_DIR)/node_modules/.bin/vscode-css-language-server
VSCODE_LANGSERVERS_PACKAGE_JSON := $(WEB_LANGUAGE_SERVERS_DIR)/node_modules/vscode-langservers-extracted/package.json
TYPESCRIPT_LIBRARY_PATH := $(WEB_LANGUAGE_SERVERS_DIR)/node_modules/typescript/lib
TYPESCRIPT_PACKAGE_JSON := $(WEB_LANGUAGE_SERVERS_DIR)/node_modules/typescript/package.json
SYNTAX_RESOURCE_STUDY := $(BUILD_DIR)/syntax-resource-study
TREE_SITTER_RESOURCE_STUDY := $(BUILD_DIR)/tree-sitter-resource-study
STRUCTURAL_SYNTAX_RESOURCE_STUDY := $(BUILD_DIR)/structural-syntax-resource-study
SYMBOL_NAVIGATION_RESOURCE_STUDY := $(BUILD_DIR)/symbol-navigation-resource-study
PROJECT_SEARCH_RESOURCE_STUDY := $(BUILD_DIR)/project-search-resource-study
SYNTAX_VENDOR_BUILD_DIR := $(BUILD_DIR)/syntax-vendor
TREE_SITTER_DIR := third_party/tree-sitter/0.26.12
TREE_SITTER_ODIN_DIR := third_party/tree-sitter-odin/1.3.0
TREE_SITTER_JAN_DIR := third_party/tree-sitter-jan/jan-org-9.8.10-v1
TREE_SITTER_RACKET_DIR := third_party/tree-sitter-racket/0.25.0
TREE_SITTER_GO_DIR := third_party/tree-sitter-go/0.25.0
TREE_SITTER_RUST_DIR := third_party/tree-sitter-rust/0.24.2
TREE_SITTER_JAVASCRIPT_DIR := third_party/tree-sitter-javascript/0.25.0
TREE_SITTER_TYPESCRIPT_DIR := third_party/tree-sitter-typescript/0.23.2
TREE_SITTER_HTML_DIR := third_party/tree-sitter-html/0.23.2
TREE_SITTER_CSS_DIR := third_party/tree-sitter-css/0.25.0
TREE_SITTER_OBJECT := $(SYNTAX_VENDOR_BUILD_DIR)/tree-sitter.o
TREE_SITTER_ODIN_PARSER_OBJECT := $(SYNTAX_VENDOR_BUILD_DIR)/odin-parser.o
TREE_SITTER_ODIN_SCANNER_OBJECT := $(SYNTAX_VENDOR_BUILD_DIR)/odin-scanner.o
TREE_SITTER_JAN_PARSER_OBJECT := $(SYNTAX_VENDOR_BUILD_DIR)/jan-parser.o
TREE_SITTER_JAN_SCANNER_OBJECT := $(SYNTAX_VENDOR_BUILD_DIR)/jan-scanner.o
TREE_SITTER_RACKET_PARSER_OBJECT := $(SYNTAX_VENDOR_BUILD_DIR)/racket-parser.o
TREE_SITTER_RACKET_SCANNER_OBJECT := $(SYNTAX_VENDOR_BUILD_DIR)/racket-scanner.o
TREE_SITTER_GO_PARSER_OBJECT := $(SYNTAX_VENDOR_BUILD_DIR)/go-parser.o
TREE_SITTER_RUST_PARSER_OBJECT := $(SYNTAX_VENDOR_BUILD_DIR)/rust-parser.o
TREE_SITTER_RUST_SCANNER_OBJECT := $(SYNTAX_VENDOR_BUILD_DIR)/rust-scanner.o
TREE_SITTER_JAVASCRIPT_PARSER_OBJECT := $(SYNTAX_VENDOR_BUILD_DIR)/javascript-parser.o
TREE_SITTER_JAVASCRIPT_SCANNER_OBJECT := $(SYNTAX_VENDOR_BUILD_DIR)/javascript-scanner.o
TREE_SITTER_TYPESCRIPT_PARSER_OBJECT := $(SYNTAX_VENDOR_BUILD_DIR)/typescript-parser.o
TREE_SITTER_TYPESCRIPT_SCANNER_OBJECT := $(SYNTAX_VENDOR_BUILD_DIR)/typescript-scanner.o
TREE_SITTER_TSX_PARSER_OBJECT := $(SYNTAX_VENDOR_BUILD_DIR)/tsx-parser.o
TREE_SITTER_TSX_SCANNER_OBJECT := $(SYNTAX_VENDOR_BUILD_DIR)/tsx-scanner.o
TREE_SITTER_HTML_PARSER_OBJECT := $(SYNTAX_VENDOR_BUILD_DIR)/html-parser.o
TREE_SITTER_HTML_SCANNER_OBJECT := $(SYNTAX_VENDOR_BUILD_DIR)/html-scanner.o
TREE_SITTER_CSS_PARSER_OBJECT := $(SYNTAX_VENDOR_BUILD_DIR)/css-parser.o
TREE_SITTER_CSS_SCANNER_OBJECT := $(SYNTAX_VENDOR_BUILD_DIR)/css-scanner.o
TREE_SITTER_MEMORY_OBJECT := $(SYNTAX_VENDOR_BUILD_DIR)/tree-sitter-memory.o
TREE_SITTER_ODIN_LIBRARY := $(SYNTAX_VENDOR_BUILD_DIR)/libtree-sitter-odin.a
TREE_SITTER_JAN_LIBRARY := $(SYNTAX_VENDOR_BUILD_DIR)/libtree-sitter-jan.a
SYNTAX_PROVIDER_FIXTURE_LIBRARY := $(BUILD_DIR)/syntax-provider-fixture/libtree-sitter-odin.so
SYNTAX_PROVIDER_FIXTURE_LINK := $(BUILD_DIR)/syntax-provider-fixture/libtree-sitter-odin-link.so
SYNTAX_VENDOR_PROBE := $(SYNTAX_VENDOR_BUILD_DIR)/syntax-vendor-probe
JAN_PARSER_PROBE := $(SYNTAX_VENDOR_BUILD_DIR)/jan-parser-probe
TERMINAL_VENDOR_DIR := third_party/libghostty-vt/7b47213f94058c3715205ce8fa73f7ae581a652c
TERMINAL_VENDOR_BUILD_DIR := $(BUILD_DIR)/terminal-vendor
TERMINAL_VENDOR_LIBRARY := $(TERMINAL_VENDOR_BUILD_DIR)/install/lib/libghostty-vt.a
TERMINAL_EMULATOR_BUILD_DIR := $(BUILD_DIR)/terminal-emulator
TERMINAL_EMULATOR_ADAPTER_OBJECT := $(TERMINAL_EMULATOR_BUILD_DIR)/adapter.o
TERMINAL_EMULATOR_ADAPTER_LIBRARY := $(TERMINAL_EMULATOR_BUILD_DIR)/libodra-terminal-emulator-adapter.a
TERMINAL_EMULATOR_PROBE := $(TERMINAL_EMULATOR_BUILD_DIR)/terminal-emulator-probe
TERMINAL_EMULATOR_ODIN_PROBE := $(TERMINAL_EMULATOR_BUILD_DIR)/terminal-emulator-odin-probe
INTERACTIVE_SESSION_BUILD_DIR := $(BUILD_DIR)/interactive-session
INTERACTIVE_SESSION_ADAPTER_OBJECT := $(INTERACTIVE_SESSION_BUILD_DIR)/adapter-linux.o
INTERACTIVE_SESSION_ADAPTER_LIBRARY := $(INTERACTIVE_SESSION_BUILD_DIR)/libodra-interactive-session-adapter.a
NATIVE_COMMAND_BENCHMARK := $(HOSTING_BUILD_DIR)/native-command-benchmark
TRANSACTION_BENCHMARK := $(BUILD_DIR)/transaction-benchmark
MULTIBUFFER_TRANSACTION_BENCHMARK := $(BUILD_DIR)/multibuffer-transaction-benchmark
MULTIBUFFER_HISTORY_BENCHMARK := $(BUILD_DIR)/multibuffer-history-benchmark
TRANSACTION_FUZZ := $(BUILD_DIR)/transaction-fuzz
HISTORY_RESOURCE_STUDY := $(BUILD_DIR)/history-resource-study
KILL_RING_RESOURCE_STUDY := $(BUILD_DIR)/kill-ring-resource-study
FEEDBACK_RESOURCE_STUDY := $(BUILD_DIR)/feedback-resource-study
SEARCH_RESOURCE_STUDY := $(BUILD_DIR)/search-resource-study
RESULT_SET_RESOURCE_STUDY := $(BUILD_DIR)/result-set-resource-study
STATUS_BAR_RESOURCE_STUDY := $(BUILD_DIR)/status-bar-resource-study
GUTTER_RESOURCE_STUDY := $(BUILD_DIR)/gutter-resource-study
EDITOR_SESSION_RESOURCE_STUDY := $(BUILD_DIR)/editor-session-resource-study
PROJECT_RESOURCE_STUDY := $(BUILD_DIR)/project-resource-study
MAKSYM_RESOURCE_STUDY := $(BUILD_DIR)/maksym-resource-study
DAREK_RESOURCE_STUDY := $(BUILD_DIR)/darek-resource-study
CANDIDATE_RESOURCE_STUDY := $(BUILD_DIR)/candidate-resource-study
CANDIDATE_HISTORY_RESOURCE_STUDY := $(BUILD_DIR)/candidate-history-resource-study
CANDIDATE_NAVIGATION_RESOURCE_STUDY := $(BUILD_DIR)/candidate-navigation-resource-study
UI_RESOURCE_STUDY := $(BUILD_DIR)/ui-resource-study
UI_ROLE_RESOURCE_STUDY := $(BUILD_DIR)/ui-role-resource-study
PRESENTATION_PROFILE_RESOURCE_STUDY := $(BUILD_DIR)/presentation-profile-resource-study
COMPLETION_RESOURCE_STUDY := $(BUILD_DIR)/completion-resource-study
KSAWERY_RESOURCE_STUDY := $(BUILD_DIR)/ksawery-resource-study
KSAWERY_DIFF_UNIT_STUDY := $(BUILD_DIR)/ksawery-diff-unit-study
KSAWERY_HISTORY_RESOURCE_STUDY := $(BUILD_DIR)/ksawery-history-resource-study
KSAWERY_REF_RESOURCE_STUDY := $(BUILD_DIR)/ksawery-ref-resource-study
KSAWERY_PROCESS_RESOURCE_STUDY := $(BUILD_DIR)/ksawery-process-resource-study
KSAWERY_SEQUENCE_RESOURCE_STUDY := $(BUILD_DIR)/ksawery-sequence-resource-study
KSAWERY_EXTENSION_RESOURCE_STUDY := $(BUILD_DIR)/ksawery-extension-resource-study
PRODUCT_MODULE_FIXTURE := $(BUILD_DIR)/product-module-fixture/libodra-product-module-fixture.so
PRODUCT_MODULE_FILE_MANAGEMENT_FIXTURE := $(BUILD_DIR)/product-module-fixture/libodra-product-module-file-management-fixture.so
PRODUCT_MODULE_WORKSPACE_HIERARCHY_FIXTURE := $(BUILD_DIR)/product-module-fixture/libodra-product-module-workspace-hierarchy-fixture.so
PRODUCT_MODULE_STRUCTURED_DOCUMENT_FIXTURE := $(BUILD_DIR)/product-module-fixture/libodra-product-module-structured-document-fixture.so
MULTI_VIEW_RESOURCE_STUDY := $(BUILD_DIR)/multi-view-resource-study
LAYOUT_RESOURCE_STUDY := $(BUILD_DIR)/layout-resource-study
KILL_RING_BENCHMARK := $(BUILD_DIR)/kill-ring-benchmark
HISTORY_FUZZ := $(BUILD_DIR)/history-fuzz
DISPLAY_PROBE := $(BUILD_DIR)/display-probe
DISPLAY_EVIDENCE := $(BUILD_DIR)/display-evidence
DISPLAY_BENCHMARK := $(BUILD_DIR)/display-benchmark
DOCUMENT_EVIDENCE := $(BUILD_DIR)/document-evidence
CLIPBOARD_TRANSPORT_PROBE := $(BUILD_DIR)/clipboard-transport-probe
DISPLAY_PRODUCTION_SOURCES := $(wildcard src/display/*.odin src/editor/*.odin src/text/*.odin src/view/*.odin src/search/*.odin)
ODRA := $(BUILD_DIR)/odra
ODRA_DEVELOPMENT := $(BUILD_DIR)/odra-development
ODRA_TIMINGS_DIR := $(BUILD_DIR)/timings
ODRA_TIMINGS := $(ODRA_TIMINGS_DIR)/odra.json
ODRA_PACKAGE_SOURCES := $(wildcard src/*/*.odin)
ODRA_CORE_PACKAGE_SOURCES := $(filter-out src/ksawery/% src/ksawery_bridge/% src/ksawery_command/% src/ksawery_module/% src/maksym/% src/maksym_module/% src/darek/% src/darek_module/% src/jan_editing/% src/jan_planning/% src/jan_computation/% src/jan_output/% src/jan_module/%,$(ODRA_PACKAGE_SOURCES))
ODRA_PRODUCTION_SOURCES := $(filter-out %_test.odin,$(ODRA_CORE_PACKAGE_SOURCES))
PREVIEW_RUNTIME_BUILD_DIR := $(BUILD_DIR)/preview-runtime
PREVIEW_RUNTIME_BINARY := $(PREVIEW_RUNTIME_BUILD_DIR)/odra
PREVIEW_RUNTIME_TIMINGS := $(PREVIEW_RUNTIME_BUILD_DIR)/odin-timings.json
PREVIEW_RUNTIME_MODULE_C := $(PREVIEW_RUNTIME_BUILD_DIR)/runtime_module.c
PREVIEW_RUNTIME_ADAPTER_OBJECT := $(PREVIEW_RUNTIME_BUILD_DIR)/runtime_adapter.o
PREVIEW_RUNTIME_ADAPTER_LIBRARY := $(PREVIEW_RUNTIME_BUILD_DIR)/libodra_racket_runtime.a
PREVIEW_RUNTIME_LIFECYCLE_TEST := $(PREVIEW_RUNTIME_BUILD_DIR)/runtime-lifecycle-test
PREVIEW_PRODUCT_MODULE_DIR := $(PREVIEW_RUNTIME_BUILD_DIR)/modules
PREVIEW_KSAWERY_MODULE_LIBRARY := $(PREVIEW_PRODUCT_MODULE_DIR)/libodra-ksawery.so
PREVIEW_MAKSYM_MODULE_LIBRARY := $(PREVIEW_PRODUCT_MODULE_DIR)/libodra-maksym.so
PREVIEW_DAREK_MODULE_LIBRARY := $(PREVIEW_PRODUCT_MODULE_DIR)/libodra-darek.so
PREVIEW_JAN_MODULE_LIBRARY := $(PREVIEW_PRODUCT_MODULE_DIR)/libodra-jan.so
PREVIEW_PRODUCT_MODULE_MANIFEST := $(PREVIEW_PRODUCT_MODULE_DIR)/product-modules.manifest
PREVIEW_RELEASE_BUILD_DIR := $(BUILD_DIR)/release/linux-x86_64
PREVIEW_RUNTIME_CLOSURE := release/linux-x86_64/runtime-closure.json
PREVIEW_TAG ?=
PREVIEW_COMMIT ?=
PREVIEW_BUILD_ENVIRONMENT ?=
PREVIEW_TREE ?=
PREVIEW_TREE_OUTPUT_PARENT ?= $(PREVIEW_RELEASE_BUILD_DIR)
PREVIEW_ARCHIVE_OUTPUT_PARENT ?= $(PREVIEW_RELEASE_BUILD_DIR)
ODRA_PREVIEW_THREAD_COUNT ?= 4
INTERACTIVE_STACK_KIB ?= 8192
VERIFY_RESUME_STATE ?= $(BUILD_DIR)/verify-resume-state.rktd
VERIFY_RESUME_RUNNER := $(RACKET) scripts/run-resumable-verification.rkt --state $(VERIFY_RESUME_STATE)
ODRA_VERIFY_RESUME ?= 0
EXTENSIBLE_LANGUAGE_SUPPORT_ACCEPTANCE_STATE ?= $(BUILD_DIR)/extensible-language-support-acceptance-state.rktd
EXTENSIBLE_LANGUAGE_SUPPORT_ACCEPTANCE_RUNNER := $(RACKET) scripts/run-resumable-verification.rkt --state $(EXTENSIBLE_LANGUAGE_SUPPORT_ACCEPTANCE_STATE)
PACKAGE_CATALOG_ACCEPTANCE_STATE ?= $(BUILD_DIR)/package-catalog-acceptance-state.rktd
PACKAGE_CATALOG_ACCEPTANCE_RUNNER := $(RACKET) scripts/run-resumable-verification.rkt --state $(PACKAGE_CATALOG_ACCEPTANCE_STATE)

.PHONY: benchmark buffer-session-acceptance buffer-session-command-benchmark candidate-history-resource-study candidate-navigation-acceptance candidate-navigation-focused-acceptance candidate-navigation-resource-study candidate-resource-study check clipboard-transport-probe command-benchmark completion-reference-test completion-resource-study display-benchmark display-evidence display-probe display-test docs-check document-evidence darek-resource-study darek-workflow-acceptance editor-event-loop-latency-study editor-event-loop-latency-test editor-session-resource-study feedback-resource-study gutter-acceptance gutter-resource-study history-fuzz history-resource-study hosting-benchmark hosting-check hosting-evidence hosting-probes hosting-runtime-check hosting-test interaction-benchmark interactive-session-model-test interactive-session-process-test interactive-session-resource-study interactive-session-test interactive-session-transport-test interactive-stack-acceptance interactive-stack-check interactive-stack-runtime-acceptance internal-test internal-verify internal-verify-resume keymap-resource-study kill-ring-benchmark kill-ring-resource-study language-service-containment-test language-service-ols-acceptance language-service-reference-test language-service-resource-study language-service-workflow-acceptance layout-acceptance layout-acceptance-runtime layout-resource-study modal-replace-focused-test operational-state-test multi-view-resource-study multibuffer-history-benchmark multibuffer-transaction-benchmark native-command-benchmark native-command-test odra maksym-resource-study maksym-workflow-acceptance personal-command-acceptance personal-command-resource-study presentation-profile-resource-study preview-archive preview-archive-normalization-test preview-build-environment-test preview-bundle-assembly-acceptance preview-identity-test preview-metadata-test preview-provenance-test preview-runtime-acceptance preview-runtime-closure-check preview-tree preview-tree-assembly-test profile-compatibility-resource-study project-resource-study project-search-resource-study project-workspace-migration-acceptance project-workspace-migration-terminal-test project-workspace-migration-test recovery-contract-test recovery-resource-study resumable-verification-test result-set-resource-study search-command-benchmark search-resource-study search-result-navigation-acceptance source-hygiene-check status-bar-acceptance status-bar-resource-study symbol-navigation-resource-study structural-syntax-equivalence-test structural-syntax-reference-test structural-syntax-resource-study syntax-dependency-study syntax-reference-test syntax-resource-study syntax-vendor-build syntax-vendor-check terminal-benchmark terminal-dependency-check terminal-emulator-check terminal-emulator-evidence terminal-emulator-test terminal-presentation-focused-test terminal-presentation-test terminal-smoke terminal-test terminal-vendor-build terminal-vendor-clean-build test theme-equivalence-test theme-reference-test theme-workflow-acceptance transaction-benchmark transaction-fuzz transfer-command-benchmark tree-sitter-resource-study ui-acceptance ui-equivalence-test ui-migration-check ui-reference-test ui-resource-gates ui-resource-study ui-role-resource-study unicode-check unicode-data unicode-generated-check unicode-source-check user-guide-acceptance-check user-guide-check verify verify-resume verify-resume-reset view-benchmark workspace-composition-acceptance workspace-composition-test
.PHONY: modal-interaction-acceptance
.PHONY: odra-source-dependency-check
.PHONY: pointer-interaction-acceptance pointer-interaction-test pointer-terminal-test preview-artifact-hygiene-test preview-artifact-smoke-test preview-package-publication-test preview-publication-dispatch-test preview-publication-workflow-acceptance terminal-session-composition-test terminal-session-resource-study terminal-session-test
.PHONY: preview-racket-runtime-test
.PHONY: release-publication-identity-test
.PHONY: release-candidate-store-test
.PHONY: release-publication-workflow-test
.PHONY: public-source-export-test
.PHONY: public-source-snapshot-test
.PHONY: snapshot-repository-lifecycle-test
.PHONY: snapshot-build-adapter-test
.PHONY: user-guide-publication-contract-test
.PHONY: nightly-policy-test
.PHONY: nightly-runner-test
.PHONY: main-check-policy-test
.PHONY: ksawery-acceptance ksawery-change-acceptance ksawery-commit-acceptance ksawery-refs-acceptance ksawery-process-acceptance ksawery-sequence-acceptance ksawery-extension-acceptance ksawery-resource-study ksawery-diff-unit-study ksawery-history-resource-study ksawery-ref-resource-study ksawery-process-resource-study ksawery-process-focused-test ksawery-sequence-resource-study ksawery-sequence-focused-test ksawery-extension-resource-study ksawery-extension-focused-test ksawery-workflow-coordination-focused-test
.PHONY: factory-language-bundle-test gopls-language-service-acceptance jan-computation-focused-test jan-computation-model-test jan-computation-resource-study jan-document-language-acceptance jan-document-language-focused-test jan-document-language-resource-study jan-output-focused-test jan-output-model-test jan-output-resource-study jan-parser-boundary-test jan-parser-provenance-check jan-planning-focused-test jan-planning-model-test jan-planning-resource-study jan-structured-editing-acceptance jan-structured-editing-focused-test jan-structured-editing-model-test jan-structured-editing-resource-study language-bundle-acquisition-test language-bundle-author-kit-test language-bundle-catalog-test language-bundle-conformance-test language-bundle-inspection-test language-bundle-lifecycle-test language-bundle-model-test language-bundle-state-test language-catalog-model-test language-catalog-resource-study language-catalog-test language-formatter-test language-intelligence-query-test language-interaction-profile-test language-interaction-test language-service-catalog-model-test language-service-catalog-test language-service-extensibility-acceptance language-service-profile-test language-service-reconciliation-test language-support-config-test language-workflow-focused-test language-workspace-edit-test maintained-language-service-pty-test packaged-language-support-test racket-go-syntax-test racket-language-service-acceptance racket-language-service-protocol-test rust-language-service-acceptance rust-language-support-test syntax-injection-test syntax-provider-contract-test syntax-provider-loader-test syntax-workflow-test
.PHONY: web-language-service-acceptance web-language-syntax-test
.PHONY: basic-language-pack-acceptance extensible-language-support-acceptance language-edit-capability-acceptance
.PHONY: package-authority-contract-test package-canary-focused-test package-canary-linked-acceptance package-catalog-acceptance package-catalog-acceptance-reset package-catalog-bootstrap-test package-catalog-config-test package-catalog-conformance-test package-catalog-curator-kit-test package-catalog-identity-test package-catalog-interaction-test package-catalog-model-test package-catalog-resource-study package-catalog-runtime-test package-catalog-state-test package-focused-test package-model-test package-private-transport-test privacy-check roman-linked-acceptance
.PHONY: agent-substrate-closure-check agent-substrate-conformance-test agent-substrate-focused-test agent-substrate-recovery-acceptance agent-substrate-resource-study darek-module-focused-test ksawery-module-focused-test maksym-module-focused-test official-module-isolation-closure product-module-focused-test product-module-host-focused-test
.PHONY: indentation-policy-focused-test smart-indentation-focused-test modal-repeat-focused-test rectangular-selection-focused-test rectangular-selection-acceptance
.PHONY: basic-editor-linked-acceptance

define run_verification_step
$(if $(filter 1,$(ODRA_VERIFY_RESUME)),$(VERIFY_RESUME_RUNNER) --step $(1) -- $(2),$(2))
endef

define run_extensible_language_support_step
$(EXTENSIBLE_LANGUAGE_SUPPORT_ACCEPTANCE_RUNNER) --step $(1) -- $(2)
endef

define run_package_catalog_acceptance_step
$(PACKAGE_CATALOG_ACCEPTANCE_RUNNER) --step $(1) -- $(2)
endef

$(PRODUCT_MODULE_FIXTURE): $(filter-out %_test.odin,$(wildcard src/product_module/*.odin)) tests/product_module_fixture/module.odin
	mkdir -p $(dir $@)
	$(ODIN) build tests/product_module_fixture -build-mode:dll -out:$@ -o:none -vet -warnings-as-errors

$(PRODUCT_MODULE_FILE_MANAGEMENT_FIXTURE): $(filter-out %_test.odin,$(wildcard src/product_module/*.odin)) tests/product_module_fixture/module.odin
	mkdir -p $(dir $@)
	$(ODIN) build tests/product_module_fixture -build-mode:dll -out:$@ -o:none -vet -warnings-as-errors \
		-define:ODRA_PRODUCT_MODULE_FILE_MANAGEMENT=true

$(PRODUCT_MODULE_WORKSPACE_HIERARCHY_FIXTURE): $(filter-out %_test.odin,$(wildcard src/product_module/*.odin)) tests/product_module_fixture/module.odin
	mkdir -p $(dir $@)
	$(ODIN) build tests/product_module_fixture -build-mode:dll -out:$@ -o:none -vet -warnings-as-errors \
		-define:ODRA_PRODUCT_MODULE_WORKSPACE_HIERARCHY=true

$(PRODUCT_MODULE_STRUCTURED_DOCUMENT_FIXTURE): $(filter-out %_test.odin,$(wildcard src/product_module/*.odin)) tests/product_module_fixture/module.odin
	mkdir -p $(dir $@)
	$(ODIN) build tests/product_module_fixture -build-mode:dll -out:$@ -o:none -vet -warnings-as-errors \
		-define:ODRA_PRODUCT_MODULE_STRUCTURED_DOCUMENT=true

product-module-focused-test: $(PRODUCT_MODULE_FIXTURE) $(PRODUCT_MODULE_FILE_MANAGEMENT_FIXTURE) $(PRODUCT_MODULE_WORKSPACE_HIERARCHY_FIXTURE) $(PRODUCT_MODULE_STRUCTURED_DOCUMENT_FIXTURE)
	$(ODIN) test tests/product_module_focused \
		-define:ODRA_PRODUCT_MODULE_FIXTURE=$(abspath $(PRODUCT_MODULE_FIXTURE)) \
		-define:ODRA_PRODUCT_MODULE_FILE_MANAGEMENT_FIXTURE=$(abspath $(PRODUCT_MODULE_FILE_MANAGEMENT_FIXTURE)) \
		-define:ODRA_PRODUCT_MODULE_WORKSPACE_HIERARCHY_FIXTURE=$(abspath $(PRODUCT_MODULE_WORKSPACE_HIERARCHY_FIXTURE)) \
		-define:ODRA_PRODUCT_MODULE_STRUCTURED_DOCUMENT_FIXTURE=$(abspath $(PRODUCT_MODULE_STRUCTURED_DOCUMENT_FIXTURE)) \
		-vet -warnings-as-errors

product-module-host-focused-test: $(ODRA_DEVELOPMENT) $(BUILD_DIR)/modules/libodra-maksym.so
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA_DEVELOPMENT)) \
	ODRA_MAKSYM_MODULE=$(abspath $(BUILD_DIR)/modules/libodra-maksym.so) \
		bash scripts/run-racket-tests.sh "$(RACO)" "$(BUILD_DIR)" \
		tests/product_module/failure_containment_test.rkt

official-module-isolation-closure: development-build odra-source-dependency-check product-module-focused-test ksawery-module-focused-test maksym-module-focused-test darek-module-focused-test jan-module-focused-test product-module-host-focused-test
	bash scripts/run-racket-tests.sh "$(RACO)" "$(BUILD_DIR)" \
		tests/product_module/isolation_closure_test.rkt

KSAWERY_MODULE_LIBRARY := $(BUILD_DIR)/modules/libodra-ksawery.so
MAKSYM_MODULE_LIBRARY := $(BUILD_DIR)/modules/libodra-maksym.so
DAREK_MODULE_LIBRARY := $(BUILD_DIR)/modules/libodra-darek.so
JAN_MODULE_LIBRARY := $(BUILD_DIR)/modules/libodra-jan.so
PRODUCT_MODULE_MANIFEST := $(BUILD_DIR)/modules/product-modules.manifest
KSAWERY_MODULE_SOURCES := $(filter-out %_test.odin,$(wildcard src/ksawery_module/*.odin) $(wildcard src/ksawery/*.odin) $(wildcard src/ksawery_bridge/*.odin) $(wildcard src/ksawery_command/*.odin))
MAKSYM_MODULE_SOURCES := $(filter-out %_test.odin,$(wildcard src/maksym_module/*.odin) $(wildcard src/maksym/*.odin) $(wildcard src/filesystem/*.odin))
DAREK_MODULE_SOURCES := $(filter-out %_test.odin,$(wildcard src/darek_module/*.odin) $(wildcard src/darek/*.odin) $(wildcard src/filesystem/*.odin) $(wildcard src/project/*.odin) $(wildcard src/ui/*.odin))
JAN_MODULE_SOURCES := $(filter-out %_test.odin,$(wildcard src/jan_module/*.odin) $(wildcard src/jan_editing/*.odin) $(wildcard src/jan_planning/*.odin) $(wildcard src/jan_computation/*.odin) $(wildcard src/jan_output/*.odin) $(wildcard src/editor/*.odin) $(wildcard src/language/*.odin) $(wildcard src/ui/*.odin) $(wildcard src/view/*.odin))

$(KSAWERY_MODULE_LIBRARY): $(KSAWERY_MODULE_SOURCES) $(filter-out %_test.odin,$(wildcard src/product_module/*.odin))
	mkdir -p $(dir $@)
	$(ODIN) build src/ksawery_module -build-mode:dll -out:$@ -o:none -vet -warnings-as-errors

$(PREVIEW_KSAWERY_MODULE_LIBRARY): $(KSAWERY_MODULE_SOURCES) $(filter-out %_test.odin,$(wildcard src/product_module/*.odin))
	mkdir -p $(dir $@)
	$(ODIN) build src/ksawery_module -build-mode:dll -out:$@ -o:speed -vet -warnings-as-errors

$(MAKSYM_MODULE_LIBRARY): $(MAKSYM_MODULE_SOURCES) $(filter-out %_test.odin,$(wildcard src/product_module/*.odin))
	mkdir -p $(dir $@)
	$(ODIN) build src/maksym_module -build-mode:dll -out:$@ -o:none -vet -warnings-as-errors

$(PREVIEW_MAKSYM_MODULE_LIBRARY): $(MAKSYM_MODULE_SOURCES) $(filter-out %_test.odin,$(wildcard src/product_module/*.odin))
	mkdir -p $(dir $@)
	$(ODIN) build src/maksym_module -build-mode:dll -out:$@ -o:speed -vet -warnings-as-errors

$(DAREK_MODULE_LIBRARY): $(DAREK_MODULE_SOURCES) $(filter-out %_test.odin,$(wildcard src/product_module/*.odin))
	mkdir -p $(dir $@)
	$(ODIN) build src/darek_module -build-mode:dll -out:$@ -o:none -vet -warnings-as-errors

$(PREVIEW_DAREK_MODULE_LIBRARY): $(DAREK_MODULE_SOURCES) $(filter-out %_test.odin,$(wildcard src/product_module/*.odin))
	mkdir -p $(dir $@)
	$(ODIN) build src/darek_module -build-mode:dll -out:$@ -o:speed -vet -warnings-as-errors

$(JAN_MODULE_LIBRARY): $(JAN_MODULE_SOURCES) $(filter-out %_test.odin,$(wildcard src/product_module/*.odin))
	mkdir -p $(dir $@)
	$(ODIN) build src/jan_module -build-mode:dll -out:$@ -o:none -vet -warnings-as-errors

$(PREVIEW_JAN_MODULE_LIBRARY): $(JAN_MODULE_SOURCES) $(filter-out %_test.odin,$(wildcard src/product_module/*.odin))
	mkdir -p $(dir $@)
	$(ODIN) build src/jan_module -build-mode:dll -out:$@ -o:speed -vet -warnings-as-errors

$(PRODUCT_MODULE_MANIFEST): $(KSAWERY_MODULE_LIBRARY) $(MAKSYM_MODULE_LIBRARY) $(DAREK_MODULE_LIBRARY) $(JAN_MODULE_LIBRARY) scripts/write-product-module-manifest.rkt
	$(RACKET) scripts/write-product-module-manifest.rkt \
		--output $@ \
		--module odra.ksawery 1.0.0 source-control $(KSAWERY_MODULE_LIBRARY) odra_product_module_entrypoint 5 5 \
		--module odra.maksym 1.0.0 file-management $(MAKSYM_MODULE_LIBRARY) odra_product_module_entrypoint 5 5 \
		--module odra.darek 1.0.0 workspace-hierarchy $(DAREK_MODULE_LIBRARY) odra_product_module_entrypoint 5 5 \
		--module odra.jan 1.0.0 structured-document $(JAN_MODULE_LIBRARY) odra_product_module_entrypoint 5 5

$(PREVIEW_PRODUCT_MODULE_MANIFEST): $(PREVIEW_KSAWERY_MODULE_LIBRARY) $(PREVIEW_MAKSYM_MODULE_LIBRARY) $(PREVIEW_DAREK_MODULE_LIBRARY) $(PREVIEW_JAN_MODULE_LIBRARY) scripts/write-product-module-manifest.rkt
	$(RACKET) scripts/write-product-module-manifest.rkt \
		--output $@ \
		--module odra.ksawery 1.0.0 source-control $(PREVIEW_KSAWERY_MODULE_LIBRARY) odra_product_module_entrypoint 5 5 \
		--module odra.maksym 1.0.0 file-management $(PREVIEW_MAKSYM_MODULE_LIBRARY) odra_product_module_entrypoint 5 5 \
		--module odra.darek 1.0.0 workspace-hierarchy $(PREVIEW_DAREK_MODULE_LIBRARY) odra_product_module_entrypoint 5 5 \
		--module odra.jan 1.0.0 structured-document $(PREVIEW_JAN_MODULE_LIBRARY) odra_product_module_entrypoint 5 5

ksawery-module-focused-test: $(KSAWERY_MODULE_LIBRARY)
	$(ODIN) test tests/ksawery_module_focused \
		-define:ODRA_KSAWERY_MODULE=$(abspath $(KSAWERY_MODULE_LIBRARY)) \
		-vet -warnings-as-errors

maksym-module-focused-test: $(MAKSYM_MODULE_LIBRARY)
	$(ODIN) test tests/maksym_module_focused \
		-define:ODRA_MAKSYM_MODULE=$(abspath $(MAKSYM_MODULE_LIBRARY)) \
		-define:ODIN_TEST_THREADS=1 \
		-vet -warnings-as-errors

darek-module-focused-test: $(DAREK_MODULE_LIBRARY)
	$(ODIN) test tests/darek_module_focused \
		-define:ODRA_DAREK_MODULE=$(abspath $(DAREK_MODULE_LIBRARY)) \
		-vet -warnings-as-errors

jan-module-focused-test: $(JAN_MODULE_LIBRARY)
	$(ODIN) test tests/jan_module_focused \
		-define:ODRA_JAN_MODULE=$(abspath $(JAN_MODULE_LIBRARY)) \
		-define:ODIN_TEST_THREADS=1 \
		-vet -warnings-as-errors

nightly-policy-test:
	$(RACKET_TEST) scripts/nightly-status.rkt
	$(RACKET_TEST) tests/nightly/admission_policy_test.rkt
	bash -n scripts/dispatch-nightly-verification.sh scripts/run-racket-tests.sh

nightly-runner-test:
	$(RACKET_TEST) tests/nightly/runner_test.rkt
	bash -n scripts/run-nightly-verification.sh

main-check-policy-test:
	$(RACKET_TEST) tests/main_check/workflow_policy_test.rkt

preview-identity-test:
	$(RACKET_TEST) scripts/release/preview-identity.rkt

release-publication-identity-test:
	$(RACKET_TEST) tests/release_publication/candidate_identity_test.rkt

release-candidate-store-test:
	$(RACKET_TEST) tests/release_publication/candidate_store_test.rkt

release-publication-workflow-test:
	$(RACKET_TEST) tests/release_publication/release_workflow_test.rkt
	racket scripts/release/check-release-publication-workflow.rkt

public-source-export-test:
	$(RACKET_TEST) tests/release_publication/public_source_export_test.rkt

public-source-snapshot-test:
	$(RACKET_TEST) tests/release_publication/public_source_snapshot_test.rkt

snapshot-repository-lifecycle-test:
	$(RACKET_TEST) tests/release_publication/snapshot_repository_test.rkt

snapshot-build-adapter-test:
	$(RACKET_TEST) tests/release_publication/snapshot_build_test.rkt

user-guide-publication-contract-test:
	$(RACKET_TEST) tests/release_publication/user_guide_publication_test.rkt

preview-build-environment-test:
	$(RACKET_TEST) scripts/release/check-build-environment.rkt
	$(RACKET) scripts/release/check-build-environment.rkt

preview-provenance-test:
	$(RACKET_TEST) scripts/release/record-preview-provenance.rkt

preview-artifact-smoke-test:
	$(RACKET_TEST) scripts/release/smoke-preview-artifact.rkt

preview-artifact-hygiene-test:
	$(RACKET_TEST) scripts/release/check-preview-artifact-hygiene.rkt

preview-publication-dispatch-test:
	$(RACKET_TEST) scripts/release/validate-preview-dispatch.rkt

preview-package-publication-test:
	$(RACKET_TEST) scripts/release/publish-preview-package.rkt

preview-publication-workflow-acceptance:
	$(RACKET_TEST) scripts/release/check-preview-publication-workflow.rkt
	$(RACKET) scripts/release/check-preview-publication-workflow.rkt

preview-metadata-test:
	$(RACKET_TEST) scripts/release/add-preview-metadata.rkt

preview-runtime-closure-check: $(ODRA)
	$(RACKET_TEST) scripts/release/check-runtime-closure.rkt
	$(RACKET) scripts/release/check-runtime-closure.rkt --binary $(ODRA)

preview-runtime-acceptance: $(PREVIEW_RUNTIME_BINARY) $(PREVIEW_PRODUCT_MODULE_MANIFEST)
	ODRA_PREVIEW_EXECUTABLE=$(abspath $(PREVIEW_RUNTIME_BINARY)) \
		ODRA_RACKET_BOOT_DIR=$(RACKET_BOOT_DIR) \
		ODRA_RACKET_COLLECTS_DIR=$(RACKET_COLLECTS_DIR) \
		ODRA_RACKET_CONFIG_DIR=$(RACKET_CONFIG_DIR) \
		$(RACKET_TEST) tests/preview_runtime/acceptance_test.rkt

preview-tree: $(PREVIEW_RUNTIME_BINARY) $(PREVIEW_PRODUCT_MODULE_MANIFEST)
	$(RACKET) scripts/release/assemble-preview-tree.rkt \
		--manifest $(PREVIEW_RUNTIME_CLOSURE) \
		--binary $(PREVIEW_RUNTIME_BINARY) \
		--repository-root . \
		--release-input-root / \
		--output-parent $(PREVIEW_TREE_OUTPUT_PARENT) \
		--tag "$(PREVIEW_TAG)" \
		--tag-commit "$(PREVIEW_COMMIT)" \
		--main-commit "$(PREVIEW_COMMIT)" \
		--source-date-epoch "$(SOURCE_DATE_EPOCH)" \
		--build-environment "$(PREVIEW_BUILD_ENVIRONMENT)" \
		--module-root $(PREVIEW_PRODUCT_MODULE_DIR)

preview-tree-assembly-test:
	$(RACKET_TEST) scripts/release/assemble-preview-tree.rkt

preview-archive:
	$(RACKET) scripts/release/archive-preview-tree.rkt \
		--manifest $(PREVIEW_RUNTIME_CLOSURE) \
		--tree $(PREVIEW_TREE) \
		--output-parent $(PREVIEW_ARCHIVE_OUTPUT_PARENT) \
		--tag "$(PREVIEW_TAG)" \
		--tag-commit "$(PREVIEW_COMMIT)" \
		--main-commit "$(PREVIEW_COMMIT)" \
		--source-date-epoch "$(SOURCE_DATE_EPOCH)"

preview-archive-normalization-test:
	$(RACKET_TEST) scripts/release/archive-preview-tree.rkt

preview-bundle-assembly-acceptance:
	$(RACKET_TEST) scripts/release/check-runtime-closure.rkt
	$(RACKET_TEST) scripts/release/add-preview-metadata.rkt
	$(RACKET_TEST) scripts/release/assemble-preview-tree.rkt
	$(RACKET_TEST) scripts/release/archive-preview-tree.rkt

ui-reference-test:
	$(ODIN) test tests/ui_reference -vet -warnings-as-errors

ui-equivalence-test:
	$(ODIN) test tests/ui_equivalence -vet -warnings-as-errors

theme-reference-test:
	$(ODIN) test tests/theme_reference -vet -warnings-as-errors

theme-equivalence-test:
	$(ODIN) test tests/theme_equivalence -vet -warnings-as-errors

$(UI_RESOURCE_STUDY): tests/ui_resource_study/main.odin $(wildcard tests/ui_reference/*.odin)
	mkdir -p $(BUILD_DIR)
	$(ODIN) build tests/ui_resource_study \
		-o:speed \
		-vet -warnings-as-errors \
		-out:$@

ui-resource-study: $(UI_RESOURCE_STUDY)
	$(ODIN) version
	uname -srm
	$(UI_RESOURCE_STUDY)

$(UI_ROLE_RESOURCE_STUDY): tests/ui_role_resource_study/main.odin $(wildcard src/command/*.odin src/hosting/*.odin src/bridge/*.odin src/ui/*.odin) $(RUNTIME_TEST_ADAPTER_LIBRARY)
	mkdir -p $(BUILD_DIR)
	$(ODIN) build tests/ui_role_resource_study \
		-o:speed \
		-vet -warnings-as-errors \
		-out:$@ \
		-define:ODRA_RACKET_RUNTIME_LIBRARY="../../$(RUNTIME_TEST_ADAPTER_LIBRARY)" \
		-extra-linker-flags:"$(RACKET_CS_LIBRARY) $(RACKET_CS_LINK_LIBS)"

ui-role-resource-study: $(UI_ROLE_RESOURCE_STUDY)
	$(ODIN) version
	uname -srm
	$(UI_ROLE_RESOURCE_STUDY)

$(PRESENTATION_PROFILE_RESOURCE_STUDY): tests/presentation_profile_resource_study/main.odin $(wildcard src/ui/*.odin)
	mkdir -p $(BUILD_DIR)
	$(ODIN) build tests/presentation_profile_resource_study \
		-o:speed \
		-vet -warnings-as-errors \
		-out:$@

presentation-profile-resource-study: $(PRESENTATION_PROFILE_RESOURCE_STUDY)
	$(ODIN) version
	uname -srm
	$(PRESENTATION_PROFILE_RESOURCE_STUDY)

completion-reference-test:
	$(ODIN) test tests/completion_reference -vet -warnings-as-errors

$(COMPLETION_RESOURCE_STUDY): tests/completion_resource_study/main.odin $(wildcard src/completion/*.odin)
	mkdir -p $(BUILD_DIR)
	$(ODIN) build tests/completion_resource_study \
		-o:speed \
		-vet -warnings-as-errors \
		-out:$@

completion-resource-study: $(COMPLETION_RESOURCE_STUDY)
	$(ODIN) version
	uname -srm
	$(COMPLETION_RESOURCE_STUDY)

ui-resource-gates:
	$(MAKE) ui-resource-study
	$(MAKE) ui-role-resource-study
	$(MAKE) presentation-profile-resource-study
	$(MAKE) multi-view-resource-study
	$(MAKE) project-resource-study
	$(MAKE) candidate-navigation-resource-study
	$(MAKE) editor-session-resource-study
	$(MAKE) search-resource-study
	$(MAKE) layout-resource-study
	$(MAKE) keymap-resource-study
	$(MAKE) display-benchmark
	$(MAKE) terminal-benchmark

benchmark:
	$(ODIN) version
	uname -srm
	$(ODIN) run tests/benchmark -o:speed -vet -warnings-as-errors --

editor-event-loop-latency-test:
	$(RACKET_TEST) tests/editor_event_loop_latency/model-test.rkt

editor-event-loop-latency-study:
	test -n "$(ODRA_PTY_EXECUTABLE)" -a -e "$(ODRA_PTY_EXECUTABLE)"
	ODRA_PTY_EXECUTABLE="$(ODRA_PTY_EXECUTABLE)" \
		$(RACKET) tests/editor_event_loop_latency/study.rkt

recovery-contract-test:
	$(ODIN) test src/recovery -vet -warnings-as-errors
	$(RACKET_TEST) src/command/recovery.rkt \
		src/recovery/root.rkt \
		tests/configuration/recovery_policy_test.rkt

.PHONY: recovery-startup-acceptance
recovery-startup-acceptance:
	@test -x $(ODRA_DEVELOPMENT) || { \
		echo 'Development executable is missing; run make development-build.' >&2; \
		exit 1; \
	}
	ODRA_PTY_EXECUTABLE=$(abspath scripts/run-development-editor.sh) \
		$(PTY_RACKET_TEST) tests/recovery/startup_acceptance_test.rkt

recovery-resource-study:
	$(RACKET) tests/recovery/resource-study.rkt

$(VIEW_BENCHMARK): tests/view_benchmark/main.odin $(wildcard src/view/*.odin src/search/*.odin src/editor/*.odin src/text/*.odin)
	mkdir -p $(BUILD_DIR)
	$(ODIN) build tests/view_benchmark \
		-o:speed \
		-vet -warnings-as-errors \
		-out:$@

view-benchmark: $(VIEW_BENCHMARK)
	$(VIEW_BENCHMARK)

$(INTERACTION_BENCHMARK): tests/interaction_benchmark/main.odin src/interaction/contracts.odin src/interaction/resolver.odin
	mkdir -p $(BUILD_DIR)
	$(ODIN) build tests/interaction_benchmark \
		-o:speed \
		-vet -warnings-as-errors \
		-out:$@

interaction-benchmark: $(INTERACTION_BENCHMARK)
	$(ODIN) version
	uname -srm
	$(INTERACTION_BENCHMARK)

$(KEYMAP_RESOURCE_STUDY): tests/keymap_resource_study/main.odin
	mkdir -p $(BUILD_DIR)
	$(ODIN) build tests/keymap_resource_study \
		-o:speed \
		-vet -warnings-as-errors \
		-out:$@

keymap-resource-study: $(KEYMAP_RESOURCE_STUDY)
	$(ODIN) version
	uname -srm
	$(KEYMAP_RESOURCE_STUDY)

$(PROFILE_COMPATIBILITY_RESOURCE_STUDY): tests/profile_compatibility_resource_study/main.odin
	mkdir -p $(BUILD_DIR)
	$(ODIN) build tests/profile_compatibility_resource_study \
		-o:speed \
		-vet -warnings-as-errors \
		-out:$@

profile-compatibility-resource-study: $(PROFILE_COMPATIBILITY_RESOURCE_STUDY)
	$(ODIN) version
	uname -srm
	$(PROFILE_COMPATIBILITY_RESOURCE_STUDY)

modal-interaction-acceptance: $(ODRA)
	$(RACKET_TEST) src/command/keymap-model.rkt src/command/keymaps.rkt
	$(RACKET_TEST) tests/configuration/personal_test.rkt
	$(ODIN) test src/interaction -vet -warnings-as-errors \
		-define:ODIN_TEST_NAMES=interaction.modal_state_transition_is_atomic,interaction.profile_selection_uses_exact_initial_state,interaction.notation_preserves_strokes_and_modifiers
	$(ODIN) test src/status_bar -vet -warnings-as-errors \
		-define:ODIN_TEST_NAMES=status_bar.status_factory_keeps_modal_state_visible
	$(ODIN) test src/ui -vet -warnings-as-errors \
		-define:ODIN_TEST_NAMES=ui.text_view_copies_revisioned_state
	$(ODIN) test src/terminal -vet -warnings-as-errors \
		-define:ODIN_TEST_NAMES=terminal_frontend.applies_theme_before_canvas_clear,terminal_frontend.terminal_decoder_normalizes_supported_input,terminal_frontend.terminal_decoder_rejects_invalid_sequences
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/modal_interaction/workflow_terminal_test.rkt

language-service-reference-test:
	$(ODIN) test tests/language_service_reference -vet -warnings-as-errors

language-service-containment-test:
	mkdir -p $(BUILD_DIR)
	trap 'rm -f language_service' EXIT; \
	$(ODIN) test src/language_service -vet -warnings-as-errors \
		-define:ODIN_TEST_THREADS=1 \
		-out:$(BUILD_DIR)/language-service-containment-test

$(LANGUAGE_SERVICE_RESOURCE_STUDY): tests/language_service_resource_study/main.odin $(wildcard tests/language_service_reference/*.odin)
	mkdir -p $(BUILD_DIR)
	$(ODIN) build tests/language_service_resource_study \
		-o:speed \
		-vet -warnings-as-errors \
		-out:$@

language-service-resource-study: $(LANGUAGE_SERVICE_RESOURCE_STUDY)
	$(ODIN) version
	uname -srm
	$(LANGUAGE_SERVICE_RESOURCE_STUDY)

$(LANGUAGE_SERVICE_OLS_ACCEPTANCE): tests/language_service_ols_acceptance/main.odin $(wildcard src/language_service/*.odin src/completion/*.odin src/project/*.odin) tests/fixtures/language-service-server.rkt tests/fixtures/language-service-fixture/source.fixture tests/fixtures/ols/main.odin
	mkdir -p $(BUILD_DIR)
	$(ODIN) build tests/language_service_ols_acceptance \
		-o:speed \
		-vet -warnings-as-errors \
		-out:$@

language-service-ols-acceptance: $(LANGUAGE_SERVICE_OLS_ACCEPTANCE)
	$(LANGUAGE_SERVICE_OLS_ACCEPTANCE)

language-service-workflow-acceptance: $(ODRA) $(LANGUAGE_SERVICE_OLS_ACCEPTANCE)
	$(LANGUAGE_SERVICE_OLS_ACCEPTANCE)
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/language_service_workflow/workflow_test.rkt

syntax-dependency-study:
	bash scripts/check-syntax-dependency-study.sh

syntax-reference-test:
	$(ODIN) test tests/syntax_analysis_reference -vet -warnings-as-errors

$(SYNTAX_RESOURCE_STUDY): tests/syntax_resource_study/main.odin
	mkdir -p $(BUILD_DIR)
	$(ODIN) build tests/syntax_resource_study \
		-o:speed \
		-vet -warnings-as-errors \
		-out:$@

syntax-resource-study: $(SYNTAX_RESOURCE_STUDY)
	$(ODIN) version
	uname -srm
	$(SYNTAX_RESOURCE_STUDY)

$(TREE_SITTER_RESOURCE_STUDY): tests/tree_sitter_resource_study/main.odin $(wildcard src/language/*.odin src/editor/*.odin src/transaction/*.odin) $(TREE_SITTER_ODIN_LIBRARY)
	mkdir -p $(BUILD_DIR)
	$(ODIN) build tests/tree_sitter_resource_study \
		-o:speed \
		-vet -warnings-as-errors \
		-out:$@ \
		-define:ODRA_TREE_SITTER_LIBRARY="../../$(TREE_SITTER_ODIN_LIBRARY)"

tree-sitter-resource-study: $(TREE_SITTER_RESOURCE_STUDY)
	$(ODIN) version
	uname -srm
	$(TREE_SITTER_RESOURCE_STUDY)

structural-syntax-reference-test:
	$(ODIN) test tests/structural_syntax_reference -vet -warnings-as-errors

structural-syntax-equivalence-test: $(TREE_SITTER_ODIN_LIBRARY)
	$(ODIN) test tests/structural_syntax_equivalence -vet -warnings-as-errors \
		-define:ODRA_TREE_SITTER_LIBRARY="../../$(TREE_SITTER_ODIN_LIBRARY)"

$(STRUCTURAL_SYNTAX_RESOURCE_STUDY): tests/structural_syntax_resource_study/main.odin $(wildcard tests/structural_syntax_reference/*.odin)
	mkdir -p $(BUILD_DIR)
	$(ODIN) build tests/structural_syntax_resource_study \
		-o:speed \
		-vet -warnings-as-errors \
		-out:$@

structural-syntax-resource-study: $(STRUCTURAL_SYNTAX_RESOURCE_STUDY)
	$(ODIN) version
	uname -srm
	$(STRUCTURAL_SYNTAX_RESOURCE_STUDY)

syntax-vendor-check:
	bash scripts/check-syntax-vendor.sh

terminal-dependency-check:
	bash scripts/check-terminal-dependency.sh
	bash tests/terminal_dependency/check.sh

$(TERMINAL_VENDOR_LIBRARY): scripts/build-terminal-vendor.sh $(TERMINAL_VENDOR_DIR)/MANIFEST $(TERMINAL_VENDOR_DIR)/SHA256SUMS $(wildcard $(TERMINAL_VENDOR_DIR)/source/* $(TERMINAL_VENDOR_DIR)/toolchain/* $(TERMINAL_VENDOR_DIR)/packages/*)
	bash scripts/build-terminal-vendor.sh $(TERMINAL_VENDOR_DIR) $(TERMINAL_VENDOR_BUILD_DIR)

terminal-vendor-build: terminal-dependency-check $(TERMINAL_VENDOR_LIBRARY)
	test -s $(TERMINAL_VENDOR_LIBRARY)

terminal-vendor-clean-build: terminal-dependency-check
	bash scripts/build-terminal-vendor.sh $(TERMINAL_VENDOR_DIR) $(TERMINAL_VENDOR_BUILD_DIR) --clean

$(TERMINAL_EMULATOR_ADAPTER_OBJECT): src/terminal_emulator/adapter.c src/terminal_emulator/adapter.h $(TERMINAL_VENDOR_DIR)/MANIFEST
	mkdir -p $(TERMINAL_EMULATOR_BUILD_DIR)
	$(CC) -std=c11 -O2 -Wall -Wextra -Werror -fPIC -DGHOSTTY_STATIC \
		-I$(TERMINAL_VENDOR_DIR)/include -Isrc/terminal_emulator \
		-c src/terminal_emulator/adapter.c -o $@

$(TERMINAL_EMULATOR_ADAPTER_LIBRARY): $(TERMINAL_EMULATOR_ADAPTER_OBJECT)
	$(AR) rcs $@ $^

terminal-emulator-check: terminal-vendor-build $(TERMINAL_EMULATOR_ADAPTER_LIBRARY)
	$(ODIN) check src/terminal_emulator $(ODIN_VET_FLAGS) \
		-define:ODRA_TERMINAL_EMULATOR_ADAPTER_LIBRARY="../../$(TERMINAL_EMULATOR_ADAPTER_LIBRARY)" \
		-define:ODRA_TERMINAL_EMULATOR_VENDOR_LIBRARY="../../$(TERMINAL_VENDOR_LIBRARY)"

$(TERMINAL_EMULATOR_PROBE): tests/terminal_emulator_probe/main.c src/terminal_emulator/adapter.h $(TERMINAL_EMULATOR_ADAPTER_LIBRARY) $(TERMINAL_VENDOR_LIBRARY)
	$(CC) -std=c11 -O2 -Wall -Wextra -Werror \
		-Isrc/terminal_emulator \
		tests/terminal_emulator_probe/main.c \
		$(TERMINAL_EMULATOR_ADAPTER_LIBRARY) $(TERMINAL_VENDOR_LIBRARY) -lm -o $@

$(TERMINAL_EMULATOR_ODIN_PROBE): tests/terminal_emulator_odin_probe/main.odin $(wildcard src/terminal_emulator/*.odin) $(TERMINAL_EMULATOR_ADAPTER_LIBRARY) $(TERMINAL_VENDOR_LIBRARY)
	$(ODIN) build tests/terminal_emulator_odin_probe -vet -warnings-as-errors -out:$@ \
		-define:ODRA_TERMINAL_EMULATOR_ADAPTER_LIBRARY="../../$(TERMINAL_EMULATOR_ADAPTER_LIBRARY)" \
		-define:ODRA_TERMINAL_EMULATOR_VENDOR_LIBRARY="../../$(TERMINAL_VENDOR_LIBRARY)"

terminal-emulator-test: terminal-emulator-check $(TERMINAL_EMULATOR_PROBE) $(TERMINAL_EMULATOR_ODIN_PROBE)
	$(TERMINAL_EMULATOR_PROBE)
	$(TERMINAL_EMULATOR_ODIN_PROBE)

terminal-emulator-evidence: terminal-emulator-test
	@adapter_bytes=$$(wc -c < $(TERMINAL_EMULATOR_ADAPTER_LIBRARY)); \
		vendor_bytes=$$(wc -c < $(TERMINAL_VENDOR_LIBRARY)); \
		start=$$(date +%s%N); \
		$(TERMINAL_EMULATOR_PROBE) >/dev/null; \
		finish=$$(date +%s%N); \
		printf 'terminal_emulator_adapter_bytes=%s vendor_bytes=%s probe_nanoseconds=%s\n' \
			"$$adapter_bytes" "$$vendor_bytes" "$$((finish - start))"

$(INTERACTIVE_SESSION_ADAPTER_OBJECT): src/interactive_session/adapter_linux.c src/interactive_session/adapter_linux.h
	mkdir -p $(INTERACTIVE_SESSION_BUILD_DIR)
	$(CC) -std=c11 -O2 -Wall -Wextra -Werror -fPIC \
		-Isrc/interactive_session \
		-c src/interactive_session/adapter_linux.c -o $@

$(INTERACTIVE_SESSION_ADAPTER_LIBRARY): $(INTERACTIVE_SESSION_ADAPTER_OBJECT)
	$(AR) rcs $@ $^

interactive-session-model-test interactive-session-process-test interactive-session-transport-test: $(INTERACTIVE_SESSION_ADAPTER_LIBRARY)
	$(ODIN) test src/interactive_session -o:none -vet -warnings-as-errors \
		-define:ODRA_INTERACTIVE_SESSION_ADAPTER_LIBRARY="../../$(INTERACTIVE_SESSION_ADAPTER_LIBRARY)"

interactive-session-resource-study: $(INTERACTIVE_SESSION_ADAPTER_LIBRARY)
	$(ODIN) run tests/interactive_session_resource_study -o:none -vet -warnings-as-errors \
		-define:ODRA_INTERACTIVE_SESSION_ADAPTER_LIBRARY="../../$(INTERACTIVE_SESSION_ADAPTER_LIBRARY)"

interactive-session-test: interactive-session-transport-test interactive-session-resource-study

terminal-session-composition-test: terminal-vendor-build $(TERMINAL_EMULATOR_ADAPTER_LIBRARY) $(INTERACTIVE_SESSION_ADAPTER_LIBRARY)
	$(ODIN) test src/terminal_session -out:$(BUILD_DIR)/terminal-session-test \
		-o:none -vet -warnings-as-errors \
		-define:ODIN_TEST_THREADS=1 \
		-define:ODRA_INTERACTIVE_SESSION_ADAPTER_LIBRARY="../../$(INTERACTIVE_SESSION_ADAPTER_LIBRARY)" \
		-define:ODRA_TERMINAL_EMULATOR_ADAPTER_LIBRARY="../../$(TERMINAL_EMULATOR_ADAPTER_LIBRARY)" \
		-define:ODRA_TERMINAL_EMULATOR_VENDOR_LIBRARY="../../$(TERMINAL_VENDOR_LIBRARY)"

terminal-session-resource-study: terminal-vendor-build $(TERMINAL_EMULATOR_ADAPTER_LIBRARY) $(INTERACTIVE_SESSION_ADAPTER_LIBRARY)
	$(ODIN) run tests/terminal_session_resource_study -out:$(BUILD_DIR)/terminal-session-resource-study \
		-o:none -vet -warnings-as-errors \
		-define:ODRA_INTERACTIVE_SESSION_ADAPTER_LIBRARY="../../$(INTERACTIVE_SESSION_ADAPTER_LIBRARY)" \
		-define:ODRA_TERMINAL_EMULATOR_ADAPTER_LIBRARY="../../$(TERMINAL_EMULATOR_ADAPTER_LIBRARY)" \
		-define:ODRA_TERMINAL_EMULATOR_VENDOR_LIBRARY="../../$(TERMINAL_VENDOR_LIBRARY)"

terminal-session-test: terminal-session-composition-test terminal-session-resource-study

$(TREE_SITTER_OBJECT): $(TREE_SITTER_DIR)/SHA256SUMS $(wildcard $(TREE_SITTER_DIR)/lib/src/*.c $(TREE_SITTER_DIR)/lib/src/*.h $(TREE_SITTER_DIR)/lib/src/portable/*.h $(TREE_SITTER_DIR)/lib/src/unicode/*.h $(TREE_SITTER_DIR)/lib/include/tree_sitter/*.h)
	mkdir -p $(SYNTAX_VENDOR_BUILD_DIR)
	$(CC) -O3 -Wall -Wextra -Wshadow -Wpedantic \
		-Werror=incompatible-pointer-types -Werror=strict-aliasing \
		-Wstrict-aliasing=2 -std=c11 -fPIC -fvisibility=hidden \
		-D_POSIX_C_SOURCE=200112L -D_DEFAULT_SOURCE -D_BSD_SOURCE \
		-D_DARWIN_C_SOURCE -I$(TREE_SITTER_DIR)/lib/src \
		-I$(TREE_SITTER_DIR)/lib/src/wasm -I$(TREE_SITTER_DIR)/lib/include \
		-c $(TREE_SITTER_DIR)/lib/src/lib.c -o $@

$(TREE_SITTER_ODIN_PARSER_OBJECT): $(TREE_SITTER_ODIN_DIR)/SHA256SUMS $(TREE_SITTER_ODIN_DIR)/src/parser.c $(wildcard $(TREE_SITTER_ODIN_DIR)/src/tree_sitter/*.h)
	mkdir -p $(SYNTAX_VENDOR_BUILD_DIR)
	$(CC) -O3 -std=c11 -fPIC -fvisibility=hidden \
		-I$(TREE_SITTER_ODIN_DIR)/src \
		-c $(TREE_SITTER_ODIN_DIR)/src/parser.c -o $@

$(TREE_SITTER_ODIN_SCANNER_OBJECT): $(TREE_SITTER_ODIN_DIR)/SHA256SUMS $(TREE_SITTER_ODIN_DIR)/src/scanner.c $(wildcard $(TREE_SITTER_ODIN_DIR)/src/tree_sitter/*.h)
	mkdir -p $(SYNTAX_VENDOR_BUILD_DIR)
	$(CC) -O3 -std=c11 -fPIC -fvisibility=hidden \
		-I$(TREE_SITTER_ODIN_DIR)/src \
		-c $(TREE_SITTER_ODIN_DIR)/src/scanner.c -o $@

$(TREE_SITTER_JAN_PARSER_OBJECT): $(TREE_SITTER_JAN_DIR)/SHA256SUMS $(TREE_SITTER_JAN_DIR)/src/parser.c $(wildcard $(TREE_SITTER_JAN_DIR)/src/tree_sitter/*.h)
	mkdir -p $(SYNTAX_VENDOR_BUILD_DIR)
	$(CC) -O3 -std=c11 -fPIC -fvisibility=hidden \
		-I$(TREE_SITTER_JAN_DIR)/src \
		-c $(TREE_SITTER_JAN_DIR)/src/parser.c -o $@

$(TREE_SITTER_JAN_SCANNER_OBJECT): $(TREE_SITTER_JAN_DIR)/SHA256SUMS $(TREE_SITTER_JAN_DIR)/src/scanner.c $(wildcard $(TREE_SITTER_JAN_DIR)/src/tree_sitter/*.h)
	mkdir -p $(SYNTAX_VENDOR_BUILD_DIR)
	$(CC) -O3 -std=c11 -Wall -Wextra -Werror -fPIC -fvisibility=hidden \
		-I$(TREE_SITTER_JAN_DIR)/src \
		-c $(TREE_SITTER_JAN_DIR)/src/scanner.c -o $@

$(TREE_SITTER_RACKET_PARSER_OBJECT): $(TREE_SITTER_RACKET_DIR)/SHA256SUMS $(TREE_SITTER_RACKET_DIR)/src/parser.c $(wildcard $(TREE_SITTER_RACKET_DIR)/src/tree_sitter/*.h)
	mkdir -p $(SYNTAX_VENDOR_BUILD_DIR)
	$(CC) -O3 -std=c11 -fPIC -fvisibility=hidden \
		-I$(TREE_SITTER_RACKET_DIR)/src \
		-c $(TREE_SITTER_RACKET_DIR)/src/parser.c -o $@

$(TREE_SITTER_RACKET_SCANNER_OBJECT): $(TREE_SITTER_RACKET_DIR)/SHA256SUMS $(TREE_SITTER_RACKET_DIR)/src/scanner.c $(wildcard $(TREE_SITTER_RACKET_DIR)/src/tree_sitter/*.h)
	mkdir -p $(SYNTAX_VENDOR_BUILD_DIR)
	$(CC) -O3 -std=c11 -fPIC -fvisibility=hidden \
		-I$(TREE_SITTER_RACKET_DIR)/src \
		-c $(TREE_SITTER_RACKET_DIR)/src/scanner.c -o $@

$(TREE_SITTER_GO_PARSER_OBJECT): $(TREE_SITTER_GO_DIR)/SHA256SUMS $(TREE_SITTER_GO_DIR)/src/parser.c $(wildcard $(TREE_SITTER_GO_DIR)/src/tree_sitter/*.h)
	mkdir -p $(SYNTAX_VENDOR_BUILD_DIR)
	$(CC) -O3 -std=c11 -fPIC -fvisibility=hidden \
		-I$(TREE_SITTER_GO_DIR)/src \
		-c $(TREE_SITTER_GO_DIR)/src/parser.c -o $@

$(TREE_SITTER_RUST_PARSER_OBJECT): $(TREE_SITTER_RUST_DIR)/SHA256SUMS $(TREE_SITTER_RUST_DIR)/src/parser.c $(wildcard $(TREE_SITTER_RUST_DIR)/src/tree_sitter/*.h)
	mkdir -p $(SYNTAX_VENDOR_BUILD_DIR)
	$(CC) -O3 -std=c11 -fPIC -fvisibility=hidden \
		-I$(TREE_SITTER_RUST_DIR)/src \
		-c $(TREE_SITTER_RUST_DIR)/src/parser.c -o $@

$(TREE_SITTER_RUST_SCANNER_OBJECT): $(TREE_SITTER_RUST_DIR)/SHA256SUMS $(TREE_SITTER_RUST_DIR)/src/scanner.c $(wildcard $(TREE_SITTER_RUST_DIR)/src/tree_sitter/*.h)
	mkdir -p $(SYNTAX_VENDOR_BUILD_DIR)
	$(CC) -O3 -std=c11 -Wall -Wextra -Werror -fPIC -fvisibility=hidden \
		-I$(TREE_SITTER_RUST_DIR)/src \
		-c $(TREE_SITTER_RUST_DIR)/src/scanner.c -o $@

$(TREE_SITTER_JAVASCRIPT_PARSER_OBJECT): $(TREE_SITTER_JAVASCRIPT_DIR)/SHA256SUMS $(TREE_SITTER_JAVASCRIPT_DIR)/src/parser.c $(wildcard $(TREE_SITTER_JAVASCRIPT_DIR)/src/tree_sitter/*.h)
	mkdir -p $(SYNTAX_VENDOR_BUILD_DIR)
	$(CC) -O3 -std=c11 -fPIC -fvisibility=hidden -I$(TREE_SITTER_JAVASCRIPT_DIR)/src -c $(TREE_SITTER_JAVASCRIPT_DIR)/src/parser.c -o $@

$(TREE_SITTER_JAVASCRIPT_SCANNER_OBJECT): $(TREE_SITTER_JAVASCRIPT_DIR)/SHA256SUMS $(TREE_SITTER_JAVASCRIPT_DIR)/src/scanner.c $(wildcard $(TREE_SITTER_JAVASCRIPT_DIR)/src/tree_sitter/*.h)
	mkdir -p $(SYNTAX_VENDOR_BUILD_DIR)
	$(CC) -O3 -std=c11 -Wall -Wextra -fPIC -fvisibility=hidden -I$(TREE_SITTER_JAVASCRIPT_DIR)/src -c $(TREE_SITTER_JAVASCRIPT_DIR)/src/scanner.c -o $@

$(TREE_SITTER_TYPESCRIPT_PARSER_OBJECT): $(TREE_SITTER_TYPESCRIPT_DIR)/SHA256SUMS $(TREE_SITTER_TYPESCRIPT_DIR)/typescript/src/parser.c $(wildcard $(TREE_SITTER_TYPESCRIPT_DIR)/typescript/src/tree_sitter/*.h)
	mkdir -p $(SYNTAX_VENDOR_BUILD_DIR)
	$(CC) -O3 -std=c11 -fPIC -fvisibility=hidden -I$(TREE_SITTER_TYPESCRIPT_DIR)/typescript/src -c $(TREE_SITTER_TYPESCRIPT_DIR)/typescript/src/parser.c -o $@

$(TREE_SITTER_TYPESCRIPT_SCANNER_OBJECT): $(TREE_SITTER_TYPESCRIPT_DIR)/SHA256SUMS $(TREE_SITTER_TYPESCRIPT_DIR)/typescript/src/scanner.c $(wildcard $(TREE_SITTER_TYPESCRIPT_DIR)/typescript/src/tree_sitter/*.h)
	mkdir -p $(SYNTAX_VENDOR_BUILD_DIR)
	$(CC) -O3 -std=c11 -Wall -Wextra -fPIC -fvisibility=hidden -I$(TREE_SITTER_TYPESCRIPT_DIR)/typescript/src -c $(TREE_SITTER_TYPESCRIPT_DIR)/typescript/src/scanner.c -o $@

$(TREE_SITTER_TSX_PARSER_OBJECT): $(TREE_SITTER_TYPESCRIPT_DIR)/SHA256SUMS $(TREE_SITTER_TYPESCRIPT_DIR)/tsx/src/parser.c $(wildcard $(TREE_SITTER_TYPESCRIPT_DIR)/tsx/src/tree_sitter/*.h)
	mkdir -p $(SYNTAX_VENDOR_BUILD_DIR)
	$(CC) -O3 -std=c11 -fPIC -fvisibility=hidden -I$(TREE_SITTER_TYPESCRIPT_DIR)/tsx/src -c $(TREE_SITTER_TYPESCRIPT_DIR)/tsx/src/parser.c -o $@

$(TREE_SITTER_TSX_SCANNER_OBJECT): $(TREE_SITTER_TYPESCRIPT_DIR)/SHA256SUMS $(TREE_SITTER_TYPESCRIPT_DIR)/tsx/src/scanner.c $(wildcard $(TREE_SITTER_TYPESCRIPT_DIR)/tsx/src/tree_sitter/*.h)
	mkdir -p $(SYNTAX_VENDOR_BUILD_DIR)
	$(CC) -O3 -std=c11 -Wall -Wextra -fPIC -fvisibility=hidden -I$(TREE_SITTER_TYPESCRIPT_DIR)/tsx/src -c $(TREE_SITTER_TYPESCRIPT_DIR)/tsx/src/scanner.c -o $@

$(TREE_SITTER_HTML_PARSER_OBJECT): $(TREE_SITTER_HTML_DIR)/SHA256SUMS $(TREE_SITTER_HTML_DIR)/src/parser.c $(wildcard $(TREE_SITTER_HTML_DIR)/src/tree_sitter/*.h)
	mkdir -p $(SYNTAX_VENDOR_BUILD_DIR)
	$(CC) -O3 -std=c11 -fPIC -fvisibility=hidden -I$(TREE_SITTER_HTML_DIR)/src -c $(TREE_SITTER_HTML_DIR)/src/parser.c -o $@

$(TREE_SITTER_HTML_SCANNER_OBJECT): $(TREE_SITTER_HTML_DIR)/SHA256SUMS $(TREE_SITTER_HTML_DIR)/src/scanner.c $(wildcard $(TREE_SITTER_HTML_DIR)/src/tree_sitter/*.h)
	mkdir -p $(SYNTAX_VENDOR_BUILD_DIR)
	$(CC) -O3 -std=c11 -Wall -Wextra -fPIC -fvisibility=hidden -I$(TREE_SITTER_HTML_DIR)/src -c $(TREE_SITTER_HTML_DIR)/src/scanner.c -o $@

$(TREE_SITTER_CSS_PARSER_OBJECT): $(TREE_SITTER_CSS_DIR)/SHA256SUMS $(TREE_SITTER_CSS_DIR)/src/parser.c $(wildcard $(TREE_SITTER_CSS_DIR)/src/tree_sitter/*.h)
	mkdir -p $(SYNTAX_VENDOR_BUILD_DIR)
	$(CC) -O3 -std=c11 -fPIC -fvisibility=hidden -I$(TREE_SITTER_CSS_DIR)/src -c $(TREE_SITTER_CSS_DIR)/src/parser.c -o $@

$(TREE_SITTER_CSS_SCANNER_OBJECT): $(TREE_SITTER_CSS_DIR)/SHA256SUMS $(TREE_SITTER_CSS_DIR)/src/scanner.c $(wildcard $(TREE_SITTER_CSS_DIR)/src/tree_sitter/*.h)
	mkdir -p $(SYNTAX_VENDOR_BUILD_DIR)
	$(CC) -O3 -std=c11 -Wall -Wextra -fPIC -fvisibility=hidden -I$(TREE_SITTER_CSS_DIR)/src -c $(TREE_SITTER_CSS_DIR)/src/scanner.c -o $@

$(TREE_SITTER_MEMORY_OBJECT): src/language/tree_sitter_memory.c $(TREE_SITTER_DIR)/lib/include/tree_sitter/api.h
	mkdir -p $(SYNTAX_VENDOR_BUILD_DIR)
	$(CC) -O3 -std=c11 -Wall -Wextra -Werror -fPIC \
		-I$(TREE_SITTER_DIR)/lib/include \
		-c src/language/tree_sitter_memory.c -o $@

$(TREE_SITTER_ODIN_LIBRARY): $(TREE_SITTER_OBJECT) $(TREE_SITTER_ODIN_PARSER_OBJECT) $(TREE_SITTER_ODIN_SCANNER_OBJECT) $(TREE_SITTER_JAN_PARSER_OBJECT) $(TREE_SITTER_JAN_SCANNER_OBJECT) $(TREE_SITTER_RACKET_PARSER_OBJECT) $(TREE_SITTER_RACKET_SCANNER_OBJECT) $(TREE_SITTER_GO_PARSER_OBJECT) $(TREE_SITTER_RUST_PARSER_OBJECT) $(TREE_SITTER_RUST_SCANNER_OBJECT) $(TREE_SITTER_JAVASCRIPT_PARSER_OBJECT) $(TREE_SITTER_JAVASCRIPT_SCANNER_OBJECT) $(TREE_SITTER_TYPESCRIPT_PARSER_OBJECT) $(TREE_SITTER_TYPESCRIPT_SCANNER_OBJECT) $(TREE_SITTER_TSX_PARSER_OBJECT) $(TREE_SITTER_TSX_SCANNER_OBJECT) $(TREE_SITTER_HTML_PARSER_OBJECT) $(TREE_SITTER_HTML_SCANNER_OBJECT) $(TREE_SITTER_CSS_PARSER_OBJECT) $(TREE_SITTER_CSS_SCANNER_OBJECT) $(TREE_SITTER_MEMORY_OBJECT)
	$(AR) rcs $@ $^

$(TREE_SITTER_JAN_LIBRARY): $(TREE_SITTER_JAN_PARSER_OBJECT) $(TREE_SITTER_JAN_SCANNER_OBJECT)
	$(AR) rcs $@ $^

$(SYNTAX_VENDOR_PROBE): tests/syntax_vendor_probe/main.c $(TREE_SITTER_ODIN_LIBRARY)
	$(CC) -std=c11 -Wall -Wextra -Werror \
		-I$(TREE_SITTER_DIR)/lib/include \
		-I$(TREE_SITTER_ODIN_DIR)/bindings/c \
		tests/syntax_vendor_probe/main.c $(TREE_SITTER_ODIN_LIBRARY) -o $@

syntax-vendor-build: $(SYNTAX_VENDOR_PROBE)
	$(SYNTAX_VENDOR_PROBE)

jan-parser-provenance-check:
	bash scripts/check-jan-parser-provenance.sh

$(JAN_PARSER_PROBE): tests/jan_parser_probe/main.c $(TREE_SITTER_JAN_LIBRARY) $(TREE_SITTER_ODIN_LIBRARY)
	$(CC) -std=c11 -Wall -Wextra -Werror \
		-I$(TREE_SITTER_DIR)/lib/include \
		-I$(TREE_SITTER_JAN_DIR)/bindings/c \
		tests/jan_parser_probe/main.c \
		$(TREE_SITTER_JAN_LIBRARY) $(TREE_SITTER_ODIN_LIBRARY) -o $@

jan-parser-boundary-test: jan-parser-provenance-check $(JAN_PARSER_PROBE)
	$(JAN_PARSER_PROBE)

jan-document-language-resource-study:
	$(RACKET) tests/jan_document_language/resource-study.rkt

jan-document-language-focused-test: jan-parser-boundary-test $(SYNTAX_PROVIDER_FIXTURE_LIBRARY) $(SYNTAX_PROVIDER_FIXTURE_LINK)
	$(RACKET_TEST) tests/jan_document_language/reference-model-test.rkt
	$(RACKET_TEST) tests/jan_document_language/structural-corpus-test.rkt
	$(RACKET_TEST) tests/jan_document_language/inline-corpus-test.rkt
	$(RACKET_TEST) tests/jan_document_language/preservation-test.rkt
	$(RACKET) tests/jan_document_language/resource-study.rkt
	$(RACKET) scripts/check-jan-document-language.rkt
	$(ODIN) check src/language $(ODIN_VET_FLAGS)
	$(ODIN) test src/language -vet -warnings-as-errors \
		-define:ODRA_TREE_SITTER_LIBRARY="../../$(TREE_SITTER_ODIN_LIBRARY)" \
		-define:ODRA_SYNTAX_PROVIDER_FIXTURE="$(abspath $(SYNTAX_PROVIDER_FIXTURE_LIBRARY))" \
		-define:ODRA_SYNTAX_PROVIDER_FIXTURE_LINK="$(abspath $(SYNTAX_PROVIDER_FIXTURE_LINK))" \
		-define:ODRA_SYNTAX_PROVIDER_QUERY="$(abspath $(TREE_SITTER_ODIN_DIR)/queries/highlights.scm)" \
		-define:ODRA_SYNTAX_PROVIDER_MALFORMED_QUERY="$(abspath tests/syntax_provider_fixture/malformed.scm)" \
		-define:ODRA_EXTERNAL_BUNDLE_GRAMMAR="$(abspath $(SYNTAX_PROVIDER_FIXTURE_LIBRARY))" \
		-define:ODRA_EXTERNAL_BUNDLE_QUERY="$(abspath tests/language_bundle_fixture/queries/highlights.scm)"

jan-document-language-acceptance: $(ODRA)
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/jan_document_language/acceptance_test.rkt

jan-structured-editing-resource-study:
	$(RACKET) tests/jan_structured_editing/resource-study.rkt

jan-structured-editing-model-test:
	$(RACKET_TEST) src/command/jan.rkt
	$(RACKET_TEST) tests/jan_structured_editing/reference-model-test.rkt
	$(MAKE) jan-structured-editing-resource-study

jan-structured-editing-focused-test: jan-structured-editing-model-test
	$(ODIN) test src/view -vet -warnings-as-errors
	$(ODIN) test src/jan_editing -vet -warnings-as-errors

jan-planning-resource-study:
	$(RACKET) tests/jan_planning/resource-study.rkt

jan-planning-model-test:
	$(RACKET_TEST) tests/jan_planning/reference-model-test.rkt
	$(RACKET_TEST) src/jan_planning/configuration-test.rkt
	$(MAKE) jan-planning-resource-study

jan-planning-focused-test: jan-planning-model-test
	$(ODIN) test src/jan_planning -o:none -vet -warnings-as-errors

jan-computation-resource-study:
	$(RACKET) tests/jan_computation/resource-study.rkt

jan-computation-model-test:
	$(RACKET_TEST) tests/jan_computation/reference-model-test.rkt
	$(RACKET_TEST) src/jan_computation/configuration-test.rkt
	$(MAKE) jan-computation-resource-study

jan-computation-focused-test: jan-computation-model-test
	$(ODIN) test src/jan_computation -o:none -vet -warnings-as-errors

jan-output-resource-study:
	$(RACKET) tests/jan_output/resource-study.rkt

jan-output-model-test:
	$(RACKET_TEST) tests/jan_output/reference-model-test.rkt
	$(RACKET_TEST) src/jan_output/configuration-test.rkt
	$(MAKE) jan-output-resource-study

jan-output-focused-test: jan-output-model-test
	$(ODIN) test src/jan_output -o:none -vet -warnings-as-errors

jan-structured-editing-acceptance: $(ODRA)
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/jan_structured_editing/acceptance_test.rkt

jan-product-acceptance: $(ODRA)
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/jan_product/acceptance_test.rkt

language-catalog-resource-study:
	$(RACKET) tests/language_catalog_reference/resource-study.rkt

package-catalog-resource-study:
	$(RACKET) tests/package_catalog_reference/resource-study.rkt

package-catalog-model-test:
	$(RACKET_TEST) tests/package_catalog_reference/model-test.rkt
	$(MAKE) package-catalog-resource-study

package-catalog-identity-test:
	$(RACKET_TEST) tests/configuration/package_catalog_contracts_test.rkt
	$(RACKET_TEST) tests/configuration/package_catalog_integrity_test.rkt
	$(RACKET_TEST) tests/configuration/package_catalog_identity_failure_test.rkt

package-catalog-state-test:
	$(RACKET_TEST) tests/package_catalog_state_reference/model-test.rkt
	$(RACKET_TEST) tests/configuration/package_catalog_state_records_test.rkt
	$(RACKET_TEST) tests/configuration/package_catalog_state_persistence_test.rkt
	$(RACKET_TEST) tests/configuration/package_catalog_state_recovery_test.rkt

package-catalog-snapshot-resource-study:
	$(RACKET) tests/package_catalog_snapshot_reference/resource-study.rkt

package-catalog-snapshot-test:
	$(RACKET_TEST) tests/package_catalog_snapshot_reference/model-test.rkt
	$(MAKE) package-catalog-snapshot-resource-study
	$(RACKET_TEST) tests/configuration/package_catalog_snapshot_records_test.rkt
	$(RACKET_TEST) tests/configuration/package_catalog_snapshot_verification_test.rkt
	$(RACKET_TEST) tests/configuration/package_catalog_snapshot_reconciliation_test.rkt
	$(RACKET_TEST) tests/configuration/package_catalog_snapshot_failure_test.rkt

package-curation-assertion-test:
	$(RACKET_TEST) tests/configuration/package_curation_assertion_test.rkt
	$(RACKET_TEST) tests/configuration/package_curation_history_test.rkt

package-catalog-resolution-test:
	$(RACKET_TEST) tests/configuration/package_catalog_resolution_test.rkt

package-manual-acquisition-test:
	$(RACKET_TEST) tests/configuration/package_manual_provenance_test.rkt
	$(RACKET_TEST) tests/configuration/package_manual_resolution_test.rkt
	$(RACKET_TEST) tests/configuration/package_manual_acquisition_failure_test.rkt

package-curation-assessment-test:
	$(RACKET_TEST) tests/configuration/package_curation_submission_test.rkt
	$(RACKET_TEST) tests/configuration/package_curation_change_classification_test.rkt
	$(RACKET_TEST) tests/configuration/package_curation_assessment_ingestion_test.rkt
	$(RACKET_TEST) tests/configuration/package_curation_assessment_failure_test.rkt

package-curation-resource-study:
	$(RACKET) tests/package_curation_assessment_reference/resource-study.rkt

package-curation-decision-test:
	$(RACKET_TEST) tests/configuration/package_curation_decision_test.rkt
	$(RACKET_TEST) tests/configuration/package_curation_authorization_test.rkt

package-catalog-publication-test:
	$(RACKET_TEST) tests/configuration/package_catalog_publication_test.rkt
	$(RACKET_TEST) tests/configuration/package_catalog_publisher_cli_test.rkt

package-catalog-advisory-test:
	$(RACKET_TEST) tests/configuration/package_catalog_advisory_records_test.rkt
	$(RACKET_TEST) tests/configuration/package_catalog_advisory_verification_test.rkt
	$(RACKET_TEST) tests/configuration/package_catalog_advisory_response_test.rkt
	$(RACKET_TEST) tests/configuration/language_bundle_advisory_lifecycle_test.rkt

package-private-transport-test:
	$(RACKET_TEST) tests/configuration/package_private_https_test.rkt

package-catalog-transport-test: package-private-transport-test
	$(RACKET_TEST) tests/configuration/package_catalog_transport_test.rkt

package-catalog-federation-test:
	$(RACKET_TEST) tests/configuration/package_catalog_refresh_test.rkt
	$(RACKET_TEST) tests/configuration/package_catalog_federated_resolution_test.rkt

package-catalog-config-test:
	$(RACKET_TEST) src/command/package-catalogs.rkt \
		src/configuration/personal.rkt \
		tests/configuration/package_catalog_config_test.rkt

package-catalog-bootstrap-test:
	$(RACKET_TEST) src/package_catalog/official-bootstrap.rkt \
		tests/configuration/package_catalog_official_bootstrap_test.rkt

package-catalog-curator-kit-test:
	$(RACKET_TEST) tests/configuration/package_catalog_curator_kit_test.rkt \
		scripts/package-catalog-curator-support.rkt \
		scripts/package-catalog-curator.rkt \
		tests/configuration/package_catalog_curator_workflow_test.rkt

package-catalog-conformance-test:
	$(RACKET_TEST) scripts/check-package-catalog-conformance.rkt
	$(RACKET) scripts/check-package-catalog-conformance.rkt \
		--fixture tests/package_catalog_conformance/fixture.rkt

privacy-check:
	$(RACKET) scripts/check-package-catalog-privacy.rkt

package-catalog-interaction-test: $(RUNTIME_TEST_ADAPTER_LIBRARY) $(TREE_SITTER_ODIN_LIBRARY)
	$(RACKET_TEST) src/command/keymaps.rkt
	$(ODIN) test src/package_catalog_interaction -vet -warnings-as-errors
	$(ODIN) test src/command -vet -warnings-as-errors \
		-define:ODIN_TEST_NAMES=command.package_catalog_operations_have_stable_semantic_commands \
		-define:ODRA_RACKET_RUNTIME_LIBRARY="../../$(RUNTIME_TEST_ADAPTER_LIBRARY)" \
		-define:ODRA_TREE_SITTER_LIBRARY="../../$(TREE_SITTER_ODIN_LIBRARY)" \
		-extra-linker-flags:"$(RACKET_CS_LIBRARY) $(RACKET_CS_LINK_LIBS)"

package-catalog-runtime-test: $(RUNTIME_TEST_ADAPTER_LIBRARY)
	$(RACKET_TEST) src/package_catalog/publication-metadata.rkt \
		tests/package_catalog_runtime_fixture.rkt \
		tests/configuration/package_catalog_runtime_test.rkt
	$(RACKET_TEST) src/hosting/personal-configuration-bridge.rkt \
		src/hosting/package-catalog-bridge.rkt \
		src/hosting/runtime-boundary.rkt
	$(RACKET) tests/package_catalog_runtime_fixture.rkt \
		.build/package-catalog-runtime-fixture
	for scenario in 1 2; do \
		$(ODIN) test src/hosting -vet -warnings-as-errors \
			-define:ODIN_TEST_NAMES=hosting.package_catalog_runtime_boundary_persists_confirmed_state \
			-define:ODRA_PACKAGE_CATALOG_RUNTIME_TEST_SCENARIO=$$scenario \
			-define:ODRA_RACKET_RUNTIME_LIBRARY="../../$(RUNTIME_TEST_ADAPTER_LIBRARY)" \
			-extra-linker-flags:"$(RACKET_CS_LIBRARY) $(RACKET_CS_LINK_LIBS)" || exit 1; \
	done
	$(ODIN) check src/command -no-entry-point -vet -warnings-as-errors

package-catalog-acceptance:
	$(PACKAGE_CATALOG_ACCEPTANCE_RUNNER) --prepare
	$(call run_package_catalog_acceptance_step,application-build,$(MAKE) odra)
	$(call run_package_catalog_acceptance_step,identity-and-bounds,$(MAKE) package-catalog-model-test package-catalog-identity-test)
	$(call run_package_catalog_acceptance_step,durable-state-and-snapshots,$(MAKE) package-catalog-state-test package-catalog-snapshot-test)
	$(call run_package_catalog_acceptance_step,curation-and-manual,$(MAKE) package-curation-assertion-test package-manual-acquisition-test package-curation-assessment-test package-curation-decision-test package-catalog-publication-test)
	$(call run_package_catalog_acceptance_step,advisories-and-federation,$(MAKE) package-catalog-advisory-test package-catalog-transport-test package-catalog-federation-test package-catalog-resolution-test)
	$(call run_package_catalog_acceptance_step,bootstrap-and-conformance,$(MAKE) package-catalog-bootstrap-test package-catalog-curator-kit-test package-catalog-conformance-test privacy-check)
	$(call run_package_catalog_acceptance_step,external-language-bundle,$(MAKE) language-bundle-catalog-test language-bundle-acquisition-test language-bundle-lifecycle-test)
	$(call run_package_catalog_acceptance_step,interaction,$(MAKE) package-catalog-config-test package-catalog-interaction-test)
	$(PACKAGE_CATALOG_ACCEPTANCE_RUNNER) --complete

package-catalog-acceptance-reset:
	$(PACKAGE_CATALOG_ACCEPTANCE_RUNNER) --reset

package-model-test:
	$(RACKET_TEST) tests/package_reference/model-test.rkt

agent-substrate-focused-test:
	$(RACKET_TEST) tests/agent_substrate/definition_test.rkt
	$(RACKET_TEST) tests/agent_substrate/registry_test.rkt
	$(RACKET_TEST) tests/agent_substrate/authority_test.rkt
	$(RACKET_TEST) tests/agent_substrate/continuity_test.rkt
	$(RACKET_TEST) tests/agent_substrate/admission_test.rkt
	$(RACKET_TEST) tests/agent_substrate/driver_test.rkt
	$(RACKET_TEST) tests/agent_substrate/execution_test.rkt
	$(RACKET_TEST) tests/agent_substrate/rot13_canary_test.rkt
	$(MAKE) agent-substrate-recovery-acceptance
	$(RACKET_TEST) tests/agent_substrate/interaction_test.rkt
	$(MAKE) agent-substrate-conformance-test
	$(MAKE) agent-substrate-resource-study
	$(RACKET_TEST) tests/configuration/package_manifest_contracts_test.rkt
	$(RACKET_TEST) tests/configuration/package_runtime_test.rkt

agent-substrate-resource-study:
	$(RACKET) tests/agent_substrate/resource_study.rkt
	$(RACKET) tests/agent_substrate/authority_resource_study.rkt
	$(RACKET) tests/agent_substrate/continuity_resource_study.rkt
	$(RACKET) tests/agent_substrate/operational_resource_study.rkt

agent-substrate-conformance-test:
	$(RACKET_TEST) scripts/check-agent-substrate-conformance.rkt
	$(RACKET) scripts/check-agent-substrate-conformance.rkt \
		--fixture tests/agent_substrate/conformance_fixture.rkt

agent-substrate-recovery-acceptance:
	$(RACKET_TEST) tests/agent_substrate/recovery_test.rkt

agent-substrate-closure-check:
	$(MAKE) agent-substrate-focused-test
	$(MAKE) package-canary-focused-test
	$(MAKE) package-canary-linked-acceptance
	$(MAKE) user-guide-check
	$(MAKE) user-guide-acceptance-check
	$(MAKE) user-guide-usability-check
	$(RACKET) scripts/check-markdown-links.rkt docs ops

package-authority-contract-test:
	$(RACKET_TEST) src/package/authority-contract.rkt \
		scripts/check-package-authority-parity.rkt
	$(RACKET) scripts/check-package-authority-parity.rkt

package-focused-test: package-authority-contract-test package-model-test package-private-transport-test
	$(RACKET_TEST) tests/configuration/package_manifest_contracts_test.rkt
	$(RACKET_TEST) tests/configuration/package_credential_provider_test.rkt
	$(RACKET_TEST) tests/configuration/package_resolution_test.rkt
	$(RACKET_TEST) tests/configuration/package_acquisition_test.rkt
	$(RACKET_TEST) tests/configuration/package_acquisition_failure_test.rkt
	$(RACKET_TEST) tests/configuration/package_installation_test.rkt
	$(RACKET_TEST) tests/configuration/package_lifecycle_test.rkt
	$(RACKET_TEST) tests/configuration/package_distribution_test.rkt
	$(RACKET_TEST) tests/configuration/package_runtime_test.rkt
	$(RACKET_TEST) tests/configuration/package_state_records_test.rkt
	$(RACKET_TEST) tests/configuration/package_state_persistence_test.rkt

package-canary-focused-test:
	$(RACKET_TEST) tests/agent_substrate/rot13_canary_test.rkt
	$(RACKET_TEST) tests/configuration/package_runtime_test.rkt

package-canary-linked-acceptance:
	@test -x $(ODRA_DEVELOPMENT) || { \
		echo 'Development executable is missing; run make development-build.' >&2; \
		exit 1; \
	}
	ODRA_PTY_EXECUTABLE=$(abspath scripts/run-development-editor.sh) \
		$(PTY_RACKET_TEST) tests/package_canary/linked_acceptance_test.rkt

roman-linked-acceptance:
	@test -x $(ODRA_DEVELOPMENT) || { \
		echo 'Development executable is missing; run make development-build.' >&2; \
		exit 1; \
	}
	@test -f "$$ROMAN_PACKAGE_MANIFEST" || { \
		echo 'ROMAN_PACKAGE_MANIFEST must identify the built Roman manifest.' >&2; \
		exit 1; \
	}
	@test -f "$$ROMAN_PACKAGE_ARCHIVE" || { \
		echo 'ROMAN_PACKAGE_ARCHIVE must identify the built Roman archive.' >&2; \
		exit 1; \
	}
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA_DEVELOPMENT)) \
		$(PTY_RACKET_TEST) tests/roman/linked_acceptance_test.rkt

language-bundle-model-test:
	$(RACKET_TEST) tests/language_bundle_reference/model-test.rkt

language-bundle-authoring-test:
	$(RACKET_TEST) src/command/language-bundles.rkt \
		src/hosting/language-bundle-bridge.rkt \
		tests/configuration/language_bundle_test.rkt
	$(ODIN) test src/language_bundle -vet -warnings-as-errors

language-bundle-state-test:
	$(RACKET_TEST) tests/language_bundle_state_reference/model-test.rkt
	$(RACKET_TEST) tests/configuration/language_bundle_state_records_test.rkt
	$(RACKET_TEST) tests/configuration/language_bundle_state_persistence_test.rkt
	$(RACKET_TEST) tests/configuration/language_bundle_state_recovery_test.rkt

language-bundle-catalog-test:
	$(RACKET_TEST) tests/configuration/language_bundle_catalog_contracts_test.rkt
	$(RACKET_TEST) tests/configuration/language_bundle_catalog_resolution_test.rkt
	$(RACKET_TEST) tests/configuration/language_bundle_catalog_integrity_test.rkt
	$(RACKET_TEST) tests/configuration/language_bundle_package_catalog_adapter_test.rkt

language-bundle-acquisition-test:
	$(RACKET_TEST) tests/configuration/language_bundle_acquisition_test.rkt
	$(RACKET_TEST) tests/configuration/language_bundle_acquisition_failure_test.rkt
	$(RACKET_TEST) tests/configuration/language_bundle_manual_package_adapter_test.rkt

language-bundle-lifecycle-test:
	$(RACKET_TEST) tests/configuration/language_bundle_activation_candidate_test.rkt
	$(RACKET_TEST) tests/configuration/language_bundle_activation_runtime_test.rkt
	$(RACKET_TEST) tests/configuration/language_bundle_lifecycle_test.rkt
	$(RACKET_TEST) tests/configuration/language_bundle_lifecycle_failure_test.rkt

language-bundle-inspection-test:
	$(RACKET_TEST) src/language_bundle/inspection.rkt \
		src/command/language-interactions.rkt

factory-language-bundle-test: $(TREE_SITTER_ODIN_LIBRARY)
	$(RACKET_TEST) src/language_bundle/factory-bundles.rkt \
		tests/configuration/factory_language_bundle_test.rkt
	tree-sitter query --grammar-path $(TREE_SITTER_JAN_DIR) \
		assets/language-bundles/factory/jan/highlights.scm \
		tests/jan_document_language/fixtures/structural-probe.org --quiet
	$(ODIN) test src/language -vet -warnings-as-errors \
		-define:ODRA_TREE_SITTER_LIBRARY="../../$(TREE_SITTER_ODIN_LIBRARY)" \
		-define:ODIN_TEST_NAMES=language.factory_odin_registration_remains_unchanged,language.factory_jan_suffixes_share_one_registration,language.factory_jan_explicit_selection_is_bounded,language.factory_catalog_confirms_maintained_language_identities,language.factory_bundle_grammar_resolution_is_stable

racket-go-syntax-test: $(TREE_SITTER_ODIN_LIBRARY)
	bash scripts/check-syntax-vendor.sh
	$(RACKET_TEST) src/language_bundle/factory-bundles.rkt \
		tests/configuration/factory_language_bundle_test.rkt
	$(ODIN) test src/language -vet -warnings-as-errors \
		-define:ODRA_TREE_SITTER_LIBRARY="../../$(TREE_SITTER_ODIN_LIBRARY)" \
		-define:ODIN_TEST_NAMES=language.factory_catalog_confirms_maintained_language_identities,language.factory_bundle_grammar_resolution_is_stable,language.factory_maintained_queries_compile,language.factory_maintained_queries_publish_spans
	$(ODIN) test src/syntax_workflow -vet -warnings-as-errors \
		-define:ODRA_TREE_SITTER_LIBRARY="../../$(TREE_SITTER_ODIN_LIBRARY)" \
		-define:ODIN_TEST_NAMES=syntax_workflow.catalog_opens_factory_syntax_providers,syntax_workflow.syntax_owner_spans_views_and_buffer,syntax_workflow.syntax_workflow_advances_analysis_on_commit
	$(ODIN) test src/language_support -vet -warnings-as-errors \
		-define:ODIN_TEST_NAMES=language_support.factory_support_source_normalizes,language_support.runtime_catalog_abandonment_rolls_back_definitions,language_support.runtime_catalog_publication_reuses_unchanged_profiles
	$(ODIN) test src/language_service -vet -warnings-as-errors \
		-define:ODIN_TEST_NAMES=language_service.provider_registry_revalidates_executable_availability,language_service.failed_replacement_preserves_selection

rust-language-support-test: $(TREE_SITTER_ODIN_LIBRARY)
	bash scripts/check-syntax-vendor.sh
	$(RACKET_TEST) src/language_bundle/factory-bundles.rkt \
		src/command/language-interactions.rkt \
		tests/configuration/factory_language_bundle_test.rkt \
		tests/rust_language_service/interaction_test.rkt
	$(ODIN) test src/language -vet -warnings-as-errors \
		-define:ODRA_TREE_SITTER_LIBRARY="../../$(TREE_SITTER_ODIN_LIBRARY)" \
		-define:ODIN_TEST_NAMES=language.factory_catalog_confirms_maintained_language_identities,language.factory_bundle_grammar_resolution_is_stable,language.factory_maintained_queries_compile,language.factory_maintained_queries_publish_spans,language.factory_rust_incremental_corpus_matches_full_parse,language.factory_rust_large_source_is_bounded
	$(ODIN) test src/syntax_workflow -vet -warnings-as-errors \
		-define:ODRA_TREE_SITTER_LIBRARY="../../$(TREE_SITTER_ODIN_LIBRARY)" \
		-define:ODIN_TEST_NAMES=syntax_workflow.catalog_opens_factory_syntax_providers
	$(ODIN) test src/language_support -vet -warnings-as-errors \
		-define:ODIN_TEST_NAMES=language_support.factory_support_source_normalizes,language_support.runtime_catalog_abandonment_rolls_back_definitions,language_support.runtime_catalog_publication_reuses_unchanged_profiles
	$(ODIN) test src/language_service -vet -warnings-as-errors \
		-define:ODIN_TEST_NAMES=language_service.factory_rust_analyzer_profile_is_pinned,language_service.factory_rust_analyzer_selects_nearest_cargo_root,language_service.provider_registry_revalidates_executable_availability,language_service.failed_replacement_preserves_selection,language_service.restores_factory_and_cleans_all_allocations,language_service.workspace_edit_commits_and_undoes_versioned_multibuffer_change,language_service.workspace_edit_rejects_invalid_text_and_membership_as_a_whole,language_service.workspace_edit_applies_checked_file_operations,language_service.workspace_edit_rolls_back_partial_filesystem_publication,language_service.workspace_edit_allocation_failure_publishes_nothing

language-catalog-model-test:
	$(RACKET_TEST) tests/language_catalog_reference/model-test.rkt
	$(RACKET) tests/language_catalog_reference/resource-study.rkt

language-catalog-test: language-catalog-model-test
	$(ODIN) test src/language -vet -warnings-as-errors \
		-define:ODIN_TEST_NAMES=language.language_catalog_confirms_multiple_definitions,language.language_catalog_rejection_preserves_confirmed_generation,language.language_catalog_resolution_matches_reference_cases,language.language_catalog_rejects_duplicate_and_ambiguous_selectors,language.language_catalog_identity_assignment_is_order_independent,language.language_catalog_allocation_and_cleanup_are_exact

language-service-catalog-model-test:
	$(RACKET_TEST) tests/language_service_catalog_reference/model-test.rkt

language-service-catalog-test: language-service-catalog-model-test
	$(ODIN) test src/language_service -vet -warnings-as-errors \
		-define:ODIN_TEST_NAMES=language_service.factory_ols_uses_the_generic_registry_path,language_service.service_catalog_records_keep_resolution_authority_explicit,language_service.service_catalog_trace_preserves_selection_outcome,language_service.service_catalog_resolves_explicit_selections_by_authority,language_service.service_catalog_preserves_fallback_across_package_conflicts,language_service.service_catalog_restores_factory_for_one_language_scope,language_service.service_catalog_rejects_duplicate_identity_atomically,language_service.service_catalog_resolution_is_order_independent,language_service.service_catalog_rejected_generations_preserve_confirmed_state,language_service.service_catalog_disable_and_restore_are_scope_local,language_service.service_catalog_allocation_and_cleanup_are_exact

language-service-profile-test:
	$(ODIN) test src/language_service -vet -warnings-as-errors \
		-define:ODIN_TEST_NAMES=language_service.effective_profile_separates_requested_and_active_features,language_service.effective_profile_activates_negotiated_completion,language_service.effective_profile_builds_configuration_notification,language_service.factory_ols_uses_the_generic_registry_path
	$(ODIN) test src/language_support -vet -warnings-as-errors \
		-define:ODIN_TEST_NAMES=language_support.factory_support_source_normalizes

language-service-reconciliation-test:
	$(ODIN) test src/language_service -vet -warnings-as-errors \
		-define:ODIN_TEST_NAMES=language_service.service_root_resolution_selects_nearest_marker,language_service.service_root_resolution_enforces_containment_and_fallback,language_service.service_root_resolution_rejects_invalid_markers,language_service.executable_resolution_uses_controlled_precedence,language_service.provider_registry_revalidates_executable_availability,language_service.executable_policy_rejects_relative_paths_and_redacts_environment,language_service.fixture_replaces_factory_atomically,language_service.failed_replacement_preserves_selection,language_service.synchronizer_releases_owned_storage
	$(ODIN) test src/language_support -vet -warnings-as-errors \
		-define:ODIN_TEST_NAMES=language_support.runtime_catalog_abandonment_rolls_back_definitions,language_support.runtime_catalog_publication_reuses_unchanged_profiles

language-support-config-test:
	$(RACKET_TEST) src/command/languages.rkt \
		src/hosting/language-support-configuration-bridge.rkt \
		src/configuration/personal.rkt \
		src/hosting/personal-configuration-bridge.rkt \
		tests/configuration/language_support_test.rkt
	$(ODIN) test src/language_support -vet -warnings-as-errors

language-interaction-profile-test:
	$(RACKET_TEST) src/command/language-interactions.rkt \
		src/command/builtins.rkt \
		src/command/keymaps.rkt \
		src/hosting/keymap-profile-bridge.rkt

language-interaction-test:
	$(ODIN) test src/language_interaction -vet -warnings-as-errors

language-intelligence-query-test:
	$(ODIN) test src/language_service -vet -warnings-as-errors \
		-define:ODIN_TEST_NAMES=language_service.intelligence_capabilities_gate_all_query_families,language_service.intelligence_normalizes_hover_locations_and_external_uris,language_service.intelligence_normalizes_symbols_and_signatures,language_service.intelligence_semantic_tokens_apply_delta_and_reject_overlap,language_service.intelligence_contains_adversarial_lifecycle_and_results,language_service.intelligence_allocation_fault_and_cleanup_are_exact

language-formatter-test:
	mkdir -p $(BUILD_DIR)
	$(ODIN) test src/language_formatter -vet -warnings-as-errors \
		-define:ODIN_TEST_NAMES=language_formatter.catalog_resolves_project_selection_only_inside_trusted_membership,language_formatter.catalog_publication_is_copied_and_atomic,language_formatter.catalog_confirms_only_exact_executable_version,language_formatter.formatting_lsp_result_commits_one_revisioned_transaction,language_formatter.formatting_rejects_malformed_overlapping_and_stale_results,language_formatter.formatting_allocation_failure_and_cleanup_are_exact,language_formatter.external_formatter_execution_is_bounded_and_cleans_up \
		-out:$(BUILD_DIR)/language-formatter-test

language-workspace-edit-test:
	mkdir -p $(BUILD_DIR)
	$(ODIN) test src/language_service -vet -warnings-as-errors \
		-define:ODIN_TEST_NAMES=language_service.workspace_edit_commits_and_undoes_versioned_multibuffer_change,language_service.workspace_edit_rejects_invalid_text_and_membership_as_a_whole,language_service.workspace_edit_applies_checked_file_operations,language_service.workspace_edit_rolls_back_partial_filesystem_publication,language_service.workspace_edit_allocation_failure_publishes_nothing \
		-out:$(BUILD_DIR)/language-workspace-edit-test

syntax-provider-contract-test: $(TREE_SITTER_ODIN_LIBRARY)
	$(ODIN) test src/language -vet -warnings-as-errors \
		-define:ODRA_TREE_SITTER_LIBRARY="../../$(TREE_SITTER_ODIN_LIBRARY)" \
		-define:ODIN_TEST_NAMES=language.syntax_provider_contract_copies_bounded_manifest_data,language.syntax_provider_contract_rejects_unsafe_and_ambiguous_inputs,language.syntax_provider_authority_requires_factory_or_complete_trust

$(SYNTAX_PROVIDER_FIXTURE_LIBRARY): $(TREE_SITTER_ODIN_DIR)/SHA256SUMS $(TREE_SITTER_ODIN_DIR)/src/parser.c $(TREE_SITTER_ODIN_DIR)/src/scanner.c $(wildcard $(TREE_SITTER_ODIN_DIR)/src/tree_sitter/*.h)
	mkdir -p $(dir $@)
	$(CC) -O2 -std=c11 -fPIC -shared -fvisibility=hidden \
		-I$(TREE_SITTER_ODIN_DIR)/src \
		$(TREE_SITTER_ODIN_DIR)/src/parser.c $(TREE_SITTER_ODIN_DIR)/src/scanner.c \
		-o $@

$(SYNTAX_PROVIDER_FIXTURE_LINK): $(SYNTAX_PROVIDER_FIXTURE_LIBRARY)
	ln -sfn $(notdir $(SYNTAX_PROVIDER_FIXTURE_LIBRARY)) $@

syntax-provider-loader-test: $(TREE_SITTER_ODIN_LIBRARY) $(SYNTAX_PROVIDER_FIXTURE_LIBRARY) $(SYNTAX_PROVIDER_FIXTURE_LINK)
	$(ODIN) test src/language -vet -warnings-as-errors \
		-define:ODRA_TREE_SITTER_LIBRARY="../../$(TREE_SITTER_ODIN_LIBRARY)" \
		-define:ODRA_SYNTAX_PROVIDER_FIXTURE="$(abspath $(SYNTAX_PROVIDER_FIXTURE_LIBRARY))" \
		-define:ODRA_SYNTAX_PROVIDER_FIXTURE_LINK="$(abspath $(SYNTAX_PROVIDER_FIXTURE_LINK))" \
		-define:ODRA_SYNTAX_PROVIDER_QUERY="$(abspath $(TREE_SITTER_ODIN_DIR)/queries/highlights.scm)" \
		-define:ODRA_SYNTAX_PROVIDER_MALFORMED_QUERY="$(abspath tests/syntax_provider_fixture/malformed.scm)" \
		-define:ODIN_TEST_NAMES=language.syntax_provider_loader_verifies_and_owns_dynamic_grammar,language.syntax_provider_loader_rejects_authority_target_integrity_symbol_and_versions,language.syntax_provider_loader_preserves_active_runtime_on_failed_replacement,language.syntax_provider_queries_compile_verified_data_and_normalize_captures,language.syntax_provider_query_failure_preserves_compiled_state,language.syntax_provider_loader_contains_missing_size_cancellation_and_allocation_failures,language.syntax_provider_queries_enforce_resource_and_cancellation_limits,language.syntax_provider_queries_publish_generic_semantics_and_structure,language.syntax_provider_reload_and_cleanup_are_exact

language-bundle-conformance-test: $(TREE_SITTER_ODIN_LIBRARY) $(SYNTAX_PROVIDER_FIXTURE_LIBRARY)
	ODRA_EXTERNAL_BUNDLE_GRAMMAR=$(abspath $(SYNTAX_PROVIDER_FIXTURE_LIBRARY)) \
		$(RACKET_TEST) tests/language_bundle_fixture/bundle.rkt \
		tests/language_bundle_fixture/conformance_test.rkt
	$(ODIN) test src/language -vet -warnings-as-errors \
		-define:ODRA_TREE_SITTER_LIBRARY="../../$(TREE_SITTER_ODIN_LIBRARY)" \
		-define:ODRA_EXTERNAL_BUNDLE_GRAMMAR="$(abspath $(SYNTAX_PROVIDER_FIXTURE_LIBRARY))" \
		-define:ODRA_EXTERNAL_BUNDLE_QUERY="$(abspath tests/language_bundle_fixture/queries/highlights.scm)" \
		-define:ODIN_TEST_NAMES=language.external_bundle_conformance_loads_uncompiled_language

language-bundle-author-kit-test: $(SYNTAX_PROVIDER_FIXTURE_LIBRARY)
	ODRA_EXTERNAL_BUNDLE_GRAMMAR=$(abspath $(SYNTAX_PROVIDER_FIXTURE_LIBRARY)) \
		$(RACKET_TEST) scripts/language-bundle-author.rkt \
		tests/language_bundle_author_kit/author_kit_test.rkt

basic-language-pack-acceptance: $(TREE_SITTER_ODIN_LIBRARY) $(SYNTAX_PROVIDER_FIXTURE_LIBRARY)
	ODRA_EXTERNAL_BUNDLE_GRAMMAR=$(abspath $(SYNTAX_PROVIDER_FIXTURE_LIBRARY)) \
		$(RACKET_TEST) tests/language_bundle_fixture/bundle.rkt \
		tests/language_bundle_fixture/conformance_test.rkt
	$(RACKET_TEST) src/language_bundle/factory-bundles.rkt \
		tests/configuration/factory_language_bundle_test.rkt
	$(ODIN) test src/language -vet -warnings-as-errors \
		-define:ODRA_TREE_SITTER_LIBRARY="../../$(TREE_SITTER_ODIN_LIBRARY)" \
		-define:ODRA_EXTERNAL_BUNDLE_GRAMMAR="$(abspath $(SYNTAX_PROVIDER_FIXTURE_LIBRARY))" \
		-define:ODRA_EXTERNAL_BUNDLE_QUERY="$(abspath tests/language_bundle_fixture/queries/highlights.scm)" \
		-define:ODIN_TEST_NAMES=language.factory_odin_registration_remains_unchanged,language.factory_jan_suffixes_share_one_registration,language.factory_jan_explicit_selection_is_bounded,language.factory_catalog_confirms_maintained_language_identities,language.factory_bundle_grammar_resolution_is_stable,language.factory_maintained_queries_compile,language.factory_maintained_queries_publish_spans,language.factory_rust_incremental_corpus_matches_full_parse,language.factory_rust_large_source_is_bounded,language.factory_web_variants_route_exact_selectors,language.factory_html_injections_select_child_languages,language.factory_web_incremental_tsx_matches_full_parse,language.factory_web_large_html_injections_are_bounded,language.external_bundle_conformance_loads_uncompiled_language

syntax-workflow-test: $(TREE_SITTER_ODIN_LIBRARY)
	$(ODIN) test src/syntax_workflow -vet -warnings-as-errors \
		-define:ODRA_TREE_SITTER_LIBRARY="../../$(TREE_SITTER_ODIN_LIBRARY)"

syntax-injection-test: $(TREE_SITTER_ODIN_LIBRARY)
	$(ODIN) test src/syntax_workflow -vet -warnings-as-errors \
		-define:ODRA_TREE_SITTER_LIBRARY="../../$(TREE_SITTER_ODIN_LIBRARY)" \
		-define:ODIN_TEST_NAMES=syntax_workflow.injections_compose_nested_regions_with_stable_precedence,syntax_workflow.injections_reject_cycles_invalid_parents_and_resource_excess,syntax_workflow.injections_incremental_invalidation_preserves_only_proven_prefix,syntax_workflow.injections_handle_empty_overlap_malformed_and_excessive_inputs,syntax_workflow.injections_honor_cancellation_without_publication,syntax_workflow.generic_workflow_copies_injections_and_invalidates_replacement

language-workflow-focused-test: $(RACKET_LANGSERVER_STAMP) $(TREE_SITTER_ODIN_LIBRARY)
	$(MAKE) syntax-workflow-test
	PLTUSERHOME=$(abspath $(RACKET_LANGSERVER_HOME)) \
		$(ODIN) test src/language_service_workflow -vet -warnings-as-errors \
		-define:ODRA_TREE_SITTER_LIBRARY="../../$(TREE_SITTER_ODIN_LIBRARY)"

$(RACKET_LANGSERVER_STAMP):
	mkdir -p $(RACKET_LANGSERVER_HOME)
	PLTUSERHOME=$(abspath $(RACKET_LANGSERVER_HOME)) \
		$(RACO) pkg install --auto --batch --scope user \
		--name racket-langserver \
		'https://github.com/jeapostrophe/racket-langserver.git#$(RACKET_LANGSERVER_CHECKSUM)'
	touch $@

racket-language-service-protocol-test: $(RACKET_LANGSERVER_STAMP)
	PLTUSERHOME=$(abspath $(RACKET_LANGSERVER_HOME)) \
		RACKET_LANGSERVER_CHECKSUM=$(RACKET_LANGSERVER_CHECKSUM) \
		$(RACKET_TEST) tests/racket_language_service/acceptance_test.rkt

maintained-language-service-pty-test: $(RACKET_LANGSERVER_STAMP) $(ODRA)
	PLTUSERHOME=$(abspath $(RACKET_LANGSERVER_HOME)) \
		ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/racket_language_service/concurrent_workflow_test.rkt

racket-language-service-acceptance: racket-language-service-protocol-test maintained-language-service-pty-test
	$(ODIN) test src/language_support -vet -warnings-as-errors
	$(ODIN) test src/language_service -vet -warnings-as-errors \
		-define:ODIN_TEST_NAMES=language_service.process_session_round_trips_frames_and_cleans_up

$(GOPLS_EXECUTABLE):
	mkdir -p $(GOPLS_BUILD_DIR)
	GOBIN=$(abspath $(GOPLS_BUILD_DIR)) \
		$(GO) install golang.org/x/tools/gopls@$(GOPLS_VERSION)

gopls-language-service-acceptance: $(GOPLS_EXECUTABLE)
	GOPLS_EXECUTABLE=$(abspath $(GOPLS_EXECUTABLE)) \
		GOPLS_VERSION=$(GOPLS_VERSION) \
		$(RACKET_TEST) tests/gopls_language_service/acceptance_test.rkt

$(RUST_ANALYZER_ARCHIVE):
	mkdir -p $(RUST_ANALYZER_BUILD_DIR)
	curl --fail --location --retry 3 \
		--output $@ \
		https://github.com/rust-lang/rust-analyzer/releases/download/$(RUST_ANALYZER_RELEASE)/rust-analyzer-x86_64-unknown-linux-gnu.gz
	printf '%s  %s\n' $(RUST_ANALYZER_SHA256) $@ | sha256sum --check --status

$(RUST_ANALYZER_EXECUTABLE): $(RUST_ANALYZER_ARCHIVE)
	gzip --decompress --stdout $(RUST_ANALYZER_ARCHIVE) > $@
	chmod 0755 $@

rust-language-service-acceptance: $(RUST_ANALYZER_EXECUTABLE)
	RUST_ANALYZER_EXECUTABLE=$(abspath $(RUST_ANALYZER_EXECUTABLE)) \
		RUST_ANALYZER_RELEASE=$(RUST_ANALYZER_RELEASE) \
		$(RACKET_TEST) tests/rust_language_service/acceptance_test.rkt

web-language-syntax-test: $(TREE_SITTER_ODIN_LIBRARY)
	bash scripts/check-syntax-vendor.sh >/dev/null
	$(RACKET_TEST) src/language_bundle/factory-bundles.rkt \
		tests/configuration/factory_language_bundle_test.rkt \
		tests/web_language_service/interaction_test.rkt
	$(ODIN) test src/language -vet -warnings-as-errors \
		-define:ODRA_TREE_SITTER_LIBRARY="../../$(TREE_SITTER_ODIN_LIBRARY)" \
		-define:ODIN_TEST_NAMES=language.factory_catalog_confirms_maintained_language_identities,language.factory_bundle_grammar_resolution_is_stable,language.factory_maintained_queries_compile,language.factory_maintained_queries_publish_spans,language.factory_web_variants_route_exact_selectors,language.factory_html_injections_select_child_languages,language.factory_web_incremental_tsx_matches_full_parse,language.factory_web_large_html_injections_are_bounded
	$(ODIN) test src/syntax_workflow -vet -warnings-as-errors \
		-define:ODRA_TREE_SITTER_LIBRARY="../../$(TREE_SITTER_ODIN_LIBRARY)" \
		-define:ODIN_TEST_NAMES=syntax_workflow.factory_web_workflow_routes_variants_and_injections,syntax_workflow.injections_handle_empty_overlap_malformed_and_excessive_inputs
	$(ODIN) test src/language_support -vet -warnings-as-errors \
		-define:ODIN_TEST_NAMES=language_support.factory_support_source_normalizes
	$(ODIN) test src/language_service -vet -warnings-as-errors \
		-define:ODIN_TEST_NAMES=language_service.factory_web_language_profiles_are_pinned,language_service.factory_typescript_language_server_selects_nearest_configured_root,language_service.provider_registry_revalidates_executable_availability,language_service.failed_replacement_preserves_selection

$(WEB_LANGUAGE_SERVERS_STAMP):
	mkdir -p $(WEB_LANGUAGE_SERVERS_DIR)
	npm install --prefix $(WEB_LANGUAGE_SERVERS_DIR) --no-audit --no-fund --no-save \
		typescript-language-server@$(TYPESCRIPT_LANGUAGE_SERVER_VERSION) \
		typescript@$(TYPESCRIPT_VERSION) \
		vscode-langservers-extracted@$(VSCODE_LANGSERVERS_VERSION)
	test -x $(TYPESCRIPT_LANGUAGE_SERVER_EXECUTABLE)
	test -x $(HTML_LANGUAGE_SERVER_EXECUTABLE)
	test -x $(CSS_LANGUAGE_SERVER_EXECUTABLE)
	touch $@

web-language-service-acceptance: $(WEB_LANGUAGE_SERVERS_STAMP)
	TYPESCRIPT_LANGUAGE_SERVER_EXECUTABLE=$(abspath $(TYPESCRIPT_LANGUAGE_SERVER_EXECUTABLE)) \
	HTML_LANGUAGE_SERVER_EXECUTABLE=$(abspath $(HTML_LANGUAGE_SERVER_EXECUTABLE)) \
	CSS_LANGUAGE_SERVER_EXECUTABLE=$(abspath $(CSS_LANGUAGE_SERVER_EXECUTABLE)) \
	VSCODE_LANGSERVERS_PACKAGE_JSON=$(abspath $(VSCODE_LANGSERVERS_PACKAGE_JSON)) \
	TYPESCRIPT_LIBRARY_PATH=$(abspath $(TYPESCRIPT_LIBRARY_PATH)) \
	TYPESCRIPT_PACKAGE_JSON=$(abspath $(TYPESCRIPT_PACKAGE_JSON)) \
	TYPESCRIPT_LANGUAGE_SERVER_VERSION=$(TYPESCRIPT_LANGUAGE_SERVER_VERSION) \
	TYPESCRIPT_VERSION=$(TYPESCRIPT_VERSION) \
	VSCODE_LANGSERVERS_VERSION=$(VSCODE_LANGSERVERS_VERSION) \
		$(RACKET_TEST) tests/web_language_service/acceptance_test.rkt

packaged-language-support-test:
	$(ODIN) test src/extension -vet -warnings-as-errors
	$(ODIN) test src/language_support -vet -warnings-as-errors \
		-define:ODIN_TEST_NAMES=language_support.package_runtime_activation_and_removal_are_atomic,language_support.package_runtime_conflicts_and_order_are_deterministic,language_support.package_runtime_requires_declared_environment_authority,language_support.support_sources_preserve_scope
	$(ODIN) test src/language_service -vet -warnings-as-errors \
		-define:ODIN_TEST_NAMES=language_service.executable_resolution_uses_controlled_precedence,language_service.service_catalog_preserves_fallback_across_package_conflicts
	$(ODIN) check src/odra -no-entry-point -vet -ignore-warnings

language-edit-capability-acceptance:
	$(ODIN) test src/language_service -vet -warnings-as-errors \
		-define:ODIN_TEST_NAMES=language_service.intelligence_capabilities_gate_all_query_families,language_service.intelligence_normalizes_hover_locations_and_external_uris,language_service.intelligence_normalizes_symbols_and_signatures,language_service.intelligence_semantic_tokens_apply_delta_and_reject_overlap,language_service.intelligence_contains_adversarial_lifecycle_and_results,language_service.intelligence_allocation_fault_and_cleanup_are_exact,language_service.workspace_edit_commits_and_undoes_versioned_multibuffer_change,language_service.workspace_edit_rejects_invalid_text_and_membership_as_a_whole,language_service.workspace_edit_applies_checked_file_operations,language_service.workspace_edit_rolls_back_partial_filesystem_publication,language_service.workspace_edit_allocation_failure_publishes_nothing
	$(MAKE) language-formatter-test

extensible-language-support-acceptance:
	$(EXTENSIBLE_LANGUAGE_SUPPORT_ACCEPTANCE_RUNNER) --prepare
	$(call run_extensible_language_support_step,basic-language-pack,$(MAKE) basic-language-pack-acceptance)
	$(call run_extensible_language_support_step,embedded-syntax,$(MAKE) syntax-injection-test)
	$(call run_extensible_language_support_step,direct-modal-commands,$(MAKE) language-interaction-profile-test language-interaction-test)
	$(call run_extensible_language_support_step,language-edits,$(MAKE) language-edit-capability-acceptance)
	$(call run_extensible_language_support_step,real-language-servers,$(MAKE) gopls-language-service-acceptance racket-language-service-protocol-test rust-language-service-acceptance web-language-service-acceptance)
	$(call run_extensible_language_support_step,retained-resources,$(MAKE) syntax-resource-study language-service-resource-study)
	$(call run_extensible_language_support_step,application-build,$(MAKE) odra)
	$(call run_extensible_language_support_step,direct-failure-shutdown-pty,$(MAKE) maintained-language-service-pty-test)
	$(call run_extensible_language_support_step,modal-pty,env ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) $(PTY_RACKET_TEST) tests/jan_structured_editing/acceptance_test.rkt)
	$(call run_extensible_language_support_step,jan-pty,env ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) $(PTY_RACKET_TEST) tests/jan_document_language/acceptance_test.rkt)
	$(call run_extensible_language_support_step,documentation,$(MAKE) docs-check)
	$(EXTENSIBLE_LANGUAGE_SUPPORT_ACCEPTANCE_RUNNER) --complete

language-service-extensibility-acceptance: $(SYNTAX_PROVIDER_FIXTURE_LIBRARY) $(SYNTAX_PROVIDER_FIXTURE_LINK)
	$(call run_verification_step,language-catalog-model-test,$(MAKE) language-catalog-model-test)
	$(call run_verification_step,language-test,$(ODIN) test src/language \
		-define:ODRA_TREE_SITTER_LIBRARY="../../$(TREE_SITTER_ODIN_LIBRARY)" \
		-define:ODRA_SYNTAX_PROVIDER_FIXTURE="$(abspath $(SYNTAX_PROVIDER_FIXTURE_LIBRARY))" \
		-define:ODRA_SYNTAX_PROVIDER_FIXTURE_LINK="$(abspath $(SYNTAX_PROVIDER_FIXTURE_LINK))" \
		-define:ODRA_SYNTAX_PROVIDER_QUERY="$(abspath $(TREE_SITTER_ODIN_DIR)/queries/highlights.scm)" \
		-define:ODRA_SYNTAX_PROVIDER_MALFORMED_QUERY="$(abspath tests/syntax_provider_fixture/malformed.scm)" \
		-define:ODRA_EXTERNAL_BUNDLE_GRAMMAR="$(abspath $(SYNTAX_PROVIDER_FIXTURE_LIBRARY))" \
		-define:ODRA_EXTERNAL_BUNDLE_QUERY="$(abspath tests/language_bundle_fixture/queries/highlights.scm)")
	$(call run_verification_step,language-service-catalog-model-test,$(MAKE) language-service-catalog-model-test)
	$(call run_verification_step,language-service-reference-test,$(MAKE) language-service-reference-test)
	$(call run_verification_step,language-service-resource-study,$(MAKE) language-service-resource-study)
	$(call run_verification_step,language-service-containment-test,$(MAKE) language-service-containment-test)
	$(call run_verification_step,language-service-test,$(ODIN) test src/language_service -vet -warnings-as-errors)
	$(call run_verification_step,language-formatter-test,$(MAKE) language-formatter-test)
	$(call run_verification_step,language-workspace-edit-test,$(MAKE) language-workspace-edit-test)
	$(call run_verification_step,language-support-config-test,$(MAKE) language-support-config-test)
	$(call run_verification_step,extension-language-support-test,$(ODIN) test src/extension -vet -warnings-as-errors)
	$(call run_verification_step,language-workflow-focused-test,$(MAKE) language-workflow-focused-test)
	$(call run_verification_step,gopls-language-service-acceptance,$(MAKE) gopls-language-service-acceptance)
	$(call run_verification_step,racket-language-service-protocol-test,$(MAKE) racket-language-service-protocol-test)
	$(call run_verification_step,odra,$(MAKE) odra)
	$(call run_verification_step,maintained-language-service-pty-test,$(MAKE) maintained-language-service-pty-test)

unicode-source-check:
	sha256sum --check third_party/unicode/17.0.0/SHA256SUMS

unicode-data: unicode-source-check
	$(RACKET) scripts/generate-unicode-data.rkt \
		third_party/unicode/17.0.0 \
		src/display/unicode17_data.odin

unicode-generated-check: unicode-source-check
	mkdir -p $(BUILD_DIR)/unicode
	$(RACKET) scripts/generate-unicode-data.rkt \
		third_party/unicode/17.0.0 \
		$(BUILD_DIR)/unicode/unicode17_data.odin
	cmp src/display/unicode17_data.odin $(BUILD_DIR)/unicode/unicode17_data.odin

unicode-check: unicode-generated-check
	$(ODIN) check src/display $(ODIN_VET_FLAGS)
	$(ODIN) test src/display -vet -warnings-as-errors

$(DISPLAY_PROBE): tests/display_probe/main.odin src/display/contracts.odin src/display/unicode17_data.odin src/display/unicode_profile.odin
	mkdir -p $(BUILD_DIR)
	$(ODIN) build tests/display_probe \
		-o:speed \
		-vet -warnings-as-errors \
		-out:$@

display-probe: $(DISPLAY_PROBE)
	$(DISPLAY_PROBE)

$(DISPLAY_EVIDENCE): tests/display_evidence/main.odin src/display/contracts.odin src/display/unicode17_data.odin src/display/unicode_profile.odin
	mkdir -p $(BUILD_DIR)
	$(ODIN) build tests/display_evidence \
		-o:speed \
		-vet -warnings-as-errors \
		-out:$@

display-evidence: $(DISPLAY_EVIDENCE)
	$(ODIN) version
	uname -srm
	$(DISPLAY_EVIDENCE)

display-test:
	$(ODIN) test src/display -vet -warnings-as-errors
	$(ODIN) test tests/display_projection -vet -warnings-as-errors

$(DISPLAY_BENCHMARK): tests/display_benchmark/main.odin $(DISPLAY_PRODUCTION_SOURCES)
	mkdir -p $(BUILD_DIR)
	$(ODIN) build tests/display_benchmark \
		-o:speed \
		-vet -warnings-as-errors \
		-out:$@

display-benchmark: $(DISPLAY_BENCHMARK)
	$(ODIN) version
	uname -srm
	$(DISPLAY_BENCHMARK)

$(DOCUMENT_EVIDENCE): tests/document_evidence/main.odin $(wildcard src/document/*.odin src/editor/*.odin src/text/*.odin)
	mkdir -p $(BUILD_DIR)
	$(ODIN) build tests/document_evidence \
		-o:speed \
		-vet -warnings-as-errors \
		-out:$@

document-evidence: $(DOCUMENT_EVIDENCE)
	$(ODIN) version
	uname -srm
	$(DOCUMENT_EVIDENCE)

$(CLIPBOARD_TRANSPORT_PROBE): tests/clipboard_transport_probe/main.odin
	mkdir -p $(BUILD_DIR)
	$(ODIN) build tests/clipboard_transport_probe \
		-o:speed \
		-vet -warnings-as-errors \
		-out:$@

clipboard-transport-probe: $(CLIPBOARD_TRANSPORT_PROBE)
	$(ODIN) version
	uname -srm
	$(CLIPBOARD_TRANSPORT_PROBE)

terminal-test:
	$(ODIN) test src/terminal -vet -warnings-as-errors
	$(ODIN) test tests/terminal_lifecycle -vet -warnings-as-errors

pointer-interaction-test: $(RUNTIME_ADAPTER_LIBRARY) $(TREE_SITTER_ODIN_LIBRARY) $(TERMINAL_EMULATOR_ADAPTER_LIBRARY) $(TERMINAL_VENDOR_LIBRARY) $(INTERACTIVE_SESSION_ADAPTER_LIBRARY)
	$(ODIN) test src/interaction -vet -warnings-as-errors
	$(ODIN) test src/editor_session -vet -warnings-as-errors
	$(ODIN) test src/ui -vet -warnings-as-errors
	$(ODIN) test src/terminal -vet -warnings-as-errors
	$(ODIN) test tests/terminal_lifecycle -vet -warnings-as-errors
	$(ODIN) test src/odra -vet -warnings-as-errors \
		-define:ODIN_TEST_NAMES=main.pointer_semantic_focus_plan_preserves_one_owner,main.pointer_darek_focus_requires_current_semantic_hit,main.pointer_darek_selection_uses_exact_module_row,main.pointer_maksym_selection_uses_exact_module_row,main.pointer_focuses_pane_from_status,main.pointer_focus_release_failure_is_atomic,main.pointer_rejects_stale_and_unsupported,main.pointer_click_focuses_and_places_text_point,main.pointer_click_retains_mark_without_edit_history,main.pointer_drag_selects_canonical_buffer_range,main.pointer_drag_cannot_select_neighboring_pane_text,main.pointer_capture_cancels_and_releases_without_empty_region,main.pointer_capture_rejects_interleaved_view_mutation,main.pointer_click_projection_failure_is_atomic,main.pointer_drag_distinguishes_same_buffer_views \
		-define:ODIN_TEST_THREADS=1 \
		-define:ODRA_RACKET_RUNTIME_LIBRARY="../../$(RUNTIME_ADAPTER_LIBRARY)" \
		-define:ODRA_TREE_SITTER_LIBRARY="../../$(TREE_SITTER_ODIN_LIBRARY)" \
		-extra-linker-flags:"$(RACKET_CS_LIBRARY) $(RACKET_CS_LINK_LIBS)"

pointer-terminal-test: $(RUNTIME_ADAPTER_LIBRARY) $(TREE_SITTER_ODIN_LIBRARY) $(TERMINAL_EMULATOR_ADAPTER_LIBRARY) $(TERMINAL_VENDOR_LIBRARY) $(INTERACTIVE_SESSION_ADAPTER_LIBRARY)
	$(ODIN) test src/terminal_session -vet -warnings-as-errors \
		-define:ODIN_TEST_NAMES=terminal_session.copy_mode_pointer_selects_retained_text,terminal_session.mouse_routing_respects_local_and_child_ownership,terminal_session.mouse_routing_contains_failure_and_session_boundaries \
		-define:ODIN_TEST_THREADS=1
	$(ODIN) test src/odra -vet -warnings-as-errors \
		-define:ODIN_TEST_NAMES=main.pointer_terminal_selects_retained_text_locally,main.pointer_terminal_routes_child_and_cleans_exit \
		-define:ODIN_TEST_THREADS=1 \
		-define:ODRA_RACKET_RUNTIME_LIBRARY="../../$(RUNTIME_ADAPTER_LIBRARY)" \
		-define:ODRA_TREE_SITTER_LIBRARY="../../$(TREE_SITTER_ODIN_LIBRARY)" \
		-extra-linker-flags:"$(RACKET_CS_LIBRARY) $(RACKET_CS_LINK_LIBS)"

pointer-interaction-acceptance: $(RUNTIME_ADAPTER_LIBRARY) $(TREE_SITTER_ODIN_LIBRARY) $(TERMINAL_EMULATOR_ADAPTER_LIBRARY) $(TERMINAL_VENDOR_LIBRARY) $(INTERACTIVE_SESSION_ADAPTER_LIBRARY)
	$(ODIN) test src/interaction -vet -warnings-as-errors \
		-define:ODIN_TEST_NAMES=interaction.pointer_queue_coalesces_only_compatible_motion,interaction.pointer_queue_preserves_incompatible_and_control_events,interaction.pointer_queue_limits_are_atomic
	$(ODIN) test src/ui -vet -warnings-as-errors \
		-define:ODIN_TEST_NAMES=ui.hit_test_generated_grid_preserves_precedence,ui.hit_test_rejects_excessive_stack_depth
	$(ODIN) test src/terminal -vet -warnings-as-errors \
		-define:ODIN_TEST_NAMES=terminal_frontend.terminal_decoder_rejects_invalid_pointer_input,terminal_frontend.terminal_pointer_cleanup_restores_every_owned_resource,terminal_frontend.terminal_pointer_cleanup_contains_frontend_loss,terminal_frontend.terminal_keyboard_input_survives_pointer_degradation
	$(ODIN) test src/terminal_session -vet -warnings-as-errors \
		-define:ODIN_TEST_NAMES=terminal_session.copy_mode_pointer_selects_retained_text,terminal_session.mouse_routing_respects_local_and_child_ownership,terminal_session.mouse_routing_contains_failure_and_session_boundaries \
		-define:ODIN_TEST_THREADS=1
	$(ODIN) test src/odra -vet -warnings-as-errors \
		-define:ODIN_TEST_NAMES=main.pointer_semantic_focus_plan_preserves_one_owner,main.pointer_darek_focus_requires_current_semantic_hit,main.pointer_darek_selection_uses_exact_module_row,main.pointer_focuses_pane_from_status,main.pointer_focus_release_failure_is_atomic,main.pointer_click_focuses_and_places_text_point,main.pointer_drag_selects_canonical_buffer_range,main.pointer_drag_cannot_select_neighboring_pane_text,main.pointer_capture_cancels_and_releases_without_empty_region,main.pointer_capture_accepts_coalesced_motion,main.pointer_capture_event_limit_is_contained,main.pointer_capture_duration_is_bounded,main.pointer_selection_generated_ranges_are_semantic,main.pointer_selection_generated_invalidations_are_atomic,main.pointer_terminal_selects_retained_text_locally,main.pointer_terminal_routes_child_and_cleans_exit \
		-define:ODIN_TEST_THREADS=1 \
		-define:ODRA_RACKET_RUNTIME_LIBRARY="../../$(RUNTIME_ADAPTER_LIBRARY)" \
		-define:ODRA_TREE_SITTER_LIBRARY="../../$(TREE_SITTER_ODIN_LIBRARY)" \
		-extra-linker-flags:"$(RACKET_CS_LIBRARY) $(RACKET_CS_LINK_LIBS)"

terminal-benchmark: terminal-vendor-build $(TERMINAL_EMULATOR_ADAPTER_LIBRARY) $(INTERACTIVE_SESSION_ADAPTER_LIBRARY)
	$(ODIN) version
	uname -srm
	$(ODIN) test src/terminal \
		-o:speed \
		-vet -warnings-as-errors \
		-define:ODRA_TERMINAL_BENCHMARK=true \
		-define:ODIN_TEST_THREADS=1
	$(ODIN) test src/odra \
		-o:speed \
		-vet -warnings-as-errors \
		-define:ODRA_TERMINAL_BENCHMARK=true \
		-define:ODRA_RACKET_RUNTIME_LIBRARY="../../$(RUNTIME_ADAPTER_LIBRARY)" \
		-define:ODRA_TREE_SITTER_LIBRARY="../../$(TREE_SITTER_ODIN_LIBRARY)" \
		-extra-linker-flags:"$(RACKET_CS_LIBRARY) $(RACKET_CS_LINK_LIBS)" \
		-define:ODIN_TEST_THREADS=1

$(ODRA): $(ODRA_PRODUCTION_SOURCES) $(RUNTIME_ADAPTER_LIBRARY) $(TREE_SITTER_ODIN_LIBRARY) $(TERMINAL_EMULATOR_ADAPTER_LIBRARY) $(TERMINAL_VENDOR_LIBRARY) $(INTERACTIVE_SESSION_ADAPTER_LIBRARY)
	mkdir -p $(BUILD_DIR) $(ODRA_TIMINGS_DIR)
	$(ODIN) build src/odra \
		-vet -warnings-as-errors \
		-show-more-timings \
		-export-timings:json \
		-export-timings-file:$(ODRA_TIMINGS) \
		-out:$@ \
		-define:ODRA_RACKET_RUNTIME_LIBRARY="../../$(RUNTIME_ADAPTER_LIBRARY)" \
		-define:ODRA_TREE_SITTER_LIBRARY="../../$(TREE_SITTER_ODIN_LIBRARY)" \
		-define:ODRA_INTERACTIVE_SESSION_ADAPTER_LIBRARY="../../$(INTERACTIVE_SESSION_ADAPTER_LIBRARY)" \
		-define:ODRA_TERMINAL_EMULATOR_ADAPTER_LIBRARY="../../$(TERMINAL_EMULATOR_ADAPTER_LIBRARY)" \
		-define:ODRA_TERMINAL_EMULATOR_VENDOR_LIBRARY="../../$(TERMINAL_VENDOR_LIBRARY)" \
		-extra-linker-flags:"$(RACKET_CS_LIBRARY) $(RACKET_CS_LINK_LIBS)"

$(ODRA_DEVELOPMENT): $(ODRA_PRODUCTION_SOURCES) $(RUNTIME_ADAPTER_LIBRARY) $(TREE_SITTER_ODIN_LIBRARY) $(TERMINAL_EMULATOR_ADAPTER_LIBRARY) $(TERMINAL_VENDOR_LIBRARY) $(INTERACTIVE_SESSION_ADAPTER_LIBRARY)
	mkdir -p $(BUILD_DIR)
	$(ODIN) build src/odra \
		-o:none \
		-vet -warnings-as-errors \
		-out:$@ \
		-define:ODRA_RACKET_RUNTIME_LIBRARY="../../$(RUNTIME_ADAPTER_LIBRARY)" \
		-define:ODRA_TREE_SITTER_LIBRARY="../../$(TREE_SITTER_ODIN_LIBRARY)" \
		-define:ODRA_INTERACTIVE_SESSION_ADAPTER_LIBRARY="../../$(INTERACTIVE_SESSION_ADAPTER_LIBRARY)" \
		-define:ODRA_TERMINAL_EMULATOR_ADAPTER_LIBRARY="../../$(TERMINAL_EMULATOR_ADAPTER_LIBRARY)" \
		-define:ODRA_TERMINAL_EMULATOR_VENDOR_LIBRARY="../../$(TERMINAL_VENDOR_LIBRARY)" \
		-extra-linker-flags:"$(RACKET_CS_LIBRARY) $(RACKET_CS_LINK_LIBS)"

$(PREVIEW_RUNTIME_BINARY): $(ODRA_PRODUCTION_SOURCES) $(PREVIEW_RUNTIME_ADAPTER_LIBRARY) $(TREE_SITTER_ODIN_LIBRARY) $(TERMINAL_EMULATOR_ADAPTER_LIBRARY) $(TERMINAL_VENDOR_LIBRARY) $(INTERACTIVE_SESSION_ADAPTER_LIBRARY)
	mkdir -p $(PREVIEW_RUNTIME_BUILD_DIR)
	$(ODIN) build src/odra \
		-vet -warnings-as-errors \
		-thread-count:$(ODRA_PREVIEW_THREAD_COUNT) \
		-show-more-timings \
		-export-timings:json \
		-export-timings-file:$(PREVIEW_RUNTIME_TIMINGS) \
		-source-code-locations:none \
		-out:$@ \
		-define:ODRA_PREVIEW_BUNDLE=true \
		-define:ODRA_RACKET_RUNTIME_LIBRARY="../../$(PREVIEW_RUNTIME_ADAPTER_LIBRARY)" \
		-define:ODRA_TREE_SITTER_LIBRARY="../../$(TREE_SITTER_ODIN_LIBRARY)" \
		-define:ODRA_INTERACTIVE_SESSION_ADAPTER_LIBRARY="../../$(INTERACTIVE_SESSION_ADAPTER_LIBRARY)" \
		-define:ODRA_TERMINAL_EMULATOR_ADAPTER_LIBRARY="../../$(TERMINAL_EMULATOR_ADAPTER_LIBRARY)" \
		-define:ODRA_TERMINAL_EMULATOR_VENDOR_LIBRARY="../../$(TERMINAL_VENDOR_LIBRARY)" \
		-extra-linker-flags:"$(RACKET_CS_LIBRARY) $(RACKET_CS_LINK_LIBS)"
	$(STRIP) --strip-all $@

odra: $(ODRA) $(KSAWERY_MODULE_LIBRARY) $(MAKSYM_MODULE_LIBRARY) $(DAREK_MODULE_LIBRARY) $(JAN_MODULE_LIBRARY) $(PRODUCT_MODULE_MANIFEST)

.PHONY: terminal-lower-pane-focused-test

terminal-lower-pane-focused-test: $(RUNTIME_ADAPTER_LIBRARY) $(TREE_SITTER_ODIN_LIBRARY) $(TERMINAL_EMULATOR_ADAPTER_LIBRARY) $(TERMINAL_VENDOR_LIBRARY) $(INTERACTIVE_SESSION_ADAPTER_LIBRARY)
	bash scripts/run-isolated-racket-tests.sh $(ODIN) test src/odra -o:none -vet -warnings-as-errors \
		-out:$(BUILD_DIR)/terminal-lower-pane-test \
		-define:ODIN_TEST_NAMES=main.terminal_default_lower_pane_preserves_editing,main.terminal_toggle_preserves_replaced_pane,main.terminal_other_pane_keeps_explicit_placement,main.terminal_lower_pane_exit_returns_to_editor,main.terminal_presentation_reuses_scoped_default,main.terminal_toggle_restores_layout_and_process,main.terminal_open_replaces_exited_default,main.terminal_exit_returns_to_scratch \
		-define:ODIN_TEST_THREADS=1 \
		-define:ODRA_RACKET_RUNTIME_LIBRARY="../../$(RUNTIME_ADAPTER_LIBRARY)" \
		-define:ODRA_TREE_SITTER_LIBRARY="../../$(TREE_SITTER_ODIN_LIBRARY)" \
		-define:ODRA_INTERACTIVE_SESSION_ADAPTER_LIBRARY="../../$(INTERACTIVE_SESSION_ADAPTER_LIBRARY)" \
		-define:ODRA_TERMINAL_EMULATOR_ADAPTER_LIBRARY="../../$(TERMINAL_EMULATOR_ADAPTER_LIBRARY)" \
		-define:ODRA_TERMINAL_EMULATOR_VENDOR_LIBRARY="../../$(TERMINAL_VENDOR_LIBRARY)" \
		-extra-linker-flags:"$(RACKET_CS_LIBRARY) $(RACKET_CS_LINK_LIBS)"

terminal-presentation-test: $(ODRA)
	$(ODIN) test src/odra -vet -warnings-as-errors \
		-define:ODRA_RACKET_RUNTIME_LIBRARY="../../$(RUNTIME_ADAPTER_LIBRARY)" \
		-define:ODRA_TREE_SITTER_LIBRARY="../../$(TREE_SITTER_ODIN_LIBRARY)" \
		-extra-linker-flags:"$(RACKET_CS_LIBRARY) $(RACKET_CS_LINK_LIBS)"
	$(MAKE) terminal-presentation-focused-test

terminal-presentation-focused-test: $(ODRA)
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/terminal_presentation/presentation_test.rkt
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/terminal_presentation/live_terminal_test.rkt
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/pane_layout/presentation_test.rkt
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/pane_buffer_lifecycle/presentation_test.rkt
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/other_pane_display/presentation_test.rkt
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/reversible_editing/semantic_terminal_test.rkt
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/selection/region_terminal_test.rkt
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/text_transfer/transfer_terminal_test.rkt
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/search/incremental_terminal_test.rkt
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/search/regexp_terminal_test.rkt
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/search/query_replacement_terminal_test.rkt
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/document_lifecycle/open_test.rkt
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/document_lifecycle/save_path_test.rkt
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/document_lifecycle/exit_test.rkt
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/buffer_session/navigation_test.rkt
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/buffer_session/lifecycle_test.rkt
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/buffer_session/menu_test.rkt
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/dir_lifecycle/opening_terminal_test.rkt
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/project_promotion/workflow_terminal_test.rkt
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/filesystem_path_navigation/navigation_test.rkt
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/command_navigation/navigation_test.rkt
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/command_navigation/area_balance_test.rkt
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/direct_navigation/acceptance_test.rkt
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/gutter/workflow_test.rkt

	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/project_context/active_membership_test.rkt
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/project_context/command_workflows_test.rkt
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/keymap_inspection/inspection_terminal_test.rkt
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/syntax_presentation/presentation_test.rkt
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/structured_syntax_workflow/workflow_test.rkt

search-result-navigation-acceptance: $(ODRA)
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/search/incremental_terminal_test.rkt
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/search/regexp_terminal_test.rkt
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/search/query_replacement_terminal_test.rkt
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/search/search_controls_terminal_test.rkt
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/search/result_navigation_terminal_test.rkt
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/symbol_navigation/workflow_test.rkt
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/project_search/workflow_test.rkt

status-bar-acceptance: $(ODRA)
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/status_bar/workflow_test.rkt

gutter-acceptance: $(ODRA)
	$(MAKE) gutter-resource-study
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/gutter/workflow_test.rkt

$(GUTTER_RESOURCE_STUDY): tests/gutter_resource_study/main.odin $(wildcard src/gutter/*.odin)
	mkdir -p $(BUILD_DIR)
	$(ODIN) build tests/gutter_resource_study \
		-o:speed \
		-vet -warnings-as-errors \
		-out:$@

gutter-resource-study: $(GUTTER_RESOURCE_STUDY)
	$(ODIN) version
	uname -srm
	$(GUTTER_RESOURCE_STUDY)

personal-command-acceptance: $(ODRA)
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/personal_commands/workflow_test.rkt
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/personal_commands/reload_workflow_test.rkt

personal-command-resource-study:
	$(RACKET_TEST) tests/personal_commands/resource_study.rkt

terminal-smoke: $(ODRA)
	$(ODRA)

$(HOSTING_BUILD_DIR):
	mkdir -p $@

$(HOSTING_MODULE_C): tests/hosting/probe.rkt | $(HOSTING_BUILD_DIR)
	$(RACO) ctool --c-mods $@ $<

$(ODIN_HOST_ADAPTER_OBJECT): tests/hosting/odin_host/adapter.c $(HOSTING_MODULE_C)
	$(CC) -std=c11 -O2 -fPIC -Wall -Wextra -Werror \
		-I$(RACKET_INCLUDE_DIR) -I$(HOSTING_BUILD_DIR) \
		-DODRA_RACKET_BOOT_DIR='"$(RACKET_BOOT_DIR)"' \
		-c $< -o $@

$(ODIN_HOST_ADAPTER_LIBRARY): $(ODIN_HOST_ADAPTER_OBJECT)
	$(AR) rcs $@ $<

$(ODIN_HOST_PROBE): tests/hosting/odin_host/main.odin $(ODIN_HOST_ADAPTER_LIBRARY)
	$(ODIN) build tests/hosting/odin_host \
		-vet -warnings-as-errors \
		-out:$@ \
		-define:RACKET_PROBE_LIBRARY="../../../$(ODIN_HOST_ADAPTER_LIBRARY)" \
		-extra-linker-flags:"$(RACKET_CS_LIBRARY) $(RACKET_CS_LINK_LIBS)"

$(RACKET_HOST_LIBRARY): tests/hosting/racket_host/probe.odin | $(HOSTING_BUILD_DIR)
	$(ODIN) build tests/hosting/racket_host \
		-build-mode:shared \
		-vet -warnings-as-errors \
		-out:$@

RUNTIME_BOUNDARY_SOURCE := src/hosting/runtime-boundary.rkt
RUNTIME_RACKET_DEPENDENCIES := $(shell find src -type f -name '*.rkt' -print | sort)
RUNTIME_PROBE_SOURCES := tests/hosting/support/runtime-call-probe.rkt tests/hosting/support/transform-probe.rkt tests/hosting/support/history-policy-probe.rkt tests/hosting/support/display-policy-probe.rkt tests/hosting/support/keymap-profile-probe.rkt tests/hosting/support/command-catalog-probe.rkt tests/hosting/support/transaction-probe.rkt tests/hosting/support/transfer-probe.rkt tests/hosting/support/search-probe.rkt tests/hosting/support/buffer-session-probe.rkt tests/hosting/support/layout-probe.rkt tests/hosting/support/ui-role-probe.rkt tests/hosting/support/theme-probe.rkt tests/hosting/support/structural-probe.rkt tests/hosting/support/language-service-probe.rkt

$(RUNTIME_MODULE_C): $(RUNTIME_RACKET_DEPENDENCIES) | $(HOSTING_BUILD_DIR)
	$(RACO) make $(RUNTIME_BOUNDARY_SOURCE)
	$(RACO) ctool --c-mods $@ ++lang racket/base $(RUNTIME_BOUNDARY_SOURCE)

$(PREVIEW_RUNTIME_MODULE_C): $(RUNTIME_RACKET_DEPENDENCIES) scripts/release/build-racket-runtime-module.rkt
	mkdir -p $(PREVIEW_RUNTIME_BUILD_DIR)
	$(RACKET) scripts/release/build-racket-runtime-module.rkt \
		--source-root src \
		--entry hosting/runtime-boundary.rkt \
		--output $@

$(PREVIEW_RUNTIME_ADAPTER_OBJECT): src/hosting/adapter.c src/hosting/runtime_boundary_manifest.h src/hosting/scoped_capability_transport.c $(PREVIEW_RUNTIME_MODULE_C)
	$(CC) -std=c11 -O2 -fPIC -Wall -Wextra -Werror \
		-I$(RACKET_INCLUDE_DIR) -I$(PREVIEW_RUNTIME_BUILD_DIR) \
		-DODRA_RACKET_BOOT_DIR='"$(RACKET_BOOT_DIR)"' \
		-DODRA_RACKET_COLLECTS_DIR='"$(RACKET_COLLECTS_DIR)"' \
		-DODRA_RACKET_CONFIG_DIR='"$(RACKET_CONFIG_DIR)"' \
		-c $< -o $@

$(PREVIEW_RUNTIME_ADAPTER_LIBRARY): $(PREVIEW_RUNTIME_ADAPTER_OBJECT)
	$(AR) rcs $@ $<

$(PREVIEW_RUNTIME_LIFECYCLE_TEST): tests/hosting/runtime_lifecycle/main.odin src/hosting/hosting.odin $(PREVIEW_RUNTIME_ADAPTER_LIBRARY)
	$(ODIN) build tests/hosting/runtime_lifecycle \
		-vet -warnings-as-errors \
		-out:$@ \
		-define:ODRA_RACKET_RUNTIME_LIBRARY="../../$(PREVIEW_RUNTIME_ADAPTER_LIBRARY)" \
		-define:ODRA_RACKET_BOUNDARY_RUNTIME_LIBRARY="../../../$(PREVIEW_RUNTIME_ADAPTER_LIBRARY)" \
		-extra-linker-flags:"$(RACKET_CS_LIBRARY) $(RACKET_CS_LINK_LIBS)"

preview-racket-runtime-test: $(PREVIEW_RUNTIME_LIFECYCLE_TEST)
	$(RACKET_TEST) scripts/release/build-racket-runtime-module.rkt
	@if strings -a $(PREVIEW_RUNTIME_ADAPTER_LIBRARY) | grep -Eq '/(home|Users|root)/|/workspace/(src|tests|ops)/'; then \
		echo 'preview Racket runtime contains a private source path' >&2; \
		exit 1; \
	fi
	$(PREVIEW_RUNTIME_LIFECYCLE_TEST)

$(RUNTIME_TEST_MODULE_C): $(RUNTIME_RACKET_DEPENDENCIES) $(RUNTIME_PROBE_SOURCES) | $(HOSTING_BUILD_DIR)
	$(RACO) make $(RUNTIME_BOUNDARY_SOURCE) $(RUNTIME_PROBE_SOURCES)
	$(RACO) ctool --c-mods $@ ++lang racket/base $(RUNTIME_BOUNDARY_SOURCE) $(RUNTIME_PROBE_SOURCES)

$(RUNTIME_ADAPTER_OBJECT): src/hosting/adapter.c src/hosting/runtime_boundary_manifest.h src/hosting/scoped_capability_transport.c $(RUNTIME_MODULE_C)
	$(CC) -std=c11 -O2 -fPIC -Wall -Wextra -Werror \
		-I$(RACKET_INCLUDE_DIR) -I$(HOSTING_BUILD_DIR) \
		-DODRA_RACKET_BOOT_DIR='"$(RACKET_BOOT_DIR)"' \
		-DODRA_RACKET_COLLECTS_DIR='"$(RACKET_COLLECTS_DIR)"' \
		-DODRA_RACKET_CONFIG_DIR='"$(RACKET_CONFIG_DIR)"' \
		-c $< -o $@

$(RUNTIME_ADAPTER_LIBRARY): $(RUNTIME_ADAPTER_OBJECT)
	$(AR) rcs $@ $<

$(RUNTIME_TEST_ADAPTER_OBJECT): src/hosting/adapter.c src/hosting/runtime_boundary_manifest.h src/hosting/scoped_capability_transport.c $(RUNTIME_TEST_MODULE_C)
	$(CC) -std=c11 -O2 -fPIC -Wall -Wextra -Werror \
		-I$(RACKET_INCLUDE_DIR) -I$(HOSTING_BUILD_DIR) \
		-DODRA_RACKET_BOOT_DIR='"$(RACKET_BOOT_DIR)"' \
		-DODRA_RACKET_COLLECTS_DIR='"$(RACKET_COLLECTS_DIR)"' \
		-DODRA_RACKET_CONFIG_DIR='"$(RACKET_CONFIG_DIR)"' \
		-DODRA_RACKET_RUNTIME_MODULE='"runtime_test_module.c"' \
		-DODRA_RACKET_TEST_PROBES=1 \
		-c $< -o $@

$(RUNTIME_TEST_ADAPTER_LIBRARY): $(RUNTIME_TEST_ADAPTER_OBJECT)
	$(AR) rcs $@ $<

$(RUNTIME_MISSING_BOOT_ADAPTER_OBJECT): src/hosting/adapter.c src/hosting/runtime_boundary_manifest.h src/hosting/scoped_capability_transport.c $(RUNTIME_MODULE_C)
	$(CC) -std=c11 -O2 -fPIC -Wall -Wextra -Werror \
		-I$(RACKET_INCLUDE_DIR) -I$(HOSTING_BUILD_DIR) \
		-DODRA_RACKET_BOOT_DIR='"/odra-missing-racket-boot-images"' \
		-DODRA_RACKET_COLLECTS_DIR='"$(RACKET_COLLECTS_DIR)"' \
		-DODRA_RACKET_CONFIG_DIR='"$(RACKET_CONFIG_DIR)"' \
		-c $< -o $@

$(RUNTIME_MISSING_BOOT_ADAPTER_LIBRARY): $(RUNTIME_MISSING_BOOT_ADAPTER_OBJECT)
	$(AR) rcs $@ $<

$(RUNTIME_INVALID_MODULE_ADAPTER_OBJECT): src/hosting/adapter.c src/hosting/runtime_boundary_manifest.h src/hosting/scoped_capability_transport.c $(RUNTIME_MODULE_C)
	$(CC) -std=c11 -O2 -fPIC -Wall -Wextra -Werror \
		-I$(RACKET_INCLUDE_DIR) -I$(HOSTING_BUILD_DIR) \
		-DODRA_RACKET_BOOT_DIR='"$(RACKET_BOOT_DIR)"' \
		-DODRA_RACKET_COLLECTS_DIR='"$(RACKET_COLLECTS_DIR)"' \
		-DODRA_RACKET_CONFIG_DIR='"$(RACKET_CONFIG_DIR)"' \
		-DODRA_RACKET_EXPECTED_START_SYMBOL='"odra-runtime-invalid"' \
		-c $< -o $@

$(RUNTIME_INVALID_MODULE_ADAPTER_LIBRARY): $(RUNTIME_INVALID_MODULE_ADAPTER_OBJECT)
	$(AR) rcs $@ $<

$(RUNTIME_MISSING_BOUNDARY_ADAPTER_OBJECT): src/hosting/adapter.c src/hosting/runtime_boundary_manifest.h src/hosting/scoped_capability_transport.c $(RUNTIME_MODULE_C)
	$(CC) -std=c11 -O2 -fPIC -Wall -Wextra -Werror \
		-I$(RACKET_INCLUDE_DIR) -I$(HOSTING_BUILD_DIR) \
		-DODRA_RACKET_BOOT_DIR='"$(RACKET_BOOT_DIR)"' \
		-DODRA_RACKET_COLLECTS_DIR='"$(RACKET_COLLECTS_DIR)"' \
		-DODRA_RACKET_CONFIG_DIR='"$(RACKET_CONFIG_DIR)"' \
		-DODRA_RACKET_MISSING_BOUNDARY_PROCEDURE='"runtime-project-unregister-batch"' \
		-c $< -o $@

$(RUNTIME_MISSING_BOUNDARY_ADAPTER_LIBRARY): $(RUNTIME_MISSING_BOUNDARY_ADAPTER_OBJECT)
	$(AR) rcs $@ $<

$(RUNTIME_INVALID_SHUTDOWN_ADAPTER_OBJECT): src/hosting/adapter.c src/hosting/runtime_boundary_manifest.h src/hosting/scoped_capability_transport.c $(RUNTIME_MODULE_C)
	$(CC) -std=c11 -O2 -fPIC -Wall -Wextra -Werror \
		-I$(RACKET_INCLUDE_DIR) -I$(HOSTING_BUILD_DIR) \
		-DODRA_RACKET_BOOT_DIR='"$(RACKET_BOOT_DIR)"' \
		-DODRA_RACKET_COLLECTS_DIR='"$(RACKET_COLLECTS_DIR)"' \
		-DODRA_RACKET_CONFIG_DIR='"$(RACKET_CONFIG_DIR)"' \
		-DODRA_RACKET_EXPECTED_STOP_SYMBOL='"odra-runtime-invalid"' \
		-c $< -o $@

$(RUNTIME_INVALID_SHUTDOWN_ADAPTER_LIBRARY): $(RUNTIME_INVALID_SHUTDOWN_ADAPTER_OBJECT)
	$(AR) rcs $@ $<

$(RUNTIME_LIFECYCLE_TEST): tests/hosting/runtime_lifecycle/main.odin src/hosting/hosting.odin $(RUNTIME_ADAPTER_LIBRARY)
	$(ODIN) build tests/hosting/runtime_lifecycle \
		-vet -warnings-as-errors \
		-out:$@ \
		-define:ODRA_RACKET_RUNTIME_LIBRARY="../../$(RUNTIME_ADAPTER_LIBRARY)" \
		-define:ODRA_RACKET_BOUNDARY_RUNTIME_LIBRARY="../../../$(RUNTIME_ADAPTER_LIBRARY)" \
		-extra-linker-flags:"$(RACKET_CS_LIBRARY) $(RACKET_CS_LINK_LIBS)"

$(RUNTIME_MISSING_BOOT_TEST): tests/hosting/runtime_failure/main.odin src/hosting/hosting.odin $(RUNTIME_MISSING_BOOT_ADAPTER_LIBRARY)
	$(ODIN) build tests/hosting/runtime_failure \
		-vet -warnings-as-errors \
		-out:$@ \
		-define:ODRA_RACKET_RUNTIME_LIBRARY="../../$(RUNTIME_MISSING_BOOT_ADAPTER_LIBRARY)" \
		-define:EXPECT_RUNTIME_UNAVAILABLE=true \
		-extra-linker-flags:"$(RACKET_CS_LIBRARY) $(RACKET_CS_LINK_LIBS)"

$(RUNTIME_INVALID_MODULE_TEST): tests/hosting/runtime_failure/main.odin src/hosting/hosting.odin $(RUNTIME_INVALID_MODULE_ADAPTER_LIBRARY)
	$(ODIN) build tests/hosting/runtime_failure \
		-vet -warnings-as-errors \
		-out:$@ \
		-define:ODRA_RACKET_RUNTIME_LIBRARY="../../$(RUNTIME_INVALID_MODULE_ADAPTER_LIBRARY)" \
		-extra-linker-flags:"$(RACKET_CS_LIBRARY) $(RACKET_CS_LINK_LIBS)"

$(RUNTIME_MISSING_BOUNDARY_TEST): tests/hosting/runtime_boundary_failure/main.odin src/hosting/hosting.odin $(RUNTIME_MISSING_BOUNDARY_ADAPTER_LIBRARY)
	$(ODIN) build tests/hosting/runtime_boundary_failure \
		-vet -warnings-as-errors \
		-out:$@ \
		-define:ODRA_RACKET_RUNTIME_LIBRARY="../../$(RUNTIME_MISSING_BOUNDARY_ADAPTER_LIBRARY)" \
		-define:ODRA_RACKET_BOUNDARY_RUNTIME_LIBRARY="../../../$(RUNTIME_MISSING_BOUNDARY_ADAPTER_LIBRARY)" \
		-extra-linker-flags:"$(RACKET_CS_LIBRARY) $(RACKET_CS_LINK_LIBS)"

$(RUNTIME_INVALID_SHUTDOWN_TEST): tests/hosting/runtime_shutdown_failure/main.odin src/hosting/hosting.odin $(RUNTIME_INVALID_SHUTDOWN_ADAPTER_LIBRARY)
	$(ODIN) build tests/hosting/runtime_shutdown_failure \
		-vet -warnings-as-errors \
		-out:$@ \
		-define:ODRA_RACKET_RUNTIME_LIBRARY="../../$(RUNTIME_INVALID_SHUTDOWN_ADAPTER_LIBRARY)" \
		-define:ODRA_RACKET_BOUNDARY_RUNTIME_LIBRARY="../../../$(RUNTIME_INVALID_SHUTDOWN_ADAPTER_LIBRARY)" \
		-extra-linker-flags:"$(RACKET_CS_LIBRARY) $(RACKET_CS_LINK_LIBS)"

$(RUNTIME_CONTRACT_MISMATCH_TEST): tests/hosting/runtime_failure/main.odin src/hosting/hosting.odin $(RUNTIME_ADAPTER_LIBRARY)
	$(ODIN) build tests/hosting/runtime_failure \
		-vet -warnings-as-errors \
		-out:$@ \
		-define:ODRA_RACKET_RUNTIME_LIBRARY="../../$(RUNTIME_ADAPTER_LIBRARY)" \
		-define:ODRA_NATIVE_CONTRACT_SCHEMA_SCENARIO=1 \
		-extra-linker-flags:"$(RACKET_CS_LIBRARY) $(RACKET_CS_LINK_LIBS)"

$(RUNTIME_COMMAND_BENCHMARK): tests/hosting/command_benchmark/main.odin src/command/command.odin src/bridge/capability.odin src/bridge/publication.odin src/hosting/hosting.odin $(RUNTIME_ADAPTER_LIBRARY)
	$(ODIN) build tests/hosting/command_benchmark \
		-o:speed \
		-vet -warnings-as-errors \
		-out:$@ \
		-define:ODRA_RACKET_RUNTIME_LIBRARY="../../$(RUNTIME_ADAPTER_LIBRARY)" \
		-extra-linker-flags:"$(RACKET_CS_LIBRARY) $(RACKET_CS_LINK_LIBS)"

$(RUNTIME_COMMAND_GC_BENCHMARK): tests/hosting/command_benchmark/main.odin src/command/command.odin src/bridge/capability.odin src/bridge/publication.odin src/hosting/hosting.odin $(RUNTIME_ADAPTER_LIBRARY)
	$(ODIN) build tests/hosting/command_benchmark \
		-o:speed \
		-vet -warnings-as-errors \
		-out:$@ \
		-define:ODRA_RACKET_RUNTIME_LIBRARY="../../$(RUNTIME_ADAPTER_LIBRARY)" \
		-define:ODRA_RACKET_COMMAND_SCENARIO=4 \
		-extra-linker-flags:"$(RACKET_CS_LIBRARY) $(RACKET_CS_LINK_LIBS)"

$(RUNTIME_VIEW_COMMAND_BENCHMARK): tests/hosting/view_command_benchmark/main.odin $(wildcard src/command/*.odin src/interaction/*.odin src/display/*.odin src/view/*.odin src/search/*.odin src/editor/*.odin src/text/*.odin src/history/*.odin src/transaction/*.odin src/bridge/*.odin src/hosting/*.odin) $(RUNTIME_ADAPTER_LIBRARY)
	$(ODIN) build tests/hosting/view_command_benchmark \
		-o:speed \
		-vet -warnings-as-errors \
		-out:$@ \
		-define:ODRA_RACKET_RUNTIME_LIBRARY="../../$(RUNTIME_ADAPTER_LIBRARY)" \
		-extra-linker-flags:"$(RACKET_CS_LIBRARY) $(RACKET_CS_LINK_LIBS)"

$(RUNTIME_TRANSACTION_COMMAND_BENCHMARK): tests/hosting/transaction_command_benchmark/main.odin $(wildcard src/transaction/*.odin src/history/*.odin src/editor/*.odin src/text/*.odin src/bridge/*.odin src/hosting/*.odin) $(RUNTIME_ADAPTER_LIBRARY)
	$(ODIN) build tests/hosting/transaction_command_benchmark \
		-o:speed \
		-vet -warnings-as-errors \
		-out:$@ \
		-define:ODRA_RACKET_RUNTIME_LIBRARY="../../$(RUNTIME_ADAPTER_LIBRARY)" \
		-extra-linker-flags:"$(RACKET_CS_LIBRARY) $(RACKET_CS_LINK_LIBS)"

$(RUNTIME_TRANSFER_COMMAND_BENCHMARK): tests/hosting/transfer_command_benchmark/main.odin $(wildcard src/transaction/*.odin src/history/*.odin src/editor/*.odin src/text/*.odin src/bridge/*.odin src/hosting/*.odin) $(RUNTIME_ADAPTER_LIBRARY)
	$(ODIN) build tests/hosting/transfer_command_benchmark \
		-o:speed \
		-vet -warnings-as-errors \
		-out:$@ \
		-define:ODRA_RACKET_RUNTIME_LIBRARY="../../$(RUNTIME_ADAPTER_LIBRARY)" \
		-extra-linker-flags:"$(RACKET_CS_LIBRARY) $(RACKET_CS_LINK_LIBS)"

$(RUNTIME_SEARCH_COMMAND_BENCHMARK): tests/hosting/search_command_benchmark/main.odin $(wildcard src/bridge/*.odin src/hosting/*.odin) $(RUNTIME_ADAPTER_LIBRARY)
	$(ODIN) build tests/hosting/search_command_benchmark \
		-o:speed \
		-vet -warnings-as-errors \
		-out:$@ \
		-define:ODRA_RACKET_RUNTIME_LIBRARY="../../$(RUNTIME_ADAPTER_LIBRARY)" \
		-extra-linker-flags:"$(RACKET_CS_LIBRARY) $(RACKET_CS_LINK_LIBS)"

$(RUNTIME_BUFFER_SESSION_COMMAND_BENCHMARK): tests/hosting/buffer_session_command_benchmark/main.odin $(wildcard src/bridge/*.odin src/hosting/*.odin) $(RUNTIME_ADAPTER_LIBRARY)
	$(ODIN) build tests/hosting/buffer_session_command_benchmark \
		-o:speed \
		-vet -warnings-as-errors \
		-out:$@ \
		-define:ODRA_RACKET_RUNTIME_LIBRARY="../../$(RUNTIME_ADAPTER_LIBRARY)" \
		-extra-linker-flags:"$(RACKET_CS_LIBRARY) $(RACKET_CS_LINK_LIBS)"

$(LAYOUT_ACCEPTANCE): tests/layout_acceptance/main.odin $(wildcard src/command/*.odin src/layout/*.odin src/view/*.odin src/editor/*.odin src/bridge/*.odin src/hosting/*.odin) $(RUNTIME_TEST_ADAPTER_LIBRARY)
	$(ODIN) build tests/layout_acceptance \
		-vet -warnings-as-errors \
		-out:$@ \
		-define:ODRA_RACKET_RUNTIME_LIBRARY="../../$(RUNTIME_TEST_ADAPTER_LIBRARY)" \
		-extra-linker-flags:"$(RACKET_CS_LIBRARY) $(RACKET_CS_LINK_LIBS)"

hosting-runtime-check: $(RUNTIME_ADAPTER_LIBRARY)
	$(ODIN) check src/hosting $(ODIN_VET_FLAGS) \
		-define:ODRA_RACKET_RUNTIME_LIBRARY="../../$(RUNTIME_ADAPTER_LIBRARY)"
	$(ODIN) check src/command $(ODIN_VET_FLAGS) \
		-define:ODRA_RACKET_RUNTIME_LIBRARY="../../$(RUNTIME_ADAPTER_LIBRARY)"

indentation-policy-focused-test: $(RUNTIME_TEST_ADAPTER_LIBRARY) $(RUNTIME_ADAPTER_LIBRARY) $(TREE_SITTER_ODIN_LIBRARY)
	$(RACKET_TEST) src/command/indentation.rkt \
		src/configuration/personal.rkt \
		src/hosting/personal-configuration-bridge.rkt
	$(ODIN) test src/indentation -vet -warnings-as-errors
	$(ODIN) test src/view -vet -warnings-as-errors
	$(ODIN) test src/editor_session -vet -warnings-as-errors
	$(ODIN) test src/command -vet -warnings-as-errors \
		-define:ODIN_TEST_THREADS=1 \
		-define:ODIN_TEST_NAMES=command.indentation_is_one_reversible_group,command.indentation_uses_the_complete_effective_policy,command.logical_line_indentation_is_atomic_and_reversible \
		-define:ODRA_RACKET_RUNTIME_LIBRARY="../../$(RUNTIME_TEST_ADAPTER_LIBRARY)" \
		-extra-linker-flags:"$(RACKET_CS_LIBRARY) $(RACKET_CS_LINK_LIBS)"
	$(ODIN) check src/language -no-entry-point -vet -warnings-as-errors \
		-define:ODRA_TREE_SITTER_LIBRARY="../../$(TREE_SITTER_ODIN_LIBRARY)"
	$(ODIN) check src/project -no-entry-point -vet -warnings-as-errors
	$(ODIN) check src/odra -vet -warnings-as-errors \
		-define:ODRA_RACKET_RUNTIME_LIBRARY="../../$(RUNTIME_ADAPTER_LIBRARY)" \
		-define:ODRA_TREE_SITTER_LIBRARY="../../$(TREE_SITTER_ODIN_LIBRARY)"

smart-indentation-focused-test: $(RUNTIME_TEST_ADAPTER_LIBRARY) $(RUNTIME_ADAPTER_LIBRARY) $(TREE_SITTER_ODIN_LIBRARY)
	$(RACKET_TEST) src/command/indentation-keymap-test.rkt
	$(ODIN) test src/indentation -vet -warnings-as-errors
	$(ODIN) test src/interaction -vet -warnings-as-errors \
		-define:ODIN_TEST_THREADS=1 \
		-define:ODIN_TEST_NAMES=interaction.contextual_maps_route_input_by_active_owner,interaction.contextual_maps_enforce_unmatched_input_policy
	$(ODIN) test src/terminal_session -vet -warnings-as-errors \
		-define:ODIN_TEST_THREADS=1 \
		-define:ODIN_TEST_NAMES=terminal_session.input_encodes_semantic_keys_and_application_modes
	$(ODIN) test src/command -vet -warnings-as-errors \
		-define:ODIN_TEST_THREADS=1 \
		-define:ODIN_TEST_NAMES=command.indentation_is_one_reversible_group,command.indentation_uses_the_complete_effective_policy,command.backspace_is_smart_only_in_leading_indentation,command.indentation_normalization_is_atomic_and_reversible \
		-define:ODRA_RACKET_RUNTIME_LIBRARY="../../$(RUNTIME_TEST_ADAPTER_LIBRARY)" \
		-extra-linker-flags:"$(RACKET_CS_LIBRARY) $(RACKET_CS_LINK_LIBS)"
	$(ODIN) test src/odra -vet -warnings-as-errors \
		-define:ODIN_TEST_THREADS=1 \
		-define:ODIN_TEST_NAMES=main.terminal_context_map_is_exact_and_contextual \
		-define:ODRA_RACKET_RUNTIME_LIBRARY="../../$(RUNTIME_ADAPTER_LIBRARY)" \
		-define:ODRA_TREE_SITTER_LIBRARY="../../$(TREE_SITTER_ODIN_LIBRARY)" \
		-extra-linker-flags:"$(RACKET_CS_LIBRARY) $(RACKET_CS_LINK_LIBS)"

modal-replace-focused-test: $(RUNTIME_TEST_ADAPTER_LIBRARY) $(RUNTIME_ADAPTER_LIBRARY) $(TREE_SITTER_ODIN_LIBRARY)
	$(RACKET_TEST) src/command/builtins.rkt src/command/keymaps.rkt
	$(ODIN) test src/command -vet -warnings-as-errors \
		-define:ODIN_TEST_THREADS=1 \
		-define:ODIN_TEST_NAMES=command.interaction_profile_commands_use_lifecycle_routes,command.overwrite_replaces_one_grapheme,command.replace_text_input_is_unicode_safe_and_line_bounded \
		-define:ODRA_RACKET_RUNTIME_LIBRARY="../../$(RUNTIME_TEST_ADAPTER_LIBRARY)" \
		-extra-linker-flags:"$(RACKET_CS_LIBRARY) $(RACKET_CS_LINK_LIBS)"
	$(ODIN) test src/status_bar -vet -warnings-as-errors \
		-define:ODIN_TEST_THREADS=1 \
		-define:ODIN_TEST_NAMES=status_bar.status_factory_names_modal_states
	$(ODIN) test src/ui -vet -warnings-as-errors \
		-define:ODIN_TEST_THREADS=1 \
		-define:ODIN_TEST_NAMES=ui.text_view_copies_revisioned_state
	$(ODIN) test src/terminal -vet -warnings-as-errors \
		-define:ODIN_TEST_THREADS=1 \
		-define:ODIN_TEST_NAMES=terminal_frontend.replace_cursor_uses_terminal_underline
	$(ODIN) check src/odra -vet -warnings-as-errors \
		-define:ODRA_RACKET_RUNTIME_LIBRARY="../../$(RUNTIME_ADAPTER_LIBRARY)" \
		-define:ODRA_TREE_SITTER_LIBRARY="../../$(TREE_SITTER_ODIN_LIBRARY)"

modal-repeat-focused-test: $(RUNTIME_TEST_ADAPTER_LIBRARY) $(RUNTIME_ADAPTER_LIBRARY) $(TREE_SITTER_ODIN_LIBRARY)
	$(RACKET_TEST) src/command/builtins.rkt src/command/keymaps.rkt
	$(ODIN) test src/interaction -vet -warnings-as-errors \
		-define:ODIN_TEST_THREADS=1 \
		-define:ODIN_TEST_NAMES=interaction.modal_repeat_retains_semantic_intent,interaction.modal_repeat_rejects_oversized_insert_without_losing_record
	$(ODIN) test src/command -vet -warnings-as-errors \
		-define:ODIN_TEST_THREADS=1 \
		-define:ODIN_TEST_NAMES=command.modal_repeat_replays_insert_semantics_through_history \
		-define:ODRA_RACKET_RUNTIME_LIBRARY="../../$(RUNTIME_TEST_ADAPTER_LIBRARY)" \
		-extra-linker-flags:"$(RACKET_CS_LIBRARY) $(RACKET_CS_LINK_LIBS)"
	$(ODIN) check src/odra -vet -warnings-as-errors \
		-define:ODRA_RACKET_RUNTIME_LIBRARY="../../$(RUNTIME_ADAPTER_LIBRARY)" \
		-define:ODRA_TREE_SITTER_LIBRARY="../../$(TREE_SITTER_ODIN_LIBRARY)"

rectangular-selection-focused-test: $(RUNTIME_TEST_ADAPTER_LIBRARY) $(RUNTIME_ADAPTER_LIBRARY) $(TREE_SITTER_ODIN_LIBRARY)
	$(RACKET_TEST) src/command/builtins.rkt src/command/keymaps.rkt
	$(ODIN) test src/editor -vet -warnings-as-errors \
		-define:ODIN_TEST_THREADS=1 \
		-define:ODIN_TEST_NAMES=editor.selection_shape_is_canonical_and_resets_on_deactivation
	$(ODIN) test src/display -vet -warnings-as-errors \
		-define:ODIN_TEST_THREADS=1 \
		-define:ODIN_TEST_NAMES=display.rectangular_selection_derives_logical_line_ranges,display.maps_rectangular_region_per_logical_row
	$(ODIN) test src/command -vet -warnings-as-errors \
		-define:ODIN_TEST_THREADS=1 \
		-define:ODIN_TEST_NAMES=command.rectangle_commands_copy_edit_and_restore_atomically,command.indentation_is_one_reversible_group,command.replace_text_input_is_unicode_safe_and_line_bounded,command.modal_repeat_replays_insert_semantics_through_history \
		-define:ODRA_RACKET_RUNTIME_LIBRARY="../../$(RUNTIME_TEST_ADAPTER_LIBRARY)" \
		-extra-linker-flags:"$(RACKET_CS_LIBRARY) $(RACKET_CS_LINK_LIBS)"
	$(ODIN) test src/status_bar -vet -warnings-as-errors \
		-define:ODIN_TEST_THREADS=1 \
		-define:ODIN_TEST_NAMES=status_bar.status_factory_names_modal_states
	$(ODIN) test src/terminal -vet -warnings-as-errors \
		-define:ODIN_TEST_THREADS=1 \
		-define:ODIN_TEST_NAMES=terminal_frontend.renderer_highlights_rectangular_ranges_per_row
	$(ODIN) test src/odra -vet -warnings-as-errors \
		-define:ODIN_TEST_THREADS=1 \
		-define:ODIN_TEST_NAMES=main.modal_visual_character_uses_canonical_region,main.modal_visual_line_materializes_complete_lines,main.modal_visual_block_uses_canonical_rectangle,main.pointer_drag_selects_canonical_buffer_range \
		-define:ODRA_RACKET_RUNTIME_LIBRARY="../../$(RUNTIME_ADAPTER_LIBRARY)" \
		-define:ODRA_TREE_SITTER_LIBRARY="../../$(TREE_SITTER_ODIN_LIBRARY)" \
		-extra-linker-flags:"$(RACKET_CS_LIBRARY) $(RACKET_CS_LINK_LIBS)"

rectangular-selection-acceptance: development-build rectangular-selection-focused-test
	ODRA_PTY_EXECUTABLE=$(abspath scripts/run-development-editor.sh) \
		$(PTY_RACKET_TEST) tests/modal_interaction/visual_block_terminal_test.rkt

basic-editor-linked-acceptance: development-build darek-module-focused-test maksym-module-focused-test
	$(ODIN) test src/feedback_workflow -vet -warnings-as-errors \
		-define:ODIN_TEST_THREADS=1
	ODRA_PTY_EXECUTABLE=$(abspath scripts/run-development-editor.sh) \
		bash scripts/run-racket-tests.sh "$(RACO)" "$(BUILD_DIR)" \
		tests/reversible_editing/semantic_terminal_test.rkt \
		tests/modal_interaction/workflow_terminal_test.rkt \
		tests/modal_interaction/visual_block_terminal_test.rkt \
		tests/maksym_workflow/acceptance_test.rkt \
		tests/darek_workflow/acceptance_test.rkt \
		tests/recovery/startup_acceptance_test.rkt

hosting-check: $(ODIN_HOST_PROBE) $(RACKET_HOST_LIBRARY) $(RUNTIME_LIFECYCLE_TEST) $(RUNTIME_MISSING_BOOT_TEST) $(RUNTIME_INVALID_MODULE_TEST) $(RUNTIME_MISSING_BOUNDARY_TEST) $(RUNTIME_INVALID_SHUTDOWN_TEST) $(RUNTIME_CONTRACT_MISMATCH_TEST) $(RUNTIME_COMMAND_BENCHMARK) $(RUNTIME_COMMAND_GC_BENCHMARK) hosting-runtime-check
	$(RACO) make \
		$(RUNTIME_BOUNDARY_SOURCE) \
		tests/hosting/probe.rkt \
		tests/hosting/racket_host_test.rkt \
		tests/hosting/racket_host_benchmark.rkt \
		tests/hosting/benchmark.rkt

hosting-probes: hosting-check
	$(ODIN_HOST_PROBE)
	$(RACKET) tests/hosting/probe.rkt $(abspath $(RACKET_HOST_LIBRARY)) 41

hosting-test: hosting-check $(RUNTIME_TEST_ADAPTER_LIBRARY)
	$(RACKET_TEST) $(RUNTIME_BOUNDARY_SOURCE)
	$(RACKET_TEST) src/hosting/runtime.rkt
	$(RACKET_TEST) src/hosting/scoped-capability.rkt
	$(RACKET_TEST) src/hosting/terminal-bridge.rkt
	$(RACKET_TEST) src/hosting/structural-bridge.rkt
	$(RACKET_TEST) src/hosting/language-service-bridge.rkt
	$(RACKET_TEST) src/hosting/result-provider-bridge.rkt
	$(RACKET_TEST) src/hosting/buffer-session-bridge.rkt
	$(RACKET_TEST) src/hosting/layout-bridge.rkt
	$(RACKET_TEST) src/hosting/ui-role-bridge.rkt
	$(RACKET_TEST) src/hosting/theme-bridge.rkt
	$(RACKET_TEST) src/hosting/project-opening-bridge.rkt
	$(RACKET_TEST) src/hosting/project-promotion-bridge.rkt
	$(RACKET_TEST) src/hosting/workspace-bridge.rkt
	$(RACKET_TEST) src/hosting/named-location-bridge.rkt
	$(RACKET_TEST) src/hosting/named-slot-bridge.rkt
	$(RACKET_TEST) src/hosting/candidate-usage-bridge.rkt
	$(RACKET_TEST) src/hosting/keymap-profile-bridge.rkt
	$(RACKET_TEST) src/hosting/personal-configuration-bridge.rkt
	$(RACKET_TEST) src/history/configuration.rkt
	$(RACKET_TEST) src/history/navigation.rkt
	$(RACKET_TEST) src/layout/display-policy-configuration.rkt
	$(RACKET_TEST) src/command/native-contracts.rkt
	$(RACKET_TEST) src/command/catalog.rkt
	$(RACKET_TEST) src/hosting/command-catalog-bridge.rkt
	$(RACKET_TEST) src/command/language-services.rkt
	$(RACKET_TEST) src/command/results.rkt
	$(RACKET_TEST) src/command/structural.rkt
	$(RACKET_TEST) src/command/transform.rkt
	$(RACKET_TEST) src/command/transaction.rkt
	$(RACKET_TEST) src/command/transfer.rkt
	$(RACKET_TEST) src/command/terminal.rkt
	$(RACKET_TEST) src/command/search-bridge.rkt
	$(RACKET_TEST) src/command/search.rkt
	$(RACKET_TEST) src/command/buffers.rkt
	$(RACKET_TEST) src/command/keymap-model.rkt
	$(RACKET_TEST) src/command/builtins.rkt
	$(RACKET_TEST) src/command/keymaps.rkt
	$(RACKET_TEST) src/command/keymap-inspection.rkt
	$(RACKET_TEST) src/project/candidate-usage.rkt
	$(RACKET_TEST) $(RUNTIME_PROBE_SOURCES)
	$(ODIN) test src/hosting \
		-vet -warnings-as-errors \
		-out:$(HOSTING_BUILD_DIR)/hosting-package-test \
		-define:ODIN_TEST_THREADS=1 \
		-define:ODRA_RACKET_RUNTIME_LIBRARY="../../$(RUNTIME_TEST_ADAPTER_LIBRARY)" \
		-extra-linker-flags:"$(RACKET_CS_LIBRARY) $(RACKET_CS_LINK_LIBS)"
	$(ODIN) test src/command \
		-vet -warnings-as-errors \
		-out:$(HOSTING_BUILD_DIR)/command-package-test \
		-define:ODIN_TEST_THREADS=1 \
		-define:ODRA_RACKET_RUNTIME_LIBRARY="../../$(RUNTIME_TEST_ADAPTER_LIBRARY)" \
		-extra-linker-flags:"$(RACKET_CS_LIBRARY) $(RACKET_CS_LINK_LIBS)"
	for scenario in 1 2 3 4 5 6; do \
		$(ODIN) test src/command \
			-vet -warnings-as-errors \
			-out:$(HOSTING_BUILD_DIR)/command-package-test \
			-define:ODRA_RACKET_RUNTIME_LIBRARY="../../$(RUNTIME_TEST_ADAPTER_LIBRARY)" \
			-define:ODRA_RACKET_COMMAND_SCENARIO=$$scenario \
			-extra-linker-flags:"$(RACKET_CS_LIBRARY) $(RACKET_CS_LINK_LIBS)" || exit 1; \
	done
	for scenario in 1 2 3 4 5 6 7 8; do \
		$(ODIN) test src/command \
			-vet -warnings-as-errors \
			-out:$(HOSTING_BUILD_DIR)/command-package-test \
			-define:ODRA_RACKET_RUNTIME_LIBRARY="../../$(RUNTIME_TEST_ADAPTER_LIBRARY)" \
			-define:ODRA_RACKET_HISTORY_POLICY_SCENARIO=$$scenario \
			-extra-linker-flags:"$(RACKET_CS_LIBRARY) $(RACKET_CS_LINK_LIBS)" || exit 1; \
	done
	for scenario in 1 2 3 4 5 6 7 8; do \
		$(ODIN) test src/command \
			-vet -warnings-as-errors \
			-out:$(HOSTING_BUILD_DIR)/command-package-test \
			-define:ODRA_RACKET_RUNTIME_LIBRARY="../../$(RUNTIME_TEST_ADAPTER_LIBRARY)" \
			-define:ODRA_RACKET_DISPLAY_POLICY_SCENARIO=$$scenario \
			-extra-linker-flags:"$(RACKET_CS_LIBRARY) $(RACKET_CS_LINK_LIBS)" || exit 1; \
	done
	$(RACKET_TEST) tests/hosting/probe.rkt
	$(ODIN_HOST_PROBE)
	$(RACKET) tests/hosting/racket_host_test.rkt $(abspath $(RACKET_HOST_LIBRARY))
	$(RUNTIME_LIFECYCLE_TEST)
	$(RUNTIME_MISSING_BOOT_TEST)
	$(RUNTIME_INVALID_MODULE_TEST)
	$(RUNTIME_MISSING_BOUNDARY_TEST)
	$(RUNTIME_INVALID_SHUTDOWN_TEST)
	$(RUNTIME_CONTRACT_MISMATCH_TEST)

hosting-benchmark: hosting-check
	$(RACKET) tests/hosting/benchmark.rkt \
		$(abspath $(ODIN_HOST_PROBE)) \
		$(abspath $(RACKET_HOST_LIBRARY))
	$(RUNTIME_COMMAND_BENCHMARK)
	$(RUNTIME_COMMAND_GC_BENCHMARK)

command-benchmark: $(RUNTIME_COMMAND_BENCHMARK) $(RUNTIME_COMMAND_GC_BENCHMARK) $(RUNTIME_VIEW_COMMAND_BENCHMARK) $(RUNTIME_TRANSACTION_COMMAND_BENCHMARK) $(RUNTIME_TRANSFER_COMMAND_BENCHMARK) $(RUNTIME_SEARCH_COMMAND_BENCHMARK) $(RUNTIME_BUFFER_SESSION_COMMAND_BENCHMARK)
	$(RUNTIME_COMMAND_BENCHMARK)
	$(RUNTIME_COMMAND_GC_BENCHMARK)
	$(RUNTIME_VIEW_COMMAND_BENCHMARK)
	$(RUNTIME_TRANSACTION_COMMAND_BENCHMARK)
	$(RUNTIME_TRANSFER_COMMAND_BENCHMARK)
	$(RUNTIME_SEARCH_COMMAND_BENCHMARK)
	$(RUNTIME_BUFFER_SESSION_COMMAND_BENCHMARK)

transfer-command-benchmark: $(RUNTIME_TRANSFER_COMMAND_BENCHMARK)
	$(RUNTIME_TRANSFER_COMMAND_BENCHMARK)

search-command-benchmark: $(RUNTIME_SEARCH_COMMAND_BENCHMARK)
	$(RUNTIME_SEARCH_COMMAND_BENCHMARK)

buffer-session-command-benchmark: $(RUNTIME_BUFFER_SESSION_COMMAND_BENCHMARK)
	$(RUNTIME_BUFFER_SESSION_COMMAND_BENCHMARK)

layout-acceptance: $(LAYOUT_ACCEPTANCE) $(ODRA)
	$(ODIN) test tests/multi_view_reference
	$(ODIN) test tests/layout_reference
	$(ODIN) test tests/pane_buffer_reference
	$(ODIN) test src/layout -vet -warnings-as-errors
	$(MAKE) native-command-test
	$(MAKE) layout-resource-study
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/pane_layout/presentation_test.rkt
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/pane_buffer_lifecycle/presentation_test.rkt
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/other_pane_display/presentation_test.rkt
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/command_navigation/area_balance_test.rkt
	$(MAKE) layout-acceptance-runtime

layout-acceptance-runtime: $(LAYOUT_ACCEPTANCE)
	$(LAYOUT_ACCEPTANCE)
	$(LAYOUT_ACCEPTANCE)

buffer-session-acceptance: $(ODRA)
	$(ODIN) test tests/session_reference
	$(MAKE) editor-session-resource-study
	$(ODIN) test src/editor_session
	$(MAKE) native-command-test
	$(MAKE) multibuffer-transaction-benchmark
	$(MAKE) multibuffer-history-benchmark
	$(MAKE) buffer-session-command-benchmark
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/buffer_session/acceptance_test.rkt
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/buffer_session/navigation_test.rkt
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/buffer_session/lifecycle_test.rkt
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/buffer_session/menu_test.rkt

native-command-test: $(RUNTIME_TEST_ADAPTER_LIBRARY) hosting-runtime-check terminal-vendor-build $(TERMINAL_EMULATOR_ADAPTER_LIBRARY) $(INTERACTIVE_SESSION_ADAPTER_LIBRARY)
	$(ODIN) test src/command \
		-vet -warnings-as-errors \
		-define:ODRA_RACKET_RUNTIME_LIBRARY="../../$(RUNTIME_TEST_ADAPTER_LIBRARY)" \
		-define:ODRA_INTERACTIVE_SESSION_ADAPTER_LIBRARY="../../$(INTERACTIVE_SESSION_ADAPTER_LIBRARY)" \
		-define:ODRA_TERMINAL_EMULATOR_ADAPTER_LIBRARY="../../$(TERMINAL_EMULATOR_ADAPTER_LIBRARY)" \
		-define:ODRA_TERMINAL_EMULATOR_VENDOR_LIBRARY="../../$(TERMINAL_VENDOR_LIBRARY)" \
		-extra-linker-flags:"$(RACKET_CS_LIBRARY) $(RACKET_CS_LINK_LIBS)"

$(NATIVE_COMMAND_BENCHMARK): tests/native_command_benchmark/main.odin $(wildcard src/command/*.odin src/interaction/*.odin src/display/*.odin src/view/*.odin src/search/*.odin src/editor/*.odin src/text/*.odin src/history/*.odin src/transaction/*.odin) $(RUNTIME_ADAPTER_LIBRARY)
	$(ODIN) build tests/native_command_benchmark \
		-o:speed \
		-vet -warnings-as-errors \
		-out:$@ \
		-define:ODRA_RACKET_RUNTIME_LIBRARY="../../$(RUNTIME_ADAPTER_LIBRARY)" \
		-extra-linker-flags:"$(RACKET_CS_LIBRARY) $(RACKET_CS_LINK_LIBS)"

native-command-benchmark: $(NATIVE_COMMAND_BENCHMARK)
	$(ODIN) version
	uname -srm
	$(NATIVE_COMMAND_BENCHMARK)

$(TRANSACTION_BENCHMARK): tests/transaction_benchmark/main.odin $(wildcard src/transaction/*.odin src/history/*.odin src/editor/*.odin src/text/*.odin)
	mkdir -p $(BUILD_DIR)
	$(ODIN) build tests/transaction_benchmark \
		-o:speed \
		-vet -warnings-as-errors \
		-out:$@

transaction-benchmark: $(TRANSACTION_BENCHMARK)
	$(ODIN) version
	uname -srm
	$(TRANSACTION_BENCHMARK)
	$(MAKE) multibuffer-transaction-benchmark

$(MULTIBUFFER_TRANSACTION_BENCHMARK): tests/multibuffer_transaction_benchmark/main.odin $(wildcard src/transaction/*.odin src/history/*.odin src/editor/*.odin src/text/*.odin)
	mkdir -p $(BUILD_DIR)
	$(ODIN) build tests/multibuffer_transaction_benchmark \
		-o:speed \
		-vet -warnings-as-errors \
		-out:$@

multibuffer-transaction-benchmark: $(MULTIBUFFER_TRANSACTION_BENCHMARK)
	$(MULTIBUFFER_TRANSACTION_BENCHMARK)

$(MULTIBUFFER_HISTORY_BENCHMARK): tests/multibuffer_history_benchmark/main.odin $(wildcard src/transaction/*.odin src/history/*.odin src/editor/*.odin src/text/*.odin)
	mkdir -p $(BUILD_DIR)
	$(ODIN) build tests/multibuffer_history_benchmark \
		-o:speed \
		-vet -warnings-as-errors \
		-out:$@

multibuffer-history-benchmark: $(MULTIBUFFER_HISTORY_BENCHMARK)
	$(ODIN) version
	uname -srm
	$(MULTIBUFFER_HISTORY_BENCHMARK)

$(TRANSACTION_FUZZ): tests/transaction_fuzz/main.odin $(wildcard src/transaction/*.odin src/history/*.odin src/editor/*.odin src/text/*.odin)
	mkdir -p $(BUILD_DIR)
	$(ODIN) build tests/transaction_fuzz \
		-o:speed \
		-vet -warnings-as-errors \
		-out:$@

transaction-fuzz: $(TRANSACTION_FUZZ)
	$(TRANSACTION_FUZZ)

$(HISTORY_RESOURCE_STUDY): tests/history_resource_study/main.odin $(wildcard src/history/*.odin src/editor/*.odin src/view/*.odin src/search/*.odin src/text/*.odin)
	mkdir -p $(BUILD_DIR)
	$(ODIN) build tests/history_resource_study \
		-o:speed \
		-vet -warnings-as-errors \
		-out:$@

history-resource-study: $(HISTORY_RESOURCE_STUDY)
	$(ODIN) version
	uname -srm
	$(HISTORY_RESOURCE_STUDY)

$(KILL_RING_RESOURCE_STUDY): tests/kill_ring_resource_study/main.odin
	mkdir -p $(BUILD_DIR)
	$(ODIN) build tests/kill_ring_resource_study \
		-o:speed \
		-vet -warnings-as-errors \
		-out:$@

kill-ring-resource-study: $(KILL_RING_RESOURCE_STUDY)
	$(ODIN) version
	uname -srm
	$(KILL_RING_RESOURCE_STUDY)

$(FEEDBACK_RESOURCE_STUDY): tests/feedback_resource_study/main.odin $(wildcard src/feedback/*.odin)
	mkdir -p $(BUILD_DIR)
	$(ODIN) build tests/feedback_resource_study \
		-o:speed \
		-vet -warnings-as-errors \
		-out:$@

feedback-resource-study: $(FEEDBACK_RESOURCE_STUDY)
	$(ODIN) version
	uname -srm
	$(FEEDBACK_RESOURCE_STUDY)

$(SEARCH_RESOURCE_STUDY): tests/search_resource_study/main.odin $(wildcard src/command/*.odin src/display/*.odin src/view/*.odin src/search/*.odin src/editor/*.odin src/text/*.odin src/history/*.odin src/transaction/*.odin src/document/*.odin src/interaction/*.odin src/bridge/*.odin src/hosting/*.odin) $(RUNTIME_ADAPTER_LIBRARY)
	mkdir -p $(BUILD_DIR)
	$(ODIN) build tests/search_resource_study \
		-o:speed \
		-vet -warnings-as-errors \
		-out:$@ \
		-define:ODRA_RACKET_RUNTIME_LIBRARY="../../$(RUNTIME_ADAPTER_LIBRARY)" \
		-extra-linker-flags:"$(RACKET_CS_LIBRARY) $(RACKET_CS_LINK_LIBS)"

search-resource-study: $(SEARCH_RESOURCE_STUDY)
	$(ODIN) version
	uname -srm
	$(SEARCH_RESOURCE_STUDY)

$(RESULT_SET_RESOURCE_STUDY): tests/result_set_resource_study/main.odin $(wildcard src/result_set/*.odin src/editor/*.odin src/text/*.odin src/history/*.odin src/transaction/*.odin src/view/*.odin)
	mkdir -p $(BUILD_DIR)
	$(ODIN) build tests/result_set_resource_study \
		-o:speed \
		-vet -warnings-as-errors \
		-out:$@

result-set-resource-study: $(RESULT_SET_RESOURCE_STUDY)
	$(ODIN) version
	uname -srm
	$(RESULT_SET_RESOURCE_STUDY)

$(STATUS_BAR_RESOURCE_STUDY): tests/status_bar_resource_study/main.odin $(wildcard src/status_bar/*.odin src/display/*.odin src/editor/*.odin src/text/*.odin src/view/*.odin src/search/*.odin)
	mkdir -p $(BUILD_DIR)
	$(ODIN) build tests/status_bar_resource_study \
		-o:speed \
		-vet -warnings-as-errors \
		-out:$@

status-bar-resource-study: $(STATUS_BAR_RESOURCE_STUDY)
	$(ODIN) version
	uname -srm
	$(STATUS_BAR_RESOURCE_STUDY)

$(SYMBOL_NAVIGATION_RESOURCE_STUDY): tests/symbol_navigation_resource_study/main.odin $(wildcard src/language/*.odin src/editor/*.odin src/document/*.odin) $(TREE_SITTER_ODIN_LIBRARY)
	mkdir -p $(BUILD_DIR)
	$(ODIN) build tests/symbol_navigation_resource_study \
		-o:speed \
		-vet -warnings-as-errors \
		-out:$@ \
		-define:ODRA_TREE_SITTER_LIBRARY="../../$(TREE_SITTER_ODIN_LIBRARY)"

symbol-navigation-resource-study: $(SYMBOL_NAVIGATION_RESOURCE_STUDY)
	$(ODIN) version
	uname -srm
	$(SYMBOL_NAVIGATION_RESOURCE_STUDY)

$(PROJECT_SEARCH_RESOURCE_STUDY): tests/project_search_resource_study/main.odin $(wildcard src/project_search/*.odin src/project/*.odin src/search/*.odin)
	mkdir -p $(BUILD_DIR)
	$(ODIN) build tests/project_search_resource_study \
		-o:speed \
		-vet -warnings-as-errors \
		-out:$@

project-search-resource-study: $(PROJECT_SEARCH_RESOURCE_STUDY)
	$(ODIN) version
	uname -srm
	$(PROJECT_SEARCH_RESOURCE_STUDY)

$(EDITOR_SESSION_RESOURCE_STUDY): tests/editor_session_resource_study/main.odin $(wildcard tests/session_reference/*.odin)
	mkdir -p $(BUILD_DIR)
	$(ODIN) build tests/editor_session_resource_study \
		-o:speed \
		-vet -warnings-as-errors \
		-out:$@

editor-session-resource-study: $(EDITOR_SESSION_RESOURCE_STUDY)
	$(ODIN) version
	uname -srm
	$(EDITOR_SESSION_RESOURCE_STUDY)

$(PROJECT_RESOURCE_STUDY): tests/project_resource_study/main.odin $(wildcard tests/project_reference/*.odin)
	mkdir -p $(BUILD_DIR)
	$(ODIN) build tests/project_resource_study \
		-o:speed \
		-vet -warnings-as-errors \
		-out:$@

project-resource-study: $(PROJECT_RESOURCE_STUDY)
	$(ODIN) version
	uname -srm
	$(PROJECT_RESOURCE_STUDY)

$(KSAWERY_RESOURCE_STUDY): tests/ksawery_resource_study/main.odin
	mkdir -p $(BUILD_DIR)
	$(ODIN) build tests/ksawery_resource_study \
		-o:speed \
		-vet -warnings-as-errors \
		-out:$@

ksawery-resource-study: $(KSAWERY_RESOURCE_STUDY)
	$(ODIN) version
	uname -srm
	$(KSAWERY_RESOURCE_STUDY)

$(KSAWERY_DIFF_UNIT_STUDY): tests/ksawery_diff_unit_study/main.odin
	mkdir -p $(BUILD_DIR)
	$(ODIN) build tests/ksawery_diff_unit_study \
		-o:speed \
		-vet -warnings-as-errors \
		-out:$@

ksawery-diff-unit-study: $(KSAWERY_DIFF_UNIT_STUDY)
	$(ODIN) version
	uname -srm
	$(KSAWERY_DIFF_UNIT_STUDY)

$(KSAWERY_HISTORY_RESOURCE_STUDY): tests/ksawery_history_resource_study/main.odin
	mkdir -p $(BUILD_DIR)
	$(ODIN) build tests/ksawery_history_resource_study \
		-o:speed \
		-vet -warnings-as-errors \
		-out:$@

ksawery-history-resource-study: $(KSAWERY_HISTORY_RESOURCE_STUDY)
	$(ODIN) version
	uname -srm
	$(KSAWERY_HISTORY_RESOURCE_STUDY)

$(KSAWERY_REF_RESOURCE_STUDY): tests/ksawery_ref_resource_study/main.odin
	mkdir -p $(BUILD_DIR)
	$(ODIN) build tests/ksawery_ref_resource_study \
		-o:speed \
		-vet -warnings-as-errors \
		-out:$@

ksawery-ref-resource-study: $(KSAWERY_REF_RESOURCE_STUDY)
	$(ODIN) version
	uname -srm
	$(KSAWERY_REF_RESOURCE_STUDY)

$(KSAWERY_PROCESS_RESOURCE_STUDY): tests/ksawery_process_resource_study/main.odin $(filter-out %_test.odin,$(wildcard src/ksawery/*.odin))
	mkdir -p $(BUILD_DIR)
	$(ODIN) build tests/ksawery_process_resource_study \
		-o:speed \
		-vet -warnings-as-errors \
		-out:$@

ksawery-process-resource-study: $(KSAWERY_PROCESS_RESOURCE_STUDY)
	$(ODIN) version
	uname -srm
	$(KSAWERY_PROCESS_RESOURCE_STUDY)

ksawery-process-focused-test:
	$(ODIN) test tests/ksawery_process_focused \
		-define:ODIN_TEST_THREADS=1 \
		-vet -warnings-as-errors
	$(ODIN) test tests/ksawery_operation_coordinator_focused \
		-define:ODIN_TEST_THREADS=1 \
		-vet -warnings-as-errors
	$(ODIN) test tests/ksawery_process_presentation_focused \
		-define:ODIN_TEST_THREADS=1 \
		-vet -warnings-as-errors

$(KSAWERY_SEQUENCE_RESOURCE_STUDY): tests/ksawery_sequence_resource_study/main.odin
	mkdir -p $(BUILD_DIR)
	$(ODIN) build tests/ksawery_sequence_resource_study \
		-o:speed \
		-vet -warnings-as-errors \
		-out:$@

ksawery-sequence-resource-study: $(KSAWERY_SEQUENCE_RESOURCE_STUDY)
	$(ODIN) version
	uname -srm
	$(KSAWERY_SEQUENCE_RESOURCE_STUDY)

ksawery-sequence-focused-test:
	$(ODIN) test tests/ksawery_sequence_focused \
		-define:ODIN_TEST_THREADS=1 \
		-vet -warnings-as-errors

$(KSAWERY_EXTENSION_RESOURCE_STUDY): tests/ksawery_extension_resource_study/main.odin
	mkdir -p $(BUILD_DIR)
	$(ODIN) build tests/ksawery_extension_resource_study \
		-o:speed \
		-vet -warnings-as-errors \
		-out:$@

ksawery-extension-resource-study: $(KSAWERY_EXTENSION_RESOURCE_STUDY)
	$(ODIN) version
	uname -srm
	$(KSAWERY_EXTENSION_RESOURCE_STUDY)

ksawery-extension-focused-test:
	$(ODIN) test tests/ksawery_extension_focused \
		-define:ODIN_TEST_THREADS=1 \
		-vet -warnings-as-errors
	$(RACKET_TEST) tests/ksawery_extensions/contribution_model_test.rkt
	$(RACKET_TEST) tests/ksawery_extensions/provider_lifecycle_test.rkt
	$(RACKET_TEST) tests/ksawery_extensions/annotation_model_test.rkt
	$(RACKET_TEST) tests/ksawery_extensions/command_model_test.rkt
	$(RACKET_TEST) tests/ksawery_extensions/command_provider_runtime_test.rkt
	$(RACKET_TEST) tests/ksawery_extensions/external_operation_command_runtime_test.rkt
	$(RACKET_TEST) tests/ksawery_extensions/operation_model_test.rkt
	$(RACKET_TEST) tests/ksawery_extensions/conflict_assistance_model_test.rkt
	$(RACKET_TEST) tests/ksawery_extensions/conflict_assistance_provider_runtime_test.rkt
	$(RACKET_TEST) tests/ksawery_extensions/annotation_provider_runtime_test.rkt
	$(RACKET_TEST) tests/ksawery_extensions/status_section_model_test.rkt
	$(RACKET_TEST) tests/ksawery_extensions/status_provider_runtime_test.rkt

ksawery-workflow-coordination-focused-test:
	$(ODIN) check src/odra -vet -warnings-as-errors
	$(RACKET) scripts/check-ksawery-workflow-coordination.rkt

ksawery-acceptance: ksawery-change-acceptance

ksawery-change-acceptance: $(ODRA)
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/ksawery_workflow/acceptance_test.rkt

ksawery-commit-acceptance: $(ODRA)
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/ksawery_workflow/commit_revision_acceptance_test.rkt

ksawery-refs-acceptance: $(ODRA)
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/ksawery_workflow/refs_synchronization_acceptance_test.rkt

ksawery-process-acceptance: $(ODRA)
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/ksawery_workflow/process_workflow_acceptance_test.rkt

ksawery-sequence-acceptance: $(ODRA)
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/ksawery_workflow/sequence_workflow_acceptance_test.rkt

ksawery-extension-acceptance: $(ODRA)
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/ksawery_workflow/extension_workflow_acceptance_test.rkt

$(MAKSYM_RESOURCE_STUDY): tests/maksym_resource_study/main.odin $(wildcard src/filesystem/*.odin src/maksym/*.odin)
	mkdir -p $(BUILD_DIR)
	$(ODIN) build tests/maksym_resource_study \
		-o:speed \
		-vet -warnings-as-errors \
		-out:$@

maksym-resource-study: $(MAKSYM_RESOURCE_STUDY)
	$(ODIN) version
	uname -srm
	$(MAKSYM_RESOURCE_STUDY)

maksym-workflow-acceptance: $(ODRA)
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/maksym_workflow/acceptance_test.rkt

$(DAREK_RESOURCE_STUDY): tests/darek_resource_study/main.odin $(wildcard src/filesystem/*.odin src/darek/*.odin src/ui/*.odin)
	mkdir -p $(BUILD_DIR)
	$(ODIN) build tests/darek_resource_study \
		-o:speed \
		-vet -warnings-as-errors \
		-out:$@

darek-resource-study: $(DAREK_RESOURCE_STUDY)
	$(ODIN) version
	uname -srm
	$(DAREK_RESOURCE_STUDY)

darek-workflow-acceptance: $(ODRA)
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/darek_workflow/acceptance_test.rkt

interactive-stack-check: $(ODRA) $(ODRA_DEVELOPMENT)
	$(RACKET_TEST) scripts/check-interactive-stack.rkt
	$(RACKET) scripts/check-interactive-stack.rkt \
		--binary $(ODRA) \
		--minimum-stack-kib $(INTERACTIVE_STACK_KIB)
	$(RACKET) scripts/check-interactive-stack.rkt \
		--binary $(ODRA_DEVELOPMENT) \
		--minimum-stack-kib $(INTERACTIVE_STACK_KIB)

interactive-stack-runtime-acceptance: $(ODRA)
	@set -e; \
	ulimit -s $(INTERACTIVE_STACK_KIB) || { \
		echo "interactive-stack: cannot establish $(INTERACTIVE_STACK_KIB) KiB stack" >&2; \
		exit 1; \
	}; \
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/darek_workflow/acceptance_test.rkt; \
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/workspace_composition/workflow_terminal_test.rkt

interactive-stack-acceptance: interactive-stack-check interactive-stack-runtime-acceptance

operational-state-test:
	$(RACO) make \
		src/storage/durable-file.rkt \
		src/storage/record-codec.rkt \
		src/storage/record-store.rkt \
		src/project/records.rkt \
		src/project/persistence.rkt \
		src/workspace/records.rkt \
		src/workspace/persistence.rkt \
		src/saved-state/records.rkt \
		src/saved-state/persistence.rkt \
		src/migration/records.rkt \
		src/migration/persistence.rkt \
		src/migration/legacy-inventory.rkt \
		tests/operational_state/durable_file_test.rkt \
		tests/operational_state/records_test.rkt \
		tests/operational_state/legacy_inventory_test.rkt \
		tests/operational_state/fault_test.rkt
	$(RACKET_TEST) tests/operational_state/durable_file_test.rkt
	$(RACKET_TEST) tests/operational_state/records_test.rkt
	$(RACKET_TEST) tests/operational_state/legacy_inventory_test.rkt
	$(RACKET_TEST) tests/operational_state/fault_test.rkt

project-promotion-test: $(ODRA)
	$(RACO) make \
		src/project/promotion.rkt \
		src/project/promotion-suppressions.rkt \
		src/hosting/project-promotion-bridge.rkt \
		tests/project_promotion/publication_test.rkt \
		tests/project_promotion/suppressions_test.rkt
	$(RACKET_TEST) src/hosting/project-promotion-bridge.rkt
	$(RACKET_TEST) tests/project_promotion/publication_test.rkt
	$(RACKET_TEST) tests/project_promotion/suppressions_test.rkt
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/project_promotion/workflow_terminal_test.rkt

workspace-composition-test:
	$(RACO) make \
		src/workspace/records.rkt \
		src/workspace/persistence.rkt \
		src/workspace/management.rkt \
		tests/workspace_composition/workspaces_test.rkt
	$(RACKET_TEST) tests/workspace_composition/workspaces_test.rkt

workspace-composition-acceptance: $(ODRA)
	$(MAKE) workspace-composition-test
	$(ODIN) test src/workspace -vet -warnings-as-errors
	$(ODIN) test src/editor_session -vet -warnings-as-errors
	$(ODIN) test src/interaction -vet -warnings-as-errors
	$(ODIN) test src/bridge -vet -warnings-as-errors
	$(ODIN) test src/command -vet -warnings-as-errors \
		-define:ODRA_RACKET_RUNTIME_LIBRARY="../../$(RUNTIME_ADAPTER_LIBRARY)" \
		-extra-linker-flags:"$(RACKET_CS_LIBRARY) $(RACKET_CS_LINK_LIBS)"
	$(ODIN) test src/odra -vet -warnings-as-errors \
		-define:ODRA_RACKET_RUNTIME_LIBRARY="../../$(RUNTIME_ADAPTER_LIBRARY)" \
		-define:ODRA_TREE_SITTER_LIBRARY="../../$(TREE_SITTER_ODIN_LIBRARY)" \
		-extra-linker-flags:"$(RACKET_CS_LIBRARY) $(RACKET_CS_LINK_LIBS)"
	$(RACKET_TEST) src/hosting/workspace-bridge.rkt
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/workspace_composition/workflow_terminal_test.rkt

project-workspace-migration-test:
	$(RACO) make \
		src/migration/legacy-inventory.rkt \
		src/migration/planner.rkt \
		src/migration/executor.rkt \
		scripts/migrate-project-workspaces.rkt \
		tests/project_workspace_migration/planner_test.rkt \
		tests/project_workspace_migration/migration_test.rkt \
		tests/project_workspace_migration/cli_test.rkt
	$(RACKET_TEST) tests/project_workspace_migration/planner_test.rkt
	$(RACKET_TEST) tests/project_workspace_migration/migration_test.rkt
	$(RACKET_TEST) tests/project_workspace_migration/cli_test.rkt

project-workspace-migration-acceptance: $(ODRA)
	$(MAKE) project-workspace-migration-test
	$(ODIN) test src/project -vet -warnings-as-errors
	$(ODIN) test src/workspace -vet -warnings-as-errors
	$(ODIN) test src/editor_session -vet -warnings-as-errors
	$(ODIN) test src/command -vet -warnings-as-errors \
		-define:ODRA_RACKET_RUNTIME_LIBRARY="../../$(RUNTIME_ADAPTER_LIBRARY)" \
		-extra-linker-flags:"$(RACKET_CS_LIBRARY) $(RACKET_CS_LINK_LIBS)"
	$(ODIN) test src/odra -vet -warnings-as-errors \
		-define:ODRA_RACKET_RUNTIME_LIBRARY="../../$(RUNTIME_ADAPTER_LIBRARY)" \
		-define:ODRA_TREE_SITTER_LIBRARY="../../$(TREE_SITTER_ODIN_LIBRARY)" \
		-extra-linker-flags:"$(RACKET_CS_LIBRARY) $(RACKET_CS_LINK_LIBS)"
	$(MAKE) project-workspace-migration-terminal-test

project-workspace-migration-terminal-test: $(ODRA) $(DAREK_MODULE_LIBRARY) $(PRODUCT_MODULE_MANIFEST)
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
	ODRA_PRODUCT_MODULE_MANIFEST=$(abspath $(PRODUCT_MODULE_MANIFEST)) \
		$(PTY_RACKET_TEST) \
		tests/support/terminal-readiness.rkt \
		tests/support/terminal-scenario-result.rkt \
		tests/project_workspace_migration/workflow_terminal_test.rkt

$(CANDIDATE_RESOURCE_STUDY): tests/candidate_resource_study/main.odin tests/candidate_reference/model.odin
	mkdir -p $(BUILD_DIR)
	$(ODIN) build tests/candidate_resource_study \
		-o:speed \
		-vet -warnings-as-errors \
		-out:$@

candidate-resource-study: $(CANDIDATE_RESOURCE_STUDY)
	$(ODIN) version
	uname -srm
	$(CANDIDATE_RESOURCE_STUDY)

$(CANDIDATE_HISTORY_RESOURCE_STUDY): tests/candidate_history_resource_study/main.odin $(wildcard tests/candidate_history_reference/*.odin)
	mkdir -p $(BUILD_DIR)
	$(ODIN) build tests/candidate_history_resource_study \
		-o:speed \
		-vet -warnings-as-errors \
		-out:$@

candidate-history-resource-study: $(CANDIDATE_HISTORY_RESOURCE_STUDY)
	$(ODIN) version
	uname -srm
	$(CANDIDATE_HISTORY_RESOURCE_STUDY)

$(CANDIDATE_NAVIGATION_RESOURCE_STUDY): tests/candidate_navigation_resource_study/main.odin $(wildcard src/interaction/*.odin src/search/*.odin)
	mkdir -p $(BUILD_DIR)
	$(ODIN) build tests/candidate_navigation_resource_study \
		-o:speed \
		-vet -warnings-as-errors \
		-out:$@

candidate-navigation-resource-study: $(CANDIDATE_NAVIGATION_RESOURCE_STUDY)
	$(ODIN) version
	uname -srm
	$(CANDIDATE_NAVIGATION_RESOURCE_STUDY)
	$(MAKE) candidate-resource-study
	$(MAKE) candidate-history-resource-study

$(MULTI_VIEW_RESOURCE_STUDY): tests/multi_view_resource_study/main.odin $(wildcard tests/multi_view_reference/*.odin)
	mkdir -p $(BUILD_DIR)
	$(ODIN) build tests/multi_view_resource_study \
		-o:speed \
		-vet -warnings-as-errors \
		-out:$@

multi-view-resource-study: $(MULTI_VIEW_RESOURCE_STUDY)
	$(ODIN) version
	uname -srm
	$(MULTI_VIEW_RESOURCE_STUDY)

$(LAYOUT_RESOURCE_STUDY): tests/layout_resource_study/main.odin $(wildcard src/layout/*.odin src/view/*.odin src/search/*.odin src/editor/*.odin src/text/*.odin)
	mkdir -p $(BUILD_DIR)
	$(ODIN) build tests/layout_resource_study \
		-o:speed \
		-vet -warnings-as-errors \
		-out:$@

layout-resource-study: $(LAYOUT_RESOURCE_STUDY)
	$(ODIN) version
	uname -srm
	$(LAYOUT_RESOURCE_STUDY)

candidate-navigation-focused-acceptance: $(ODRA)
	$(ODIN) test tests/candidate_reference
	$(ODIN) test tests/candidate_history_reference
	$(ODIN) test tests/candidate_kernel
	$(ODIN) test src/interaction -vet -warnings-as-errors
	$(ODIN) test src/project -vet -warnings-as-errors
	$(RACKET_TEST) src/project/candidate-usage.rkt src/hosting/candidate-usage-bridge.rkt
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/command_navigation/navigation_test.rkt
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/buffer_session/navigation_test.rkt
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/project_context/command_workflows_test.rkt

candidate-navigation-acceptance: candidate-navigation-focused-acceptance
	$(ODIN) test src/odra -vet -warnings-as-errors \
		-define:ODRA_RACKET_RUNTIME_LIBRARY="../../$(RUNTIME_ADAPTER_LIBRARY)" \
		-define:ODRA_TREE_SITTER_LIBRARY="../../$(TREE_SITTER_ODIN_LIBRARY)" \
		-extra-linker-flags:"$(RACKET_CS_LIBRARY) $(RACKET_CS_LINK_LIBS)"

theme-workflow-acceptance: $(ODRA)
	ODRA_PTY_EXECUTABLE=$(abspath $(ODRA)) \
		$(PTY_RACKET_TEST) tests/theme_workflow/workflow_test.rkt

$(KILL_RING_BENCHMARK): tests/kill_ring_benchmark/main.odin $(wildcard src/kill_ring/*.odin)
	mkdir -p $(BUILD_DIR)
	$(ODIN) build tests/kill_ring_benchmark \
		-o:speed \
		-vet -warnings-as-errors \
		-out:$@

kill-ring-benchmark: $(KILL_RING_BENCHMARK)
	$(ODIN) version
	uname -srm
	$(KILL_RING_BENCHMARK)

$(HISTORY_FUZZ): tests/history_fuzz/main.odin $(wildcard src/history/*.odin src/transaction/*.odin src/editor/*.odin src/text/*.odin src/view/*.odin src/search/*.odin)
	mkdir -p $(BUILD_DIR)
	$(ODIN) build tests/history_fuzz \
		-o:speed \
		-vet -warnings-as-errors \
		-out:$@

history-fuzz: $(HISTORY_FUZZ)
	$(HISTORY_FUZZ)

hosting-evidence:
	$(MAKE) hosting-test
	$(MAKE) hosting-benchmark

user-guide-check:
	$(RACKET) scripts/check-user-guide.rkt
	$(RACKET_TEST) scripts/check-user-guide.rkt

user-guide-acceptance-check:
	$(RACKET) scripts/check-user-guide-acceptance.rkt
	$(RACKET_TEST) scripts/check-user-guide-acceptance.rkt

docs-check: command-reference-check user-guide-check user-guide-acceptance-check user-guide-usability-check
	mkdir -p $(BUILD_DIR)/docs
	$(ODIN) doc src/text -in-source-order > $(BUILD_DIR)/docs/text.txt
	$(ODIN) doc src/editor -in-source-order > $(BUILD_DIR)/docs/editor.txt
	$(ODIN) doc src/editor_session -in-source-order > $(BUILD_DIR)/docs/editor_session.txt
	$(ODIN) doc src/transaction -in-source-order > $(BUILD_DIR)/docs/transaction.txt
	$(ODIN) doc src/history -in-source-order > $(BUILD_DIR)/docs/history.txt
	$(ODIN) doc src/kill_ring -in-source-order > $(BUILD_DIR)/docs/kill_ring.txt
	$(ODIN) doc src/feedback -in-source-order > $(BUILD_DIR)/docs/feedback.txt
	$(ODIN) doc src/feedback_routing -in-source-order > $(BUILD_DIR)/docs/feedback_routing.txt
	$(ODIN) doc src/feedback_workflow -in-source-order > $(BUILD_DIR)/docs/feedback_workflow.txt
	$(ODIN) doc src/view -in-source-order > $(BUILD_DIR)/docs/view.txt
	$(ODIN) doc src/layout -in-source-order > $(BUILD_DIR)/docs/layout.txt
	$(ODIN) doc src/display -in-source-order > $(BUILD_DIR)/docs/display.txt
	$(ODIN) doc src/terminal -in-source-order > $(BUILD_DIR)/docs/terminal.txt
	$(ODIN) doc src/odra -in-source-order > $(BUILD_DIR)/docs/odra.txt
	$(ODIN) doc src/bridge -in-source-order > $(BUILD_DIR)/docs/bridge.txt
	$(ODIN) doc src/hosting -in-source-order > $(BUILD_DIR)/docs/hosting.txt
	$(ODIN) doc src/command -in-source-order > $(BUILD_DIR)/docs/command.txt
	$(ODIN) doc src/extension -in-source-order > $(BUILD_DIR)/docs/extension.txt
	$(ODIN) doc src/interaction -in-source-order > $(BUILD_DIR)/docs/interaction.txt
	$(ODIN) doc src/document -in-source-order > $(BUILD_DIR)/docs/document.txt
	$(ODIN) doc src/search -in-source-order > $(BUILD_DIR)/docs/search.txt
	$(ODIN) doc src/project -in-source-order > $(BUILD_DIR)/docs/project.txt
	$(ODIN) doc src/project_search -in-source-order > $(BUILD_DIR)/docs/project_search.txt
	$(ODIN) doc src/workspace -in-source-order > $(BUILD_DIR)/docs/workspace.txt
	$(ODIN) doc src/ui -in-source-order > $(BUILD_DIR)/docs/ui.txt
	$(ODIN) doc src/theme -in-source-order > $(BUILD_DIR)/docs/theme.txt
	$(ODIN) doc src/status_bar -in-source-order > $(BUILD_DIR)/docs/status_bar.txt
	$(ODIN) doc src/gutter -in-source-order > $(BUILD_DIR)/docs/gutter.txt
	$(ODIN) doc src/language -in-source-order > $(BUILD_DIR)/docs/language.txt
	$(ODIN) doc src/jan_editing -in-source-order > $(BUILD_DIR)/docs/jan_editing.txt
	$(ODIN) doc src/jan_planning -in-source-order > $(BUILD_DIR)/docs/jan_planning.txt
	$(ODIN) doc src/syntax_workflow -in-source-order > $(BUILD_DIR)/docs/syntax_workflow.txt
	$(ODIN) doc src/language_service -in-source-order > $(BUILD_DIR)/docs/language_service.txt
	$(ODIN) doc src/language_service_workflow -in-source-order > $(BUILD_DIR)/docs/language_service_workflow.txt
	$(ODIN) doc src/completion -in-source-order > $(BUILD_DIR)/docs/completion.txt
	$(ODIN) doc src/interactive_session -in-source-order > $(BUILD_DIR)/docs/interactive_session.txt
	$(ODIN) doc src/terminal_session -in-source-order > $(BUILD_DIR)/docs/terminal_session.txt
	test -s $(BUILD_DIR)/docs/text.txt \
		-a -s $(BUILD_DIR)/docs/editor.txt \
		-a -s $(BUILD_DIR)/docs/editor_session.txt \
		-a -s $(BUILD_DIR)/docs/transaction.txt \
		-a -s $(BUILD_DIR)/docs/history.txt \
		-a -s $(BUILD_DIR)/docs/kill_ring.txt \
		-a -s $(BUILD_DIR)/docs/feedback.txt \
		-a -s $(BUILD_DIR)/docs/feedback_routing.txt \
		-a -s $(BUILD_DIR)/docs/feedback_workflow.txt \
		-a -s $(BUILD_DIR)/docs/view.txt \
		-a -s $(BUILD_DIR)/docs/layout.txt \
		-a -s $(BUILD_DIR)/docs/display.txt \
		-a -s $(BUILD_DIR)/docs/terminal.txt \
		-a -s $(BUILD_DIR)/docs/odra.txt \
		-a -s $(BUILD_DIR)/docs/bridge.txt \
		-a -s $(BUILD_DIR)/docs/hosting.txt \
		-a -s $(BUILD_DIR)/docs/command.txt \
		-a -s $(BUILD_DIR)/docs/extension.txt \
		-a -s $(BUILD_DIR)/docs/interaction.txt \
		-a -s $(BUILD_DIR)/docs/document.txt \
		-a -s $(BUILD_DIR)/docs/search.txt \
		-a -s $(BUILD_DIR)/docs/project.txt \
		-a -s $(BUILD_DIR)/docs/project_search.txt \
		-a -s $(BUILD_DIR)/docs/workspace.txt \
		-a -s $(BUILD_DIR)/docs/ui.txt \
		-a -s $(BUILD_DIR)/docs/theme.txt \
		-a -s $(BUILD_DIR)/docs/status_bar.txt \
		-a -s $(BUILD_DIR)/docs/gutter.txt \
		-a -s $(BUILD_DIR)/docs/language.txt \
		-a -s $(BUILD_DIR)/docs/jan_editing.txt \
		-a -s $(BUILD_DIR)/docs/jan_planning.txt \
		-a -s $(BUILD_DIR)/docs/syntax_workflow.txt \
		-a -s $(BUILD_DIR)/docs/language_service.txt \
		-a -s $(BUILD_DIR)/docs/language_service_workflow.txt \
		-a -s $(BUILD_DIR)/docs/completion.txt \
		-a -s $(BUILD_DIR)/docs/interactive_session.txt \
		-a -s $(BUILD_DIR)/docs/terminal_session.txt
	$(RACKET) scripts/check-odin-doc-comments.rkt $(BUILD_DIR)/docs/*.txt
	$(RACKET) scripts/check-markdown-links.rkt docs ops

source-hygiene-check: source-license-check
	$(RACKET) scripts/check-pty-test-isolation.rkt
	@status=0; \
	git grep -nI -E '[[:blank:]]+$$' -- ':!third_party/**' ':!vendor/**' || status=$$?; \
	if [ $$status -eq 0 ]; then \
		echo "source-hygiene: trailing whitespace detected" >&2; \
		exit 1; \
	fi; \
	if [ $$status -ne 1 ]; then exit $$status; fi

odra-source-dependency-check:
	@expected="$$(find src -mindepth 2 -maxdepth 2 -type f -name '*.odin' ! -name '*_test.odin' -print | \
		grep -Ev '^src/(ksawery|ksawery_bridge|ksawery_command|ksawery_module|maksym|maksym_module|darek|darek_module|jan_editing|jan_planning|jan_computation|jan_output|jan_module)/' | sort)"; \
	actual="$$(printf '%s\n' $(ODRA_PRODUCTION_SOURCES) | sort)"; \
	differences="$$(printf '%s\n%s\n%s\n' "$$expected" '-- actual --' "$$actual" | \
		awk '$$0 == "-- actual --" { actual_phase = 1; next } \
			!actual_phase { expected[$$0] = 1; next } \
			{ actual[$$0] = 1 } \
			END { \
				for (source in expected) if (!(source in actual)) print "missing: " source; \
				for (source in actual) if (!(source in expected)) print "unexpected: " source; \
			}' | sort)"; \
	if [ -n "$$differences" ]; then \
		echo 'odra source dependency check: application prerequisite mismatch' >&2; \
		printf '%s\n' "$$differences" >&2; \
		exit 1; \
	fi; \
	printf 'Checked %s application Odin source prerequisites.\n' '$(words $(ODRA_PRODUCTION_SOURCES))'

check: odra-source-dependency-check terminal-emulator-check syntax-vendor-check syntax-vendor-build $(RUNTIME_ADAPTER_LIBRARY) $(INTERACTIVE_SESSION_ADAPTER_LIBRARY)
	$(ODIN) check src/text $(ODIN_VET_FLAGS)
	$(ODIN) check src/editor $(ODIN_VET_FLAGS)
	$(ODIN) check src/editor_session $(ODIN_VET_FLAGS)
	$(ODIN) check src/transaction $(ODIN_VET_FLAGS)
	$(ODIN) check src/history $(ODIN_VET_FLAGS)
	$(ODIN) check src/kill_ring $(ODIN_VET_FLAGS)
	$(ODIN) check src/feedback $(ODIN_VET_FLAGS)
	$(ODIN) check src/feedback_routing $(ODIN_VET_FLAGS)
	$(ODIN) check src/feedback_workflow $(ODIN_VET_FLAGS)
	$(ODIN) check src/view $(ODIN_VET_FLAGS)
	$(ODIN) check src/layout $(ODIN_VET_FLAGS)
	$(ODIN) check src/display $(ODIN_VET_FLAGS)
	$(ODIN) check src/terminal $(ODIN_VET_FLAGS)
	$(ODIN) check src/odra -vet -warnings-as-errors \
		-define:ODRA_RACKET_RUNTIME_LIBRARY="../../$(RUNTIME_ADAPTER_LIBRARY)" \
		-define:ODRA_TREE_SITTER_LIBRARY="../../$(TREE_SITTER_ODIN_LIBRARY)"
	$(ODIN) check src/bridge $(ODIN_VET_FLAGS)
	$(ODIN) check src/interaction $(ODIN_VET_FLAGS)
	$(ODIN) check src/document $(ODIN_VET_FLAGS)
	$(ODIN) check src/search $(ODIN_VET_FLAGS)
	$(ODIN) check src/project $(ODIN_VET_FLAGS)
	$(ODIN) check src/workspace $(ODIN_VET_FLAGS)
	$(ODIN) check src/ui $(ODIN_VET_FLAGS)
	$(ODIN) check src/theme $(ODIN_VET_FLAGS)
	$(ODIN) check src/status_bar $(ODIN_VET_FLAGS)
	$(ODIN) check src/gutter $(ODIN_VET_FLAGS)
	$(ODIN) check src/language $(ODIN_VET_FLAGS) \
		-define:ODRA_TREE_SITTER_LIBRARY="../../$(TREE_SITTER_ODIN_LIBRARY)"
	$(ODIN) check src/syntax_workflow $(ODIN_VET_FLAGS) \
		-define:ODRA_TREE_SITTER_LIBRARY="../../$(TREE_SITTER_ODIN_LIBRARY)"
	$(ODIN) check src/language_service $(ODIN_VET_FLAGS)
	$(ODIN) check src/language_service_workflow $(ODIN_VET_FLAGS) \
		-define:ODRA_TREE_SITTER_LIBRARY="../../$(TREE_SITTER_ODIN_LIBRARY)"
	$(ODIN) check src/completion $(ODIN_VET_FLAGS)
	$(ODIN) check src/interactive_session $(ODIN_VET_FLAGS) \
		-define:ODRA_INTERACTIVE_SESSION_ADAPTER_LIBRARY="../../$(INTERACTIVE_SESSION_ADAPTER_LIBRARY)"
	$(ODIN) check src/terminal_session $(ODIN_VET_FLAGS) \
		-define:ODRA_INTERACTIVE_SESSION_ADAPTER_LIBRARY="../../$(INTERACTIVE_SESSION_ADAPTER_LIBRARY)" \
		-define:ODRA_TERMINAL_EMULATOR_ADAPTER_LIBRARY="../../$(TERMINAL_EMULATOR_ADAPTER_LIBRARY)" \
		-define:ODRA_TERMINAL_EMULATOR_VENDOR_LIBRARY="../../$(TERMINAL_VENDOR_LIBRARY)"

resumable-verification-test:
	$(RACKET_TEST) scripts/run-resumable-verification.rkt

internal-test:
	$(call run_verification_step,nightly-policy-test,$(MAKE) nightly-policy-test)
	$(call run_verification_step,nightly-runner-test,$(MAKE) nightly-runner-test)
	$(call run_verification_step,main-check-policy-test,$(MAKE) main-check-policy-test)
	$(call run_verification_step,syntax-vendor-check,$(MAKE) syntax-vendor-check)
	$(call run_verification_step,syntax-vendor-build,$(MAKE) syntax-vendor-build)
	$(call run_verification_step,resumable-verification-test,$(MAKE) resumable-verification-test)
	$(call run_verification_step,operational-state-test,$(MAKE) operational-state-test)
	$(call run_verification_step,project-workspace-migration-test,$(MAKE) project-workspace-migration-test)
	$(call run_verification_step,project-workspace-migration-terminal-test,$(MAKE) project-workspace-migration-terminal-test)
	$(call run_verification_step,interactive-stack-acceptance,$(MAKE) interactive-stack-acceptance)
	$(call run_verification_step,theme-reference-test,$(MAKE) theme-reference-test)
	$(call run_verification_step,theme-equivalence-test,$(MAKE) theme-equivalence-test)
	$(call run_verification_step,ui-reference-test,$(MAKE) ui-reference-test)
	$(call run_verification_step,ui-equivalence-test,$(MAKE) ui-equivalence-test)
	$(call run_verification_step,ui-resource-gates,$(MAKE) ui-resource-gates)
	$(call run_verification_step,profile-compatibility-resource-study,$(MAKE) profile-compatibility-resource-study)
	$(call run_verification_step,completion-reference-test,$(MAKE) completion-reference-test)
	$(call run_verification_step,completion-test,$(ODIN) test src/completion -vet -warnings-as-errors)
	$(call run_verification_step,completion-resource-study,$(MAKE) completion-resource-study)
	$(call run_verification_step,syntax-reference-test,$(MAKE) syntax-reference-test)
	$(call run_verification_step,syntax-resource-study,$(MAKE) syntax-resource-study)
	$(call run_verification_step,tree-sitter-resource-study,$(MAKE) tree-sitter-resource-study)
	$(call run_verification_step,structural-syntax-reference-test,$(MAKE) structural-syntax-reference-test)
	$(call run_verification_step,structural-syntax-equivalence-test,$(MAKE) structural-syntax-equivalence-test)
	$(call run_verification_step,structural-syntax-resource-study,$(MAKE) structural-syntax-resource-study)
	$(call run_verification_step,multi-view-reference-test,$(ODIN) test tests/multi_view_reference)
	$(call run_verification_step,project-reference-test,$(ODIN) test tests/project_reference)
	$(call run_verification_step,candidate-navigation-focused-acceptance,$(MAKE) candidate-navigation-focused-acceptance)
	$(call run_verification_step,theme-workflow-acceptance,$(MAKE) theme-workflow-acceptance)
	$(call run_verification_step,session-reference-test,$(ODIN) test tests/session_reference)
	$(call run_verification_step,text-test,$(ODIN) test src/text)
	$(call run_verification_step,editor-test,$(ODIN) test src/editor)
	$(call run_verification_step,editor-session-test,$(ODIN) test src/editor_session)
	$(call run_verification_step,transaction-test,$(ODIN) test src/transaction)
	$(call run_verification_step,history-test,$(ODIN) test src/history)
	$(call run_verification_step,kill-ring-test,$(ODIN) test src/kill_ring)
	$(call run_verification_step,kill-ring-resource-study,$(MAKE) kill-ring-resource-study)
	$(call run_verification_step,feedback-test,$(ODIN) test src/feedback)
	$(call run_verification_step,feedback-routing-test,$(ODIN) test src/feedback_routing)
	$(call run_verification_step,feedback-workflow-test,$(ODIN) test src/feedback_workflow)
	$(call run_verification_step,feedback-resource-study,$(MAKE) feedback-resource-study)
	$(call run_verification_step,kill-ring-benchmark,$(MAKE) kill-ring-benchmark)
	$(call run_verification_step,history-resource-study,$(MAKE) history-resource-study)
	$(call run_verification_step,multibuffer-history-benchmark,$(MAKE) multibuffer-history-benchmark)
	$(call run_verification_step,history-fuzz,$(MAKE) history-fuzz)
	$(call run_verification_step,transaction-fuzz,$(MAKE) transaction-fuzz)
	$(call run_verification_step,view-test,$(ODIN) test src/view)
	$(call run_verification_step,layout-reference-test,$(ODIN) test tests/layout_reference)
	$(call run_verification_step,pane-buffer-reference-test,$(ODIN) test tests/pane_buffer_reference)
	$(call run_verification_step,layout-test,$(ODIN) test src/layout)
	$(call run_verification_step,layout-acceptance-runtime,$(MAKE) layout-acceptance-runtime)
	$(call run_verification_step,display-test,$(MAKE) display-test)
	$(call run_verification_step,terminal-test,$(MAKE) terminal-test)
	$(call run_verification_step,terminal-presentation-focused-test,$(MAKE) terminal-presentation-focused-test)
	$(call run_verification_step,interactive-session-test,$(MAKE) interactive-session-test)
	$(call run_verification_step,terminal-session-test,$(MAKE) terminal-session-test)
	$(call run_verification_step,bridge-test,$(ODIN) test src/bridge)
	$(call run_verification_step,interaction-test,$(ODIN) test src/interaction)
	$(call run_verification_step,document-test,$(ODIN) test src/document)
	$(call run_verification_step,search-test,$(ODIN) test src/search)
	$(call run_verification_step,project-test,$(ODIN) test src/project)
	$(call run_verification_step,workspace-test,$(ODIN) test src/workspace)
	$(call run_verification_step,ui-test,$(ODIN) test src/ui)
	$(call run_verification_step,theme-test,$(ODIN) test src/theme)
	$(call run_verification_step,status-bar-test,$(ODIN) test src/status_bar)
	$(call run_verification_step,gutter-test,$(ODIN) test src/gutter)
	$(MAKE) language-service-extensibility-acceptance
	$(call run_verification_step,reference-test,$(ODIN) test tests/reference)
	$(call run_verification_step,storage-probe-test,$(ODIN) test tests/storage_probe)
	$(call run_verification_step,core-test,$(ODIN) test tests/core)

ui-acceptance:
	$(MAKE) ui-migration-check
	$(MAKE) internal-test
	$(MAKE) hosting-test

ui-migration-check:
	$(RACKET) scripts/check-ui-migration.rkt

internal-verify: source-hygiene-check check ui-acceptance docs-check

internal-verify-resume:
	$(call run_verification_step,source-hygiene-check,$(MAKE) source-hygiene-check)
	$(call run_verification_step,check,$(MAKE) check)
	$(call run_verification_step,ui-migration-check,$(MAKE) ui-migration-check)
	$(MAKE) internal-test
	$(call run_verification_step,hosting-test,$(MAKE) hosting-test)
	$(call run_verification_step,docs-check,$(MAKE) docs-check)

verify-resume:
	$(VERIFY_RESUME_RUNNER) --prepare
	ODRA_VERIFY_RESUME=1 $(MAKE) internal-verify-resume
	$(VERIFY_RESUME_RUNNER) --complete

verify-resume-reset:
	$(VERIFY_RESUME_RUNNER) --reset
