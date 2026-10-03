// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "base:runtime"
import "core:fmt"
import "core:time"
import "../command"
import "../editor_session"
import "../hosting"
import "../interaction"
import "../layout"
import "../terminal_emulator"
import "../terminal_session"
import "../ui"

/* Terminal_Workflow_Stage identifies the failed terminal composition step. */
Terminal_Workflow_Stage :: enum u8 {
	None,
	Initialize,
	Open,
	Project,
	Register_Buffer,
	Present,
	Input,
	Refresh,
	Close,
}

/* Terminal_Workflow_Failure preserves typed details from one failed step. */
Terminal_Workflow_Failure :: struct {
	stage:    Terminal_Workflow_Stage,
	terminal: terminal_session.Failure_Record,
	session:  editor_session.Failure_Context,
	layout:   layout.Failure_Context,
	ui:       ui.Failure,
}

/* Terminal_One_Shot_Kind classifies task-backed terminal sessions. */
Terminal_One_Shot_Kind :: enum u8 {
	None,
	Shell,
	Async_Shell,
	Compilation,
}

/* Terminal_Workflow_Entry associates one terminal session with its editor entry. */
Terminal_Workflow_Entry :: struct {
	terminal: terminal_session.Session_Ref,
	entry:    editor_session.Entry_Handle,
	live:     bool,
	columns:  u16,
	rows:     u16,
	cell_width_pixels:  u32,
	cell_height_pixels: u32,
	scope:    Terminal_Workflow_Scope,
	default_session: bool,
	focus_sequence:  u64,
	yank:            command.Terminal_Yank_State,
	yanked_codepoints: u32,
	yanked_multiline:  bool,
	prompt_sequence:   u64,
	copy_mode:         terminal_session.Copy_Mode_State,
	audible_attention: bool,
	visual_attention:  bool,
	one_shot_kind:     Terminal_One_Shot_Kind,
}

/* Terminal_Workflow_Scope identifies one Workspace or instance-global terminal set. */
Terminal_Workflow_Scope :: struct {
	kind:      Terminal_Context_Scope,
	workspace: editor_session.Workspace_ID,
}

/* Terminal_Toggle_Presentation remembers one reversible lower-pane attachment. */
Terminal_Toggle_Presentation :: struct {
	visible:      bool,
	pane:         layout.Pane_Handle,
	return_pane:  layout.Pane_Handle,
	return_entry: editor_session.Entry_Handle,
	terminal:     terminal_session.Session_Ref,
	scope:        Terminal_Workflow_Scope,
	height:       i32,
}

/* Terminal_Pointer_Capture retains one app-owned local or child gesture identity. */
Terminal_Pointer_Capture :: struct {
	active:              bool,
	route:               terminal_session.Mouse_Route,
	frontend:            interaction.Pointer_Frontend_ID,
	source:              interaction.Pointer_Source_ID,
	button:              interaction.Pointer_Button,
	root_generation:     interaction.Pointer_Root_Generation,
	geometry_generation: interaction.Pointer_Geometry_Generation,
	last_sequence:       interaction.Pointer_Sequence,
	started_at:          time.Tick,
	event_count:         u32,
	terminal:            terminal_session.Session_Ref,
	content_row:         i32,
	content_column:      i32,
}

/* Terminal_Workflow_State owns composed terminal sessions and editor associations. */
Terminal_Workflow_State :: struct {
	registry:    terminal_session.Registry,
	entries:     [terminal_session.MAX_SESSIONS]Terminal_Workflow_Entry,
	initialized: bool,
	allocator:   runtime.Allocator,
	clock_start: time.Tick,
	next_delivery_generation: u64,
	attention: Terminal_Attention_Channel,
	literal_next: terminal_session.Session_Ref,
	next_name_index: u32,
	next_focus_sequence: u64,
	toggle: Terminal_Toggle_Presentation,
	pointer_capture: Terminal_Pointer_Capture,
	exit_confirmed: bool,
	last_compile_command: [4_096]u8,
	last_compile_length:  u16,
}

