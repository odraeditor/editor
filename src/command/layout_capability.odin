// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../layout"

/* Layout_Capability_Access identifies one independently granted layout operation. */
Layout_Capability_Access :: enum u8 {
	Inspect,
	Split_Below,
	Split_Right,
	Focus,
	Close,
	Keep_Only,
	Resize,
	Balance_Dimensions,
	Balance_Areas,
	Inspect_Dedication,
	Set_Dedication,
}

/* Layout_Capability_Access_Set is the immutable authority granted for one turn. */
Layout_Capability_Access_Set :: bit_set[Layout_Capability_Access; u16]

/* Layout_Capability_Failure_Code classifies rejection before a layout call. */
Layout_Capability_Failure_Code :: enum u8 {
	None,
	Invalid_Context,
	Permission_Denied,
	Wrong_Authority,
	Wrong_Layout,
	Stale_Layout,
	Wrong_Pane,
	Stale_Pane,
}

/* Layout_Capability_Scope is the complete pointer-free programmable authority. */
Layout_Capability_Scope :: struct {
	access:        Layout_Capability_Access_Set,
	layout_handle: layout.Layout_Handle,
	pane:          layout.Pane_Handle,
}

/* Layout_Capability_Context borrows one registry behind exact copied identities. */
Layout_Capability_Context :: struct {
	registry:  ^layout.Registry,
	access:    Layout_Capability_Access_Set,
	layout_handle: layout.Layout_Handle,
	pane:      layout.Pane_Handle,
	cancelled: bool,
}

/* Layout_Capability_Result is one pointer-free public mutation outcome. */
Layout_Capability_Result :: struct {
	scope:                Layout_Capability_Scope,
	primary:              layout.Pane_Handle,
	secondary:            layout.Pane_Handle,
	changed:              bool,
	partition_id:         layout.Node_ID,
	arrangement:          layout.Arrangement,
	delta:                i32,
	first_span:           i32,
	second_span:          i32,
	previous_dedication:  layout.Pane_Dedication,
	current_dedication:   layout.Pane_Dedication,
}

/* layout_capability_scope validates and copies the complete current authority. */
layout_capability_scope :: proc(
	ctx: Layout_Capability_Context,
) -> (scope: Layout_Capability_Scope, ok: bool, failure: Failure_Context) {
	if ctx.registry == nil || ctx.access == {} || ctx.registry.state == nil ||
	   ctx.registry.closed || ctx.layout_handle.owner_id == layout.Owner_ID(0) ||
	   ctx.layout_handle.layout_id == layout.Layout_ID(0) ||
	   ctx.layout_handle.generation == layout.Layout_Generation(0) ||
	   ctx.pane.layout != ctx.layout_handle || ctx.pane.pane_id == layout.Pane_ID(0) ||
	   ctx.pane.slot_generation == 0 {
		return {}, false, layout_capability_failure(.Invalid_Context)
	}
	if ctx.cancelled {
		return {}, false, Failure_Context{code = .Cancelled}
	}
	snapshot, inspected, layout_failure := layout.registry_snapshot(ctx.registry, ctx.layout_handle)
	if !inspected {
		return {}, false, layout_capability_layout_failure(layout_failure)
	}
	if !layout_capability_snapshot_contains_pane(snapshot, ctx.pane) {
		return {}, false, layout_capability_failure(.Stale_Pane)
	}
	return Layout_Capability_Scope {
		access = ctx.access,
		layout_handle = snapshot.handle,
		pane = ctx.pane,
	}, true, {}
}

/* layout_capability_snapshot returns one copied current layout generation. */
layout_capability_snapshot :: proc(
	ctx: Layout_Capability_Context,
	expected: Layout_Capability_Scope,
) -> (snapshot: layout.Snapshot, ok: bool, failure: Failure_Context) {
	_, valid, validation_failure := layout_capability_validate(ctx, expected, .Inspect)
	if !valid {
		return {}, false, validation_failure
	}
	inspected_snapshot, inspected, layout_failure := layout.registry_snapshot(
		ctx.registry, expected.layout_handle,
	)
	if !inspected {
		return {}, false, layout_capability_layout_failure(layout_failure)
	}
	return inspected_snapshot, true, {}
}

