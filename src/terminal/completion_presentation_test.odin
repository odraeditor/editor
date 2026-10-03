// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package terminal_frontend

import "../completion"
import "../display"
import "../editor"
import "../ui"
import editor_view "../view"
import "core:strings"
import "core:testing"

@(private = "file")
Completion_Terminal_Root :: struct {
	snapshot:        ui.Snapshot,
	text_projection: [1]Text_Surface_Projection,
	source:          ui.Object_Handle,
	popup:           ui.Object_Handle,
}

/* Verifies live completion generations replace one captured terminal presentation. */
@(test)
completion_replaces_without_focus_transfer :: proc(
	t: ^testing.T,
) {
	fixture: Renderer_Fixture
	if !renderer_fixture_init(t, &fixture, 901, "pri") do return
	defer renderer_fixture_close(&fixture)
	point, point_found, _ := editor.buffer_position(&fixture.buffer, 3)
	point_set, _ := editor_view.set_point(&fixture.registry, fixture.handle, point)
	testing.expect(t, point_found && point_set)
	if !point_found || !point_set do return
	logical, logical_ok, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	constraints := display.Viewport_Constraints{width_cells = 48, height_rows = 12}
	display_snapshot, projected, _ := display.project(
		&fixture.buffer,
		renderer_projection_request(901, logical, constraints),
	)
	testing.expect(t, logical_ok && projected)
	if !logical_ok || !projected do return
	defer display.snapshot_close(&display_snapshot)

	renderer: Renderer
	config := renderer_config(constraints)
	config.color = .True_Color
	renderer_ok, _ := renderer_init(&renderer, config)
	testing.expect(t, renderer_ok)
	if !renderer_ok do return
	defer renderer_close(&renderer)

	roles: completion.Role_Registry
	controller: completion.Controller
	composition, completion_ok := completion_terminal_controller_init(&roles, &controller)
	testing.expect(t, completion_ok)
	if !completion_ok do return
	defer completion.registry_close(&roles)
	defer completion.controller_close(&controller)
	request := completion_terminal_request(902, 1, 1, "pri", composition)
	items := []completion.Candidate {
		completion_terminal_candidate(903, "print", .Callable, "function"),
		completion_terminal_candidate(904, "printf", .Callable, "formatted output"),
		completion_terminal_candidate(905, "priority", .Field, "task priority"),
	}
	ready := completion_terminal_publish(&controller, 906, 1, request, composition, items, 1)
	testing.expect(t, ready)
	if !ready do return

	registry: ui.Registry
	registry_ok, _ := ui.registry_init(&registry, 907)
	testing.expect(t, registry_ok)
	if !registry_ok do return
	defer ui.registry_close(&registry)
	first: Completion_Terminal_Root
	first_root, first_ok := completion_terminal_root(
		t,
		&first,
		&registry,
		{},
		&renderer,
		&fixture,
		display_snapshot,
		logical,
		&controller,
		1,
		1,
		constraints,
	)
	testing.expect(t, first_ok)
	if !first_ok do return
	defer completion_terminal_root_close(&first)
	captured, capture_failure := ui.registry_capture_transient_input(&registry, first.popup)
	testing.expectf(t, captured, "completion capture failed with %v", capture_failure.code)
	if !captured do return

	first_frame, first_rendered, first_failure := renderer_prepare_ui(
		renderer_state(&renderer),
		completion_terminal_presentation(&first),
	)
	testing.expectf(t, first_rendered, "completion frame failed with %v", first_failure.code)
	if !first_rendered do return
	first_output := string(first_frame.output[:first_frame.used])
	testing.expect(t, strings.contains(first_output, "pri"))
	testing.expect(t, strings.contains(first_output, "[call]"))
	testing.expect(t, strings.contains(first_output, "print"))
	testing.expect(t, strings.contains(first_output, "[field]   priority"))
	testing.expect(t, strings.contains(first_output, "\x1b[38;2;255;160;80m"))
	testing.expect(t, strings.contains(first_output, "\x1b[7m"))
	testing.expect(t, strings.has_suffix(first_output, "\x1b[1;4H\x1b[?25h"))
	completion_terminal_expect_single_frame_controls(t, first_output)
	frame_close(&first_frame)

	refined_request := completion_terminal_request(908, 2, 2, "print", composition)
	action, refined, _ := completion.controller_refine(&controller, refined_request)
	selected, _ := completion.controller_select_candidate(&controller, 904)
	testing.expect(t, refined && selected)
	testing.expect_value(t, action, completion.Refresh_Action.Local_Filter)
	if !refined || !selected do return

	second: Completion_Terminal_Root
	second_root, second_ok := completion_terminal_root(
		t,
		&second,
		&registry,
		first_root,
		&renderer,
		&fixture,
		display_snapshot,
		logical,
		&controller,
		2,
		2,
		constraints,
	)
	testing.expect(t, second_ok)
	if !second_ok do return
	defer completion_terminal_root_close(&second)
	second_focus, focus_ok, _ := ui.registry_focus(&registry)
	testing.expect(t, focus_ok && second_focus.transient.active)
	testing.expect_value(t, second_focus.target, second.source)
	testing.expect_value(t, second_focus.transient.popup, second.popup)

	second_frame, second_rendered, second_failure := renderer_prepare_ui(
		renderer_state(&renderer),
		completion_terminal_presentation(&second),
	)
	testing.expectf(t, second_rendered, "replacement frame failed with %v", second_failure.code)
	if !second_rendered do return
	second_output := string(second_frame.output[:second_frame.used])
	testing.expect(t, strings.contains(second_output, "[call]"))
	testing.expect(t, strings.contains(second_output, "print"))
	testing.expect(t, strings.contains(second_output, "printf"))
	testing.expect(t, !strings.contains(second_output, "priority"))
	testing.expect(t, strings.has_suffix(second_output, "\x1b[1;4H\x1b[?25h"))
	completion_terminal_expect_single_frame_controls(t, second_output)
	frame_close(&second_frame)

	restored, released, release_failure := ui.registry_release_transient_input(
		&registry,
		second.popup,
	)
	testing.expectf(t, released, "completion release failed with %v", release_failure.code)
	testing.expect_value(t, restored, second.source)
	plain: Completion_Terminal_Root
	_, plain_ok := completion_terminal_plain_root(
		t,
		&plain,
		&registry,
		second_root,
		&renderer,
		&fixture,
		display_snapshot,
		logical,
		constraints,
	)
	testing.expect(t, plain_ok)
	if !plain_ok do return
	defer completion_terminal_root_close(&plain)
	stats, stats_ok, _ := ui.registry_stats(&registry)
	plain_focus, plain_focus_ok, _ := ui.registry_focus(&registry)
	testing.expect(t, stats_ok && plain_focus_ok)
	testing.expect_value(t, stats.popups, u16(0))
	testing.expect(t, !stats.transient_input_captured && !plain_focus.transient.active)
	testing.expect_value(t, plain_focus.target, plain.source)
}