/* terminal_workflow_deliver_events runs at most one queued subscriber on Racket's owner thread. */
terminal_workflow_deliver_events :: proc(commands: ^Command_Context) {
	if commands == nil || commands.terminal_workflow == nil ||
	   !commands.terminal_workflow.initialized || commands.racket_runtime == nil ||
	   !terminal_session.registry_event_pending(&commands.terminal_workflow.registry) {
		return
	}
	workflow := commands.terminal_workflow
	descriptors: [terminal_session.MAX_SESSIONS]command.Terminal_Capability_Session
	count: int
	for &entry in workflow.entries {
		if !entry.live do continue
		descriptor := &descriptors[count]
		descriptor.ref = entry.terminal
		switch entry.scope.kind {
		case .Instance:
			descriptor.scope = .Instance
		case .Workspace:
			descriptor.scope = .Workspace
			descriptor.workspace_identity = string(entry.scope.workspace.bytes[:entry.scope.workspace.length])
		case .Invalid:
			continue
		}
		count += 1
	}
	if count == 0 do return
	title_bytes: u64
	for descriptor in descriptors[:count] {
		metadata, copied, _ := terminal_session.registry_metadata_copy(
			&workflow.registry, descriptor.ref, .Title, nil,
		)
		if copied && metadata.required_bytes <= terminal_session.MAX_METADATA_BYTES {
			title_bytes += metadata.required_bytes
		}
	}
	title_storage: []u8
	if title_bytes > 0 {
		allocation_error: runtime.Allocator_Error
		title_storage, allocation_error = make([]u8, int(title_bytes), workflow.allocator)
		if allocation_error != nil do return
		defer delete(title_storage, workflow.allocator)
		cursor := 0
		for &descriptor in descriptors[:count] {
			metadata, copied, _ := terminal_session.registry_metadata_copy(
				&workflow.registry, descriptor.ref, .Title, title_storage[cursor:],
			)
			if !copied || metadata.truncated do continue
			length := int(metadata.copied_bytes)
			descriptor.title = string(title_storage[cursor:cursor + length])
			cursor += length
		}
	}
	workflow.next_delivery_generation += 1
	if workflow.next_delivery_generation == 0 do workflow.next_delivery_generation = 1
	turn, delivered, failure := command.racket_terminal_delivery_turn(
		commands.racket_runtime,
		command.Terminal_Capability_Context {
			registry = &workflow.registry,
			sessions = descriptors[:count],
			authority_generation = workflow.next_delivery_generation,
			access = {.Inspect, .Input, .Terminate, .Subscribe},
			now_nanoseconds = terminal_workflow_now_ns(workflow),
		},
	)
	if !delivered {
		if turn.delivery_ref.id != 0 {
			_, _ = terminal_session.registry_event_reject(
				&workflow.registry, turn.delivery_ref,
				{stage = .Process, code = .Event_Limit},
			)
		}
		diagnostic := hosting.runtime_diagnostic(commands.racket_runtime)
		if len(diagnostic) == 0 {
			diagnostic = fmt.tprintf("Terminal event delivery unavailable (%v)", failure)
		}
		command_context_set_diagnostic(commands, diagnostic)
	}
}

@(private)
app_terminal_workflow_failure :: proc(failure: Terminal_Workflow_Failure) -> App_Failure {
	return App_Failure {
		stage = .Terminal_Workflow,
		terminal_workflow_stage = failure.stage,
		terminal_session_failure = failure.terminal,
		editor_session = failure.session,
		layout = failure.layout,
		ui = failure.ui,
	}
}

/* Terminal_Presentation selects where a newly opened terminal buffer appears. */
Terminal_Presentation :: enum u8 {
	Replace_Active,
	Other_Pane,
	Hidden,
}

/* Terminal_Open_Request describes one bounded terminal buffer creation. */
Terminal_Open_Request :: struct {
	name:            string,
	working_context: string,
	terminal:        terminal_session.Open_Request,
	presentation:    Terminal_Presentation,
	configuration:   editor_session.Entry_Configuration,
	scope:           Terminal_Workflow_Scope,
	default_session: bool,
	one_shot_kind:   Terminal_One_Shot_Kind,
}

/* Terminal_Open_Result identifies the composed terminal, buffer, pane, and view. */
Terminal_Open_Result :: struct {
	terminal: terminal_session.Session_Ref,
	entry:    editor_session.Entry_Handle,
	pane:     layout.Pane_Handle,
	view:     editor_session.Terminal_Buffer_State,
}

/* terminal_workflow_init initializes terminal composition ownership. */
terminal_workflow_init :: proc(
	workflow: ^Terminal_Workflow_State,
	allocator := context.allocator,
) -> (bool, Terminal_Workflow_Failure) {
	if workflow == nil || workflow.initialized || allocator.procedure == nil {
		return false, Terminal_Workflow_Failure{stage = .Initialize}
	}
	workflow^ = {}
	initialized, failure := terminal_session.registry_init(&workflow.registry, allocator)
	if !initialized do return false, {stage = .Initialize, terminal = failure}
	workflow.initialized = true
	workflow.allocator = allocator
	workflow.clock_start = time.tick_now()
	workflow.next_name_index = 1
	workflow.next_focus_sequence = 1
	return true, {}
}

