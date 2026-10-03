// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ui

import "base:runtime"

@(private)
Registry_State :: struct {
	id:               Registry_ID,
	generation:       Root_Generation,
	limits:           Resource_Limits,
	allocator:        runtime.Allocator,
	active:           ^Generation_State,
	proposal_active:  bool,
	focus_generation: u64,
}

@(private)
Generation_State :: struct {
	registry:          ^Registry_State,
	registry_id:       Registry_ID,
	expected:          Root_Generation,
	generation:        Root_Generation,
	next_object_id:    Object_ID,
	projections:       []Projection_Descriptor,
	views:             []Visual_View_Descriptor,
	terminal_rows:     []Terminal_Row,
	terminal_cells:    []Terminal_Cell,
	list_items:        []List_Item_Descriptor,
	list_content:      []u8,
	tree_nodes:        []Tree_Node_Descriptor,
	tree_content:      []u8,
	input_choices:     []Input_Choice_Descriptor,
	input_content:     []u8,
	surfaces:          []Surface_Descriptor,
	nodes:             []Composition_Descriptor,
	status_regions:    []Status_Region_Descriptor,
	popups:            []Popup_Descriptor,
	compact_content:   []u8,
	styles:            []Style_Descriptor,
	decorations:       []Decoration_Descriptor,
	projection_count:  int,
	view_count:        int,
	terminal_row_count: int,
	terminal_cell_count: int,
	list_item_count:   int,
	tree_node_count:   int,
	input_choice_count: int,
	surface_count:     int,
	node_count:        int,
	status_count:      int,
	popup_count:       int,
	style_count:       int,
	decoration_count:  int,
	root_node:         Object_Handle,
	focus:             Focus_Descriptor,
	renderer:          Renderer_Profile,
	accounting:        Resource_Accounting,
	allocator:         runtime.Allocator,
}

/* registry_init creates one empty bounded logical UI registry. */
registry_init :: proc(
	registry: ^Registry,
	id: Registry_ID,
	limits := DEFAULT_RESOURCE_LIMITS,
	allocator := context.allocator,
) -> (ok: bool, failure: Failure) {
	if registry == nil {
		return false, Failure{operation = .Initialize, code = .Invalid_Registry}
	}
	registry^ = {}
	if id == Registry_ID(0) || !resource_limits_are_valid(limits) {
		return false, Failure{operation = .Initialize, code = .Invalid_Registry}
	}
	if allocator.procedure == nil {
		return false, Failure{operation = .Initialize, code = .Allocation}
	}
	state, allocation_error := new(Registry_State, allocator)
	if allocation_error != nil {
		return false, Failure{operation = .Initialize, code = .Allocation}
	}
	state^ = Registry_State {
		id = id,
		limits = limits,
		allocator = allocator,
	}
	registry.state = state
	return true, {}
}

/* registry_close releases the active generation and registry storage exactly once. */
registry_close :: proc(registry: ^Registry) -> (ok: bool, failure: Failure) {
	state := registry_state(registry)
	if state == nil {
		return false, registry_failure(registry, .Teardown, .Invalid_Registry)
	}
	if state.proposal_active {
		return false, state_failure(state, .Teardown, .Busy)
	}
	if state.active != nil {
		generation_release(state.active)
	}
	allocator := state.allocator
	free(state, allocator)
	registry^ = Registry{closed = true}
	return true, {}
}

/* registry_handle returns the exact current published root generation. */
registry_handle :: proc(registry: ^Registry) -> (handle: Root_Handle, ok: bool, failure: Failure) {
	state := registry_state(registry)
	if state == nil {
		return {}, false, registry_failure(registry, .Inspect, .Invalid_Registry)
	}
	if state.active == nil || state.generation == Root_Generation(0) {
		return {}, false, state_failure(state, .Inspect, .Invalid_Root)
	}
	return current_root(state), true, {}
}

/* registry_stats returns exact current occupancy and retained accounting. */
registry_stats :: proc(registry: ^Registry) -> (stats: Registry_Stats, ok: bool, failure: Failure) {
	state := registry_state(registry)
	if state == nil || state.active == nil {
		return {}, false, registry_failure(registry, .Inspect, .Invalid_Registry)
	}
	active := state.active
	return Registry_Stats {
		root = current_root(state),
		surfaces = u16(active.surface_count),
		views = u16(active.view_count),
		projections = u16(active.projection_count),
		composition_nodes = u16(active.node_count),
		status_regions = u16(active.status_count),
		popups = u16(active.popup_count),
		styles = u16(active.style_count),
		decorations = u32(active.decoration_count),
		list_items = u32(active.list_item_count),
		tree_nodes = u32(active.tree_node_count),
		focus_captured = active.focus.captured || active.focus.transient.active,
		transient_input_captured = active.focus.transient.active,
		focus_generation = state.focus_generation,
		accounting = active.accounting,
	}, true, {}
}

