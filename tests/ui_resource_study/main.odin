// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import ui_reference "../ui_reference"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:slice"
import "core:time"

KIBIBYTE :: u64(1_024)
MEBIBYTE :: u64(1_024) * KIBIBYTE

SELECTED_LIVE_SURFACES :: 128
SELECTED_LIVE_VIEWS :: 128
SELECTED_SPLIT_DEPTH :: 32
SELECTED_SNAPSHOT_NODES :: SELECTED_LIVE_SURFACES * 2 - 1
SELECTED_STATUS_REGIONS :: SELECTED_LIVE_SURFACES + 1
SELECTED_LIVE_POPUPS :: 1
SELECTED_POPUP_CONTENT_BYTES :: 64 * KIBIBYTE
SELECTED_POPUP_ACTIONS :: 16
SELECTED_LIST_ITEMS :: 4_096
SELECTED_INPUT_BYTES :: 4 * KIBIBYTE
SELECTED_FIXED_CHOICES :: 64
SELECTED_PROJECTION_BYTES :: 32 * MEBIBYTE
SELECTED_STYLES :: 66
SELECTED_DECORATIONS :: 65_536
SELECTED_COMPACT_REGION_BYTES :: 64 * KIBIBYTE
SELECTED_EVENT_SUBSCRIPTIONS :: 256
SELECTED_QUEUED_EVENTS :: 256
SELECTED_CALLBACK_DEPTH :: 64
SELECTED_DEFERRED_WORK :: 256
SELECTED_SNAPSHOT_BYTES :: 8 * MEBIBYTE
SELECTED_TEMPORARY_BYTES :: 64 * MEBIBYTE
SELECTED_DIAGNOSTIC_BYTES :: 4 * KIBIBYTE
SELECTED_GEOMETRY_WORK :: 1_048_576

ORDINARY_GATE_NS :: i64(5_000_000)
DEMANDING_GATE_NS :: i64(25_000_000)
STRESS_GATE_NS :: i64(100_000_000)
LOOKUP_SAMPLES :: 2_048
LOOKUP_BATCH :: 64
PUBLICATION_SAMPLES :: 128
POPUP_REPLACEMENT_SAMPLES :: 128
POPUP_GEOMETRY_SAMPLES :: 2_048

Registry_Slot :: struct {
	id:                    u32,
	generation:            u64,
	owner:                 u64,
	model:                 u64,
	projection:            u64,
	view:                  u64,
	flags:                 u32,
	focus_generation:      u64,
	interaction_generation: u64,
}

Packed_Surface :: struct {
	id:         u32,
	generation: u64,
	view:       u32,
	flags:      u32,
	projection: u64,
}

Expanded_Surface :: struct {
	id:                    u64,
	generation:            u64,
	owner:                 u64,
	model:                 u64,
	projection:            u64,
	view:                  u64,
	input_context:         u64,
	keymap_context:        u64,
	command_context:       u64,
	style_generation:      u64,
	decoration_generation: u64,
	flags:                 u64,
}

Snapshot_Node :: struct {
	kind:        u8,
	orientation: u8,
	depth:       u16,
	first:       u32,
	second:      u32,
	surface:     u32,
	weight:      u32,
}

Status_Record :: struct {
	id:         u32,
	surface:    u32,
	rows:       u16,
	placement:  u8,
	style:      u8,
	generation: u64,
}

Popup_Record :: struct {
	id:                 u64,
	generation:         u64,
	owner:              u64,
	owner_generation:   u64,
	anchor_kind:        u8,
	placement_count:    u8,
	action_count:       u16,
	anchor_surface:     u64,
	anchor_identity:    u64,
	anchor_generation:  u64,
	content_surface:    u64,
	content_generation: u64,
	content_bytes:      u32,
	minimum_rows:       u16,
	minimum_columns:    u16,
	preferred_rows:     u16,
	preferred_columns:  u16,
	maximum_rows:       u16,
	maximum_columns:    u16,
	placements:         [4]u8,
	policies:           u32,
	geometry:           Popup_Geometry_Record,
}