/* terminal_workflow_open creates and presents one terminal-backed buffer. */
terminal_workflow_open :: proc(
	workflow: ^Terminal_Workflow_State,
	session: ^editor_session.Session,
	session_handle: editor_session.Session_Handle,
	layout_registry: ^layout.Registry,
	request: Terminal_Open_Request,
) -> (result: Terminal_Open_Result, ok: bool, failure: Terminal_Workflow_Failure) {
	if workflow == nil || !workflow.initialized || session == nil || layout_registry == nil ||
	   len(request.name) == 0 || len(request.working_context) == 0 ||
	   request.scope.kind == .Invalid ||
	   (request.presentation != .Replace_Active && request.presentation != .Other_Pane &&
	    request.presentation != .Hidden) {
		return {}, false, {stage = .Open}
	}
	record, opened, terminal_failure := terminal_session.registry_open(&workflow.registry, request.terminal)
	if !opened do return {}, false, {stage = .Open, terminal = terminal_failure}
	retain_terminal := false
	defer if !retain_terminal do _, _ = terminal_session.registry_close_session(&workflow.registry, record.ref)
	_, effect_configured, effect_failure := terminal_session.registry_effect_configure(
		&workflow.registry,
		record.ref,
		terminal_workflow_effect_policy(workflow.attention),
	)
	if !effect_configured do return {}, false, {stage = .Open, terminal = effect_failure}
	text, text_ok, text_failure := terminal_workflow_copy_screen(workflow, record.ref, request.terminal.limits.copied_text_bytes)
	if !text_ok do return {}, false, {stage = .Project, terminal = text_failure}
	defer delete(text, workflow.allocator)
	admission, admitted, session_failure := editor_session.session_create_terminal_buffer(
		session,
		editor_session.Create_Terminal_Buffer_Request {
			session = session_handle,
			name = request.name,
			terminal = {
				ref = terminal_editor_ref(record.ref),
				lifecycle = terminal_editor_lifecycle(record.lifecycle),
				working_context = request.working_context,
			},
			copied_projection = string(text),
			configuration = request.configuration,
		},
	)
	if !admitted do return {}, false, {stage = .Register_Buffer, session = session_failure}
	retain_entry := false
	defer if !retain_entry do terminal_workflow_abandon_entry(session, admission.entry)
	layout_handle, layout_ok, layout_failure := layout.registry_handle(layout_registry)
	if !layout_ok do return {}, false, {stage = .Present, layout = layout_failure}
	pane: layout.Pane_Handle
	if request.presentation == .Replace_Active {
		snapshot, snapshot_ok, snapshot_failure := layout.registry_snapshot(layout_registry, layout_handle)
		if !snapshot_ok do return {}, false, {stage = .Present, layout = snapshot_failure}
		replaced, replaced_ok, replace_failure := layout.registry_replace_pane_buffer(
			layout_registry, snapshot.active_pane, session, admission.entry,
		)
		if !replaced_ok do return {}, false, {stage = .Present, layout = replace_failure}
		pane = replaced.pane
	} else if request.presentation == .Other_Pane {
		display_request, requested, request_failure := layout.registry_display_request(
			layout_registry, layout_handle, session, admission.entry,
		)
		if !requested do return {}, false, {stage = .Present, layout = request_failure}
		proposal, proposed, proposal_failure := layout.registry_display_policy_factory_proposal(
			layout_registry, session, display_request,
		)
		if !proposed do return {}, false, {stage = .Present, layout = proposal_failure}
		displayed, displayed_ok, display_failure := layout.registry_display_buffer(
			layout_registry, session, proposal,
		)
		if !displayed_ok do return {}, false, {stage = .Present, layout = display_failure}
		pane = displayed.pane
	}
	index := int(u32(record.ref.id) - 1)
	workflow.entries[index] = {
		terminal = record.ref,
		entry = admission.entry,
		live = true,
		columns = request.terminal.emulator.columns,
		rows = request.terminal.emulator.rows,
		cell_width_pixels = request.terminal.emulator.cell_width_pixels,
		cell_height_pixels = request.terminal.emulator.cell_height_pixels,
		scope = request.scope,
		default_session = request.default_session,
		one_shot_kind = request.one_shot_kind,
		focus_sequence = workflow.next_focus_sequence,
	}
	workflow.next_focus_sequence += 1
	state, state_ok, state_failure := editor_session.session_terminal_buffer_state(session, admission.entry)
	if !state_ok do return {}, false, {stage = .Register_Buffer, session = state_failure}
	retain_entry = true
	retain_terminal = true
	return {terminal = record.ref, entry = admission.entry, pane = pane, view = state}, true, {}
}

/* terminal_workflow_refresh advances output and refreshes copied editor state. */
terminal_workflow_refresh :: proc(
	workflow: ^Terminal_Workflow_State,
	session: ^editor_session.Session,
	ref: terminal_session.Session_Ref,
) -> (state: editor_session.Terminal_Buffer_State, ok: bool, failure: Terminal_Workflow_Failure) {
	state, _, ok, failure = terminal_workflow_refresh_observed(workflow, session, ref)
	return
}

/* terminal_workflow_refresh_all advances every retained terminal by one fair application turn. */
terminal_workflow_refresh_all :: proc(
	workflow: ^Terminal_Workflow_State,
	session: ^editor_session.Session,
) -> (changed: bool, ok: bool, failure: Terminal_Workflow_Failure) {
	if workflow == nil || !workflow.initialized || session == nil {
		return false, false, {stage = .Refresh}
	}
	for entry in workflow.entries {
		if !entry.live do continue
		_, entry_changed, refreshed, refresh_failure := terminal_workflow_refresh_observed(
			workflow,
			session,
			entry.terminal,
		)
		if !refreshed do return changed, false, refresh_failure
		changed = changed || entry_changed
	}
	return changed, true, {}
}

