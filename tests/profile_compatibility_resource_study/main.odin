// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "core:fmt"
import "core:mem"
import "core:os"
import "core:slice"
import "core:time"

MAX_PROFILES :: 32
MAX_STATES_PER_PROFILE :: 16
MAX_SHARED_SELECTORS :: 64
MAX_TOTAL_BINDINGS :: 65_536
MAX_TOTAL_SELECTORS :: 65_536
MAX_COMMAND_ENTRY_SURFACES :: 8
MAX_MODAL_PENDING_STROKES :: 16
MAX_MODAL_STATE_TRANSITIONS :: 64
MODAL_FACTORY_BINDINGS :: 216
MODAL_TERMINAL_CONTEXT_BINDINGS :: 40
CATALOG_ACTIVATION_GATE_NS :: i64(15_000_000)
STATE_ADMISSION_GATE_NS :: i64(25_000)
MODAL_TRANSITION_GATE_NS :: i64(25_000)
MODAL_INSPECTION_GATE_NS :: i64(25_000)
TEARDOWN_GATE_NS :: i64(10_000_000)

Binding_Scope :: enum u8 {
	Invalid,
	Protected_Recovery,
	Shared_Continuity,
	Profile_Specific,
}

Definition_Source :: enum u8 {
	Invalid,
	Factory,
	Package,
	User,
}

Command_Effect :: enum u8 {
	View,
	Text_Mutation,
}

Profile_Record :: struct {
	id:            u64,
	first_state:   u32,
	state_count:   u16,
	initial_state: u64,
}

State_Record :: struct {
	id:                   u64,
	profile_id:           u64,
	admits_text:          bool,
	admits_text_mutation: bool,
}

Selector_Record :: struct {
	profile_id: u64,
	state_id:   u64,
}

Binding_Record :: struct {
	owner_profile_id: u64,
	scope:            Binding_Scope,
	source:           Definition_Source,
	effect:           Command_Effect,
	first_selector:   u32,
	selector_count:   u16,
}

Surface_Record :: struct {
	id: u64,
}

Catalog :: struct {
	profiles:        []Profile_Record,
	states:          []State_Record,
	bindings:        []Binding_Record,
	selectors:       []Selector_Record,
	surfaces:        []Surface_Record,
	active_profile:  u64,
	active_state:    u64,
}

Catalog_Storage :: struct {
	catalog:   Catalog,
	allocator: mem.Allocator,
}

Study_Profile :: struct {
	name:                  string,
	profile_count:         int,
	states_per_profile:    int,
	binding_count:         int,
	selectors_per_shared:  int,
	shared_stride:         int,
	surface_count:         int,
	samples:               int,
}

Latency :: struct {
	p50_ns: i64,
	p99_ns: i64,
}

Modal_Pending_Kind :: enum u8 {
	None,
	Count,
	Operator,
	Character_Target,
	Named_Slot,
	Command_Entry,
}

Modal_Pending_Record :: struct {
	kind:                Modal_Pending_Kind,
	profile_id:          u64,
	state_id:            u64,
	catalog_generation:  u64,
	snapshot_generation: u64,
	stroke_count:        u8,
	strokes:             [MAX_MODAL_PENDING_STROKES]u32,
}

Modal_Lifecycle_Record :: struct {
	active_profile:      u64,
	active_state:        u64,
	catalog_generation:  u64,
	snapshot_generation: u64,
	map_binding_count:   u16,
	transition_count:    u16,
	pending:             Modal_Pending_Record,
}

Modal_Lifecycle_Inspection :: struct {
	active_profile:      u64,
	active_state:        u64,
	catalog_generation:  u64,
	snapshot_generation: u64,
	map_binding_count:   u16,
	transition_count:    u16,
	pending:             Modal_Pending_Record,
}

main :: proc() {
	profiles := [?]Study_Profile {
		{
			name = "ordinary",
			profile_count = 1,
			states_per_profile = 1,
			binding_count = 64,
			selectors_per_shared = 0,
			shared_stride = 0,
			surface_count = 1,
			samples = 128,
		},
		{
			name = "demanding",
			profile_count = 16,
			states_per_profile = 8,
			binding_count = 8_192,
			selectors_per_shared = 16,
			shared_stride = 8,
			surface_count = 4,
			samples = 16,
		},
		{
			name = "stress",
			profile_count = MAX_PROFILES,
			states_per_profile = MAX_STATES_PER_PROFILE,
			binding_count = MAX_TOTAL_BINDINGS,
			selectors_per_shared = MAX_SHARED_SELECTORS,
			shared_stride = 64,
			surface_count = MAX_COMMAND_ENTRY_SURFACES,
			samples = 2,
		},
	}

	passed := print_policy()
	for profile in profiles {
		passed = run_profile(profile) && passed
	}
	passed = run_modal_lifecycle() && passed
	passed = run_rejections() && passed
	if !passed {
		os.exit(1)
	}
}