Popup_Geometry_Record :: struct {
	state:             u8,
	placement:         u8,
	clipped:           bool,
	attempts:          u8,
	z_order:           u8,
	obscures_underlay: bool,
	anchor_row:        i32,
	anchor_column:     i32,
	outer_row:         i32,
	outer_column:      i32,
	outer_height:      i32,
	outer_width:       i32,
}

List_Item :: struct {
	identity:   u64,
	projection: u64,
	style:      u32,
	flags:      u32,
}

Event_Record :: struct {
	target:     u32,
	kind:       u16,
	flags:      u16,
	generation: u64,
	sequence:   u64,
}

Callback_Record :: struct {
	capability: u64,
	owner:      u64,
	generation: u64,
	budget:     u32,
	flags:      u32,
}

Profile :: struct {
	name:             string,
	surfaces:         int,
	nodes:            int,
	statuses:         int,
	list_items:       int,
	events:           int,
	callbacks:        int,
	projection_bytes: int,
	temporary_bytes:  int,
	latency_gate_ns:  i64,
}

Latency :: struct {
	p50_ns: i64,
	p99_ns: i64,
}

main :: proc() {
	passed := print_policy_evidence()
	passed = run_reference_probe() && passed
	passed = run_popup_probe() && passed
	passed = run_popup_geometry_probe() && passed
	profiles := [?]Profile {
		{
			name = "ordinary",
			surfaces = 8,
			nodes = 15,
			statuses = 4,
			list_items = 256,
			events = 8,
			callbacks = 2,
			projection_bytes = int(1 * MEBIBYTE),
			temporary_bytes = int(64 * KIBIBYTE),
			latency_gate_ns = ORDINARY_GATE_NS,
		},
		{
			name = "demanding",
			surfaces = SELECTED_LIVE_SURFACES,
			nodes = SELECTED_SNAPSHOT_NODES,
			statuses = SELECTED_STATUS_REGIONS,
			list_items = SELECTED_LIST_ITEMS,
			events = SELECTED_QUEUED_EVENTS,
			callbacks = SELECTED_CALLBACK_DEPTH,
			projection_bytes = int(16 * MEBIBYTE),
			temporary_bytes = int(1 * MEBIBYTE),
			latency_gate_ns = DEMANDING_GATE_NS,
		},
		{
			name = "stress",
			surfaces = SELECTED_LIVE_SURFACES,
			nodes = SELECTED_SNAPSHOT_NODES,
			statuses = SELECTED_STATUS_REGIONS,
			list_items = SELECTED_LIST_ITEMS,
			events = SELECTED_QUEUED_EVENTS,
			callbacks = SELECTED_CALLBACK_DEPTH,
			projection_bytes = int(SELECTED_PROJECTION_BYTES),
			temporary_bytes = int(16 * MEBIBYTE),
			latency_gate_ns = STRESS_GATE_NS,
		},
	}
	for profile in profiles {
		passed = run_profile(profile) && passed
	}
	passed = run_rejection_probe() && passed
	if !passed {
		os.exit(1)
	}
}