/* terminal_workflow_resize aligns one live PTY and emulator with its pane geometry. */
terminal_workflow_resize :: proc(
	workflow: ^Terminal_Workflow_State,
	ref: terminal_session.Session_Ref,
	columns, rows: u16,
) -> (changed: bool, ok: bool, failure: Terminal_Workflow_Failure) {
	entry := terminal_workflow_entry_record(workflow, ref)
	if entry == nil || columns == 0 || rows == 0 do return false, false, {stage = .Present}
	if entry.columns == columns && entry.rows == rows do return false, true, {}
	resized, terminal_failure := terminal_session.registry_resize(
		&workflow.registry,
		ref,
		columns,
		rows,
		entry.cell_width_pixels,
		entry.cell_height_pixels,
	)
	if !resized {
		record, recorded, _ := terminal_session.registry_poll(&workflow.registry, ref)
		if recorded && record.lifecycle == .Exited do return false, true, {}
		return false, false, {stage = .Present, terminal = terminal_failure}
	}
	entry.columns = columns
	entry.rows = rows
	return true, true, {}
}

@(private)
terminal_workflow_refresh_observed :: proc(
	workflow: ^Terminal_Workflow_State,
	session: ^editor_session.Session,
	ref: terminal_session.Session_Ref,
) -> (
	state: editor_session.Terminal_Buffer_State,
	changed: bool,
	ok: bool,
	failure: Terminal_Workflow_Failure,
) {
	entry, found := terminal_workflow_entry(workflow, ref)
	if !found do return {}, false, false, {stage = .Refresh}
	before, before_ok, before_failure := terminal_session.registry_record(&workflow.registry, ref)
	if !before_ok do return {}, false, false, {stage = .Refresh, terminal = before_failure}
	observation, stepped := terminal_session.registry_step_output(
		&workflow.registry, ref, terminal_workflow_now_ns(workflow),
	)
	if !stepped do return {}, false, false, {stage = .Refresh, terminal = observation.failure}
	record, recorded, record_failure := terminal_session.registry_poll(&workflow.registry, ref)
	if !recorded && record.lifecycle != .Failed {
		return {}, false, false, {stage = .Refresh, terminal = record_failure}
	}
	if record.lifecycle != .Running && workflow.pointer_capture.terminal == ref {
		workflow.pointer_capture = {}
	}
	entry_record := terminal_workflow_entry_record(workflow, ref)
	if entry_record == nil do return {}, false, false, {stage = .Refresh}
	attention_changed := entry_record.audible_attention != observation.effects.audible_attention ||
		entry_record.visual_attention != observation.effects.visual_attention
	entry_record.audible_attention = observation.effects.audible_attention
	entry_record.visual_attention = observation.effects.visual_attention
	changed = observation.progress || before.lifecycle != record.lifecycle || attention_changed
	if !changed {
		current_state, current_ok, session_failure := editor_session.session_terminal_buffer_state(session, entry)
		if !current_ok do return {}, false, false, {stage = .Refresh, session = session_failure}
		return current_state, false, true, {}
	}
	text, text_ok, text_failure := terminal_workflow_copy_screen(
		workflow, ref, terminal_session.DEFAULT_LIMITS.copied_text_bytes,
	)
	if !text_ok do return {}, false, false, {stage = .Refresh, terminal = text_failure}
	defer delete(text, workflow.allocator)
	session_failure: editor_session.Failure_Context
	state, ok, session_failure = editor_session.session_refresh_terminal_buffer(
		session,
		editor_session.Terminal_Buffer_Update_Request {
			entry = entry,
			terminal = terminal_editor_ref(ref),
			lifecycle = terminal_editor_lifecycle(record.lifecycle),
			copied_projection = string(text),
		},
	)
	if !ok do return {}, false, false, {stage = .Refresh, session = session_failure}
	return state, true, true, {}
}

