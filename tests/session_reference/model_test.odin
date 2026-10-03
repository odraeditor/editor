// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package session_reference

import "core:fmt"
import "core:testing"

/* Verifies creation, activation, and closure preserve deterministic MRU order. */
@(test)
creation_activation_and_close_preserve_mru_order :: proc(t: ^testing.T) {
	model, ready := model_init(4)
	testing.expect(t, ready)
	if !ready {
		return
	}
	defer model_deinit(&model)

	alpha, alpha_ok, _ := model_create(&model, "alpha")
	beta, beta_ok, _ := model_create(&model, "beta")
	gamma, gamma_ok, _ := model_create(&model, "gamma")
	testing.expect(t, alpha_ok && beta_ok && gamma_ok && model_validate(&model))
	testing.expect_value(t, model_active(&model), gamma)

	activated, _ := model_activate(&model, alpha)
	first, first_ok := model_mru_handle(&model, 0)
	second, second_ok := model_mru_handle(&model, 1)
	third, third_ok := model_mru_handle(&model, 2)
	testing.expect(t, activated && first_ok && second_ok && third_ok)
	testing.expect_value(t, first, alpha)
	testing.expect_value(t, second, gamma)
	testing.expect_value(t, third, beta)

	successor, closed, _ := model_close(&model, alpha)
	testing.expect(t, closed && model_validate(&model))
	testing.expect_value(t, successor, gamma)
	testing.expect_value(t, model_live_count(&model), 2)
}

/* Verifies normalized-path reuse never publishes competing canonical entries. */
@(test)
open_reuses_one_associated_path :: proc(t: ^testing.T) {
	model, ready := model_init(3)
	testing.expect(t, ready)
	if !ready {
		return
	}
	defer model_deinit(&model)

	first, first_reused, first_ok, _ := model_open(&model, "/tmp/odra-one.txt", 12)
	second, second_reused, second_ok, _ := model_open(&model, "/tmp/odra-one.txt", 99)
	testing.expect(t, first_ok && second_ok && !first_reused && second_reused)
	testing.expect_value(t, second, first)
	testing.expect_value(t, model_live_count(&model), 1)
	descriptor, inspected := model_inspect(&model, first)
	testing.expect(t, inspected && descriptor.associated && descriptor.active)
	testing.expect_value(t, descriptor.text_bytes, u64(12))
}

/* Verifies association rejects every live label or path owner without mutation. */
@(test)
association_rejects_live_identity_collisions :: proc(t: ^testing.T) {
	model, ready := model_init(4)
	testing.expect(t, ready)
	if !ready {
		return
	}
	defer model_deinit(&model)

	named, named_ok, _ := model_create(&model, "notes")
	path_owner, _, path_ok, _ := model_open(&model, "/tmp/notes.txt")
	testing.expect(t, named_ok && path_ok)

	associated, collision := model_associate(&model, named, "/tmp/notes.txt")
	testing.expect(t, !associated)
	testing.expect_value(t, collision.code, Failure_Code.Path_Collision)
	descriptor, inspected := model_inspect(&model, named)
	testing.expect(t, inspected && !descriptor.associated && descriptor.label == "notes")
	testing.expect(t, model_validate(&model))

	_, _, label_opened, label_collision := model_open(&model, "notes")
	testing.expect(t, !label_opened)
	testing.expect_value(t, label_collision.code, Failure_Code.Label_Collision)
	_, path_inspected := model_inspect(&model, path_owner)
	testing.expect(t, path_inspected)
}