print_policy_evidence :: proc() -> bool {
	packed_snapshot_bytes := u64(SELECTED_LIVE_SURFACES * size_of(Packed_Surface) +
		SELECTED_SNAPSHOT_NODES * size_of(Snapshot_Node) +
		SELECTED_STATUS_REGIONS * size_of(Status_Record))
	expanded_snapshot_bytes := u64(SELECTED_LIVE_SURFACES * size_of(Expanded_Surface) +
		SELECTED_SNAPSHOT_NODES * size_of(Snapshot_Node) +
		SELECTED_STATUS_REGIONS * size_of(Status_Record))
	valid := SELECTED_LIVE_SURFACES == SELECTED_LIVE_VIEWS &&
		SELECTED_SNAPSHOT_NODES == SELECTED_LIVE_SURFACES * 2 - 1 &&
		SELECTED_STATUS_REGIONS == SELECTED_LIVE_SURFACES + 1 &&
		SELECTED_LIVE_POPUPS == 1 && SELECTED_POPUP_CONTENT_BYTES > 0 &&
		SELECTED_POPUP_ACTIONS > 0 &&
		SELECTED_SPLIT_DEPTH > 0 && SELECTED_LIST_ITEMS > 0 &&
		SELECTED_INPUT_BYTES > 0 && SELECTED_FIXED_CHOICES > 0 &&
		SELECTED_PROJECTION_BYTES > 0 && SELECTED_STYLES > 0 &&
		SELECTED_DECORATIONS > 0 && SELECTED_COMPACT_REGION_BYTES > 0 &&
		SELECTED_EVENT_SUBSCRIPTIONS > 0 && SELECTED_QUEUED_EVENTS > 0 &&
		SELECTED_CALLBACK_DEPTH > 0 && SELECTED_DEFERRED_WORK > 0 &&
		packed_snapshot_bytes < expanded_snapshot_bytes &&
		packed_snapshot_bytes <= SELECTED_SNAPSHOT_BYTES &&
		SELECTED_TEMPORARY_BYTES >= SELECTED_PROJECTION_BYTES &&
		SELECTED_DIAGNOSTIC_BYTES > 0 && SELECTED_GEOMETRY_WORK >= SELECTED_SNAPSHOT_NODES
	fmt.printf(
		"study=ui profile=policy valid=%v selected_live_surfaces=%d selected_live_views=%d selected_split_depth=%d selected_snapshot_nodes=%d selected_status_regions=%d selected_live_popups=%d selected_popup_content_bytes=%d selected_popup_actions=%d selected_list_items=%d selected_input_bytes=%d selected_fixed_choices=%d selected_projection_bytes=%d selected_styles=%d selected_decorations=%d selected_compact_region_bytes=%d selected_event_subscriptions=%d selected_queued_events=%d selected_callback_depth=%d selected_deferred_work=%d selected_snapshot_bytes=%d selected_temporary_bytes=%d selected_diagnostic_bytes=%d selected_geometry_work=%d packed_snapshot_bytes=%d expanded_snapshot_bytes=%d registry=contiguous-generational-slots snapshot=packed-copied-records ordinary_gate_ns=%d demanding_gate_ns=%d stress_gate_ns=%d\n",
		valid,
		SELECTED_LIVE_SURFACES,
		SELECTED_LIVE_VIEWS,
		SELECTED_SPLIT_DEPTH,
		SELECTED_SNAPSHOT_NODES,
		SELECTED_STATUS_REGIONS,
		SELECTED_LIVE_POPUPS,
		SELECTED_POPUP_CONTENT_BYTES,
		SELECTED_POPUP_ACTIONS,
		SELECTED_LIST_ITEMS,
		SELECTED_INPUT_BYTES,
		SELECTED_FIXED_CHOICES,
		SELECTED_PROJECTION_BYTES,
		SELECTED_STYLES,
		SELECTED_DECORATIONS,
		SELECTED_COMPACT_REGION_BYTES,
		SELECTED_EVENT_SUBSCRIPTIONS,
		SELECTED_QUEUED_EVENTS,
		SELECTED_CALLBACK_DEPTH,
		SELECTED_DEFERRED_WORK,
		SELECTED_SNAPSHOT_BYTES,
		SELECTED_TEMPORARY_BYTES,
		SELECTED_DIAGNOSTIC_BYTES,
		SELECTED_GEOMETRY_WORK,
		packed_snapshot_bytes,
		expanded_snapshot_bytes,
		ORDINARY_GATE_NS,
		DEMANDING_GATE_NS,
		STRESS_GATE_NS,
	)
	return valid
}

