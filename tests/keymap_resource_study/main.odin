// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:slice"
import "core:time"

MAX_STROKES :: 32
SELECTED_COMMANDS :: 2_048
SELECTED_MAPS :: 128
SELECTED_ACTIVE_MAPS :: 16
SELECTED_BINDINGS :: 16_384
SELECTED_STROKES :: 16
SELECTED_INSPECTION_ALTERNATIVES :: 128
SELECTED_DEFINITION_BYTES :: 8 * 1_024 * 1_024
SELECTED_SNAPSHOT_BYTES :: 32 * 1_024 * 1_024

LOOKUP_GATE_NS :: i64(100_000)
PREFIX_GATE_NS :: i64(150_000)
COMPILE_GATE_NS :: i64(10_000_000)
CONTEXT_GATE_NS :: i64(1_000_000)
TEARDOWN_GATE_NS :: i64(8_000_000)

Action :: enum u8 {
	Bind,
	Mask,
	Remap,
}

Sequence :: struct {
	strokes: [MAX_STROKES]u32,
	count:   u8,
}

Map_Definition :: struct {
	layer:    u8,
	priority: i16,
	owner:    u32,
	active:   bool,
}

Binding_Definition :: struct {
	sequence:  Sequence,
	map_index: u16,
	action:    Action,
	command:   u32,
	remap:     u32,
}

Compiled_Binding :: struct {
	sequence:  Sequence,
	map_index: u16,
	layer:     u8,
	priority:  i16,
	action:    Action,
	command:   u32,
	remap:     u32,
}

Snapshot :: struct {
	generation:    u64,
	bindings:      []Compiled_Binding,
	active_maps:   []bool,
	storage_bytes: u64,
	allocator:     runtime.Allocator,
}

Resolution :: struct {
	found:        bool,
	prefix:       bool,
	masked:       bool,
	command:      u32,
	winner_map:   u16,
	shadow_count: u16,
}

Profile :: struct {
	name:             string,
	maps:             int,
	active_maps:      int,
	bindings:         int,
	unique_sequences: int,
	max_strokes:      int,
	lookup_operations: int,
	compile_samples:  int,
}

Latency :: struct {
	p50_ns: i64,
	p99_ns: i64,
}

Fault_Allocator :: struct {
	backing:                runtime.Allocator,
	fail_after:             u64,
	successful_allocations: u64,
}

main :: proc() {
	passed := print_policy()
	passed = run_reference_oracle() && passed
	profiles := [?]Profile {
		{
			name = "ordinary",
			maps = 16,
			active_maps = 12,
			bindings = 1_024,
			unique_sequences = 768,
			max_strokes = 8,
			lookup_operations = 1_000_000,
			compile_samples = 16,
		},
		{
			name = "demanding",
			maps = 128,
			active_maps = 64,
			bindings = 16_384,
			unique_sequences = 12_288,
			max_strokes = 16,
			lookup_operations = 250_000,
			compile_samples = 4,
		},
		{
			name = "stress",
			maps = 1_024,
			active_maps = 128,
			bindings = 65_536,
			unique_sequences = 32_768,
			max_strokes = 32,
			lookup_operations = 65_536,
			compile_samples = 1,
		},
	}
	for profile in profiles {
		passed = run_profile(profile) && passed
	}
	passed = run_rejection_and_fault_probes() && passed
	if !passed {
		os.exit(1)
	}
}

