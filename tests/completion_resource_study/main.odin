// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import completion "../../src/completion"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:time"

LATENCY_GATE_NS :: i64(5_000_000_000)
MEMORY_GATE_BYTES :: i64(8 * 1_024 * 1_024)

Profile :: struct {
	name:         string,
	candidates:   int,
	sessions:     int,
	replacements: int,
}

main :: proc() {
	valid := print_policy()
	profiles := [?]Profile {
		{name = "ordinary", candidates = 8, sessions = 64, replacements = 8},
		{
			name = "demanding",
			candidates = completion.MAX_COMPLETION_CANDIDATES,
			sessions = 1_024,
			replacements = completion.MAX_COMPLETION_REPLACEMENTS,
		},
	}
	for profile, index in profiles {
		valid = run_profile(profile, completion.Role_Registry_ID(index + 1)) && valid
	}
	if !valid do os.exit(1)
}

print_policy :: proc() -> bool {
	valid := completion.MAX_COMPLETION_CANDIDATES == 128 &&
		completion.MAX_COMPLETION_ADDITIONAL_EDITS == 8 &&
		completion.MAX_COMPLETION_TEXT_BYTES == 256 &&
		completion.MAX_COMPLETION_DETAIL_BYTES == 1 * 1_024 &&
		completion.MAX_COMPLETION_RESOLVE_BYTES == 512 &&
		completion.MAX_COMPLETION_IMPLEMENTATIONS == 16 &&
		completion.MAX_COMPLETION_REPLACEMENTS == 1_024 &&
		completion.MAX_COMPLETION_REQUEST_REPLACEMENTS == 1_024 &&
		completion.MAX_ACTIVE_COMPLETION_SESSIONS_PER_CONTROLLER == 1 &&
		completion.MAX_RETAINED_COMPLETION_BATCHES_PER_SESSION == 1
	fmt.printf(
		"study=completion profile=policy valid=%v candidates=%d edits=%d text_bytes=%d detail_bytes=%d resolve_bytes=%d implementations=%d replacements=%d request_replacements=%d active_sessions=%d retained_batches=%d ownership=copied-generational-controller\n",
		valid,
		completion.MAX_COMPLETION_CANDIDATES,
		completion.MAX_COMPLETION_ADDITIONAL_EDITS,
		completion.MAX_COMPLETION_TEXT_BYTES,
		completion.MAX_COMPLETION_DETAIL_BYTES,
		completion.MAX_COMPLETION_RESOLVE_BYTES,
		completion.MAX_COMPLETION_IMPLEMENTATIONS,
		completion.MAX_COMPLETION_REPLACEMENTS,
		completion.MAX_COMPLETION_REQUEST_REPLACEMENTS,
		completion.MAX_ACTIVE_COMPLETION_SESSIONS_PER_CONTROLLER,
		completion.MAX_RETAINED_COMPLETION_BATCHES_PER_SESSION,
	)
	return valid
}