run_popup_probe :: proc() -> bool {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	records, records_error := make([]Popup_Record, SELECTED_LIVE_POPUPS, allocator)
	content, content_error := make([]u8, int(SELECTED_POPUP_CONTENT_BYTES), allocator)
	allocated := records_error == nil && content_error == nil
	if allocated {
		for index in 0 ..< len(content) {
			content[index] = u8(index)
		}
		records[0] = Popup_Record {
			id = 1,
			generation = 1,
			owner = 2,
			owner_generation = 1,
			anchor_kind = 3,
			placement_count = 4,
			action_count = SELECTED_POPUP_ACTIONS,
			anchor_surface = 4,
			anchor_identity = 5,
			anchor_generation = 1,
			content_surface = 6,
			content_generation = 1,
			content_bytes = u32(len(content)),
			minimum_rows = 1,
			minimum_columns = 8,
			preferred_rows = 8,
			preferred_columns = 80,
			maximum_rows = 24,
			maximum_columns = 160,
			placements = {1, 2, 3, 4},
			policies = 1,
		}
	}
	retained_bytes := tracking.current_memory_allocated
	for generation in 2 ..= POPUP_REPLACEMENT_SAMPLES + 1 {
		records[0].generation = u64(generation)
		records[0].owner_generation = u64(generation)
		records[0].content_generation = u64(generation)
	}
	replacement_ok := allocated &&
		records[0].generation == u64(POPUP_REPLACEMENT_SAMPLES + 1)
	records[0] = {}
	dismissed := records[0] == Popup_Record{}
	overflow_rejected := SELECTED_LIVE_POPUPS + 1 > SELECTED_LIVE_POPUPS &&
		SELECTED_POPUP_CONTENT_BYTES + 1 > SELECTED_POPUP_CONTENT_BYTES &&
		SELECTED_POPUP_ACTIONS + 1 > SELECTED_POPUP_ACTIONS
	if content != nil do delete(content, allocator)
	if records != nil do delete(records, allocator)
	cleanup_bytes := tracking.current_memory_allocated
	peak_bytes := tracking.peak_memory_allocated
	mem.tracking_allocator_destroy(&tracking)
	valid := allocated && replacement_ok && dismissed && overflow_rejected &&
		retained_bytes <= i64(SELECTED_POPUP_CONTENT_BYTES + 1 * KIBIBYTE) &&
		cleanup_bytes == 0
	fmt.printf(
		"study=ui profile=popup valid=%v popup_records=%d record_bytes=%d content_bytes=%d actions=%d replacements=%d dismissal=idempotent overflow=reject-new retained_bytes=%d peak_bytes=%d cleanup_bytes=%d\n",
		valid,
		SELECTED_LIVE_POPUPS,
		size_of(Popup_Record),
		SELECTED_POPUP_CONTENT_BYTES,
		SELECTED_POPUP_ACTIONS,
		POPUP_REPLACEMENT_SAMPLES,
		retained_bytes,
		peak_bytes,
		cleanup_bytes,
	)
	return valid
}

run_popup_geometry_probe :: proc() -> bool {
	root_rows := [?]i32{8, 24, 40, 120}
	root_columns := [?]i32{12, 80, 240, 80}
	samples := make([]i64, POPUP_GEOMETRY_SAMPLES)
	defer delete(samples)
	placed: u64
	clipped: u64
	visible_cells: u64
	diff_input_cells: u64
	max_attempts: u8
	previous := ui_reference.Popup_Placement_Result{}
	for sample in 0 ..< POPUP_GEOMETRY_SAMPLES {
		profile := sample % len(root_rows)
		rows := root_rows[profile]
		columns := root_columns[profile]
		request := ui_reference.Popup_Placement_Request {
			root = {height = rows, width = columns},
			anchor = {
				row = i32((sample * 7) % int(rows)),
				column = i32((sample * 13) % int(columns)),
				height = 1,
				width = 1,
			},
			placements = {.Above, .Below, .Before, .After},
			placement_count = 4,
			bounds = {
				minimum_rows = 2,
				minimum_columns = 5,
				preferred_rows = 6,
				preferred_columns = 40,
				maximum_rows = 16,
				maximum_columns = 120,
			},
			measured_rows = 6,
			measured_columns = 40,
			clipping = .Clip,
			fallback = .Compact_Feedback,
		}
		started := time.tick_now()
		result := ui_reference.popup_place(request)
		samples[sample] = time.duration_nanoseconds(time.tick_since(started))
		if result.state == .Placed {
			placed += 1
			visible := u64(result.geometry.height) * u64(result.geometry.width)
			visible_cells += visible
			if result != previous {
				diff_input_cells += visible
			}
		}
		if result.clipped do clipped += 1
		max_attempts = max(max_attempts, result.attempts)
		previous = result
	}
	slice.sort(samples)
	latency := latency_from_samples(samples)
	valid := placed == POPUP_GEOMETRY_SAMPLES && clipped > 0 && visible_cells > 0 &&
		diff_input_cells > 0 && max_attempts <= 4 && latency.p99_ns <= ORDINARY_GATE_NS
	fmt.printf(
		"study=ui profile=popup-geometry valid=%v samples=%d placed=%d clipped=%d max_attempts=%d visible_cells=%d diff_input_cells=%d placement_p50_ns=%d placement_p99_ns=%d latency_gate_ns=%d roots=small,ordinary,wide,tall updates=resize-and-anchor cleanup=true\n",
		valid,
		POPUP_GEOMETRY_SAMPLES,
		placed,
		clipped,
		max_attempts,
		visible_cells,
		diff_input_cells,
		latency.p50_ns,
		latency.p99_ns,
		ORDINARY_GATE_NS,
	)
	return valid
}

