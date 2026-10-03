// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import command "../../src/command"
import bridge "../../src/bridge"
import hosting "../../src/hosting"
import ui "../../src/ui"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:slice"
import "core:time"

KIBIBYTE :: 1_024
MEBIBYTE :: 1_024 * KIBIBYTE
MAX_STUDY_CONTENT_BYTES :: int(
	bridge.MAX_UI_ROLE_PROPOSAL_BYTES - bridge.UI_ROLE_REQUEST_HEADER_BYTES -
	4 * bridge.UI_ROLE_CAPABILITY_REQUIREMENT_RECORD_BYTES - 16 - 10 - 4,
)

Profile :: struct {
	name:                   string,
	scenario:               i32,
	list_items:             int,
	samples:                int,
	content_bytes:          u64,
	crossing_gate_ns:       i64,
	snapshot_gate_ns:       i64,
	proposal_gate_ns:       i64,
}

Latency :: struct {
	p50_ns: i64,
	p99_ns: i64,
	calls:  u64,
	ok:     bool,
}

Command_Probe :: struct {
	calls: u64,
}

main :: proc() {
	racket_runtime: hosting.Runtime
	started, start_failure := hosting.runtime_start(&racket_runtime)
	if !started {
		fmt.eprintf("study=ui-role phase=runtime-start valid=false diagnostic=%s\n", start_failure.diagnostic)
		os.exit(1)
	}

	profiles := [?]Profile {
		{
			name = "ordinary",
			scenario = 12,
			list_items = 16,
			samples = 32,
			content_bytes = 4 * KIBIBYTE,
			crossing_gate_ns = 10_000_000,
			snapshot_gate_ns = 250_000_000,
			proposal_gate_ns = 100_000_000,
		},
		{
			name = "demanding",
			scenario = 13,
			list_items = 1_024,
			samples = 16,
			content_bytes = 1 * MEBIBYTE,
			crossing_gate_ns = 10_000_000,
			snapshot_gate_ns = 250_000_000,
			proposal_gate_ns = 150_000_000,
		},
		{
			name = "stress",
			scenario = 14,
			list_items = ui.MAX_LIST_ITEMS,
			samples = 8,
			content_bytes = u64(MAX_STUDY_CONTENT_BYTES),
			crossing_gate_ns = 10_000_000,
			snapshot_gate_ns = 500_000_000,
			proposal_gate_ns = 500_000_000,
		},
	}

	passed := print_policy_evidence()
	for profile, index in profiles {
		passed = run_profile(&racket_runtime, profile, u64(index + 1)) && passed
	}
	stopped, stop_failure := hosting.runtime_shutdown(&racket_runtime)
	if !stopped {
		fmt.eprintf("study=ui-role phase=runtime-stop valid=false diagnostic=%s\n", stop_failure.diagnostic)
		passed = false
	}
	if !passed {
		os.exit(1)
	}
}

print_policy_evidence :: proc() -> bool {
	valid := ui.INITIAL_ROLE_COUNT == 7 && ui.MAX_ROLE_PROVIDERS == 64 &&
		ui.MAX_ROLE_PROVIDER_NAME_BYTES == 96 && ui.MAX_ROLE_PACKAGE_NAME_BYTES == 256 &&
		ui.MAX_ROLE_COMMAND_NAME_BYTES == 96 &&
		ui.MAX_ROLE_PROPOSAL_BYTES == bridge.MAX_UI_ROLE_PROPOSAL_BYTES &&
		ui.MAX_ROLE_CALLBACKS_PER_TURN == 256
	fmt.printf(
		"study=ui-role profile=policy valid=%v roles=%d providers=%d provider_name_bytes=%d package_name_bytes=%d command_name_bytes=%d proposal_bytes=%d callback_budget=%d snapshot_bytes=%d scope=session failure_fallback=built-in timeout=measured-turn-completion\n",
		valid,
		ui.INITIAL_ROLE_COUNT,
		ui.MAX_ROLE_PROVIDERS,
		ui.MAX_ROLE_PROVIDER_NAME_BYTES,
		ui.MAX_ROLE_PACKAGE_NAME_BYTES,
		ui.MAX_ROLE_COMMAND_NAME_BYTES,
		ui.MAX_ROLE_PROPOSAL_BYTES,
		ui.MAX_ROLE_CALLBACKS_PER_TURN,
		ui.MAX_SNAPSHOT_BYTES,
	)
	return valid
}