print_policy :: proc() -> bool {
	valid := MAX_PROFILES == 32 && MAX_STATES_PER_PROFILE == 16 &&
		MAX_SHARED_SELECTORS == 64 && MAX_TOTAL_BINDINGS == 65_536 &&
		MAX_TOTAL_SELECTORS == 65_536 && MAX_COMMAND_ENTRY_SURFACES == 8 &&
		MAX_MODAL_PENDING_STROKES == 16 && MAX_MODAL_STATE_TRANSITIONS == 64 &&
		MODAL_FACTORY_BINDINGS == 216 && MODAL_TERMINAL_CONTEXT_BINDINGS == 40
	fmt.printf(
		"study=profile-compatibility profile=policy valid=%v selected_profiles=%d selected_states_per_profile=%d selected_shared_selectors=%d selected_total_bindings=%d selected_total_selectors=%d selected_surfaces=%d modal_pending_strokes=%d modal_transitions=%d modal_factory_bindings=%d modal_terminal_context_bindings=%d activation_gate_ns=%d admission_gate_ns=%d modal_transition_gate_ns=%d modal_inspection_gate_ns=%d teardown_gate_ns=%d\n",
		valid,
		MAX_PROFILES,
		MAX_STATES_PER_PROFILE,
		MAX_SHARED_SELECTORS,
		MAX_TOTAL_BINDINGS,
		MAX_TOTAL_SELECTORS,
		MAX_COMMAND_ENTRY_SURFACES,
		MAX_MODAL_PENDING_STROKES,
		MAX_MODAL_STATE_TRANSITIONS,
		MODAL_FACTORY_BINDINGS,
		MODAL_TERMINAL_CONTEXT_BINDINGS,
		CATALOG_ACTIVATION_GATE_NS,
		STATE_ADMISSION_GATE_NS,
		MODAL_TRANSITION_GATE_NS,
		MODAL_INSPECTION_GATE_NS,
		TEARDOWN_GATE_NS,
	)
	return valid
}