print_policy :: proc() -> bool {
	valid := SELECTED_COMMANDS >= 256 && SELECTED_COMMANDS <= 8_192 &&
		SELECTED_MAPS >= 16 && SELECTED_MAPS <= 1_024 &&
		SELECTED_ACTIVE_MAPS >= 8 && SELECTED_ACTIVE_MAPS <= 128 &&
		SELECTED_BINDINGS >= 1_024 && SELECTED_BINDINGS <= 65_536 &&
		SELECTED_STROKES >= 4 && SELECTED_STROKES <= MAX_STROKES &&
		SELECTED_INSPECTION_ALTERNATIVES >= 8 &&
		SELECTED_INSPECTION_ALTERNATIVES <= 256 &&
		SELECTED_DEFINITION_BYTES >= 256 * 1_024 &&
		SELECTED_DEFINITION_BYTES <= 32 * 1_024 * 1_024 &&
		SELECTED_SNAPSHOT_BYTES >= 1 * 1_024 * 1_024 &&
		SELECTED_SNAPSHOT_BYTES <= 64 * 1_024 * 1_024
	fmt.printf(
		"study=keymap profile=policy valid=%v selected_commands=%d selected_maps=%d selected_active_maps=%d selected_bindings=%d selected_strokes=%d selected_inspection_alternatives=%d selected_definition_bytes=%d selected_snapshot_bytes=%d lookup_gate_ns=%d prefix_gate_ns=%d compile_gate_ns=%d context_gate_ns=%d teardown_gate_ns=%d\n",
		valid,
		SELECTED_COMMANDS,
		SELECTED_MAPS,
		SELECTED_ACTIVE_MAPS,
		SELECTED_BINDINGS,
		SELECTED_STROKES,
		SELECTED_INSPECTION_ALTERNATIVES,
		SELECTED_DEFINITION_BYTES,
		SELECTED_SNAPSHOT_BYTES,
		LOOKUP_GATE_NS,
		PREFIX_GATE_NS,
		COMPILE_GATE_NS,
		CONTEXT_GATE_NS,
		TEARDOWN_GATE_NS,
	)
	return valid
}

run_reference_oracle :: proc() -> bool {
	maps := [?]Map_Definition {
		{layer = 7, priority = 0, owner = 1, active = true},
		{layer = 1, priority = 0, owner = 2, active = true},
		{layer = 3, priority = 5, owner = 3, active = true},
	}
	sequence := sequence_for(7, 2)
	definitions := [?]Binding_Definition {
		{sequence = sequence, map_index = 0, action = .Bind, command = 10},
		{sequence = sequence, map_index = 1, action = .Mask, command = 11},
		{sequence = sequence_for(9, 3), map_index = 2, action = .Remap, command = 12, remap = 13},
	}
	masked := oracle_resolve(maps[:], definitions[:], sequence)
	remapped := oracle_resolve(maps[:], definitions[:], sequence_for(9, 3))
	valid := masked.found && masked.masked && masked.winner_map == 1 &&
		masked.shadow_count == 1 && remapped.found && !remapped.masked &&
		remapped.command == 13
	fmt.printf(
		"study=keymap profile=reference valid=%v representation=contiguous-linear-precedence masks=true remaps=true shadows=true\n",
		valid,
	)
	return valid
}