run_profile :: proc(runtime: ^hosting.Runtime, profile: Profile, identity: u64) -> bool {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)

	registry: ui.Registry
	registry_ready, _ := ui.registry_init(&registry, ui.Registry_ID(100 + identity), ui.DEFAULT_RESOURCE_LIMITS, allocator)
	if !registry_ready {
		mem.tracking_allocator_destroy(&tracking)
		return false
	}
	root, published := publish_list_root(&registry, profile.list_items, allocator)
	if !published {
		ui.registry_close(&registry)
		mem.tracking_allocator_destroy(&tracking)
		return false
	}

	roles: ui.Role_Registry
	roles_ready, _ := ui.role_registry_init(
		&roles,
		ui.Role_Session_ID(200 + identity),
		1,
		allocator,
	)
	if !roles_ready {
		ui.registry_close(&registry)
		mem.tracking_allocator_destroy(&tracking)
		return false
	}

	renderer := resource_renderer()
	_ = measure_turn(runtime, &roles, &registry, renderer, 0, 1)
	_ = measure_turn(runtime, &roles, &registry, renderer, 6, 1)
	_ = measure_turn(runtime, &roles, &registry, renderer, profile.scenario, 1)
	crossing := measure_turn(runtime, &roles, &registry, renderer, 0, profile.samples)
	snapshot := measure_turn(runtime, &roles, &registry, renderer, 6, profile.samples)
	proposal := measure_turn(runtime, &roles, &registry, renderer, profile.scenario, profile.samples)
	stats, stats_ok, _ := ui.role_registry_stats(&roles)
	live_bytes := tracking.current_memory_allocated
	peak_bytes := tracking.peak_memory_allocated
	roles_closed, _ := ui.role_registry_close(&roles)
	registry_closed, _ := ui.registry_close(&registry)
	cleanup_bytes := tracking.current_memory_allocated
	mem.tracking_allocator_destroy(&tracking)

	valid := root.generation != ui.Root_Generation(0) && crossing.ok && snapshot.ok &&
		proposal.ok && stats_ok && stats.package_providers == 0 &&
		crossing.p99_ns <= profile.crossing_gate_ns &&
		snapshot.p99_ns <= profile.snapshot_gate_ns &&
		proposal.p99_ns <= profile.proposal_gate_ns &&
		roles_closed && registry_closed && cleanup_bytes == 0
	fmt.printf(
		"study=ui-role profile=%s valid=%v samples=%d list_items=%d content_bytes=%d proposal_limit_bytes=%d crossing_calls=%d crossing_p50_ns=%d crossing_p99_ns=%d crossing_gate_ns=%d snapshot_calls=%d snapshot_p50_ns=%d snapshot_p99_ns=%d snapshot_gate_ns=%d proposal_activation_callback_calls=%d proposal_activation_callback_p50_ns=%d proposal_activation_callback_p99_ns=%d proposal_gate_ns=%d retained_bytes=%d peak_bytes=%d package_providers=%d teardown_bytes=%d\n",
		profile.name,
		valid,
		profile.samples,
		profile.list_items,
		profile.content_bytes,
		bridge.MAX_UI_ROLE_PROPOSAL_BYTES,
		crossing.calls,
		crossing.p50_ns,
		crossing.p99_ns,
		profile.crossing_gate_ns,
		snapshot.calls,
		snapshot.p50_ns,
		snapshot.p99_ns,
		profile.snapshot_gate_ns,
		proposal.calls,
		proposal.p50_ns,
		proposal.p99_ns,
		profile.proposal_gate_ns,
		live_bytes,
		peak_bytes,
		stats.package_providers,
		cleanup_bytes,
	)
	return valid
}