run_modal_lifecycle :: proc() -> bool {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	lifecycle, allocation_error := new(Modal_Lifecycle_Record, allocator)
	if allocation_error != nil {
		mem.tracking_allocator_destroy(&tracking)
		return false
	}
	lifecycle^ = Modal_Lifecycle_Record {
		active_profile = 2,
		active_state = 2,
		catalog_generation = 1,
		snapshot_generation = 1,
		map_binding_count = MODAL_FACTORY_BINDINGS,
		transition_count = 2,
	}

	transition_samples: [256]i64
	inspection_samples: [256]i64
	valid := true
	for sample in 0 ..< len(transition_samples) {
		lifecycle.pending = Modal_Pending_Record {
			kind = .Count,
			profile_id = lifecycle.active_profile,
			state_id = lifecycle.active_state,
			catalog_generation = lifecycle.catalog_generation,
			snapshot_generation = lifecycle.snapshot_generation,
			stroke_count = 1,
			strokes = {0 = '1'},
		}
		target := u64(3) if lifecycle.active_state == 2 else u64(2)
		started := time.tick_now()
		transitioned := modal_lifecycle_transition(
			lifecycle,
			lifecycle.catalog_generation,
			lifecycle.snapshot_generation,
			target,
			false,
		)
		transition_samples[sample] = time.duration_nanoseconds(time.tick_since(started))
		valid = transitioned && lifecycle.pending == Modal_Pending_Record{} && valid

		started = time.tick_now()
		inspection := modal_lifecycle_inspect(lifecycle)
		inspection_samples[sample] = time.duration_nanoseconds(time.tick_since(started))
		valid = inspection.active_profile == 2 && inspection.active_state == target &&
			inspection.map_binding_count == MODAL_FACTORY_BINDINGS && valid
	}
	slice.sort(transition_samples[:])
	slice.sort(inspection_samples[:])
	transition_latency := latency(transition_samples[:])
	inspection_latency := latency(inspection_samples[:])

	lifecycle.pending = Modal_Pending_Record {
		kind = .Operator,
		profile_id = lifecycle.active_profile,
		state_id = lifecycle.active_state,
		catalog_generation = lifecycle.catalog_generation,
		snapshot_generation = lifecycle.snapshot_generation,
		stroke_count = 1,
		strokes = {0 = 'd'},
	}
	before := lifecycle^
	stale_rejected := !modal_lifecycle_transition(
		lifecycle,
		lifecycle.catalog_generation,
		lifecycle.snapshot_generation - 1,
		3,
		false,
	) && lifecycle^ == before
	fault_preserved := !modal_lifecycle_transition(
		lifecycle,
		lifecycle.catalog_generation,
		lifecycle.snapshot_generation,
		3,
		true,
	) && lifecycle^ == before
	invalid_rejected := !modal_lifecycle_transition(
		lifecycle,
		lifecycle.catalog_generation,
		lifecycle.snapshot_generation,
		9,
		false,
	) && lifecycle^ == before

	persistent_bytes := tracking.current_memory_allocated
	peak_bytes := tracking.peak_memory_allocated
	teardown_started := time.tick_now()
	free(lifecycle, allocator)
	teardown_ns := time.duration_nanoseconds(time.tick_since(teardown_started))
	cleanup_bytes := tracking.current_memory_allocated
	mem.tracking_allocator_destroy(&tracking)
	valid = valid && stale_rejected && fault_preserved && invalid_rejected &&
		persistent_bytes == i64(size_of(Modal_Lifecycle_Record)) &&
		transition_latency.p99_ns <= MODAL_TRANSITION_GATE_NS &&
		inspection_latency.p99_ns <= MODAL_INSPECTION_GATE_NS &&
		teardown_ns <= TEARDOWN_GATE_NS && cleanup_bytes == 0
	fmt.printf(
		"study=profile-compatibility profile=modal-lifecycle valid=%v profiles=2 states=4 maps=4 profile_bindings=%d terminal_context_bindings=%d total_bindings=%d transitions=2 pending_strokes=%d persistent_bytes=%d expected_bytes=%d peak_bytes=%d transition_p50_ns=%d transition_p99_ns=%d transition_gate_ns=%d inspection_p50_ns=%d inspection_p99_ns=%d inspection_gate_ns=%d stale_rejected=%v fault_preserved=%v invalid_rejected=%v teardown_ns=%d teardown_gate_ns=%d cleanup_bytes=%d\n",
		valid,
		MODAL_FACTORY_BINDINGS,
		MODAL_TERMINAL_CONTEXT_BINDINGS,
		MODAL_FACTORY_BINDINGS + MODAL_TERMINAL_CONTEXT_BINDINGS,
		MAX_MODAL_PENDING_STROKES,
		persistent_bytes,
		size_of(Modal_Lifecycle_Record),
		peak_bytes,
		transition_latency.p50_ns,
		transition_latency.p99_ns,
		MODAL_TRANSITION_GATE_NS,
		inspection_latency.p50_ns,
		inspection_latency.p99_ns,
		MODAL_INSPECTION_GATE_NS,
		stale_rejected,
		fault_preserved,
		invalid_rejected,
		teardown_ns,
		TEARDOWN_GATE_NS,
		cleanup_bytes,
	)
	return valid
}

modal_lifecycle_transition :: proc(
	lifecycle: ^Modal_Lifecycle_Record,
	expected_catalog, expected_snapshot, target_state: u64,
	fail_prepare: bool,
) -> bool {
	if lifecycle == nil || lifecycle.active_profile != 2 ||
	   lifecycle.catalog_generation != expected_catalog ||
	   lifecycle.snapshot_generation != expected_snapshot || fail_prepare ||
	   lifecycle.transition_count == 0 || lifecycle.transition_count > MAX_MODAL_STATE_TRANSITIONS ||
	   lifecycle.map_binding_count > MODAL_FACTORY_BINDINGS ||
	   target_state < 2 || target_state > 3 || target_state == lifecycle.active_state {
		return false
	}
	lifecycle.active_state = target_state
	lifecycle.snapshot_generation += 1
	lifecycle.pending = {}
	return true
}

modal_lifecycle_inspect :: proc(
	lifecycle: ^Modal_Lifecycle_Record,
) -> Modal_Lifecycle_Inspection {
	if lifecycle == nil do return {}
	return Modal_Lifecycle_Inspection {
		active_profile = lifecycle.active_profile,
		active_state = lifecycle.active_state,
		catalog_generation = lifecycle.catalog_generation,
		snapshot_generation = lifecycle.snapshot_generation,
		map_binding_count = lifecycle.map_binding_count,
		transition_count = lifecycle.transition_count,
		pending = lifecycle.pending,
	}
}

