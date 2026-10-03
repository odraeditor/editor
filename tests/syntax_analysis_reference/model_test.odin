// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package syntax_analysis_reference

import "core:testing"

/* Ensures factory selection publishes analysis for one exact document revision. */
@(test)
factory_selection_publishes_exact_revision :: proc(t: ^testing.T) {
	model, initialized := model_init(1)
	snapshot, published, _ := model_publish_snapshot(
		&model,
		model.selection.generation,
		41,
		7,
		12,
	)

	testing.expect(t, initialized && published && model_valid(&model))
	testing.expect_value(t, snapshot.source_revision, u64(7))
	testing.expect_value(t, snapshot.provider, model.selection.factory)
}

/* Ensures provider replacement is atomic and invalidates the prior snapshot. */
@(test)
replacement_invalidates_snapshot :: proc(t: ^testing.T) {
	model, _ := model_init(1)
	_, _, _ = model_publish_snapshot(&model, model.selection.generation, 41, 7, 4)
	registered, added, _ := model_register(&model, 2)
	confirmed, confirmed_ok, _ := model_confirm(&model, registered)
	before := model.selection
	replaced, replacement_ok, _ := model_replace(&model, before.generation, confirmed)
	_, stale_ok, stale_failure := model_replace(&model, before.generation, model.selection.factory)

	testing.expect(t, added && confirmed_ok && replacement_ok && !stale_ok)
	testing.expect_value(t, stale_failure.code, Failure_Code.Stale_Selection)
	testing.expect_value(t, replaced.active, confirmed)
	testing.expect(t, !model.snapshot.confirmed && model_valid(&model))
}

/* Ensures disable and restore keep factory ownership explicit. */
@(test)
restore_keeps_factory_owner :: proc(t: ^testing.T) {
	model, _ := model_init(1)
	disabled, disabled_ok, _ := model_disable(&model, model.selection.generation)
	_, published, publish_failure := model_publish_snapshot(
		&model,
		disabled.generation,
		41,
		8,
		1,
	)
	restored, restored_ok, _ := model_restore(&model, disabled.generation)

	testing.expect(t, disabled_ok && !published && restored_ok)
	testing.expect_value(t, publish_failure.code, Failure_Code.Syntax_Disabled)
	testing.expect_value(t, restored.active, restored.factory)
	testing.expect(t, !restored.disabled && model_valid(&model))
}

/* Ensures active provider failure restores one factory selection. */
@(test)
failure_restores_factory_selection :: proc(t: ^testing.T) {
	model, _ := model_init(1)
	registered, _, _ := model_register(&model, 2)
	confirmed, _, _ := model_confirm(&model, registered)
	selected, _, _ := model_replace(&model, model.selection.generation, confirmed)
	restored, failed, _ := model_fail_active(&model, selected.generation)
	stale := model_provider(&model, confirmed)

	testing.expect(t, failed && stale == nil)
	testing.expect_value(t, restored.active, restored.factory)
	testing.expect(t, model_valid(&model))
}

/* Ensures analysis limits and teardown produce explicit bounded state. */
@(test)
limits_and_teardown_are_explicit :: proc(t: ^testing.T) {
	model, _ := model_init(1)
	for key in u32(2) ..= u32(MAX_PROVIDERS) {
		_, added, _ := model_register(&model, key)
		testing.expect(t, added)
	}
	_, overflow, overflow_failure := model_register(&model, 99)
	_, published, span_failure := model_publish_snapshot(
		&model,
		model.selection.generation,
		41,
		9,
		MAX_SPANS + 1,
	)
	closed := model_close(&model)

	testing.expect(t, !overflow && !published && closed && !model_close(&model))
	testing.expect_value(t, overflow_failure.code, Failure_Code.Provider_Limit)
	testing.expect_value(t, span_failure.code, Failure_Code.Span_Limit)
}