/* registry_inspect_popup copies one exact published popup descriptor. */
registry_inspect_popup :: proc(
	registry: ^Registry,
	handle: Object_Handle,
) -> (popup: Popup_Descriptor, ok: bool, failure: Failure) {
	state := registry_state(registry)
	if state == nil || state.active == nil {
		return {}, false, registry_failure(registry, .Inspect, .Invalid_Registry)
	}
	if handle.root_generation != state.generation {
		return {}, false, object_failure(state, .Inspect, .Stale_Popup, handle)
	}
	entry, valid := resolve_popup(state.active, handle)
	if !valid {
		return {}, false, object_failure(state, .Inspect, .Invalid_Popup, handle)
	}
	return entry^, true, {}
}

/* registry_focus returns the current checked target and capture state. */
registry_focus :: proc(registry: ^Registry) -> (focus: Focus_Descriptor, ok: bool, failure: Failure) {
	state := registry_state(registry)
	if state == nil || state.active == nil {
		return {}, false, registry_failure(registry, .Inspect, .Invalid_Registry)
	}
	return state.active.focus, true, {}
}

/* registry_inspect_surface copies one exact published surface descriptor. */
registry_inspect_surface :: proc(
	registry: ^Registry,
	handle: Object_Handle,
) -> (surface: Surface_Descriptor, ok: bool, failure: Failure) {
	state := registry_state(registry)
	if state == nil || state.active == nil {
		return {}, false, registry_failure(registry, .Inspect, .Invalid_Registry)
	}
	entry, valid := resolve_surface(state.active, handle)
	if !valid {
		return {}, false, object_failure(state, .Inspect, .Invalid_Surface, handle)
	}
	return entry^, true, {}
}

/* registry_inspect_view copies one exact published visual-view descriptor. */
registry_inspect_view :: proc(
	registry: ^Registry,
	handle: Object_Handle,
) -> (view: Visual_View_Descriptor, ok: bool, failure: Failure) {
	state := registry_state(registry)
	if state == nil || state.active == nil {
		return {}, false, registry_failure(registry, .Inspect, .Invalid_Registry)
	}
	entry, valid := resolve_view(state.active, handle)
	if !valid {
		return {}, false, object_failure(state, .Inspect, .Invalid_View, handle)
	}
	return entry^, true, {}
}

/* registry_focus_surface changes ordinary focus without replacing semantic state. */
registry_focus_surface :: proc(
	registry: ^Registry,
	handle: Object_Handle,
) -> (ok: bool, failure: Failure) {
	state := registry_state(registry)
	if state == nil || state.active == nil {
		return false, registry_failure(registry, .Focus, .Invalid_Registry)
	}
	if state.active.focus.captured || state.active.focus.transient.active {
		return false, object_failure(state, .Focus, .Focus_Captured, handle)
	}
	surface, valid := resolve_surface(state.active, handle)
	if !valid || !surface.focusable || !surface.visible {
		return false, object_failure(state, .Focus, .Invalid_Focus, handle)
	}
	if state.focus_generation == max(u64) {
		return false, state_failure(state, .Focus, .Generation_Limit)
	}
	state.active.focus.target = handle
	state.focus_generation += 1
	return true, {}
}

/* registry_capture_focus gives one input surface exclusive transient focus. */
registry_capture_focus :: proc(
	registry: ^Registry,
	handle: Object_Handle,
) -> (ok: bool, failure: Failure) {
	state := registry_state(registry)
	if state == nil || state.active == nil {
		return false, registry_failure(registry, .Capture_Focus, .Invalid_Registry)
	}
	if state.active.focus.captured || state.active.focus.transient.active {
		return false, object_failure(state, .Capture_Focus, .Focus_Captured, handle)
	}
	surface, surface_ok := resolve_surface(state.active, handle)
	if !surface_ok || !surface.focusable || !surface.visible {
		return false, object_failure(state, .Capture_Focus, .Invalid_Focus, handle)
	}
	view, view_ok := resolve_view(state.active, surface.view)
	if !view_ok || view.kind != .Input {
		return false, object_failure(state, .Capture_Focus, .Invalid_View, surface.view)
	}
	if state.focus_generation == max(u64) {
		return false, state_failure(state, .Capture_Focus, .Generation_Limit)
	}
	state.active.focus = Focus_Descriptor {
		target = handle,
		captured = true,
		return_target = state.active.focus.target,
	}
	state.focus_generation += 1
	return true, {}
}