measure_turn :: proc(
	runtime: ^hosting.Runtime,
	roles: ^ui.Role_Registry,
	registry: ^ui.Registry,
	renderer: ui.Renderer_Profile,
	scenario: i32,
	sample_count: int,
) -> Latency {
	samples := make([]i64, sample_count)
	defer delete(samples)
	probe: Command_Probe
	result := Latency{ok = true}
	for sample in 0 ..< sample_count {
		started := time.tick_now()
		turn, ok, _ := command.racket_ui_role_turn(
			runtime,
			roles,
			registry,
			renderer,
			scenario,
			resource_command,
			&probe,
		)
		samples[sample] = time.duration_nanoseconds(time.tick_since(started))
		result.calls += u64(turn.calls)
		result.ok = ok && result.ok
	}
	slice.sort(samples)
	result.p50_ns = percentile(samples, 50)
	result.p99_ns = percentile(samples, 99)
	if scenario >= 12 && scenario <= 14 {
		result.ok = probe.calls == u64(sample_count) && result.ok
	}
	return result
}

publish_list_root :: proc(
	registry: ^ui.Registry,
	item_count: int,
	allocator: mem.Allocator,
) -> (root: ui.Root_Handle, ok: bool) {
	items, allocation_error := make([]ui.List_Item_Definition, item_count, allocator)
	if allocation_error != nil {
		return {}, false
	}
	defer delete(items, allocator)
	for index in 0 ..< item_count {
		items[index] = ui.List_Item_Definition {
			id = ui.List_Item_ID(index + 1),
			text = "programmable role item",
			action = {
				owner_id = 1,
				action_id = ui.List_Action_ID(index + 1),
				generation = 1,
			},
		}
	}

	proposal, prepared, _ := ui.proposal_begin(registry)
	if !prepared {
		return {}, false
	}
	defer if proposal.state != nil do ui.proposal_abort(&proposal)
	_, normal_ok, _ := ui.proposal_add_style(&proposal, .List_Normal)
	_, current_ok, _ := ui.proposal_add_style(&proposal, .List_Current, {.Reverse})
	view, view_ok, _ := ui.proposal_project_list_view(
		&proposal,
		ui.List_Projection_Request {
			model = {owner_id = 1, model_id = 1, generation = 1},
			position = {
				presentation_generation = 1,
				selection_owner = .Model,
				current_item = 0,
				first_visible_item = 0,
				viewport_items = u32(min(item_count, 64)),
			},
		},
		items,
	)
	if !view_ok {
		return {}, false
	}
	surface, surface_ok, _ := ui.proposal_add_surface(
		&proposal,
		ui.Surface_Descriptor {
			owner_id = 1,
			view = view,
			focusable = true,
			visible = true,
			required_profile = 1,
			geometry = {height = 64, width = 240},
		},
	)
	node, node_ok, _ := ui.proposal_add_surface_node(&proposal, surface)
	root_ok, _ := ui.proposal_set_root(&proposal, node, surface)
	published: bool
	root, published, _ = ui.proposal_publish(registry, &proposal, resource_renderer())
	return root, normal_ok && current_ok && surface_ok && node_ok && root_ok && published
}

resource_command :: proc(
	user_data: rawptr,
	role: ui.Role,
	provider: ui.Role_Provider_Handle,
	command_name: string,
) -> bool {
	probe := (^Command_Probe)(user_data)
	if probe == nil || role != .Startup || provider.provider_id == ui.Role_Provider_ID(0) ||
	   command_name != "open" {
		return false
	}
	probe.calls += 1
	return true
}

resource_renderer :: proc() -> ui.Renderer_Profile {
	return ui.Renderer_Profile {
		id = 1,
		capabilities = {
			.Cell_Geometry,
			.Clipping,
			.Unicode_Profile,
			.Text_Cursor,
			.Input_Cursor,
			.Semantic_Attributes,
			.Atomic_Generation,
			.Full_Redraw,
		},
		unicode_profile = 17,
		max_rows = 80,
		max_columns = 240,
		max_cells = 19_200,
		attributes = {.Bold, .Dim, .Underline, .Reverse},
	}
}

percentile :: proc(samples: []i64, percent: int) -> i64 {
	if len(samples) == 0 {
		return 0
	}
	index := max(0, min(len(samples) - 1, (len(samples) * percent + 99) / 100 - 1))
	return samples[index]
}