/* terminal_workflow_project_ui copies one terminal revision into a UI proposal. */
terminal_workflow_project_ui :: proc(
	workflow: ^Terminal_Workflow_State,
	proposal: ^ui.Proposal,
	ref: terminal_session.Session_Ref,
	owner: ui.Owner_ID,
	title: string,
) -> (ui.Object_Handle, bool, Terminal_Workflow_Failure) {
	revision, projected, terminal_failure := terminal_session.registry_project_render(&workflow.registry, ref)
	if !projected do return {}, false, {stage = .Project, terminal = terminal_failure}
	rows, row_error := make([]terminal_session.Render_Row, int(revision.row_count), workflow.allocator)
	if row_error != nil do return {}, false, {stage = .Project}
	defer delete(rows, workflow.allocator)
	cells, cell_error := make([]terminal_session.Render_Cell, int(revision.cell_count), workflow.allocator)
	if cell_error != nil do return {}, false, {stage = .Project}
	defer delete(cells, workflow.allocator)
	if _, copied, copy_failure := terminal_session.registry_copy_render_rows(&workflow.registry, ref, rows); !copied {
		return {}, false, {stage = .Project, terminal = copy_failure}
	}
	if _, copied, copy_failure := terminal_session.registry_copy_render_cells(&workflow.registry, ref, cells); !copied {
		return {}, false, {stage = .Project, terminal = copy_failure}
	}
	ui_rows, ui_row_error := make([]ui.Terminal_Row, len(rows), workflow.allocator)
	if ui_row_error != nil do return {}, false, {stage = .Project}
	defer delete(ui_rows, workflow.allocator)
	ui_cells, ui_cell_error := make([]ui.Terminal_Cell, len(cells), workflow.allocator)
	if ui_cell_error != nil do return {}, false, {stage = .Project}
	defer delete(ui_cells, workflow.allocator)
	entry := terminal_workflow_entry_record(workflow, ref)
	copy_state := terminal_session.Copy_Mode_State{}
	if entry != nil do copy_state = entry.copy_mode
	for row, index in rows do ui_rows[index] = terminal_ui_row(row)
	for cell, index in cells {
		ui_cells[index] = terminal_ui_cell(cell)
		if copy_state.active {
			absolute_row := copy_state.viewport_top_row + u64(cell.row)
			ui_cells[index].selected = terminal_copy_position_selected(
				copy_state, absolute_row, u32(cell.column),
			)
		}
	}
	images: [terminal_session.MAX_IMAGE_PLACEMENTS]terminal_session.Image_Placement
	image_count, images_copied, image_failure := terminal_session.registry_copy_image_placements(
		&workflow.registry, ref, images[:],
	)
	if !images_copied do return {}, false, {stage = .Project, terminal = image_failure}
	terminal_workflow_apply_image_fallbacks(
		ui_cells,
		revision.projection.columns,
		revision.projection.rows,
		images[:image_count],
		revision.images_truncated,
	)
	record, recorded, record_failure := terminal_session.registry_record(&workflow.registry, ref)
	if !recorded do return {}, false, {stage = .Project, terminal = record_failure}
	metadata_storage: [terminal_session.MAX_METADATA_BYTES]u8
	metadata, metadata_ok, _ := terminal_session.registry_metadata_copy(
		&workflow.registry, ref, .Title, metadata_storage[:],
	)
	resolved_title := title
	if metadata_ok && !metadata.truncated && metadata.copied_bytes > 0 {
		resolved_title = string(metadata_storage[:metadata.copied_bytes])
	}
	request := terminal_ui_request(owner, resolved_title, record, revision)
	if entry != nil {
		request.audible_attention = entry.audible_attention
		request.visual_attention = entry.visual_attention
	}
	if copy_state.active {
		request.damage = .Full
		request.cursor.column = u16(min(copy_state.point_column, u32(max(u16))))
		request.cursor.visible = true
		request.cursor.blinking = false
		request.cursor.style = .Block
		request.cursor.in_viewport = copy_state.point_row >= copy_state.viewport_top_row &&
			copy_state.point_row - copy_state.viewport_top_row < u64(revision.projection.rows)
		if request.cursor.in_viewport {
			request.cursor.row = u16(copy_state.point_row - copy_state.viewport_top_row)
		}
	}
	handle, published, ui_failure := ui.proposal_project_terminal_view(proposal, request, ui_rows, ui_cells)
	if !published do return {}, false, {stage = .Project, ui = ui_failure}
	return handle, true, {}
}

@(private)
terminal_copy_position_selected :: proc(
	state: terminal_session.Copy_Mode_State,
	row: u64,
	column: u32,
) -> bool {
	if !state.active || !state.selection_active || !state.mark_present do return false
	start_row, start_column := state.mark_row, state.mark_column
	end_row, end_column := state.point_row, state.point_column
	if end_row < start_row || (end_row == start_row && end_column < start_column) {
		start_row, end_row = end_row, start_row
		start_column, end_column = end_column, start_column
	}
	if row < start_row || row > end_row do return false
	if row == start_row && column < start_column do return false
	if row == end_row && column > end_column do return false
	return true
}