/* Verifies insufficient terminal geometry takes the declared compact fallback. */
@(test)
completion_fallback_preserves_source :: proc(t: ^testing.T) {
	fixture: Renderer_Fixture
	if !renderer_fixture_init(t, &fixture, 911, "pri") do return
	defer renderer_fixture_close(&fixture)
	point, _, _ := editor.buffer_position(&fixture.buffer, 3)
	_, _ = editor_view.set_point(&fixture.registry, fixture.handle, point)
	logical, logical_ok, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	constraints := display.Viewport_Constraints{width_cells = 16, height_rows = 3}
	display_snapshot, projected, _ := display.project(
		&fixture.buffer,
		renderer_projection_request(911, logical, constraints),
	)
	testing.expect(t, logical_ok && projected)
	if !logical_ok || !projected do return
	defer display.snapshot_close(&display_snapshot)
	renderer: Renderer
	renderer_ok, _ := renderer_init(&renderer, renderer_config(constraints))
	testing.expect(t, renderer_ok)
	if !renderer_ok do return
	defer renderer_close(&renderer)
	roles: completion.Role_Registry
	controller: completion.Controller
	composition, completion_ok := completion_terminal_controller_init(&roles, &controller)
	if !completion_ok do return
	defer completion.registry_close(&roles)
	defer completion.controller_close(&controller)
	request := completion_terminal_request(912, 1, 1, "pri", composition)
	items := []completion.Candidate {
		completion_terminal_candidate(913, "print", .Callable, "function"),
	}
	if !completion_terminal_publish(&controller, 914, 1, request, composition, items, 1) do return
	registry: ui.Registry
	registry_ok, _ := ui.registry_init(&registry, 915)
	if !registry_ok do return
	defer ui.registry_close(&registry)
	root: Completion_Terminal_Root
	_, root_ok := completion_terminal_root(
		t,
		&root,
		&registry,
		{},
		&renderer,
		&fixture,
		display_snapshot,
		logical,
		&controller,
		1,
		1,
		constraints,
	)
	testing.expect(t, root_ok)
	if !root_ok do return
	defer completion_terminal_root_close(&root)
	view, viewed := ui.snapshot_view(&root.snapshot)
	testing.expect(t, viewed)
	if viewed {
		testing.expect_value(t, len(view.popups), 1)
		if len(view.popups) == 1 {
			testing.expect_value(t, view.popups[0].geometry.state, ui.Popup_Geometry_State.Fallback)
		}
	}
	frame, rendered, failure := renderer_prepare_ui(
		renderer_state(&renderer),
		completion_terminal_presentation(&root),
	)
	testing.expectf(t, rendered, "fallback frame failed with %v", failure.code)
	if !rendered do return
	defer frame_close(&frame)
	output := string(frame.output[:frame.used])
	testing.expect(t, strings.contains(output, "pri"))
	testing.expect(t, !strings.contains(output, "[call]"))
	testing.expect(t, strings.has_suffix(output, "\x1b[1;4H\x1b[?25h"))
	completion_terminal_expect_single_frame_controls(t, output)
}