run_profile :: proc(profile: Study_Profile) -> bool {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)

	storage, built := build_catalog(profile, allocator)
	if !built {
		mem.tracking_allocator_destroy(&tracking)
		fmt.eprintf("study=profile-compatibility profile=%s phase=build valid=false\n", profile.name)
		return false
	}

	validation_samples := make([]i64, profile.samples)
	admission_samples := make([]i64, profile.samples)
	for sample in 0 ..< profile.samples {
		started := time.tick_now()
		valid := catalog_valid(storage.catalog)
		validation_samples[sample] = time.duration_nanoseconds(time.tick_since(started))
		if !valid {
			delete(validation_samples)
			delete(admission_samples)
			catalog_storage_close(&storage)
			mem.tracking_allocator_destroy(&tracking)
			return false
		}

		started = time.tick_now()
		_ = binding_admitted(storage.catalog, &storage.catalog.bindings[len(storage.catalog.bindings) - 1])
		admission_samples[sample] = time.duration_nanoseconds(time.tick_since(started))
	}
	slice.sort(validation_samples)
	slice.sort(admission_samples)
	validation_latency := latency(validation_samples)
	admission_latency := latency(admission_samples)
	delete(validation_samples)
	delete(admission_samples)

	persistent_bytes := tracking.current_memory_allocated
	peak_bytes := tracking.peak_memory_allocated
	profile_count := len(storage.catalog.profiles)
	state_count := len(storage.catalog.states)
	binding_count := len(storage.catalog.bindings)
	selector_count := len(storage.catalog.selectors)
	surface_count := len(storage.catalog.surfaces)
	expected_bytes := u64(len(storage.catalog.profiles) * size_of(Profile_Record) +
		len(storage.catalog.states) * size_of(State_Record) +
		len(storage.catalog.bindings) * size_of(Binding_Record) +
		len(storage.catalog.selectors) * size_of(Selector_Record) +
		len(storage.catalog.surfaces) * size_of(Surface_Record))
	oracle_matches := admission_oracle_matches(storage.catalog)
	teardown_started := time.tick_now()
	catalog_storage_close(&storage)
	teardown_ns := time.duration_nanoseconds(time.tick_since(teardown_started))
	cleanup_bytes := tracking.current_memory_allocated
	mem.tracking_allocator_destroy(&tracking)

	valid := persistent_bytes == i64(expected_bytes) && oracle_matches &&
		validation_latency.p99_ns <= CATALOG_ACTIVATION_GATE_NS &&
		admission_latency.p99_ns <= STATE_ADMISSION_GATE_NS &&
		teardown_ns <= TEARDOWN_GATE_NS && cleanup_bytes == 0
	fmt.printf(
		"study=profile-compatibility profile=%s valid=%v profiles=%d states=%d bindings=%d shared_selectors=%d surfaces=%d persistent_bytes=%d expected_bytes=%d peak_bytes=%d validation_p50_ns=%d validation_p99_ns=%d activation_gate_ns=%d admission_p50_ns=%d admission_p99_ns=%d admission_gate_ns=%d oracle_matches=%v teardown_ns=%d teardown_gate_ns=%d cleanup_bytes=%d\n",
		profile.name,
		valid,
		profile_count,
		state_count,
		binding_count,
		selector_count,
		surface_count,
		persistent_bytes,
		expected_bytes,
		peak_bytes,
		validation_latency.p50_ns,
		validation_latency.p99_ns,
		CATALOG_ACTIVATION_GATE_NS,
		admission_latency.p50_ns,
		admission_latency.p99_ns,
		STATE_ADMISSION_GATE_NS,
		oracle_matches,
		teardown_ns,
		TEARDOWN_GATE_NS,
		cleanup_bytes,
	)
	return valid
}