@(private)
terminal_workflow_apply_image_fallbacks :: proc(
	cells: []ui.Terminal_Cell,
	columns, rows: u16,
	images: []terminal_session.Image_Placement,
	truncated: bool,
) {
	if columns == 0 || rows == 0 || len(cells) != int(columns) * int(rows) do return
	for image in images {
		if !image.visible do continue
		label_storage: [64]u8
		label := "[image unavailable]"
		if !truncated && !image.rejected {
			if image.pending {
				label = "[image loading]"
			} else {
				label = fmt.bprintf(
					label_storage[:], "[image %dx%d]", image.image_width, image.image_height,
				)
			}
		}
		row := max(image.viewport_row, 0)
		column := max(image.viewport_column, 0)
		if row >= i32(rows) || column >= i32(columns) do continue
		for byte, offset in transmute([]u8)label {
			target_column := column + i32(offset)
			if target_column >= i32(columns) do break
			index := int(row) * int(columns) + int(target_column)
			if index < 0 || index >= len(cells) do break
			cell := &cells[index]
			if cell.row != u16(row) || cell.column != u16(target_column) do continue
			cell.text[0] = byte
			cell.text_length = 1
			cell.width = 0
			cell.style.attributes += {.Dim}
		}
	}
}

/* terminal_workflow_close releases every terminal workflow resource. */
terminal_workflow_close :: proc(workflow: ^Terminal_Workflow_State) -> (bool, Terminal_Workflow_Failure) {
	if workflow == nil || !workflow.initialized do return false, {stage = .Close}
	closed, failure := terminal_session.registry_close(&workflow.registry)
	workflow.entries = {}
	workflow.pointer_capture = {}
	workflow.initialized = false
	return closed, {stage = .Close, terminal = failure} if !closed else {}
}

/* terminal_workflow_configure_attention atomically applies one policy to live sessions. */
terminal_workflow_configure_attention :: proc(
	workflow: ^Terminal_Workflow_State,
	attention: Terminal_Attention_Channel,
) -> (bool, terminal_session.Failure_Record) {
	if workflow == nil || !workflow.initialized || attention == .Invalid {
		return false, {stage = .Process, code = .Invalid_Argument}
	}
	previous := workflow.attention
	configured: [terminal_session.MAX_SESSIONS]terminal_session.Session_Ref
	configured_count: int
	for entry in workflow.entries {
		if !entry.live do continue
		_, applied, failure := terminal_session.registry_effect_configure(
			&workflow.registry, entry.terminal, terminal_workflow_effect_policy(attention),
		)
		if !applied {
			for ref in configured[:configured_count] {
				_, _, _ = terminal_session.registry_effect_configure(
					&workflow.registry, ref, terminal_workflow_effect_policy(previous),
				)
			}
			return false, failure
		}
		configured[configured_count] = entry.terminal
		configured_count += 1
	}
	workflow.attention = attention
	return true, {}
}

/* terminal_workflow_scope copies the default-session boundary from a resolved context. */
terminal_workflow_scope :: proc(ctx: ^Terminal_Working_Context) -> Terminal_Workflow_Scope {
	if ctx == nil do return {}
	scope := Terminal_Workflow_Scope{kind = ctx.scope}
	if ctx.scope == .Workspace do scope.workspace = ctx.workspace.id
	return scope
}

/* terminal_workflow_default returns the live default terminal for one exact scope. */
terminal_workflow_default :: proc(
	workflow: ^Terminal_Workflow_State,
	scope: Terminal_Workflow_Scope,
) -> (Terminal_Workflow_Entry, bool) {
	if workflow == nil || !workflow.initialized || scope.kind == .Invalid do return {}, false
	for index in 0 ..< len(workflow.entries) {
		entry := &workflow.entries[index]
		if !entry.live || !entry.default_session || !terminal_workflow_scope_equal(entry.scope, scope) {
			continue
		}
		record, recorded, _ := terminal_session.registry_poll(&workflow.registry, entry.terminal)
		if !recorded || record.lifecycle != .Running {
			entry.default_session = false
			continue
		}
		return entry^, true
	}
	return {}, false
}

/* terminal_workflow_last_focused returns the most recently focused retained terminal in scope. */
terminal_workflow_last_focused :: proc(
	workflow: ^Terminal_Workflow_State,
	scope: Terminal_Workflow_Scope,
) -> (Terminal_Workflow_Entry, bool) {
	if workflow == nil || !workflow.initialized || scope.kind == .Invalid do return {}, false
	result: Terminal_Workflow_Entry
	found := false
	for entry in workflow.entries {
		if !entry.live || !terminal_workflow_scope_equal(entry.scope, scope) do continue
		if !found || entry.focus_sequence > result.focus_sequence {
			result = entry
			found = true
		}
	}
	return result, found
}

/* terminal_workflow_note_focus records explicit user focus without affecting layout. */
terminal_workflow_note_focus :: proc(
	workflow: ^Terminal_Workflow_State,
	ref: terminal_session.Session_Ref,
) -> bool {
	entry := terminal_workflow_entry_record(workflow, ref)
	if entry == nil do return false
	entry.focus_sequence = workflow.next_focus_sequence
	workflow.next_focus_sequence += 1
	return true
}

/* terminal_workflow_clear_yank ends terminal-local yank-pop continuity. */
terminal_workflow_clear_yank :: proc(
	workflow: ^Terminal_Workflow_State,
	ref: terminal_session.Session_Ref,
) {
	entry := terminal_workflow_entry_record(workflow, ref)
	if entry == nil do return
	entry.yank = {}
	entry.yanked_codepoints = 0
	entry.yanked_multiline = false
}