@(private = "file")
completion_terminal_controller_init :: proc(
	registry: ^completion.Role_Registry,
	controller: ^completion.Controller,
) -> (completion.Composition_Scope, bool) {
	registry_ok, _ := completion.registry_init(registry, 91)
	if !registry_ok do return {}, false
	composition, scoped, _ := completion.registry_scope(registry)
	if !scoped do return {}, false
	controller_ok, _ := completion.controller_init(controller, 92, 1, composition)
	return composition, controller_ok
}

@(private = "file")
completion_terminal_request :: proc(
	id, generation, revision: u64,
	query_value: string,
	composition: completion.Composition_Scope,
) -> completion.Request {
	query, _ := completion.text_copy(query_value)
	provider := composition.selections[0].selected
	return {
		id = completion.Request_ID(id),
		generation = completion.Request_Generation(generation),
		scope = {
			document_id = 1,
			buffer_id = 901,
			document_revision = completion.Document_Revision(revision),
			view_id = 1,
			view_generation = 1,
			language_id = 1,
			language_generation = 1,
			provider_id = completion.Provider_ID(provider.implementation_id),
			provider_generation = completion.Provider_Generation(provider.implementation_generation),
			server_session_id = 1,
			server_session_generation = 1,
			document_binding_id = 1,
			document_binding_generation = 1,
			transmitted_revision = completion.Document_Revision(revision),
		},
		cursor_byte = u64(len(query_value)),
		query_range = {start = 0, end = u64(len(query_value))},
		query = query,
		trigger = .Explicit,
		provider_capabilities = {.Explicit, .Identifier, .Resolve, .Documentation},
		state = .Prepared,
	}
}