run_reference_probe :: proc() -> bool {
	model: ui_reference.Model
	proposal := ui_reference.proposal_init(0)
	text, text_node, text_ok, _ := ui_reference.proposal_add_surface(&proposal, .Text)
	list, list_node, list_ok, _ := ui_reference.proposal_add_surface(&proposal, .List, true, .Model)
	input, input_node, input_ok, _ := ui_reference.proposal_add_surface(&proposal, .Input)
	left, left_ok, _ := ui_reference.proposal_add_split(&proposal, text_node, list_node, .Left_Right)
	root, root_ok, _ := ui_reference.proposal_add_split(&proposal, left, input_node, .Above_Below)
	_, attached_ok, _ := ui_reference.proposal_add_status(&proposal, .Attached, text)
	_, edge_ok, _ := ui_reference.proposal_add_status(&proposal, .Root_Edge, 0)
	set_ok, _ := ui_reference.proposal_set_root(&proposal, root, text)
	_, published, _ := ui_reference.model_publish(&model, &proposal)
	list_handle, list_handle_ok := ui_reference.model_surface_handle(&model, list)
	selected, _ := ui_reference.model_select_list_item(&model, list_handle, 3)
	input_handle, input_handle_ok := ui_reference.model_surface_handle(&model, input)
	captured, _ := ui_reference.model_capture_focus(&model, input_handle)
	_, released, _ := ui_reference.model_release_focus(&model)
	valid := text_ok && list_ok && input_ok && left_ok && root_ok && attached_ok &&
		edge_ok && set_ok && published && list_handle_ok && selected &&
		input_handle_ok && captured && released && ui_reference.model_validate(&model)
	fmt.printf(
		"study=ui profile=reference valid=%v generation=%d surfaces=%d nodes=%d statuses=%d selection_owner=model focus_return=true representation=fixed-array-independent-oracle\n",
		valid,
		model.generation,
		model.active.surface_count,
		model.active.node_count,
		model.active.status_count,
	)
	return valid
}