/* registry_capture_transient_input routes one popup command family without moving source focus. */
registry_capture_transient_input :: proc(
	registry: ^Registry,
	handle: Object_Handle,
) -> (ok: bool, failure: Failure) {
	state := registry_state(registry)
	if state == nil || state.active == nil {
		return false, registry_failure(registry, .Capture_Transient_Input, .Invalid_Registry)
	}
	if state.active.focus.captured || state.active.focus.transient.active {
		return false, object_failure(
			state, .Capture_Transient_Input, .Transient_Input_Captured, handle,
		)
	}
	if handle.root_generation != state.generation {
		return false, object_failure(state, .Capture_Transient_Input, .Stale_Popup, handle)
	}
	popup, popup_ok := resolve_popup(state.active, handle)
	if !popup_ok || popup.behavior != .Interactive ||
	   popup.input_policy != .Transient_Capture ||
	   state.active.focus.target != popup.anchor.source_surface {
		return false, object_failure(
			state, .Capture_Transient_Input, .Invalid_Transient_Input, handle,
		)
	}
	source, source_ok := resolve_surface(state.active, popup.anchor.source_surface)
	content, content_ok := resolve_surface(state.active, popup.content_surface)
	if !source_ok || !source.visible || !source.focusable || !content_ok ||
	   !content.visible || content.focusable {
		return false, object_failure(
			state, .Capture_Transient_Input, .Invalid_Transient_Input, handle,
		)
	}
	view, view_ok := resolve_view(state.active, content.view)
	if !view_ok || view.kind != .List_View {
		return false, object_failure(
			state, .Capture_Transient_Input, .Invalid_Transient_Input, handle,
		)
	}
	if state.focus_generation == max(u64) {
		return false, state_failure(state, .Capture_Transient_Input, .Generation_Limit)
	}
	state.active.focus.transient = {
		active = true,
		popup = popup.handle,
		popup_id = popup.id,
		popup_generation = popup.generation,
		owner_id = popup.owner_id,
		owner_generation = popup.owner_generation,
		source_surface = popup.anchor.source_surface,
	}
	state.focus_generation += 1
	return true, {}
}

/* registry_release_transient_input releases one exact popup capture without changing focus. */
registry_release_transient_input :: proc(
	registry: ^Registry,
	handle: Object_Handle,
) -> (focus: Object_Handle, ok: bool, failure: Failure) {
	state := registry_state(registry)
	if state == nil || state.active == nil {
		return {}, false, registry_failure(registry, .Release_Transient_Input, .Invalid_Registry)
	}
	capture := state.active.focus.transient
	if !capture.active || capture.popup != handle {
		return {}, false, object_failure(
			state, .Release_Transient_Input, .Invalid_Transient_Input, handle,
		)
	}
	if state.focus_generation == max(u64) {
		return {}, false, state_failure(state, .Release_Transient_Input, .Generation_Limit)
	}
	state.active.focus.transient = {}
	state.focus_generation += 1
	return state.active.focus.target, true, {}
}

/* registry_release_focus restores the checked return target or safe root fallback. */
registry_release_focus :: proc(registry: ^Registry) -> (focus: Object_Handle, ok: bool, failure: Failure) {
	state := registry_state(registry)
	if state == nil || state.active == nil {
		return {}, false, registry_failure(registry, .Release_Focus, .Invalid_Registry)
	}
	if !state.active.focus.captured {
		return {}, false, state_failure(state, .Release_Focus, .Invalid_Focus)
	}
	if state.focus_generation == max(u64) {
		return {}, false, state_failure(state, .Release_Focus, .Generation_Limit)
	}
	target := state.active.focus.return_target
	if surface, valid := resolve_surface(state.active, target); !valid ||
	   !surface.focusable || !surface.visible {
		target, valid = first_focusable_surface(state.active)
		if !valid {
			return {}, false, state_failure(state, .Release_Focus, .No_Focus_Fallback)
		}
	}
	state.active.focus = Focus_Descriptor{target = target}
	state.focus_generation += 1
	return target, true, {}
}