@(private = "file")
completion_terminal_candidate :: proc(
	id: completion.Candidate_ID,
	label_value: string,
	kind: completion.Candidate_Kind,
	description_value: string,
) -> completion.Candidate {
	label, _ := completion.text_copy(label_value)
	description, _ := completion.text_copy(description_value)
	return {
		id = id,
		kind = kind,
		availability = .Available,
		label = label,
		description = description,
		filter_text = label,
		sort_text = label,
		insertion_text = label,
		provenance = {provider_id = 1, provider_generation = 1},
		copied_bytes = u64(len(label_value) * 4 + len(description_value)),
	}
}

@(private = "file")
completion_terminal_publish :: proc(
	controller: ^completion.Controller,
	session_id, session_generation: u64,
	request: completion.Request,
	composition: completion.Composition_Scope,
	items: []completion.Candidate,
	batch_generation: u64,
) -> bool {
	for &item in items {
		item.provenance.provider_id = request.scope.provider_id
		item.provenance.provider_generation = request.scope.provider_generation
	}
	started, _ := completion.controller_start(
		controller,
		completion.Session_ID(session_id),
		completion.Session_Generation(session_generation),
		request,
		composition,
	)
	queued, _ := completion.controller_queue(controller)
	sent, _ := completion.controller_send(controller)
	batch := completion.Batch {
		id = 1,
		generation = completion.Batch_Generation(batch_generation),
		request_id = request.id,
		request_generation = request.generation,
		scope = request.scope,
		request_cursor_byte = request.cursor_byte,
		query_range = request.query_range,
		disposition = .Complete,
		items = items,
		item_count = u16(len(items)),
	}
	published, _ := completion.controller_publish(controller, &batch)
	return started && queued && sent && published
}