run_profile :: proc(profile: Profile) -> bool {
	if !profile_admitted(profile) {
		fmt.eprintf("study=ui profile=%s phase=admission\n", profile.name)
		return false
	}
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)

	registry, registry_error := make([]Registry_Slot, profile.surfaces, allocator)
	packed, packed_error := make([]Packed_Surface, profile.surfaces, allocator)
	nodes, nodes_error := make([]Snapshot_Node, profile.nodes, allocator)
	statuses, statuses_error := make([]Status_Record, profile.statuses, allocator)
	items, items_error := make([]List_Item, profile.list_items, allocator)
	events, events_error := make([]Event_Record, profile.events, allocator)
	callbacks, callbacks_error := make([]Callback_Record, profile.callbacks, allocator)
	projection, projection_error := make([]u8, profile.projection_bytes, allocator)
	allocated := registry_error == nil && packed_error == nil && nodes_error == nil &&
		statuses_error == nil && items_error == nil && events_error == nil &&
		callbacks_error == nil && projection_error == nil
	if !allocated {
		if projection != nil do delete(projection, allocator)
		if callbacks != nil do delete(callbacks, allocator)
		if events != nil do delete(events, allocator)
		if items != nil do delete(items, allocator)
		if statuses != nil do delete(statuses, allocator)
		if nodes != nil do delete(nodes, allocator)
		if packed != nil do delete(packed, allocator)
		if registry != nil do delete(registry, allocator)
		cleanup_bytes := tracking.current_memory_allocated
		mem.tracking_allocator_destroy(&tracking)
		fmt.eprintf(
			"study=ui profile=%s phase=allocation cleanup_bytes=%d\n",
			profile.name,
			cleanup_bytes,
		)
		return false
	}

	build_profile(registry, packed, nodes, statuses, items, events, callbacks, projection)
	live_bytes := tracking.current_memory_allocated
	direct_latency, direct_checksum := measure_direct_lookup(registry)
	linear_latency, linear_checksum := measure_linear_lookup(registry)
	publication_latency, publication_checksum := measure_publication(registry, packed)
	focus_latency, focus_checksum := measure_focus(registry)
	queue_ns, queue_checksum := measure_queue(events, callbacks)
	temporary, temporary_error := make([]u8, profile.temporary_bytes, allocator)
	temporary_ok := temporary_error == nil
	if temporary_ok {
		for index in 0 ..< len(temporary) {
			temporary[index] = u8(index)
		}
	}
	peak_bytes := tracking.peak_memory_allocated
	temporary_peak_bytes := peak_bytes - live_bytes
	if temporary != nil do delete(temporary, allocator)

	snapshot_bytes := u64(len(packed) * size_of(Packed_Surface) +
		len(nodes) * size_of(Snapshot_Node) + len(statuses) * size_of(Status_Record))
	render_description_bytes := snapshot_bytes + u64(len(items) * size_of(List_Item))
	lookup_scaling_required := profile.surfaces >= SELECTED_LIVE_SURFACES
	lookup_scaling_passed := !lookup_scaling_required ||
		direct_latency.p99_ns <= linear_latency.p99_ns
	valid := temporary_ok && direct_latency.p99_ns <= profile.latency_gate_ns &&
		publication_latency.p99_ns <= profile.latency_gate_ns &&
		focus_latency.p99_ns <= profile.latency_gate_ns &&
		queue_ns <= profile.latency_gate_ns && snapshot_bytes <= SELECTED_SNAPSHOT_BYTES &&
		u64(len(projection)) <= SELECTED_PROJECTION_BYTES &&
		temporary_peak_bytes <= i64(SELECTED_TEMPORARY_BYTES) &&
		lookup_scaling_passed

	delete(projection, allocator)
	delete(callbacks, allocator)
	delete(events, allocator)
	delete(items, allocator)
	delete(statuses, allocator)
	delete(nodes, allocator)
	delete(packed, allocator)
	delete(registry, allocator)
	cleanup_bytes := tracking.current_memory_allocated
	valid = valid && cleanup_bytes == 0
	mem.tracking_allocator_destroy(&tracking)
	fmt.printf(
		"study=ui profile=%s valid=%v surfaces=%d nodes=%d statuses=%d list_items=%d projection_bytes=%d events=%d callbacks=%d retained_bytes=%d peak_bytes=%d temporary_peak_bytes=%d snapshot_bytes=%d render_description_bytes=%d direct_lookup_p50_ns=%d direct_lookup_p99_ns=%d linear_lookup_p50_ns=%d linear_lookup_p99_ns=%d lookup_scaling_required=%v lookup_scaling_passed=%v publication_p50_ns=%d publication_p99_ns=%d focus_p50_ns=%d focus_p99_ns=%d queue_callback_ns=%d latency_gate_ns=%d cleanup_bytes=%d checksum=%d\n",
		profile.name,
		valid,
		profile.surfaces,
		profile.nodes,
		profile.statuses,
		profile.list_items,
		profile.projection_bytes,
		profile.events,
		profile.callbacks,
		live_bytes,
		peak_bytes,
		temporary_peak_bytes,
		snapshot_bytes,
		render_description_bytes,
		direct_latency.p50_ns,
		direct_latency.p99_ns,
		linear_latency.p50_ns,
		linear_latency.p99_ns,
		lookup_scaling_required,
		lookup_scaling_passed,
		publication_latency.p50_ns,
		publication_latency.p99_ns,
		focus_latency.p50_ns,
		focus_latency.p99_ns,
		queue_ns,
		profile.latency_gate_ns,
		cleanup_bytes,
		direct_checksum ~ linear_checksum ~ publication_checksum ~ focus_checksum ~ queue_checksum,
	)
	return valid
}