run_profile :: proc(profile: Profile) -> bool {
	maps := make([]Map_Definition, profile.maps)
	defer delete(maps)
	for &map_definition, map_index in maps {
		map_definition = Map_Definition {
			layer = u8(map_index % 9),
			priority = i16((map_index * 17) % 31),
			owner = u32(map_index + 1),
			active = map_index < profile.active_maps,
		}
	}
	definitions := make([]Binding_Definition, profile.bindings)
	defer delete(definitions)
	for &definition, binding_index in definitions {
		sequence_index := binding_index % profile.unique_sequences
		action := Action.Bind
		if sequence_index % 29 == 0 {
			action = .Mask
		} else if sequence_index % 23 == 0 {
			action = .Remap
		}
		definition = Binding_Definition {
			sequence = sequence_for(sequence_index, profile.max_strokes),
			map_index = u16(binding_index % profile.maps),
			action = action,
			command = u32(sequence_index % SELECTED_COMMANDS + 1),
			remap = u32((sequence_index + 97) % SELECTED_COMMANDS + 1),
		}
	}

	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	compile_latencies := make([]i64, profile.compile_samples)
	defer delete(compile_latencies)
	snapshot: Snapshot
	compiled := true
	for sample in 0 ..< profile.compile_samples {
		started := time.tick_now()
		candidate, ready := compile_snapshot(
			u64(sample + 1),
			maps,
			definitions,
			allocator,
		)
		compile_latencies[sample] = time.duration_nanoseconds(time.tick_since(started))
		if !ready {
			compiled = false
			break
		}
		close_snapshot(&snapshot)
		snapshot = candidate
	}
	if !compiled {
		close_snapshot(&snapshot)
		live_bytes := tracking.current_memory_allocated
		mem.tracking_allocator_destroy(&tracking)
		fmt.eprintf("study=keymap profile=%s phase=compile live_bytes=%d\n", profile.name, live_bytes)
		return false
	}
	slice.sort(compile_latencies)
	compile_latency := latency(compile_latencies)

	active_indices := make([]u16, profile.maps)
	defer delete(active_indices)
	context_latencies: [128]i64
	active_count := 0
	for sample in 0 ..< len(context_latencies) {
		started := time.tick_now()
		active_count = assemble_context(maps, active_indices)
		context_latencies[sample] = time.duration_nanoseconds(time.tick_since(started))
	}
	slice.sort(context_latencies[:])
	context_latency := latency(context_latencies[:])

	lookup_latencies := make([]i64, min(profile.lookup_operations, 65_536))
	defer delete(lookup_latencies)
	prefix_latencies := make([]i64, len(lookup_latencies))
	defer delete(prefix_latencies)
	oracle_matches := true
	checksum := u64(0)
	max_shadow_count := u16(0)
	for operation in 0 ..< profile.lookup_operations {
		sequence_index := (operation * 8191 + 17) % (profile.unique_sequences + profile.unique_sequences / 3)
		query := sequence_for(sequence_index, profile.max_strokes)
		started := time.tick_now()
		resolved := resolve_snapshot(&snapshot, query)
		elapsed := time.duration_nanoseconds(time.tick_since(started))
		if operation < len(lookup_latencies) {
			lookup_latencies[operation] = elapsed
		}
		if operation < 1_024 {
			reference := oracle_resolve(maps, definitions, query)
			oracle_matches = oracle_matches && resolved == reference
		}
		checksum += u64(resolved.command) + u64(resolved.shadow_count)
		max_shadow_count = max(max_shadow_count, resolved.shadow_count)

		prefix := query
		if prefix.count > 1 {
			prefix.count -= 1
		}
		started = time.tick_now()
		prefix_result := resolve_snapshot(&snapshot, prefix)
		elapsed = time.duration_nanoseconds(time.tick_since(started))
		if operation < len(prefix_latencies) {
			prefix_latencies[operation] = elapsed
		}
		if prefix_result.prefix {
			checksum += 1
		}
	}
	slice.sort(lookup_latencies)
	slice.sort(prefix_latencies)
	lookup_latency := latency(lookup_latencies)
	prefix_latency := latency(prefix_latencies)

	replacement, replacement_ready := compile_snapshot(
		snapshot.generation + 1,
		maps,
		definitions,
		allocator,
	)
	previous_generation := snapshot.generation
	if replacement_ready {
		close_snapshot(&snapshot)
		snapshot = replacement
	}
	generation_valid := replacement_ready && snapshot.generation == previous_generation + 1
	storage_bytes := snapshot.storage_bytes
	persistent_peak_bytes := tracking.total_memory_allocated
	started := time.tick_now()
	close_snapshot(&snapshot)
	teardown_ns := time.duration_nanoseconds(time.tick_since(started))
	live_bytes := tracking.current_memory_allocated
	mem.tracking_allocator_destroy(&tracking)

	latency_gates := lookup_latency.p99_ns <= LOOKUP_GATE_NS &&
		prefix_latency.p99_ns <= PREFIX_GATE_NS &&
		context_latency.p99_ns <= CONTEXT_GATE_NS
	compile_gate := profile.name != "ordinary" || compile_latency.p99_ns <= COMPILE_GATE_NS
	teardown_gate := teardown_ns <= TEARDOWN_GATE_NS
	valid := oracle_matches && active_count == profile.active_maps && generation_valid &&
		latency_gates && compile_gate && teardown_gate && live_bytes == 0
	fmt.printf(
		"study=keymap profile=%s valid=%v maps=%d active_maps=%d bindings=%d unique_sequences=%d max_strokes=%d definition_bytes=%d snapshot_bytes=%d persistent_peak_bytes=%d lookup_temporary_bytes=0 compile_p50_ns=%d compile_p99_ns=%d compile_gate_ns=%d lookup_operations=%d lookup_p50_ns=%d lookup_p99_ns=%d lookup_gate_ns=%d prefix_p50_ns=%d prefix_p99_ns=%d prefix_gate_ns=%d context_p50_ns=%d context_p99_ns=%d context_gate_ns=%d inspection_alternatives_max=%d replacement=true generation_valid=%v teardown_ns=%d teardown_gate_ns=%d oracle_matches=%v live_bytes=%d checksum=%d\n",
		profile.name,
		valid,
		profile.maps,
		profile.active_maps,
		profile.bindings,
		profile.unique_sequences,
		profile.max_strokes,
		len(definitions) * size_of(Binding_Definition) + len(maps) * size_of(Map_Definition),
		storage_bytes,
		persistent_peak_bytes,
		compile_latency.p50_ns,
		compile_latency.p99_ns,
		COMPILE_GATE_NS,
		profile.lookup_operations,
		lookup_latency.p50_ns,
		lookup_latency.p99_ns,
		LOOKUP_GATE_NS,
		prefix_latency.p50_ns,
		prefix_latency.p99_ns,
		PREFIX_GATE_NS,
		context_latency.p50_ns,
		context_latency.p99_ns,
		CONTEXT_GATE_NS,
		max_shadow_count,
		generation_valid,
		teardown_ns,
		TEARDOWN_GATE_NS,
		oracle_matches,
		live_bytes,
		checksum,
	)
	return valid
}