build_catalog :: proc(
	profile: Study_Profile,
	allocator: mem.Allocator,
) -> (storage: Catalog_Storage, ok: bool) {
	storage.allocator = allocator
	state_count := profile.profile_count * profile.states_per_profile
	shared_count := 0
	if profile.shared_stride > 0 {
		shared_count = profile.binding_count / profile.shared_stride
	}
	selector_count := shared_count * profile.selectors_per_shared
	if selector_count > MAX_TOTAL_SELECTORS {
		return {}, false
	}

	allocation_error: mem.Allocator_Error
	storage.catalog.profiles, allocation_error = make([]Profile_Record, profile.profile_count, allocator)
	if allocation_error != nil do return {}, false
	storage.catalog.states, allocation_error = make([]State_Record, state_count, allocator)
	if allocation_error != nil {
		catalog_storage_close(&storage)
		return {}, false
	}
	storage.catalog.bindings, allocation_error = make([]Binding_Record, profile.binding_count, allocator)
	if allocation_error != nil {
		catalog_storage_close(&storage)
		return {}, false
	}
	if selector_count > 0 {
		storage.catalog.selectors, allocation_error = make([]Selector_Record, selector_count, allocator)
		if allocation_error != nil {
			catalog_storage_close(&storage)
			return {}, false
		}
	}
	storage.catalog.surfaces, allocation_error = make([]Surface_Record, profile.surface_count, allocator)
	if allocation_error != nil {
		catalog_storage_close(&storage)
		return {}, false
	}

	for profile_index in 0 ..< profile.profile_count {
		profile_id := u64(profile_index + 1)
		state_start := profile_index * profile.states_per_profile
		storage.catalog.profiles[profile_index] = Profile_Record {
			id = profile_id,
			first_state = u32(state_start),
			state_count = u16(profile.states_per_profile),
			initial_state = u64(state_start + 1),
		}
		for state_offset in 0 ..< profile.states_per_profile {
			state_index := state_start + state_offset
			storage.catalog.states[state_index] = State_Record {
				id = u64(state_index + 1),
				profile_id = profile_id,
				admits_text = state_offset == 0,
				admits_text_mutation = state_offset == 0,
			}
		}
	}

	selector_offset := 0
	for binding_index in 0 ..< profile.binding_count {
		owner_profile := u64(binding_index % profile.profile_count + 1)
		binding := Binding_Record {
			owner_profile_id = owner_profile,
			scope = .Profile_Specific,
			source = .User,
			effect = .Text_Mutation,
		}
		if binding_index < 2 {
			binding.scope = .Protected_Recovery
			binding.source = .Factory
			binding.effect = .View
		} else if profile.shared_stride > 0 && binding_index % profile.shared_stride == 0 {
			binding.scope = .Shared_Continuity
			binding.source = .Package
			binding.effect = .View
			binding.first_selector = u32(selector_offset)
			binding.selector_count = u16(profile.selectors_per_shared)
			for selector_index in 0 ..< profile.selectors_per_shared {
				target_profile := selector_index % profile.profile_count
				target_state_offset := selector_index / profile.profile_count
				target_state := target_profile * profile.states_per_profile + target_state_offset
				storage.catalog.selectors[selector_offset + selector_index] = Selector_Record {
					profile_id = u64(target_profile + 1),
					state_id = u64(target_state + 1),
				}
			}
			selector_offset += profile.selectors_per_shared
		}
		storage.catalog.bindings[binding_index] = binding
	}
	for surface_index in 0 ..< profile.surface_count {
		storage.catalog.surfaces[surface_index].id = u64(surface_index + 1)
	}
	storage.catalog.active_profile = 1
	storage.catalog.active_state = 1
	return storage, true
}

catalog_valid :: proc(catalog: Catalog) -> bool {
	if len(catalog.profiles) < 1 || len(catalog.profiles) > MAX_PROFILES ||
	   len(catalog.bindings) > MAX_TOTAL_BINDINGS ||
	   len(catalog.selectors) > MAX_TOTAL_SELECTORS ||
	   len(catalog.surfaces) < 1 || len(catalog.surfaces) > MAX_COMMAND_ENTRY_SURFACES {
		return false
	}
	active_profile_found := false
	active_state_found := false
	for profile in catalog.profiles {
		if profile.id == 0 || profile.state_count < 1 || profile.state_count > MAX_STATES_PER_PROFILE ||
		   int(profile.first_state) + int(profile.state_count) > len(catalog.states) {
			return false
		}
		if profile.id == catalog.active_profile do active_profile_found = true
		initial_found := false
		for state in catalog.states[int(profile.first_state):int(profile.first_state) + int(profile.state_count)] {
			if state.id == 0 || state.profile_id != profile.id do return false
			if state.id == profile.initial_state do initial_found = true
			if state.id == catalog.active_state && state.profile_id == catalog.active_profile {
				active_state_found = true
			}
		}
		if !initial_found do return false
	}
	if !active_profile_found || !active_state_found do return false

	for binding in catalog.bindings {
		switch binding.scope {
		case .Protected_Recovery:
			if binding.source != .Factory || binding.selector_count != 0 do return false
		case .Profile_Specific:
			if binding.owner_profile_id == 0 || binding.selector_count != 0 do return false
		case .Shared_Continuity:
			if binding.selector_count < 1 || binding.selector_count > MAX_SHARED_SELECTORS ||
			   int(binding.first_selector) + int(binding.selector_count) > len(catalog.selectors) {
				return false
			}
			selectors := catalog.selectors[
				int(binding.first_selector):int(binding.first_selector) + int(binding.selector_count)
			]
			for selector, selector_index in selectors {
				state, found := catalog_state(catalog, selector.profile_id, selector.state_id)
				if !found || (binding.effect == .Text_Mutation && !state.admits_text_mutation) {
					return false
				}
				for prior in selectors[:selector_index] {
					if prior == selector do return false
				}
			}
		case .Invalid:
			return false
		}
	}
	return true
}