/* terminal_workflow_next_name returns the next stable automatic terminal name. */
terminal_workflow_next_name :: proc(
	workflow: ^Terminal_Workflow_State,
	storage: []u8,
) -> (string, bool) {
	if workflow == nil || !workflow.initialized || workflow.next_name_index == 0 do return "", false
	name := "terminal"
	if workflow.next_name_index > 1 {
		name = fmt.bprintf(storage, "terminal-%d", workflow.next_name_index)
		if len(name) == 0 do return "", false
	}
	return name, true
}

/* terminal_workflow_commit_name advances automatic naming after successful creation. */
terminal_workflow_commit_name :: proc(workflow: ^Terminal_Workflow_State) -> bool {
	if workflow == nil || !workflow.initialized || workflow.next_name_index == max(u32) do return false
	workflow.next_name_index += 1
	return true
}

/* terminal_workflow_live_count reports retained processes that are still running. */
terminal_workflow_live_count :: proc(workflow: ^Terminal_Workflow_State) -> u16 {
	if workflow == nil || !workflow.initialized do return 0
	stats, inspected, _ := terminal_session.registry_inspect(&workflow.registry)
	if !inspected do return 0
	return stats.running_count
}

/* terminal_workflow_dispose releases one confirmed terminal process and emulator owner. */
terminal_workflow_dispose :: proc(
	workflow: ^Terminal_Workflow_State,
	ref: terminal_session.Session_Ref,
) -> (bool, Terminal_Workflow_Failure) {
	entry := terminal_workflow_entry_record(workflow, ref)
	if entry == nil do return false, {stage = .Close}
	closed, terminal_failure := terminal_session.registry_close_session(&workflow.registry, ref)
	entry.live = false
	entry.default_session = false
	if workflow.pointer_capture.terminal == ref do workflow.pointer_capture = {}
	if workflow.literal_next == ref do workflow.literal_next = {}
	if workflow.toggle.terminal == ref do workflow.toggle = {height = workflow.toggle.height}
	if !closed do return false, {stage = .Close, terminal = terminal_failure}
	return true, {}
}

/* terminal_workflow_scope_equal compares scope identity without Workspace generation drift. */
terminal_workflow_scope_equal :: proc(left, right: Terminal_Workflow_Scope) -> bool {
	if left.kind != right.kind || left.kind == .Invalid do return false
	if left.kind == .Instance do return true
	return left.workspace == right.workspace
}

@(private)
terminal_workflow_effect_policy :: proc(
	attention: Terminal_Attention_Channel,
) -> terminal_session.Effect_Policy {
	channel := terminal_session.Attention_Channel.None
	switch attention {
	case .Audible: channel = .Audible
	case .Visual:  channel = .Visual
	case .Both:    channel = .Both
	case .Invalid, .None:
	}
	return {
		attention = channel,
		bell_interval_nanoseconds = terminal_session.DEFAULT_BELL_INTERVAL_NANOSECONDS,
	}
}

@(private)
terminal_workflow_now_ns :: proc(workflow: ^Terminal_Workflow_State) -> i64 {
	if workflow == nil || !workflow.initialized do return 1
	return max(i64(1), time.duration_nanoseconds(time.tick_since(workflow.clock_start)))
}

@(private)
terminal_workflow_copy_screen :: proc(
	workflow: ^Terminal_Workflow_State,
	ref: terminal_session.Session_Ref,
	limit: u64,
) -> ([]u8, bool, terminal_session.Failure_Record) {
	_, projected, failure := terminal_session.registry_project_render(&workflow.registry, ref)
	if !projected do return nil, false, failure
	capacity := int(min(limit, terminal_session.MAX_COPIED_TEXT_BYTES))
	text, allocation_error := make([]u8, capacity, workflow.allocator)
	if allocation_error != nil do return nil, false, {stage = .Scrollback, code = .Allocation}
	copy_record, copied, copy_failure := terminal_session.registry_copy_text(
		&workflow.registry, ref, {scope = .Screen}, text,
	)
	if !copied {
		delete(text, workflow.allocator)
		return nil, false, copy_failure
	}
	return text[:int(copy_record.copied_bytes)], true, {}
}

@(private)
terminal_workflow_entry :: proc(
	workflow: ^Terminal_Workflow_State,
	ref: terminal_session.Session_Ref,
) -> (editor_session.Entry_Handle, bool) {
	if workflow == nil || !workflow.initialized || ref.id == 0 || u32(ref.id) > terminal_session.MAX_SESSIONS {
		return {}, false
	}
	entry := workflow.entries[int(u32(ref.id) - 1)]
	return entry.entry, entry.live && entry.terminal == ref
}