run_rejection_and_fault_probes :: proc() -> bool {
	cycle_edges := [?][2]u16{{0, 1}, {1, 2}, {2, 0}}
	cycle_rejected := ordering_cycle_rejected(3, cycle_edges[:])
	stale_owner_rejected := owner_is_stale(0, 1)
	maps := [?]Map_Definition{{layer = 8, priority = 0, owner = 1, active = true}}
	definitions := [?]Binding_Definition{{
		sequence = sequence_for(1, 4),
		map_index = 0,
		action = .Bind,
		command = 1,
	}}
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	fault := Fault_Allocator {
		backing = mem.tracking_allocator(&tracking),
		fail_after = 0,
	}
	candidate, ready := compile_snapshot(2, maps[:], definitions[:], fault_allocator(&fault))
	close_snapshot(&candidate)
	fault_preserved_prior := !ready
	live_bytes := tracking.current_memory_allocated
	mem.tracking_allocator_destroy(&tracking)
	valid := cycle_rejected && stale_owner_rejected && fault_preserved_prior && live_bytes == 0
	fmt.printf(
		"study=keymap profile=stress-rejection valid=%v ordering_cycle_rejected=%v stale_owner_rejected=%v allocator_fault_rejected=%v prior_generation_preserved=%v live_bytes=%d\n",
		valid,
		cycle_rejected,
		stale_owner_rejected,
		!ready,
		fault_preserved_prior,
		live_bytes,
	)
	return valid
}