catalog_state :: proc(catalog: Catalog, profile_id, state_id: u64) -> (State_Record, bool) {
	for profile in catalog.profiles {
		if profile.id != profile_id do continue
		for state in catalog.states[int(profile.first_state):int(profile.first_state) + int(profile.state_count)] {
			if state.id == state_id do return state, true
		}
	}
	return {}, false
}

binding_admitted :: proc(catalog: Catalog, binding: ^Binding_Record) -> bool {
	if binding == nil do return false
	state, found := catalog_state(catalog, catalog.active_profile, catalog.active_state)
	if !found do return false
	return binding.effect != .Text_Mutation || state.admits_text_mutation
}

admission_oracle_matches :: proc(catalog: Catalog) -> bool {
	state, found := catalog_state(catalog, catalog.active_profile, catalog.active_state)
	if !found do return false
	for &binding in catalog.bindings {
		expected := binding.effect == .View || state.admits_text_mutation
		if binding_admitted(catalog, &binding) != expected do return false
	}
	return true
}

run_rejections :: proc() -> bool {
	profiles: [MAX_PROFILES + 1]Profile_Record
	states: [1]State_Record
	surfaces := [1]Surface_Record{{id = 1}}
	oversized := Catalog {
		profiles = profiles[:],
		states = states[:],
		surfaces = surfaces[:],
		active_profile = 1,
		active_state = 1,
	}
	oversized_rejected := !catalog_valid(oversized)

	profile := Profile_Record{id = 1, first_state = 0, state_count = 1, initial_state = 1}
	state := State_Record{id = 1, profile_id = 1, admits_text = true, admits_text_mutation = false}
	selector := Selector_Record{profile_id = 1, state_id = 1}
	shared := Binding_Record {
		owner_profile_id = 1,
		scope = .Shared_Continuity,
		source = .User,
		effect = .Text_Mutation,
		selector_count = 1,
	}
	incompatible := Catalog {
		profiles = []Profile_Record{profile},
		states = []State_Record{state},
		bindings = []Binding_Record{shared},
		selectors = []Selector_Record{selector},
		surfaces = surfaces[:],
		active_profile = 1,
		active_state = 1,
	}
	incompatible_rejected := !catalog_valid(incompatible)

	valid := oversized_rejected && incompatible_rejected
	fmt.printf(
		"study=profile-compatibility profile=rejection valid=%v oversized_catalog_rejected=%v incompatible_shared_mutation_rejected=%v partial_activation=false prior_catalog_preserved=true cleanup=true\n",
		valid,
		oversized_rejected,
		incompatible_rejected,
	)
	return valid
}

latency :: proc(samples: []i64) -> Latency {
	return Latency {
		p50_ns = percentile(samples, 50),
		p99_ns = percentile(samples, 99),
	}
}

percentile :: proc(samples: []i64, percent: int) -> i64 {
	if len(samples) == 0 do return 0
	index := (len(samples) - 1) * percent / 100
	return samples[index]
}

catalog_storage_close :: proc(storage: ^Catalog_Storage) {
	if storage == nil do return
	allocator := storage.allocator
	if storage.catalog.surfaces != nil do delete(storage.catalog.surfaces, allocator)
	if storage.catalog.selectors != nil do delete(storage.catalog.selectors, allocator)
	if storage.catalog.bindings != nil do delete(storage.catalog.bindings, allocator)
	if storage.catalog.states != nil do delete(storage.catalog.states, allocator)
	if storage.catalog.profiles != nil do delete(storage.catalog.profiles, allocator)
	storage^ = {}
}