@(private = "file")
completion_terminal_root :: proc(
	t: ^testing.T,
	root: ^Completion_Terminal_Root,
	registry: ^ui.Registry,
	expected: ui.Root_Handle,
	renderer: ^Renderer,
	fixture: ^Renderer_Fixture,
	display_snapshot: display.Snapshot,
	logical: editor_view.Snapshot,
	controller: ^completion.Controller,
	presentation_generation, popup_generation: u64,
	constraints: display.Viewport_Constraints,
) -> (ui.Root_Handle, bool) {
	profile, profile_ok := renderer_ui_profile(renderer)
	proposal, prepared, _ := ui.proposal_begin(registry, expected)
	if !profile_ok || !prepared do return {}, false
	defer if proposal.state != nil do ui.proposal_abort(&proposal)
	styles_ok := completion_terminal_styles(&proposal)
	source_view, source_view_ok, _ := ui.proposal_project_editor_text_view(
		&proposal,
		&fixture.registry,
		fixture.handle,
		&fixture.buffer,
		ui.Owner_ID(logical.buffer_id),
		false,
	)
	completion_profile, completion_profile_ok := completion_terminal_profile()
	completion_state, completion_state_ok, _ := completion.controller_inspect(controller)
	list, list_ok, _ := completion.controller_project_candidates(
		controller,
		&proposal,
		completion.Presentation_Request {
			presentation_generation = presentation_generation,
			viewport_items = 4,
			row_bytes = 40,
			profile = completion_profile,
		},
	)
	source, source_ok, _ := ui.proposal_add_surface(
		&proposal,
		ui.Surface_Descriptor {
			owner_id = ui.Owner_ID(logical.buffer_id),
			view = source_view,
			focusable = true,
			visible = true,
			required_profile = profile.id,
			geometry = {
				height = i32(constraints.height_rows),
				width = i32(constraints.width_cells),
			},
		},
	)
	content, content_ok, _ := ui.proposal_add_surface(
		&proposal,
		ui.Surface_Descriptor {
			owner_id = 92,
			view = list,
			visible = true,
			required_profile = profile.id,
			geometry = {height = 4, width = 40},
		},
	)
	source_node, source_node_ok, _ := ui.proposal_add_surface_node(&proposal, source)
	definition := completion_profile.definition
	descriptor := ui.Popup_Descriptor {
		id = 92,
		generation = ui.Popup_Generation(popup_generation),
		owner_id = 92,
		owner_generation = popup_generation,
		anchor = {
			kind = .Surface,
			source_surface = source,
			owner_id = ui.Owner_ID(logical.buffer_id),
			source_id = u64(source.object_id),
			source_generation = u64(source.root_generation),
			start = u64(logical.point_position.byte_offset),
			end = u64(logical.point_position.byte_offset),
			presentation_generation = u64(source.root_generation),
			viewport_row = 0,
			viewport_column = 3,
			height_rows = 1,
			width_columns = 1,
		},
		content_surface = content,
		content_generation = u64(completion_state.session_generation),
		placements = {.Below, .Above, .Invalid, .Invalid},
		placement_count = 2,
		bounds = definition.bounds,
		margin_rows = definition.margin_rows,
		margin_columns = definition.margin_columns,
		padding_rows = definition.padding_rows,
		padding_columns = definition.padding_columns,
		border = definition.border == .Single,
		clipping = definition.clipping,
		behavior = .Interactive,
		input_policy = .Transient_Capture,
		dismissal = {
			.Explicit_Cancel,
			.Action_Completion,
			.Owner_Cancellation,
			.Owner_Teardown,
			.Anchor_Invalidation,
			.Generation_Replacement,
			.Focus_Loss,
			.Cursor_Movement,
		},
		fallback = definition.popup_fallback,
		required_profile = profile.id,
		presentation_profile = completion_profile,
		content_bytes = 1,
		action_count = completion_state.filtered_candidate_count,
	}
	popup, popup_ok, popup_failure := ui.proposal_add_popup(&proposal, descriptor)
	root_ok, _ := ui.proposal_set_root(&proposal, source_node, source)
	handle, published, publish_failure := ui.proposal_publish(registry, &proposal, profile)
	testing.expectf(t, popup_ok, "completion popup failed with %v", popup_failure.code)
	testing.expectf(t, published, "completion root failed with %v", publish_failure.code)
	if !published do return {}, false
	snapshot, copied, _ := ui.registry_snapshot(registry, handle, profile)
	if !copied do return {}, false
	root^ = {
		snapshot = snapshot,
		source = source,
		popup = popup,
		text_projection = {
			0 = {surface = source, snapshot = display_snapshot, logical = logical},
		},
	}
	return handle,
		styles_ok && source_view_ok && completion_profile_ok && completion_state_ok &&
		list_ok && source_ok &&
		content_ok && source_node_ok && popup_ok && root_ok && copied
}

@(private = "file")
completion_terminal_plain_root :: proc(
	t: ^testing.T,
	root: ^Completion_Terminal_Root,
	registry: ^ui.Registry,
	expected: ui.Root_Handle,
	renderer: ^Renderer,
	fixture: ^Renderer_Fixture,
	display_snapshot: display.Snapshot,
	logical: editor_view.Snapshot,
	constraints: display.Viewport_Constraints,
) -> (ui.Root_Handle, bool) {
	profile, profile_ok := renderer_ui_profile(renderer)
	proposal, prepared, _ := ui.proposal_begin(registry, expected)
	if !profile_ok || !prepared do return {}, false
	defer if proposal.state != nil do ui.proposal_abort(&proposal)
	_, style_ok, _ := ui.proposal_add_style(&proposal, .Text_Normal)
	view, view_ok, _ := ui.proposal_project_editor_text_view(
		&proposal,
		&fixture.registry,
		fixture.handle,
		&fixture.buffer,
		ui.Owner_ID(logical.buffer_id),
		false,
	)
	source, source_ok, _ := ui.proposal_add_surface(
		&proposal,
		ui.Surface_Descriptor {
			owner_id = ui.Owner_ID(logical.buffer_id),
			view = view,
			focusable = true,
			visible = true,
			required_profile = profile.id,
			geometry = {height = i32(constraints.height_rows), width = i32(constraints.width_cells)},
		},
	)
	node, node_ok, _ := ui.proposal_add_surface_node(&proposal, source)
	root_ok, _ := ui.proposal_set_root(&proposal, node, source)
	handle, published, _ := ui.proposal_publish(registry, &proposal, profile)
	if !published do return {}, false
	snapshot, copied, _ := ui.registry_snapshot(registry, handle, profile)
	if !copied do return {}, false
	root^ = {
		snapshot = snapshot,
		source = source,
		text_projection = {
			0 = {surface = source, snapshot = display_snapshot, logical = logical},
		},
	}
	return handle, style_ok && view_ok && source_ok && node_ok && root_ok && copied
}