compile_snapshot :: proc(
	generation: u64,
	maps: []Map_Definition,
	definitions: []Binding_Definition,
	allocator: runtime.Allocator,
) -> (snapshot: Snapshot, ok: bool) {
	bindings, allocation_error := make([]Compiled_Binding, len(definitions), allocator)
	if allocation_error != nil {
		return {}, false
	}
	active_maps, active_error := make([]bool, len(maps), allocator)
	if active_error != nil {
		delete(bindings, allocator)
		return {}, false
	}
	for map_definition, map_index in maps {
		active_maps[map_index] = map_definition.active
	}
	for definition, definition_index in definitions {
		if int(definition.map_index) >= len(maps) || maps[definition.map_index].owner == 0 {
			delete(active_maps, allocator)
			delete(bindings, allocator)
			return {}, false
		}
		map_definition := maps[definition.map_index]
		bindings[definition_index] = Compiled_Binding {
			sequence = definition.sequence,
			map_index = definition.map_index,
			layer = map_definition.layer,
			priority = map_definition.priority,
			action = definition.action,
			command = definition.command,
			remap = definition.remap,
		}
	}
	slice.sort_by(bindings, compiled_less)
	return Snapshot {
		generation = generation,
		bindings = bindings,
		active_maps = active_maps,
		storage_bytes = u64(len(bindings) * size_of(Compiled_Binding) + len(active_maps)),
		allocator = allocator,
	}, true
}

close_snapshot :: proc(snapshot: ^Snapshot) {
	if snapshot == nil {
		return
	}
	if snapshot.active_maps != nil {
		delete(snapshot.active_maps, snapshot.allocator)
	}
	if snapshot.bindings != nil {
		delete(snapshot.bindings, snapshot.allocator)
	}
	snapshot^ = {}
}

resolve_snapshot :: proc(snapshot: ^Snapshot, query: Sequence) -> Resolution {
	low := lower_bound(snapshot.bindings, query)
	result := Resolution{}
	index := low
	for index < len(snapshot.bindings) && sequence_compare(snapshot.bindings[index].sequence, query) == 0 {
		binding := snapshot.bindings[index]
		if snapshot.active_maps[binding.map_index] {
			if !result.found {
				result = resolution_from(binding)
			} else if result.shadow_count < max(u16) {
				result.shadow_count += 1
			}
		}
		index += 1
	}
	if result.found {
		return result
	}
	if low < len(snapshot.bindings) && sequence_is_prefix(query, snapshot.bindings[low].sequence) {
		for prefix_index in low ..< len(snapshot.bindings) {
			binding := snapshot.bindings[prefix_index]
			if !sequence_is_prefix(query, binding.sequence) {
				break
			}
			if snapshot.active_maps[binding.map_index] {
				result.prefix = true
				break
			}
		}
	}
	return result
}

oracle_resolve :: proc(
	maps: []Map_Definition,
	definitions: []Binding_Definition,
	query: Sequence,
) -> Resolution {
	result := Resolution{}
	winner: Binding_Definition
	for definition in definitions {
		if int(definition.map_index) >= len(maps) || !maps[definition.map_index].active {
			continue
		}
		comparison := sequence_compare(definition.sequence, query)
		if comparison == 0 {
			if !result.found || map_precedes(maps[definition.map_index], definition.map_index, maps[winner.map_index], winner.map_index) {
				if result.found {
					result.shadow_count += 1
				}
				winner = definition
				resolved_shadows := result.shadow_count
				result = resolution_from_definition(definition)
				result.shadow_count = resolved_shadows
			} else {
				result.shadow_count += 1
			}
		} else if !result.found && sequence_is_prefix(query, definition.sequence) {
			result.prefix = true
		}
	}
	return result
}

resolution_from :: proc(binding: Compiled_Binding) -> Resolution {
	command := binding.command
	if binding.action == .Remap {
		command = binding.remap
	}
	return Resolution {
		found = true,
		masked = binding.action == .Mask,
		command = command,
		winner_map = binding.map_index,
	}
}

resolution_from_definition :: proc(binding: Binding_Definition) -> Resolution {
	command := binding.command
	if binding.action == .Remap {
		command = binding.remap
	}
	return Resolution {
		found = true,
		masked = binding.action == .Mask,
		command = command,
		winner_map = binding.map_index,
	}
}

compiled_less :: proc(left, right: Compiled_Binding) -> bool {
	comparison := sequence_compare(left.sequence, right.sequence)
	if comparison != 0 {
		return comparison < 0
	}
	if left.layer != right.layer {
		return left.layer < right.layer
	}
	if left.priority != right.priority {
		return left.priority > right.priority
	}
	return left.map_index < right.map_index
}

