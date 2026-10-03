// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ui

import "core:testing"

@(private="file")
PROFILE_MODEL_CAPACITY :: 4

@(private="file")
Profile_Model_Handle :: struct {
	id:         u64,
	generation: u64,
}

@(private="file")
Profile_Model_Entry :: struct {
	handle:   Profile_Model_Handle,
	fallback: Profile_Model_Handle,
	live:     bool,
}

@(private="file")
Profile_Model :: struct {
	generation:      u64,
	next_id:         u64,
	factory:         Profile_Model_Handle,
	selected:        Profile_Model_Handle,
	entries:         [PROFILE_MODEL_CAPACITY]Profile_Model_Entry,
	reject_next:     bool,
	last_rejected:   Profile_Model_Handle,
}

@(private="file")
profile_model_init :: proc(model: ^Profile_Model) {
	model^ = {
		generation = 1,
		next_id = 2,
		factory = {id = 1, generation = 1},
		selected = {id = 1, generation = 1},
		entries = {
			0 = {
				handle = {id = 1, generation = 1},
				live = true,
			},
		},
	}
}

@(private="file")
profile_model_resolve :: proc(
	model: ^Profile_Model,
	handle: Profile_Model_Handle,
) -> (^Profile_Model_Entry, bool) {
	if model == nil || handle.id == 0 || handle.generation == 0 {
		return nil, false
	}
	for &entry in model.entries {
		if entry.live && entry.handle.id == handle.id {
			return &entry, entry.handle == handle
		}
	}
	return nil, false
}

@(private="file")
profile_model_register :: proc(
	model: ^Profile_Model,
	fallback: Profile_Model_Handle,
) -> (Profile_Model_Handle, bool) {
	if model == nil || model.reject_next {
		if model != nil {
			model.reject_next = false
			model.last_rejected = {id = model.next_id, generation = 1}
		}
		return {}, false
	}
	if _, resolved := profile_model_resolve(model, fallback); !resolved {
		model.last_rejected = fallback
		return {}, false
	}
	for &entry in model.entries {
		if entry.live {
			continue
		}
		handle := Profile_Model_Handle{id = model.next_id, generation = 1}
		model.next_id += 1
		entry = {handle = handle, fallback = fallback, live = true}
		model.generation += 1
		return handle, true
	}
	model.last_rejected = {id = model.next_id, generation = 1}
	return {}, false
}

@(private="file")
profile_model_select :: proc(
	model: ^Profile_Model,
	expected_generation: u64,
	handle: Profile_Model_Handle,
) -> bool {
	if model == nil || expected_generation != model.generation {
		if model != nil do model.last_rejected = handle
		return false
	}
	if _, resolved := profile_model_resolve(model, handle); !resolved {
		model.last_rejected = handle
		return false
	}
	if model.selected != handle {
		model.selected = handle
		model.generation += 1
	}
	return true
}

@(private="file")
profile_model_replace :: proc(
	model: ^Profile_Model,
	expected_generation: u64,
	handle: Profile_Model_Handle,
	fallback: Profile_Model_Handle,
) -> (Profile_Model_Handle, bool) {
	if model == nil || expected_generation != model.generation || model.reject_next {
		if model != nil {
			model.reject_next = false
			model.last_rejected = handle
		}
		return {}, false
	}
	entry, resolved := profile_model_resolve(model, handle)
	_, fallback_ok := profile_model_resolve(model, fallback)
	if !resolved || !fallback_ok || fallback.id == handle.id ||
	   handle.generation == max(u64) {
		model.last_rejected = handle
		return {}, false
	}
	replacement := handle
	replacement.generation += 1
	entry.handle = replacement
	entry.fallback = fallback
	if model.selected == handle do model.selected = replacement
	model.generation += 1
	return replacement, true
}

@(private="file")
profile_model_restore :: proc(model: ^Profile_Model, expected_generation: u64) -> bool {
	return profile_model_select(model, expected_generation, model.factory)
}

/* Verifies profile selection and restoration publish exact generations. */
@(test)
selects_and_restores_factory :: proc(t: ^testing.T) {
	model: Profile_Model
	profile_model_init(&model)
	package_profile, registered := profile_model_register(&model, model.factory)
	registration_generation := model.generation
	selected := profile_model_select(&model, registration_generation, package_profile)
	selection_generation := model.generation
	restored := profile_model_restore(&model, selection_generation)

	testing.expect(t, registered && selected && restored)
	testing.expect_value(t, package_profile, Profile_Model_Handle{id = 2, generation = 1})
	testing.expect_value(t, model.selected, model.factory)
	testing.expect_value(t, model.generation, u64(4))
}

/* Verifies stale and failed replacements preserve the last valid selection. */
@(test)
rejects_stale_or_failed_replacement :: proc(t: ^testing.T) {
	model: Profile_Model
	profile_model_init(&model)
	package_profile, registered := profile_model_register(&model, model.factory)
	selected := profile_model_select(&model, model.generation, package_profile)
	confirmed := model.selected
	confirmed_generation := model.generation

	_, stale_ok := profile_model_replace(
		&model,
		confirmed_generation - 1,
		package_profile,
		model.factory,
	)
	model.reject_next = true
	_, allocation_ok := profile_model_replace(
		&model,
		confirmed_generation,
		package_profile,
		model.factory,
	)

	testing.expect(t, registered && selected && !stale_ok && !allocation_ok)
	testing.expect_value(t, model.selected, confirmed)
	testing.expect_value(t, model.generation, confirmed_generation)
	testing.expect_value(t, model.last_rejected, package_profile)
}

/* Verifies replacement invalidates stale handles and rejects fallback cycles. */
@(test)
invalidates_stale_handles_and_cycles :: proc(t: ^testing.T) {
	model: Profile_Model
	profile_model_init(&model)
	package_profile, registered := profile_model_register(&model, model.factory)
	replacement, replaced := profile_model_replace(
		&model,
		model.generation,
		package_profile,
		model.factory,
	)
	_, stale_resolves := profile_model_resolve(&model, package_profile)
	_, replacement_resolves := profile_model_resolve(&model, replacement)
	_, cycle_ok := profile_model_replace(
		&model,
		model.generation,
		replacement,
		replacement,
	)

	testing.expect(t, registered && replaced)
	testing.expect(t, !stale_resolves && replacement_resolves && !cycle_ok)
	testing.expect_value(t, model.selected, model.factory)
}

/* Verifies bounded profile capacity rejects overflow without mutation. */
@(test)
rejects_capacity_overflow :: proc(t: ^testing.T) {
	model: Profile_Model
	profile_model_init(&model)
	for _ in 1..<PROFILE_MODEL_CAPACITY {
		_, registered := profile_model_register(&model, model.factory)
		testing.expect(t, registered)
	}
	confirmed_generation := model.generation
	confirmed_selection := model.selected
	_, overflow_ok := profile_model_register(&model, model.factory)

	testing.expect(t, !overflow_ok)
	testing.expect_value(t, model.generation, confirmed_generation)
	testing.expect_value(t, model.selected, confirmed_selection)
}