/* layout_capability_request validates and invokes one public layout operation. */
layout_capability_request :: proc(
	ctx: ^Layout_Capability_Context,
	expected: Layout_Capability_Scope,
	access: Layout_Capability_Access,
	target: layout.Pane_Handle,
	arrangement: layout.Arrangement = .Invalid,
	delta: i32 = 0,
	dedication: layout.Pane_Dedication = .None,
) -> (result: Layout_Capability_Result, ok: bool, failure: Failure_Context) {
	if ctx == nil {
		return {}, false, layout_capability_failure(.Invalid_Context)
	}
	snapshot, valid, validation_failure := layout_capability_validate(ctx^, expected, access)
	if !valid {
		return {}, false, validation_failure
	}
	if target.layout != expected.layout_handle {
		return {}, false, layout_capability_failure(.Wrong_Layout)
	}
	if !layout_capability_snapshot_contains_pane(snapshot, target) {
		return {}, false, layout_capability_failure(.Stale_Pane)
	}
	primary := target
	secondary: layout.Pane_Handle
	changed := false
	partition_id: layout.Node_ID
	first_span, second_span: i32
	result_arrangement := arrangement
	result_delta := delta
	previous_dedication, current_dedication := dedication, dedication

	switch access {
	case .Inspect:
		return {}, false, layout_capability_failure(.Permission_Denied)
	case .Split_Below:
		mutation, mutated, layout_failure := layout.registry_split_below(ctx.registry, target)
		if !mutated {
			return {}, false, layout_capability_layout_failure(layout_failure)
		}
		primary, secondary, changed = mutation.original, mutation.created, true
	case .Split_Right:
		mutation, mutated, layout_failure := layout.registry_split_right(ctx.registry, target)
		if !mutated {
			return {}, false, layout_capability_layout_failure(layout_failure)
		}
		primary, secondary, changed = mutation.original, mutation.created, true
	case .Focus:
		mutation, mutated, layout_failure := layout.registry_focus(ctx.registry, target)
		if !mutated {
			return {}, false, layout_capability_layout_failure(layout_failure)
		}
		primary = mutation.active
		changed = mutation.layout != expected.layout_handle
	case .Close:
		mutation, mutated, layout_failure := layout.registry_close_pane(ctx.registry, target)
		if !mutated {
			return {}, false, layout_capability_layout_failure(layout_failure)
		}
		primary, changed = mutation.active, true
	case .Keep_Only:
		mutation, mutated, layout_failure := layout.registry_keep_only(ctx.registry, target)
		if !mutated {
			return {}, false, layout_capability_layout_failure(layout_failure)
		}
		primary = mutation.active
		changed = mutation.layout != expected.layout_handle
	case .Resize:
		mutation, mutated, layout_failure := layout.registry_resize_pane(
			ctx.registry, target, arrangement, delta,
		)
		if !mutated {
			return {}, false, layout_capability_layout_failure(layout_failure)
		}
		primary = mutation.pane
		changed = true
		partition_id = mutation.partition_id
		result_arrangement = mutation.arrangement
		result_delta = mutation.delta
		first_span, second_span = mutation.first_span, mutation.second_span
	case .Balance_Dimensions:
		mutation, mutated, layout_failure := layout.registry_balance_panes(
			ctx.registry, expected.layout_handle,
		)
		if !mutated {
			return {}, false, layout_capability_layout_failure(layout_failure)
		}
		primary, changed = mutation.active_pane, mutation.changed
	case .Balance_Areas:
		mutation, mutated, layout_failure := layout.registry_balance_pane_areas(
			ctx.registry, expected.layout_handle,
		)
		if !mutated {
			return {}, false, layout_capability_layout_failure(layout_failure)
		}
		primary, changed = mutation.active_pane, mutation.changed
	case .Inspect_Dedication:
		inspection, inspected, layout_failure := layout.registry_pane_dedication_inspect(
			ctx.registry, target,
		)
		if !inspected {
			return {}, false, layout_capability_layout_failure(layout_failure)
		}
		primary = inspection.pane
		previous_dedication, current_dedication = inspection.dedication, inspection.dedication
	case .Set_Dedication:
		mutation, mutated, layout_failure := layout.registry_pane_dedication_set(
			ctx.registry, target, dedication,
		)
		if !mutated {
			return {}, false, layout_capability_layout_failure(layout_failure)
		}
		primary = mutation.pane
		changed = mutation.changed
		previous_dedication = mutation.previous
		current_dedication = mutation.current
	}

	current, current_ok, current_failure := layout.registry_handle(ctx.registry)
	if !current_ok {
		return {}, false, layout_capability_layout_failure(current_failure)
	}
	current_snapshot, current_snapshot_ok, current_snapshot_failure := layout.registry_snapshot(
		ctx.registry, current,
	)
	if !current_snapshot_ok {
		return {}, false, layout_capability_layout_failure(current_snapshot_failure)
	}
	if !layout_capability_snapshot_contains_pane(current_snapshot, primary) {
		primary = current_snapshot.active_pane
	}
	ctx.layout_handle = current
	ctx.pane = primary
	refreshed := Layout_Capability_Scope {
		access = ctx.access,
		layout_handle = current,
		pane = primary,
	}
	return Layout_Capability_Result {
		scope = refreshed,
		primary = primary,
		secondary = secondary,
		changed = changed,
		partition_id = partition_id,
		arrangement = result_arrangement,
		delta = result_delta,
		first_span = first_span,
		second_span = second_span,
		previous_dedication = previous_dedication,
		current_dedication = current_dedication,
	}, true, {}
}