@(private = "file")
completion_terminal_profile :: proc() -> (ui.Presentation_Profile_Record, bool) {
	registry: ui.Presentation_Profile_Registry
	initialized, _ := ui.presentation_profile_registry_init(&registry, 93)
	if !initialized do return {}, false
	defer ui.presentation_profile_registry_close(&registry)
	scope, scoped, _ := ui.presentation_profile_registry_scope(
		&registry,
		.Interactive_Candidates,
	)
	if !scoped do return {}, false
	record, recorded, _ := ui.presentation_profile_registry_record(&registry, scope.selected)
	return record, recorded
}

@(private = "file")
completion_terminal_styles :: proc(proposal: ^ui.Proposal) -> bool {
	orange := ui.Optional_SRGB_Color{present = true, color = {red = 255, green = 160, blue = 80}}
	roles := [?]ui.Style_Role {
		.Text_Normal,
		.List_Normal,
		.List_Current,
		.List_Emphasis,
		.Syntax_String,
		.Syntax_Function,
		.Syntax_Constructor,
		.Syntax_Constant,
		.Syntax_Type,
		.Syntax_Label,
		.Syntax_Attribute,
		.Syntax_Keyword,
		.Popup_Background,
		.Popup_Content,
		.Popup_Border,
		.Popup_Diagnostic,
		.Popup_Unavailable,
		.Diagnostic_Rejected,
		.Status_Alert,
	}
	for role in roles {
		attributes: ui.Style_Attributes
		foreground: ui.Optional_SRGB_Color
		if role == .List_Current || role == .List_Emphasis do attributes = {.Reverse}
		if role == .Syntax_Function do foreground = orange
		_, added, _ := ui.proposal_add_style(proposal, role, attributes, foreground)
		if !added do return false
	}
	return true
}

@(private = "file")
completion_terminal_presentation :: proc(root: ^Completion_Terminal_Root) -> UI_Presentation {
	return {root = &root.snapshot, text_surfaces = root.text_projection[:]}
}

@(private = "file")
completion_terminal_root_close :: proc(root: ^Completion_Terminal_Root) {
	if root.snapshot.state != nil do ui.snapshot_close(&root.snapshot)
}

@(private = "file")
completion_terminal_expect_single_frame_controls :: proc(t: ^testing.T, output: string) {
	testing.expect_value(t, completion_terminal_count(output, "\x1b[?25l"), 1)
	testing.expect_value(t, completion_terminal_count(output, "\x1b[2J"), 1)
	testing.expect_value(t, completion_terminal_count(output, "\x1b[?25h"), 1)
}

@(private = "file")
completion_terminal_count :: proc(value, target: string) -> int {
	if target == "" do return 0
	count := 0
	remaining := value
	for {
		index := strings.index(remaining, target)
		if index < 0 do break
		count += 1
		remaining = remaining[index + len(target):]
	}
	return count
}
