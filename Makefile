# SPDX-FileCopyrightText: 2026 Adrian PK
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Odra. See COPYING for license terms.

.DEFAULT_GOAL := build

include makefiles/internal.mk

.PHONY: build command-reference-check development-build development-run interaction-compatibility-focused-test interaction-compatibility-isolation-test interaction-compatibility-linked-acceptance interaction-profile-bridge-test interactive-stack-development-check main-check nightly nightly-dispatch nightly-status run source-license-check test user-guide-exercise-check user-guide-exercise-package user-guide-usability-check verify

build: odra

command-reference-check:
	$(RACKET) scripts/check-command-keybinding-reference.rkt

development-build: $(ODRA_DEVELOPMENT) $(KSAWERY_MODULE_LIBRARY) $(MAKSYM_MODULE_LIBRARY) $(DAREK_MODULE_LIBRARY) $(JAN_MODULE_LIBRARY) $(PRODUCT_MODULE_MANIFEST)

development-run: $(ODRA_DEVELOPMENT) $(KSAWERY_MODULE_LIBRARY) $(MAKSYM_MODULE_LIBRARY) $(DAREK_MODULE_LIBRARY) $(JAN_MODULE_LIBRARY) $(PRODUCT_MODULE_MANIFEST)
	@scripts/run-development-editor.sh $(ODRA_DEVELOPMENT_ARGS)

interaction-profile-bridge-test: $(RUNTIME_TEST_ADAPTER_LIBRARY)
	$(RACKET_TEST) src/hosting/keymap-profile-bridge.rkt
	$(ODIN) test src/hosting \
		-vet -warnings-as-errors \
		-out:$(HOSTING_BUILD_DIR)/interaction-profile-bridge-test \
		-define:ODIN_TEST_THREADS=1 \
		-define:ODIN_TEST_NAMES=hosting.runtime_boundary_contains_failures, \
		-define:ODRA_RACKET_RUNTIME_LIBRARY="../../$(RUNTIME_TEST_ADAPTER_LIBRARY)" \
		-extra-linker-flags:"$(RACKET_CS_LIBRARY) $(RACKET_CS_LINK_LIBS)"

interaction-compatibility-focused-test: interaction-profile-bridge-test
	$(RACKET_TEST) src/language_bundle/keymap-projection.rkt
	$(RACKET_TEST) scripts/check-interaction-compatibility.rkt
	$(RACKET) scripts/check-interaction-compatibility.rkt --fixture tests/interaction_compatibility/cases.tsv

interactive-stack-development-check: $(ODRA_DEVELOPMENT)
	$(RACKET_TEST) scripts/check-interactive-stack.rkt
	$(RACKET) scripts/check-interactive-stack.rkt \
		--binary $(ODRA_DEVELOPMENT) \
		--minimum-stack-kib $(INTERACTIVE_STACK_KIB)

interaction-compatibility-linked-acceptance:
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
	for test_source in \
		tests/interaction_compatibility/linked_acceptance_test.rkt \
		tests/maksym_workflow/acceptance_test.rkt \
		tests/darek_workflow/acceptance_test.rkt \
		tests/ksawery_workflow/sequence_workflow_acceptance_test.rkt \
		tests/jan_product/acceptance_test.rkt \
		tests/roman/linked_acceptance_test.rkt; do \
		ODRA_PTY_EXECUTABLE=$(abspath scripts/run-development-editor.sh) \
			$(PTY_RACKET_TEST) "$$test_source" || exit 1; \
	done

interaction-compatibility-isolation-test:
	$(RACKET_TEST) \
		src/command/builtins.rkt \
		src/command/keymaps.rkt \
		src/command/keymap-inspection.rkt \
		src/language_bundle/keymap-projection.rkt \
		tests/configuration/package_runtime_test.rkt
	$(MAKE) ksawery-module-focused-test
	$(MAKE) maksym-module-focused-test
	$(MAKE) darek-module-focused-test
	$(MAKE) jan-module-focused-test

run: $(ODRA)
	$(ODRA)

source-license-check:
	$(RACKET) scripts/plan-source-licensing.rkt --check

test: internal-test

user-guide-exercise-package:
	bash scripts/build-user-guide-exercises.sh

user-guide-exercise-check:
	bash scripts/check-user-guide-exercises.sh

user-guide-usability-check:
	$(RACKET) scripts/check-user-guide-usability.rkt
	$(RACKET_TEST) scripts/check-user-guide-usability.rkt

.PHONY: verification-evidence-test

verify: internal-verify

main-check:
	bash scripts/evidence/run-stage.sh source-hygiene -- $(MAKE) source-hygiene-check
	bash scripts/evidence/run-stage.sh documentation -- $(MAKE) docs-check
	bash scripts/evidence/run-stage.sh build -- $(MAKE) build
	bash scripts/evidence/run-stage.sh project-workspace-migration -- $(MAKE) project-workspace-migration-terminal-test

verification-evidence-test:
	$(RACKET_TEST) tests/verification_evidence/definitions_test.rkt tests/verification_evidence/producer_test.rkt tests/verification_evidence/release_test.rkt tests/verification_evidence/workflow_test.rkt

nightly:
	bash scripts/run-nightly-verification.sh

nightly-status:
	$(RACKET) scripts/nightly-status.rkt

nightly-dispatch:
	bash scripts/dispatch-nightly-verification.sh