@(private)
layout_capability_validate :: proc(
	ctx: Layout_Capability_Context,
	expected: Layout_Capability_Scope,
	required: Layout_Capability_Access,
) -> (snapshot: layout.Snapshot, ok: bool, failure: Failure_Context) {
	actual, scoped, scope_failure := layout_capability_scope(ctx)
	if !scoped {
		return {}, false, scope_failure
	}
	if required not_in ctx.access {
		return {}, false, layout_capability_failure(.Permission_Denied)
	}
	if expected.access != actual.access {
		return {}, false, layout_capability_failure(.Wrong_Authority)
	}
	if expected.layout_handle.owner_id != actual.layout_handle.owner_id ||
	   expected.layout_handle.layout_id != actual.layout_handle.layout_id {
		return {}, false, layout_capability_failure(.Wrong_Layout)
	}
	if expected.layout_handle.generation != actual.layout_handle.generation {
		return {}, false, layout_capability_failure(.Stale_Layout)
	}
	if expected.pane.layout != expected.layout_handle ||
	   expected.pane.pane_id != actual.pane.pane_id ||
	   expected.pane.slot != actual.pane.slot {
		return {}, false, layout_capability_failure(.Wrong_Pane)
	}
	if expected.pane.slot_generation != actual.pane.slot_generation {
		return {}, false, layout_capability_failure(.Stale_Pane)
	}
	inspected_snapshot, inspected, layout_failure := layout.registry_snapshot(
		ctx.registry, actual.layout_handle,
	)
	if !inspected {
		return {}, false, layout_capability_layout_failure(layout_failure)
	}
	return inspected_snapshot, true, {}
}

@(private)
layout_capability_snapshot_contains_pane :: proc(
	snapshot: layout.Snapshot,
	pane: layout.Pane_Handle,
) -> bool {
	for index in 0 ..< int(snapshot.node_count) {
		node := snapshot.nodes[index]
		if node.kind == .Pane && node.pane == pane {
			return true
		}
	}
	return false
}

@(private)
layout_capability_failure :: proc(code: Layout_Capability_Failure_Code) -> Failure_Context {
	return Failure_Context{code = .Capability_Failure, layout_capability_code = code}
}

@(private)
layout_capability_layout_failure :: proc(failure: layout.Failure_Context) -> Failure_Context {
	return Failure_Context {
		code = .Layout_Failure,
		layout_code = failure.code,
		layout_failure = failure,
		limit = failure.maximum,
		actual = failure.actual,
	}
}
