// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package completion

import "../ui"
import "core:strings"
import "core:testing"

/* Verifies selected detail issues one exact lazy request and rejects stale publication. */
@(test)
detail_resolves_only_the_current_candidate :: proc(t: ^testing.T) {
	registry: Role_Registry
	controller: Controller
	composition, initialized := controller_fixture(&registry, &controller)
	if !initialized do return
	defer registry_close(&registry)
	defer controller_close(&controller)
	request := controller_request(901, 1, 3, composition)
	first := completion_filter_candidate(903, "print", provider_order = 0)
	first.resolve_token, _ = resolve_token_copy(`{"item":1}`)
	second := completion_filter_candidate(904, "private", provider_order = 1)
	items := []Candidate{first, second}
	_, _ = controller_start(&controller, 902, 1, request, composition)
	_, _ = controller_queue(&controller)
	_, _ = controller_send(&controller)
	batch := controller_batch(request, items)
	_, _ = controller_publish(&controller, &batch)

	initial, initial_ok, _ := controller_candidate_detail(&controller)
	resolving, resolve_request, requested, _ := controller_request_candidate_detail(&controller)
	_, repeated_request, repeated, _ := controller_request_candidate_detail(&controller)
	selected, _ := controller_select_candidate(&controller, 904)
	unavailable, unavailable_ok, _ := controller_candidate_detail(&controller)
	detail_text, _ := detail_copy("resolved detail")
	documentation, _ := detail_copy("resolved documentation")
	stale, stale_failure := controller_publish_candidate_resolution(
		&controller,
		Candidate_Resolution {
			request = resolve_request,
			detail = detail_text,
			documentation = documentation,
			documentation_format = .Plain_Text,
		},
	)

	testing.expect(t, initial_ok && requested && repeated && selected && unavailable_ok && !stale)
	testing.expect_value(t, initial.state, Detail_State.Resolve_Required)
	testing.expect_value(t, resolving.state, Detail_State.Resolving)
	testing.expect_value(t, repeated_request, resolve_request)
	testing.expect_value(t, resolve_request.candidate_id, Candidate_ID(903))
	testing.expect_value(t, unavailable.state, Detail_State.Unavailable)
	testing.expect_value(t, stale_failure.code, Failure_Code.Stale_Request)
}

/* Verifies a current resolution changes only bounded detail and documentation state. */
@(test)
completion_detail_publishes_bounded_resolution :: proc(t: ^testing.T) {
	registry: Role_Registry
	controller: Controller
	composition, initialized := controller_fixture(&registry, &controller)
	if !initialized do return
	defer registry_close(&registry)
	defer controller_close(&controller)
	request := controller_request(911, 1, 3, composition)
	candidate := completion_filter_candidate(913, "print")
	candidate.resolve_token, _ = resolve_token_copy(`{"item":1}`)
	items := []Candidate{candidate}
	_, _ = controller_start(&controller, 912, 1, request, composition)
	_, _ = controller_queue(&controller)
	_, _ = controller_send(&controller)
	batch := controller_batch(request, items)
	_, _ = controller_publish(&controller, &batch)
	_, resolve_request, requested, _ := controller_request_candidate_detail(&controller)
	detail_text, _ := detail_copy("proc(value: string)")
	documentation, _ := detail_copy("**Print** one value.")
	resolved, resolve_failure := controller_publish_candidate_resolution(
		&controller,
		Candidate_Resolution {
			request = resolve_request,
			detail = detail_text,
			documentation = documentation,
			documentation_format = .Markdown,
		},
	)
	detail, detailed, _ := controller_candidate_detail(&controller)
	inspection, inspected, _ := controller_inspect(&controller)

	testing.expectf(t, requested && resolved, "resolution failed with %v", resolve_failure.code)
	testing.expect(t, detailed && inspected)
	testing.expect_value(t, detail.state, Detail_State.Ready)
	testing.expect_value(t, detail_view(&detail.detail), "proc(value: string)")
	testing.expect_value(t, detail_view(&detail.documentation), "**Print** one value.")
	testing.expect(t, inspection.selected_resolved && !inspection.resolve_pending)
	testing.expect_value(t, inspection.resolved_candidate_count, u16(1))
}