run_profile :: proc(profile: Profile, registry_id: completion.Role_Registry_ID) -> bool {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	started_at := time.tick_now()
	registry: completion.Role_Registry
	initialized, _ := completion.registry_init(&registry, registry_id, completion.DEFAULT_LIMITS, allocator)
	if !initialized {
		mem.tracking_allocator_destroy(&tracking)
		return false
	}
	composition, scoped, _ := completion.registry_scope(&registry)
	controller: completion.Controller
	controller_ready, _ := completion.controller_init(
		&controller,
		completion.Controller_ID(u64(registry_id)),
		1,
		composition,
		completion.DEFAULT_LIMITS,
		allocator,
	)
	valid := scoped && controller_ready
	items, item_error := make([]completion.Candidate, profile.candidates, allocator)
	if item_error != nil {
		_, _ = completion.controller_close(&controller)
		_, _ = completion.registry_close(&registry)
		mem.tracking_allocator_destroy(&tracking)
		return false
	}
	for &item, index in items {
		label_value := fmt.aprintf("candidate-%03d", index)
		label, copied := completion.text_copy(label_value)
		delete(label_value)
		valid = copied && valid
		item = {
			id = completion.Candidate_ID(index + 1),
			kind = .Callable,
			availability = .Available,
			label = label,
			insertion_text = label,
			copied_bytes = u64(label.byte_count) * 2,
		}
	}

	for session_index in 0 ..< profile.sessions {
		request := resource_request(u64(session_index + 1), composition)
		for &item in items {
			item.provenance = {
				provider_id = request.scope.provider_id,
				provider_generation = request.scope.provider_generation,
			}
		}
		batch := resource_batch(request, items, u64(session_index + 1))
		session_ready, _ := completion.controller_start(
			&controller,
			completion.Session_ID(session_index + 1),
			completion.Session_Generation(session_index + 1),
			request,
			composition,
		)
		queued, _ := completion.controller_queue(&controller)
		sent, _ := completion.controller_send(&controller)
		published, _ := completion.controller_publish(&controller, &batch)
		inspection, inspected, _ := completion.controller_inspect(&controller)
		retired, _ := completion.controller_retire(&controller)
		valid = session_ready && queued && sent && published && inspected && retired &&
			inspection.candidate_count == u16(profile.candidates) && valid
	}

	provider_definition := resource_provider_definition("resource-provider")
	provider, registered, _ := completion.registry_register(&registry, provider_definition)
	valid = registered && valid
	after_register, _, _ := completion.registry_scope(&registry)
	selected: bool
	composition, selected, _ = completion.registry_select(&registry, after_register, provider.handle)
	valid = selected && valid
	for _ in 0 ..< profile.replacements {
		definition := provider.definition
		definition.capabilities = {.Explicit}
		provider, composition, selected, _ = completion.registry_replace(
			&registry,
			composition,
			provider.handle,
			definition,
		)
		valid = selected && valid
	}
	compatible, _ := completion.controller_reconcile_composition(&controller, composition)
	valid = compatible && valid

	overflow_items, overflow_error := make(
		[]completion.Candidate,
		completion.MAX_COMPLETION_CANDIDATES + 1,
		allocator,
	)
	overflow_code := completion.Failure_Code.Allocation
	if overflow_error == nil {
		overflow_request := resource_request(u64(profile.sessions + 1), composition)
		for &item, index in overflow_items {
			item = items[index % len(items)]
			item.id = completion.Candidate_ID(index + 1)
			item.provenance = {
				provider_id = overflow_request.scope.provider_id,
				provider_generation = overflow_request.scope.provider_generation,
			}
		}
		overflow_batch := resource_batch(overflow_request, overflow_items, u64(profile.sessions + 1))
		started, _ := completion.controller_start(
			&controller,
			completion.Session_ID(profile.sessions + 1),
			completion.Session_Generation(profile.sessions + 1),
			overflow_request,
			composition,
		)
		queued, _ := completion.controller_queue(&controller)
		sent, _ := completion.controller_send(&controller)
		_, overflow_failure := completion.controller_publish(&controller, &overflow_batch)
		overflow_code = overflow_failure.code
		_, _ = completion.controller_retire(&controller)
		valid = started && queued && sent && overflow_code == .Invalid_Batch && valid
		delete(overflow_items, allocator)
	}

	registry_inspection, inspected_registry, _ := completion.registry_inspect(&registry)
	retained_bytes := tracking.current_memory_allocated
	peak_bytes := tracking.peak_memory_allocated
	delete(items, allocator)
	closed_controller, _ := completion.controller_close(&controller)
	closed_registry, _ := completion.registry_close(&registry)
	cleanup_bytes := tracking.current_memory_allocated
	latency_ns := time.duration_nanoseconds(time.tick_since(started_at))
	valid = inspected_registry &&
		registry_inspection.stats.replacements == u16(profile.replacements) &&
		retained_bytes <= MEMORY_GATE_BYTES && peak_bytes <= MEMORY_GATE_BYTES &&
		latency_ns <= LATENCY_GATE_NS && closed_controller && closed_registry &&
		cleanup_bytes == 0 && valid
	mem.tracking_allocator_destroy(&tracking)
	fmt.printf(
		"study=completion profile=%s valid=%v candidates=%d sessions=%d replacements=%d retained_bytes=%d peak_bytes=%d memory_gate_bytes=%d latency_ns=%d latency_gate_ns=%d overflow=%s cleanup_bytes=%d\n",
		profile.name,
		valid,
		profile.candidates,
		profile.sessions,
		profile.replacements,
		retained_bytes,
		peak_bytes,
		MEMORY_GATE_BYTES,
		latency_ns,
		LATENCY_GATE_NS,
		overflow_code,
		cleanup_bytes,
	)
	return valid
}

resource_request :: proc(generation: u64, composition: completion.Composition_Scope) -> completion.Request {
	provider := composition.selections[0].selected
	query, _ := completion.text_copy("can")
	return {
		id = completion.Request_ID(generation),
		generation = completion.Request_Generation(generation),
		scope = {
			document_id = 1,
			buffer_id = 2,
			document_revision = completion.Document_Revision(generation),
			view_id = 3,
			view_generation = 1,
			language_id = 4,
			language_generation = 1,
			provider_id = completion.Provider_ID(provider.implementation_id),
			provider_generation = completion.Provider_Generation(provider.implementation_generation),
			server_session_id = 5,
			server_session_generation = 1,
			document_binding_id = 6,
			document_binding_generation = 1,
			transmitted_revision = completion.Document_Revision(generation),
		},
		cursor_byte = 3,
		query_range = {start = 0, end = 3},
		query = query,
		trigger = .Explicit,
		provider_capabilities = composition.selections[0].selected_capabilities,
		state = .Prepared,
	}
}

resource_batch :: proc(
	request: completion.Request,
	items: []completion.Candidate,
	generation: u64,
) -> completion.Batch {
	return {
		id = completion.Batch_ID(generation),
		generation = completion.Batch_Generation(generation),
		request_id = request.id,
		request_generation = request.generation,
		scope = request.scope,
		request_cursor_byte = request.cursor_byte,
		query_range = request.query_range,
		disposition = .Complete,
		items = items,
		item_count = u16(len(items)),
	}
}

resource_provider_definition :: proc(name_value: string) -> completion.Implementation_Definition {
	name, _ := completion.name_copy(name_value)
	source, _ := completion.name_copy("resource-study")
	return {
		name = name,
		source = source,
		role = .Provider,
		kind = .Package,
		capabilities = {.Explicit},
	}
}