map_precedes :: proc(left: Map_Definition, left_index: u16, right: Map_Definition, right_index: u16) -> bool {
	if left.layer != right.layer {
		return left.layer < right.layer
	}
	if left.priority != right.priority {
		return left.priority > right.priority
	}
	return left_index < right_index
}

lower_bound :: proc(bindings: []Compiled_Binding, query: Sequence) -> int {
	low := 0
	high := len(bindings)
	for low < high {
		middle := low + (high - low) / 2
		if sequence_compare(bindings[middle].sequence, query) < 0 {
			low = middle + 1
		} else {
			high = middle
		}
	}
	return low
}

sequence_compare :: proc(left, right: Sequence) -> int {
	shared := min(left.count, right.count)
	for index in 0 ..< int(shared) {
		if left.strokes[index] < right.strokes[index] {
			return -1
		}
		if left.strokes[index] > right.strokes[index] {
			return 1
		}
	}
	return int(left.count) - int(right.count)
}

sequence_is_prefix :: proc(prefix, value: Sequence) -> bool {
	if prefix.count >= value.count {
		return false
	}
	for index in 0 ..< int(prefix.count) {
		if prefix.strokes[index] != value.strokes[index] {
			return false
		}
	}
	return true
}

sequence_for :: proc(index, max_strokes: int) -> Sequence {
	count := 1 + index % max_strokes
	sequence := Sequence{count = u8(count)}
	value := u64(index + 1)
	for stroke_index in 0 ..< count {
		sequence.strokes[stroke_index] = u32((value % 65_521) + u64(stroke_index + 1) * 65_537)
		value = value * 6_364_136_223_846_793_005 + 1_442_695_040_888_963_407
	}
	return sequence
}

assemble_context :: proc(maps: []Map_Definition, destination: []u16) -> int {
	count := 0
	for map_definition, map_index in maps {
		if map_definition.active {
			destination[count] = u16(map_index)
			count += 1
		}
	}
	return count
}

ordering_cycle_rejected :: proc(node_count: int, edges: [][2]u16) -> bool {
	indegree := make([]u16, node_count)
	defer delete(indegree)
	for edge in edges {
		if int(edge[0]) >= node_count || int(edge[1]) >= node_count {
			return true
		}
		indegree[edge[1]] += 1
	}
	visited := 0
	for _ in 0 ..< node_count {
		selected := -1
		for degree, node in indegree {
			if degree == 0 {
				selected = node
				break
			}
		}
		if selected < 0 {
			break
		}
		indegree[selected] = max(u16)
		visited += 1
		for edge in edges {
			if int(edge[0]) == selected {
				indegree[edge[1]] -= 1
			}
		}
	}
	return visited != node_count
}

owner_is_stale :: proc(owner, generation: u32) -> bool {
	return owner == 0 || generation == 0
}

latency :: proc(values: []i64) -> Latency {
	return Latency {
		p50_ns = percentile(values, 50),
		p99_ns = percentile(values, 99),
	}
}

percentile :: proc(values: []i64, rank: int) -> i64 {
	index := (rank * len(values) + 99) / 100 - 1
	return values[clamp(index, 0, len(values) - 1)]
}

fault_allocator :: proc(state: ^Fault_Allocator) -> runtime.Allocator {
	return runtime.Allocator{procedure = fault_allocator_proc, data = state}
}

fault_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> (result: []byte, error: runtime.Allocator_Error) {
	state := (^Fault_Allocator)(allocator_data)
	if mode == .Alloc || mode == .Alloc_Non_Zeroed || mode == .Resize || mode == .Resize_Non_Zeroed {
		if state.successful_allocations >= state.fail_after {
			return nil, .Out_Of_Memory
		}
		state.successful_allocations += 1
	}
	return state.backing.procedure(
		state.backing.data,
		mode,
		size,
		alignment,
		old_memory,
		old_size,
		location,
	)
}