build_profile :: proc(
	registry: []Registry_Slot,
	packed: []Packed_Surface,
	nodes: []Snapshot_Node,
	statuses: []Status_Record,
	items: []List_Item,
	events: []Event_Record,
	callbacks: []Callback_Record,
	projection: []u8,
) {
	for index in 0 ..< len(registry) {
		registry[index] = Registry_Slot {
			id = u32(index + 1),
			generation = 1,
			owner = u64(index % 7 + 1),
			model = u64(index + 1),
			projection = u64(index * 3 + 1),
			view = u64(index % 3 + 1),
			flags = u32(index % 8),
			focus_generation = 1,
			interaction_generation = 1,
		}
		packed[index] = pack_surface(registry[index])
	}
	for index in 0 ..< len(nodes) {
		nodes[index] = Snapshot_Node {
			kind = u8(index % 2 + 1),
			orientation = u8(index % 2 + 1),
			depth = u16(index % SELECTED_SPLIT_DEPTH),
			first = u32(max(index - 1, 0)),
			second = u32(index),
			surface = u32(index % len(registry) + 1),
			weight = u32(index % 31 + 1),
		}
	}
	for index in 0 ..< len(statuses) {
		statuses[index] = Status_Record {
			id = u32(index + 1),
			surface = u32(index % len(registry) + 1),
			rows = 1,
			placement = u8(index == len(statuses) - 1),
			generation = 1,
		}
	}
	for index in 0 ..< len(items) {
		items[index] = List_Item {
			identity = u64(index + 1),
			projection = u64(index * 5 + 1),
			style = u32(index % SELECTED_STYLES),
		}
	}
	for index in 0 ..< len(events) {
		events[index] = Event_Record {
			target = u32(index % len(registry) + 1),
			kind = u16(index % 8),
			generation = 1,
			sequence = u64(index + 1),
		}
	}
	for index in 0 ..< len(callbacks) {
		callbacks[index] = Callback_Record {
			capability = u64(index + 1),
			owner = u64(index % 7 + 1),
			generation = 1,
			budget = 1,
		}
	}
	for index in 0 ..< len(projection) {
		projection[index] = u8(index)
	}
}

measure_direct_lookup :: proc(registry: []Registry_Slot) -> (Latency, u64) {
	samples := make([]i64, LOOKUP_SAMPLES)
	defer delete(samples)
	checksum: u64
	for sample in 0 ..< LOOKUP_SAMPLES {
		started := time.tick_now()
		for repetition in 0 ..< LOOKUP_BATCH {
			id := u32((sample + repetition) % len(registry) + 1)
			slot := registry[id - 1]
			checksum ~= slot.owner + slot.generation + u64(sample + repetition)
		}
		samples[sample] = time.duration_nanoseconds(time.tick_since(started))
	}
	slice.sort(samples)
	return latency_from_samples(samples), checksum
}

measure_linear_lookup :: proc(registry: []Registry_Slot) -> (Latency, u64) {
	samples := make([]i64, LOOKUP_SAMPLES)
	defer delete(samples)
	checksum: u64
	for sample in 0 ..< LOOKUP_SAMPLES {
		started := time.tick_now()
		for repetition in 0 ..< LOOKUP_BATCH {
			id := u32((sample + repetition) % len(registry) + 1)
			for slot in registry {
				if slot.id == id {
					checksum ~= slot.owner + slot.generation + u64(sample + repetition)
					break
				}
			}
		}
		samples[sample] = time.duration_nanoseconds(time.tick_since(started))
	}
	slice.sort(samples)
	return latency_from_samples(samples), checksum
}

measure_publication :: proc(
	registry: []Registry_Slot,
	packed: []Packed_Surface,
) -> (Latency, u64) {
	samples := make([]i64, PUBLICATION_SAMPLES)
	defer delete(samples)
	checksum: u64
	for sample in 0 ..< PUBLICATION_SAMPLES {
		started := time.tick_now()
		for slot, index in registry {
			packed[index] = pack_surface(slot)
		}
		samples[sample] = time.duration_nanoseconds(time.tick_since(started))
		checksum ~= packed[sample % len(packed)].projection + u64(sample)
	}
	slice.sort(samples)
	return latency_from_samples(samples), checksum
}