@(private)
terminal_workflow_entry_record :: proc(
	workflow: ^Terminal_Workflow_State,
	ref: terminal_session.Session_Ref,
) -> ^Terminal_Workflow_Entry {
	if workflow == nil || !workflow.initialized || ref.id == 0 || u32(ref.id) > terminal_session.MAX_SESSIONS {
		return nil
	}
	entry := &workflow.entries[int(u32(ref.id) - 1)]
	if !entry.live || entry.terminal != ref do return nil
	return entry
}

@(private)
terminal_workflow_abandon_entry :: proc(session: ^editor_session.Session, entry: editor_session.Entry_Handle) {
	detached: editor_session.Detached_Entry
	_, detached_ok, _ := editor_session.session_entry_detach(session, entry, &detached)
	if !detached_ok do return
	_, _, _ = editor_session.detached_entry_cleanup(&detached)
	_, _ = editor_session.detached_entry_release(&detached)
}

@(private)
terminal_editor_ref :: proc(ref: terminal_session.Session_Ref) -> editor_session.Terminal_Session_Ref {
	return {id = u32(ref.id), generation = u32(ref.generation)}
}

@(private)
terminal_editor_lifecycle :: proc(value: terminal_session.Lifecycle) -> editor_session.Terminal_Lifecycle {
	switch value {
	case .Running: return .Running
	case .Exited: return .Exited
	case .Failed: return .Failed
	case .Invalid, .Closed: return .Failed
	}
	return .Failed
}

@(private)
terminal_ui_row :: proc(row: terminal_session.Render_Row) -> ui.Terminal_Row {
	return {row = row.row, dirty = row.dirty, wrapped = row.wrapped, wrap_continuation = row.wrap_continuation}
}

@(private)
terminal_ui_cell :: proc(cell: terminal_session.Render_Cell) -> ui.Terminal_Cell {
	result := ui.Terminal_Cell {
		column = cell.column,
		row = cell.row,
		text_length = cell.text_length,
		width = u8(cell.width),
		selected = cell.selected,
		hyperlink = cell.hyperlink,
		style = {
			foreground = terminal_ui_style_color(cell.style.foreground),
			background = terminal_ui_style_color(cell.style.background),
			underline_color = terminal_ui_style_color(cell.style.underline_color),
			invisible = cell.style.invisible,
		},
	}
	copy_cell := cell
	copy(result.text[:], copy_cell.text[:])
	if cell.style.bold do result.style.attributes += {.Bold}
	if cell.style.faint do result.style.attributes += {.Dim}
	if cell.style.italic do result.style.attributes += {.Italic}
	if cell.style.underline != 0 do result.style.attributes += {.Underline}
	if cell.style.blink do result.style.attributes += {.Blink}
	if cell.style.inverse do result.style.attributes += {.Reverse}
	if cell.style.strikethrough do result.style.attributes += {.Strikethrough}
	if cell.style.overline do result.style.attributes += {.Overline}
	if cell.hyperlink do result.style.attributes += {.Underline}
	return result
}

@(private)
terminal_ui_style_color :: proc(color: terminal_emulator.Style_Color) -> ui.Terminal_Color {
	switch color.kind {
	case .None: return {}
	case .Palette: return {kind = .Palette, palette = color.palette}
	case .RGB: return {kind = .RGB, rgb = {red = color.rgb.r, green = color.rgb.g, blue = color.rgb.b}}
	}
	return {}
}

@(private)
terminal_ui_request :: proc(
	owner: ui.Owner_ID,
	title: string,
	record: terminal_session.Session_Record,
	revision: terminal_session.Render_Revision,
) -> ui.Terminal_Projection_Request {
	projection := revision.projection
	request := ui.Terminal_Projection_Request {
		model = {owner_id = owner, model_id = ui.Model_ID(u32(record.ref.id)), generation = ui.Model_Generation(revision.revision)},
		session_id = u32(record.ref.id),
		session_generation = u32(record.ref.generation),
		revision = revision.revision,
		columns = projection.columns,
		rows = projection.rows,
		damage = ui.Terminal_Damage(projection.damage),
		cursor = {
			column = projection.cursor_column,
			row = projection.cursor_row,
			style = ui.Terminal_Cursor_Style(projection.cursor_style),
			in_viewport = projection.cursor_in_viewport,
			visible = projection.cursor_visible,
			blinking = projection.cursor_blinking,
			wide_tail = projection.cursor_wide_tail,
		},
		foreground = {red = projection.foreground.r, green = projection.foreground.g, blue = projection.foreground.b},
		background = {red = projection.background.r, green = projection.background.g, blue = projection.background.b},
		lifecycle = .Running if record.lifecycle == .Running else .Exited if record.lifecycle == .Exited else .Failed,
		exit_code = record.process.exit_status.value,
		activity_generation = record.output_bytes,
		title = title,
	}
	if projection.cursor_color_set {
		request.cursor_color = {present = true, color = {red = projection.cursor.r, green = projection.cursor.g, blue = projection.cursor.b}}
	}
	for color, index in projection.palette {
		request.palette[index] = {red = color.r, green = color.g, blue = color.b}
	}
	return request
}