@(private)
registry_state :: proc(registry: ^Registry) -> ^Registry_State {
	if registry == nil || registry.state == nil || registry.closed {
		return nil
	}
	return cast(^Registry_State)registry.state
}

@(private)
current_root :: proc(state: ^Registry_State) -> Root_Handle {
	return Root_Handle{registry_id = state.id, generation = state.generation}
}

@(private)
registry_failure :: proc(
	registry: ^Registry,
	operation: Operation,
	code: Failure_Code,
) -> Failure {
	state := registry_state(registry)
	if state == nil {
		return Failure{operation = operation, code = code}
	}
	return state_failure(state, operation, code)
}

@(private)
state_failure :: proc(
	state: ^Registry_State,
	operation: Operation,
	code: Failure_Code,
) -> Failure {
	failure := Failure{operation = operation, code = code}
	if state != nil {
		failure.root = current_root(state)
	}
	return failure
}

@(private)
object_failure :: proc(
	state: ^Registry_State,
	operation: Operation,
	code: Failure_Code,
	handle: Object_Handle,
) -> Failure {
	failure := state_failure(state, operation, code)
	failure.object = handle
	return failure
}

@(private)
generation_failure :: proc(
	state: ^Generation_State,
	operation: Operation,
	code: Failure_Code,
) -> Failure {
	if state == nil {
		return Failure{operation = operation, code = code}
	}
	return state_failure(state.registry, operation, code)
}

@(private)
generation_allocate :: proc(
	registry: ^Registry_State,
) -> (^Generation_State, bool) {
	state, state_error := new(Generation_State, registry.allocator)
	if state_error != nil {
		return nil, false
	}
	state^ = Generation_State {
		registry = registry,
		registry_id = registry.id,
		expected = registry.generation,
		generation = Root_Generation(u64(registry.generation) + 1),
		next_object_id = Object_ID(1),
		allocator = registry.allocator,
	}
	limits := registry.limits
	state.projections, state_error = make([]Projection_Descriptor, limits.live_views, state.allocator)
	if state_error == nil do state.views, state_error = make([]Visual_View_Descriptor, limits.live_views, state.allocator)
	if state_error == nil do state.list_items, state_error = make([]List_Item_Descriptor, limits.list_items, state.allocator)
	if state_error == nil do state.tree_nodes, state_error = make([]Tree_Node_Descriptor, limits.tree_nodes, state.allocator)
	if state_error == nil do state.input_choices, state_error = make([]Input_Choice_Descriptor, limits.fixed_choices, state.allocator)
	if state_error == nil do state.surfaces, state_error = make([]Surface_Descriptor, limits.live_surfaces, state.allocator)
	if state_error == nil do state.nodes, state_error = make([]Composition_Descriptor, limits.composition_nodes, state.allocator)
	if state_error == nil do state.status_regions, state_error = make([]Status_Region_Descriptor, limits.status_regions, state.allocator)
	if state_error == nil do state.popups, state_error = make([]Popup_Descriptor, limits.live_popups, state.allocator)
	if state_error == nil do state.compact_content, state_error = make([]u8, int(limits.compact_region_bytes), state.allocator)
	if state_error == nil do state.styles, state_error = make([]Style_Descriptor, limits.styles, state.allocator)
	if state_error == nil do state.decorations, state_error = make([]Decoration_Descriptor, limits.decorations, state.allocator)
	if state_error != nil {
		generation_release(state)
		return nil, false
	}
	state.accounting.registry_bytes = u64(size_of(Generation_State)) +
		u64(len(state.projections) * size_of(Projection_Descriptor)) +
		u64(len(state.views) * size_of(Visual_View_Descriptor)) +
		u64(len(state.list_items) * size_of(List_Item_Descriptor)) +
		u64(len(state.tree_nodes) * size_of(Tree_Node_Descriptor)) +
		u64(len(state.input_choices) * size_of(Input_Choice_Descriptor)) +
		u64(len(state.surfaces) * size_of(Surface_Descriptor)) +
		u64(len(state.nodes) * size_of(Composition_Descriptor)) +
		u64(len(state.status_regions) * size_of(Status_Region_Descriptor)) +
		u64(len(state.popups) * size_of(Popup_Descriptor)) +
		u64(len(state.compact_content)) +
		u64(len(state.styles) * size_of(Style_Descriptor)) +
		u64(len(state.decorations) * size_of(Decoration_Descriptor))
	return state, true
}

