// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package view

/* terminal_view_state returns one copied view-local terminal attachment. */
terminal_view_state :: proc(
	registry: ^Registry,
	handle: View_Handle,
) -> (state: Terminal_View_State, ok: bool, failure: Failure_Context) {
	slot, slot_failure := resolve(registry, handle)
	if slot_failure.code != .None {
		return {}, false, slot_failure
	}
	if !slot.terminal.attached || slot.buffer_kind != .Terminal_Projection {
		return {}, false, view_failure(registry, handle, .Terminal_View_Required)
	}
	return slot.terminal, true, {}
}

/* terminal_viewport_set changes only one terminal view's retained viewport. */
terminal_viewport_set :: proc(
	registry: ^Registry,
	handle: View_Handle,
	viewport: Terminal_Viewport,
) -> (ok: bool, failure: Failure_Context) {
	slot, slot_failure := resolve(registry, handle)
	if slot_failure.code != .None {
		return false, slot_failure
	}
	if !slot.terminal.attached || slot.buffer_kind != .Terminal_Projection {
		return false, view_failure(registry, handle, .Terminal_View_Required)
	}
	if !prepare_mutation(registry, handle, slot) {
		return false, mutation_failure(registry, handle, slot)
	}
	if slot.terminal.viewport == viewport {
		return true, {}
	}
	slot.terminal.viewport = viewport
	slot.state_generation += 1
	return true, {}
}

/* terminal_copy_state_set changes only one terminal view's copy-mode state. */
terminal_copy_state_set :: proc(
	registry: ^Registry,
	handle: View_Handle,
	copy_state: Terminal_Copy_State,
) -> (ok: bool, failure: Failure_Context) {
	slot, slot_failure := resolve(registry, handle)
	if slot_failure.code != .None {
		return false, slot_failure
	}
	if !slot.terminal.attached || slot.buffer_kind != .Terminal_Projection {
		return false, view_failure(registry, handle, .Terminal_View_Required)
	}
	if (!copy_state.active && copy_state != (Terminal_Copy_State{})) ||
	   (copy_state.mark_present && !copy_state.active) {
		return false, view_failure(registry, handle, .Invalid_Terminal_State)
	}
	if !prepare_mutation(registry, handle, slot) {
		return false, mutation_failure(registry, handle, slot)
	}
	if slot.terminal.copy == copy_state {
		return true, {}
	}
	slot.terminal.copy = copy_state
	slot.state_generation += 1
	return true, {}
}

/*
terminal_geometry_claim transfers the single focused-terminal resize authority.
It records geometry only; the terminal-session owner performs the checked PTY resize.
*/
terminal_geometry_claim :: proc(
	registry: ^Registry,
	handle: View_Handle,
	geometry: Terminal_Geometry,
) -> (update: Terminal_Geometry_Update, ok: bool, failure: Failure_Context) {
	data := registry_data(registry)
	if data == nil || data.state != .Ready {
		return {}, false, registry_failure(registry, .Invalid_Registry)
	}
	target, target_failure := resolve(registry, handle)
	if target_failure.code != .None {
		return {}, false, target_failure
	}
	if !target.terminal.attached || target.buffer_kind != .Terminal_Projection {
		return {}, false, view_failure(registry, handle, .Terminal_View_Required)
	}
	if geometry.columns == 0 || geometry.rows == 0 {
		return {}, false, view_failure(registry, handle, .Invalid_Terminal_State)
	}
	previous: View_Handle
	previous_slot: ^View_Slot
	for &candidate, index in data.slots {
		if !candidate.live || !candidate.terminal.geometry_authority {
			continue
		}
		previous = view_handle(data, index)
		previous_slot = &candidate
		break
	}
	if previous_slot != nil && previous_slot != target &&
	   previous_slot.state_generation == max(u64) {
		return {}, false, generation_failure(registry, previous)
	}
	if !prepare_mutation(registry, handle, target) {
		return {}, false, mutation_failure(registry, handle, target)
	}
	if previous_slot != nil && previous_slot != target {
		previous_slot.terminal.geometry_authority = false
		previous_slot.state_generation += 1
	}
	changed := previous != handle || target.terminal.geometry != geometry ||
	           !target.terminal.geometry_authority
	if changed {
		target.terminal.geometry_authority = true
		target.terminal.geometry = geometry
		target.state_generation += 1
	}
	return Terminal_Geometry_Update {
		previous = previous,
		current = handle,
		geometry = geometry,
		changed = changed,
	}, true, {}
}

/* terminal_geometry_release removes authority without detaching the view or session. */
terminal_geometry_release :: proc(
	registry: ^Registry,
	handle: View_Handle,
) -> (ok: bool, failure: Failure_Context) {
	slot, slot_failure := resolve(registry, handle)
	if slot_failure.code != .None {
		return false, slot_failure
	}
	if !slot.terminal.attached || slot.buffer_kind != .Terminal_Projection {
		return false, view_failure(registry, handle, .Terminal_View_Required)
	}
	if !slot.terminal.geometry_authority {
		return false, view_failure(registry, handle, .Geometry_Authority_Required)
	}
	if !prepare_mutation(registry, handle, slot) {
		return false, mutation_failure(registry, handle, slot)
	}
	slot.terminal.geometry_authority = false
	slot.state_generation += 1
	return true, {}
}

@(private)
view_handle :: proc(data: ^Registry_Data, slot_index: int) -> View_Handle {
	slot := &data.slots[slot_index]
	return View_Handle {
		registry_id = data.registry_id,
		view_id = slot.view_id,
		slot = u16(slot_index),
		generation = slot.generation,
	}
}
