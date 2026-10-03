// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package layout

/* registry_pane_dedication_inspect copies one pane's current dedication state. */
registry_pane_dedication_inspect :: proc(
	registry: ^Registry,
	pane: Pane_Handle,
) -> (snapshot: Pane_Dedication_Snapshot, ok: bool, failure: Failure_Context) {
	data, resolved := resolve_layout(registry, pane.layout, .Inspect_Dedication)
	if resolved.code != .None {
		return {}, false, resolved
	}
	slot, pane_ref, pane_failure := resolve_pane(data, pane, .Inspect_Dedication)
	if pane_failure.code != .None {
		return {}, false, pane_failure
	}
	return Pane_Dedication_Snapshot {
		layout = current_layout_handle(data),
		pane = pane_handle(data, pane_ref),
		dedication = slot.dedication,
	}, true, {}
}

/* registry_pane_dedication_set publishes one checked pane dedication mutation. */
registry_pane_dedication_set :: proc(
	registry: ^Registry,
	pane: Pane_Handle,
	dedication: Pane_Dedication,
) -> (result: Pane_Dedication_Result, ok: bool, failure: Failure_Context) {
	data, resolved := resolve_layout(registry, pane.layout, .Set_Dedication)
	if resolved.code != .None {
		return {}, false, resolved
	}
	slot, pane_ref, pane_failure := resolve_pane(data, pane, .Set_Dedication)
	if pane_failure.code != .None {
		return {}, false, pane_failure
	}
	if !pane_dedication_is_valid(dedication) {
		failure = data_failure(data, .Set_Dedication, .Invalid_Dedication)
		failure.pane = pane
		failure.dedication = dedication
		return {}, false, failure
	}
	if slot.dedication == dedication {
		return Pane_Dedication_Result {
			layout = current_layout_handle(data),
			pane = pane_handle(data, pane_ref),
			previous = dedication,
			current = dedication,
		}, true, {}
	}
	if data.generation == Layout_Generation(max(u64)) {
		failure = data_failure(data, .Set_Dedication, .Generation_Limit)
		failure.pane = pane
		failure.dedication = dedication
		return {}, false, failure
	}
	if !prepared_state_fits(data) {
		return {}, false, prepared_failure(data, .Set_Dedication)
	}
	proposed, prepared := prepared_state_copy(data, .Set_Dedication)
	if prepared.code != .None {
		return {}, false, prepared
	}
	defer prepared_state_release(proposed)
	proposed_slot := resolve_node(proposed, pane_ref)
	assert(proposed_slot != nil && proposed_slot.kind == .Pane)
	previous := proposed_slot.dedication
	proposed_slot.dedication = dedication
	proposed.generation = Layout_Generation(u64(data.generation) + 1)
	if !validate_layout_state(proposed) {
		return {}, false, data_failure(data, .Set_Dedication, .Invalid_Topology)
	}
	result = Pane_Dedication_Result {
		layout = current_layout_handle(proposed),
		pane = pane_handle(proposed, pane_ref),
		previous = previous,
		current = dedication,
		changed = true,
	}
	registry_publish(registry, proposed)
	return result, true, {}
}

@(private)
pane_dedication_is_valid :: proc(dedication: Pane_Dedication) -> bool {
	return dedication == .None || dedication == .Soft || dedication == .Hard
}

@(private)
registry_dedication_counts :: proc(data: ^Registry_Data) -> (soft, hard: u16) {
	for &slot in data.nodes {
		if !slot.live || slot.kind != .Pane {
			continue
		}
		switch slot.dedication {
		case .Soft:
			soft += 1
		case .Hard:
			hard += 1
		case .None:
		}
	}
	return
}