@(private)
generation_release :: proc(state: ^Generation_State) {
	if state == nil {
		return
	}
	allocator := state.allocator
	if state.decorations != nil do delete(state.decorations, allocator)
	if state.styles != nil do delete(state.styles, allocator)
	if state.compact_content != nil do delete(state.compact_content, allocator)
	if state.status_regions != nil do delete(state.status_regions, allocator)
	if state.popups != nil do delete(state.popups, allocator)
	if state.nodes != nil do delete(state.nodes, allocator)
	if state.surfaces != nil do delete(state.surfaces, allocator)
	if state.list_content != nil do delete(state.list_content, allocator)
	if state.list_items != nil do delete(state.list_items, allocator)
	if state.tree_content != nil do delete(state.tree_content, allocator)
	if state.tree_nodes != nil do delete(state.tree_nodes, allocator)
	if state.input_content != nil do delete(state.input_content, allocator)
	if state.input_choices != nil do delete(state.input_choices, allocator)
	if state.terminal_cells != nil do delete(state.terminal_cells, allocator)
	if state.terminal_rows != nil do delete(state.terminal_rows, allocator)
	if state.views != nil do delete(state.views, allocator)
	if state.projections != nil do delete(state.projections, allocator)
	free(state, allocator)
}

@(private)
next_handle :: proc(state: ^Generation_State, slot: int) -> (Object_Handle, bool) {
	if state == nil || state.next_object_id == Object_ID(max(u64)) || slot < 0 ||
	   u64(slot) > u64(max(u32)) {
		return {}, false
	}
	handle := Object_Handle {
		registry_id = state.registry_id,
		object_id = state.next_object_id,
		root_generation = state.generation,
		slot = u32(slot),
		slot_generation = 1,
	}
	state.next_object_id = Object_ID(u64(state.next_object_id) + 1)
	return handle, true
}

@(private)
handle_matches :: proc(actual, expected: Object_Handle) -> bool {
	return actual == expected && actual.registry_id != Registry_ID(0) &&
		actual.object_id != Object_ID(0) && actual.root_generation != Root_Generation(0) &&
		actual.slot_generation != 0
}

@(private)
resolve_projection :: proc(
	state: ^Generation_State,
	handle: Object_Handle,
) -> (^Projection_Descriptor, bool) {
	if state == nil || int(handle.slot) >= state.projection_count {
		return nil, false
	}
	entry := &state.projections[handle.slot]
	return entry, handle_matches(entry.handle, handle)
}

@(private)
resolve_view :: proc(
	state: ^Generation_State,
	handle: Object_Handle,
) -> (^Visual_View_Descriptor, bool) {
	if state == nil || int(handle.slot) >= state.view_count {
		return nil, false
	}
	entry := &state.views[handle.slot]
	return entry, handle_matches(entry.handle, handle)
}

@(private)
resolve_surface :: proc(
	state: ^Generation_State,
	handle: Object_Handle,
) -> (^Surface_Descriptor, bool) {
	if state == nil || int(handle.slot) >= state.surface_count {
		return nil, false
	}
	entry := &state.surfaces[handle.slot]
	return entry, handle_matches(entry.handle, handle)
}

@(private)
resolve_node :: proc(
	state: ^Generation_State,
	handle: Object_Handle,
) -> (^Composition_Descriptor, bool) {
	if state == nil || int(handle.slot) >= state.node_count {
		return nil, false
	}
	entry := &state.nodes[handle.slot]
	return entry, handle_matches(entry.handle, handle)
}

@(private)
resolve_popup :: proc(
	state: ^Generation_State,
	handle: Object_Handle,
) -> (^Popup_Descriptor, bool) {
	if state == nil || int(handle.slot) >= state.popup_count {
		return nil, false
	}
	entry := &state.popups[handle.slot]
	return entry, handle_matches(entry.handle, handle)
}

@(private)
resolve_style_role :: proc(state: ^Generation_State, role: Style_Role) -> bool {
	for style in state.styles[:state.style_count] {
		if style.role == role {
			return true
		}
	}
	return false
}

@(private)
first_focusable_surface :: proc(state: ^Generation_State) -> (Object_Handle, bool) {
	for surface in state.surfaces[:state.surface_count] {
		if surface.focusable && surface.visible {
			return surface.handle, true
		}
	}
	return {}, false
}