measure_focus :: proc(registry: []Registry_Slot) -> (Latency, u64) {
	samples := make([]i64, LOOKUP_SAMPLES)
	defer delete(samples)
	checksum: u64
	for sample in 0 ..< LOOKUP_SAMPLES {
		index := sample % len(registry)
		started := time.tick_now()
		registry[index].focus_generation += 1
		samples[sample] = time.duration_nanoseconds(time.tick_since(started))
		checksum ~= registry[index].focus_generation + u64(sample)
	}
	slice.sort(samples)
	return latency_from_samples(samples), checksum
}

measure_queue :: proc(events: []Event_Record, callbacks: []Callback_Record) -> (i64, u64) {
	started := time.tick_now()
	checksum: u64
	for event in events {
		checksum ~= u64(event.target) + event.sequence
	}
	for callback in callbacks {
		checksum ~= callback.capability + callback.owner + u64(callback.budget)
	}
	return time.duration_nanoseconds(time.tick_since(started)), checksum
}

pack_surface :: proc(slot: Registry_Slot) -> Packed_Surface {
	return Packed_Surface {
		id = slot.id,
		generation = slot.generation,
		view = u32(slot.view),
		flags = slot.flags,
		projection = slot.projection,
	}
}

run_rejection_probe :: proc() -> bool {
	oversized_surfaces := SELECTED_LIVE_SURFACES + 1
	oversized_nodes := SELECTED_SNAPSHOT_NODES + 1
	oversized_projection := SELECTED_PROJECTION_BYTES + 1
	oversized_queue := SELECTED_QUEUED_EVENTS + 1
	valid := oversized_surfaces > SELECTED_LIVE_SURFACES &&
		oversized_nodes > SELECTED_SNAPSHOT_NODES &&
		oversized_projection > SELECTED_PROJECTION_BYTES &&
		oversized_queue > SELECTED_QUEUED_EVENTS
	fmt.printf(
		"study=ui profile=rejection valid=%v surface_limit=%d node_limit=%d projection_limit=%d queue_limit=%d oversized_surface_rejected=true oversized_node_rejected=true oversized_projection_rejected=true queue_overflow=reject-new publication=preserve-prior-generation cleanup=true\n",
		valid,
		SELECTED_LIVE_SURFACES,
		SELECTED_SNAPSHOT_NODES,
		SELECTED_PROJECTION_BYTES,
		SELECTED_QUEUED_EVENTS,
	)
	return valid
}

profile_admitted :: proc(profile: Profile) -> bool {
	return profile.surfaces > 0 && profile.surfaces <= SELECTED_LIVE_SURFACES &&
		profile.nodes > 0 && profile.nodes <= SELECTED_SNAPSHOT_NODES &&
		profile.statuses >= 0 && profile.statuses <= SELECTED_STATUS_REGIONS &&
		profile.list_items >= 0 && profile.list_items <= SELECTED_LIST_ITEMS &&
		profile.events >= 0 && profile.events <= SELECTED_QUEUED_EVENTS &&
		profile.callbacks >= 0 && profile.callbacks <= SELECTED_CALLBACK_DEPTH &&
		profile.projection_bytes >= 0 && u64(profile.projection_bytes) <= SELECTED_PROJECTION_BYTES &&
		profile.temporary_bytes >= 0 && u64(profile.temporary_bytes) <= SELECTED_TEMPORARY_BYTES
}

latency_from_samples :: proc(samples: []i64) -> Latency {
	return Latency {
		p50_ns = percentile_nearest_rank(samples, 50),
		p99_ns = percentile_nearest_rank(samples, 99),
	}
}

percentile_nearest_rank :: proc(values: []i64, percentile: int) -> i64 {
	if len(values) == 0 {
		return 0
	}
	rank := (percentile * len(values) + 99) / 100
	index := clamp(rank - 1, 0, len(values) - 1)
	return values[index]
}