/* Verifies dirty closure is non-mutating until explicit discard authority is supplied. */
@(test)
modified_close_requires_discard :: proc(t: ^testing.T) {
	model, ready := model_init(3)
	testing.expect(t, ready)
	if !ready {
		return
	}
	defer model_deinit(&model)

	associated, _, associated_ok, _ := model_open(&model, "/tmp/associated.txt")
	named, named_ok, _ := model_create(&model, "notes")
	modified, _ := model_set_modified(&model, named, true)
	testing.expect(t, associated_ok && named_ok && modified && model_validate(&model))

	outcome, successor, closed, close_failure := model_close_checked(&model, named)
	testing.expect(t, !closed)
	testing.expect_value(t, close_failure.code, Failure_Code.None)
	testing.expect_value(t, outcome, Close_Outcome.Discard_Required)
	testing.expect_value(t, successor, Handle{})
	descriptor, inspected := model_inspect(&model, named)
	testing.expect(t, inspected && descriptor.modified && descriptor.active)
	testing.expect_value(t, model_live_count(&model), 2)

	outcome, successor, closed, close_failure = model_close_checked(
		&model,
		named,
		.Discard_Modified,
	)
	testing.expect(t, closed && model_validate(&model))
	testing.expect_value(t, close_failure.code, Failure_Code.None)
	testing.expect_value(t, outcome, Close_Outcome.Closed)
	testing.expect_value(t, successor, associated)
	_, stale_ok := model_inspect(&model, named)
	testing.expect(t, !stale_ok)

	outcome, successor, closed, close_failure = model_close_checked(&model, associated)
	testing.expect(t, closed && model_validate(&model))
	testing.expect_value(t, close_failure.code, Failure_Code.None)
	testing.expect_value(t, outcome, Close_Outcome.Closed)
	testing.expect_value(t, successor, Handle{})
}

/* Verifies slot reuse advances generation and permanently rejects stale handles. */
@(test)
slot_reuse_invalidates_stale_handles :: proc(t: ^testing.T) {
	model, ready := model_init(1)
	testing.expect(t, ready)
	if !ready {
		return
	}
	defer model_deinit(&model)

	first, first_ok, _ := model_create(&model, "first")
	_, closed, _ := model_close(&model, first)
	second, second_ok, _ := model_create(&model, "second")
	testing.expect(t, first_ok && closed && second_ok)
	testing.expect_value(t, second.id, first.id)
	testing.expect_value(t, second.generation, first.generation + 1)

	stale_activated, stale_failure := model_activate(&model, first)
	testing.expect(t, !stale_activated)
	testing.expect_value(t, stale_failure.code, Failure_Code.Invalid_Handle)
	testing.expect(t, model_validate(&model))
}

/* Verifies deterministic mixed operations preserve all oracle invariants. */
@(test)
generated_operations_preserve_model_invariants :: proc(t: ^testing.T) {
	model, ready := model_init(32)
	testing.expect(t, ready)
	if !ready {
		return
	}
	defer model_deinit(&model)

	seed := u64(0x6f6472615f736573)
	for operation in 0 ..< 1_024 {
		seed = seed * 6_364_136_223_846_793_005 + 1_442_695_040_888_963_407
		choice := int(seed % 5)
		if choice <= 1 && model_live_count(&model) < len(model.entries) {
			name := fmt.aprintf("buffer-%04d-%016x", operation, seed)
			_, created, _ := model_create(&model, name, seed % 1_048_576)
			delete(name)
			testing.expect(t, created)
		} else if choice == 2 && model_live_count(&model) > 0 {
			position := int((seed >> 8) % u64(model_live_count(&model)))
			handle, found := model_mru_handle(&model, position)
			activated, _ := model_activate(&model, handle)
			testing.expect(t, found && activated)
		} else if choice == 3 && model_live_count(&model) > 0 {
			position := int((seed >> 16) % u64(model_live_count(&model)))
			handle, found := model_mru_handle(&model, position)
			modified, _ := model_set_modified(&model, handle, (seed & 1) == 1)
			testing.expect(t, found && modified)
		} else if model_live_count(&model) > 0 {
			position := int((seed >> 24) % u64(model_live_count(&model)))
			handle, found := model_mru_handle(&model, position)
			_, closed, _ := model_close(&model, handle)
			testing.expect(t, found && closed)
		}
		testing.expect(t, model_validate(&model))
	}
}
