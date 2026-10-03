// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../ui"
import "base:runtime"

@(private)
Popup_Fallback_State :: struct {
	present:          bool,
	owner_id:         ui.Owner_ID,
	owner_generation: u64,
	style_role:       ui.Style_Role,
	content:          []byte,
	allocator:        runtime.Allocator,
}

@(private)
popup_fallback_prepare :: proc(
	state: ^Popup_Fallback_State,
	owner_id: ui.Owner_ID,
	owner_generation: u64,
	content: string,
	style_role: ui.Style_Role,
	allocator := context.allocator,
) -> bool {
	if state == nil || owner_id == ui.Owner_ID(0) || owner_generation == 0 ||
	   len(content) == 0 || u64(len(content)) > ui.MAX_DIAGNOSTIC_BYTES ||
	   allocator.procedure == nil || !ui.style_role_is_valid(style_role) {
		return false
	}
	retained, allocation_error := make([]byte, len(content), allocator)
	if allocation_error != nil do return false
	copy(retained, transmute([]byte)content)
	popup_fallback_clear(state)
	state^ = Popup_Fallback_State {
		present = true,
		owner_id = owner_id,
		owner_generation = owner_generation,
		style_role = style_role,
		content = retained,
		allocator = allocator,
	}
	return true
}

@(private)
popup_fallback_view :: proc(
	state: ^Popup_Fallback_State,
) -> (content: string, style_role: ui.Style_Role, ok: bool) {
	if state == nil || !state.present || len(state.content) == 0 ||
	   state.allocator.procedure == nil {
		return "", .Invalid, false
	}
	return string(state.content), state.style_role, true
}

@(private)
popup_fallback_clear :: proc(state: ^Popup_Fallback_State) {
	if state == nil do return
	if state.content != nil && state.allocator.procedure != nil {
		delete(state.content, state.allocator)
	}
	state^ = {}
}

@(private)
popup_fallback_required :: proc(
	profile: ui.Renderer_Profile,
	bounds: ui.Popup_Dimension_Bounds,
) -> bool {
	return profile.id == ui.Renderer_Profile_ID(0) || .Popup_Overlap not_in profile.capabilities ||
		profile.max_rows < u32(bounds.minimum_rows) ||
		profile.max_columns < u32(bounds.minimum_columns)
}