/* Verifies contextual projection normalizes markup, clips rows, and reports unavailability. */
@(test)
completion_detail_projects_contextual_content :: proc(t: ^testing.T) {
	registry: Role_Registry
	controller: Controller
	composition, initialized := controller_fixture(&registry, &controller)
	if !initialized do return
	defer registry_close(&registry)
	defer controller_close(&controller)
	request := controller_request(921, 1, 3, composition)
	candidate := completion_filter_candidate(923, "print")
	candidate.kind = .Callable
	candidate.detail, _ = detail_copy("proc(value: string)")
	candidate.documentation, _ = detail_copy("# Print\n**Print** one `value` with a long explanation.")
	candidate.documentation_format = .Markdown
	items := []Candidate{candidate}
	_, _ = controller_start(&controller, 922, 1, request, composition)
	_, _ = controller_queue(&controller)
	_, _ = controller_send(&controller)
	batch := controller_batch(request, items)
	_, _ = controller_publish(&controller, &batch)

	ui_registry: ui.Registry
	ui_initialized, _ := ui.registry_init(&ui_registry, 924)
	if !ui_initialized do return
	defer ui.registry_close(&ui_registry)
	proposal, prepared, _ := ui.proposal_begin(&ui_registry)
	styles_ok := completion_detail_test_styles(&proposal)
	presentation, projected, projection_failure := controller_project_candidate_detail(
		&controller,
		&proposal,
		completion_detail_test_request(925, 24),
	)
	testing.expectf(t, projected, "detail projection failed with %v", projection_failure.code)
	if !projected do return
	surface, surface_ok, _ := ui.proposal_add_surface(
		&proposal,
		ui.Surface_Descriptor {
			owner_id = 82,
			view = presentation.view,
			focusable = true,
			visible = true,
			required_profile = 1,
			geometry = {height = i32(presentation.rows), width = i32(presentation.columns)},
		},
	)
	node, node_ok, _ := ui.proposal_add_surface_node(&proposal, surface)
	root_ok, _ := ui.proposal_set_root(&proposal, node, surface)
	root, published, publish_failure := ui.proposal_publish(
		&ui_registry, &proposal, completion_presentation_test_renderer(),
	)
	testing.expectf(t, published, "detail publication failed with %v", publish_failure.code)
	if !published do return
	snapshot, copied, _ := ui.registry_snapshot(
		&ui_registry, root, completion_presentation_test_renderer(),
	)
	if !copied do return
	defer ui.snapshot_close(&snapshot)
	view, viewed := ui.snapshot_view(&snapshot)
	rows, rows_ok := ui.snapshot_list_items(view, view.views[0])
	title, title_ok := ui.snapshot_list_item_text(view, rows[0])
	heading, heading_ok := ui.snapshot_list_item_text(view, rows[2])
	body, body_ok := ui.snapshot_list_item_text(view, rows[3])

	testing.expect(
		t,
		prepared && styles_ok && surface_ok && node_ok && root_ok && copied && viewed &&
		rows_ok && title_ok && heading_ok && body_ok,
	)
	testing.expect_value(t, presentation.state, Detail_State.Ready)
	testing.expect_value(t, len(rows), 4)
	testing.expect(t, strings.has_prefix(title, "[call]"))
	testing.expect_value(t, heading, "Print")
	testing.expect(t, !strings.contains(body, "**") && !strings.contains(body, "`"))
	testing.expect(t, strings.has_suffix(body, "..."))
	if len(rows) > 1 do testing.expect(t, rows[1].passive)
}

@(private)
completion_detail_test_request :: proc(
	generation: u64,
	row_bytes: u32,
) -> Detail_Presentation_Request {
	profiles: ui.Presentation_Profile_Registry
	initialized, _ := ui.presentation_profile_registry_init(&profiles, 92)
	if !initialized do return {}
	scope, scoped, _ := ui.presentation_profile_registry_scope(
		&profiles, .Contextual_Information,
	)
	record, recorded, _ := ui.presentation_profile_registry_record(&profiles, scope.selected)
	_, _ = ui.presentation_profile_registry_close(&profiles)
	if !scoped || !recorded do return {}
	return {
		presentation_generation = generation,
		row_bytes = row_bytes,
		profile = record,
	}
}

@(private)
completion_detail_test_styles :: proc(proposal: ^ui.Proposal) -> bool {
	roles := [?]ui.Style_Role {
		.List_Normal,
		.List_Current,
		.Popup_Content,
		.Popup_Border,
		.Popup_Diagnostic,
		.Popup_Unavailable,
	}
	for role in roles {
		_, added, _ := ui.proposal_add_style(proposal, role)
		if !added do return false
	}
	return true
}
