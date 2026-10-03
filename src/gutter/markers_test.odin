// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package gutter

import "core:testing"

MARKER_TEST_ROWS: [1]Visible_Row = {{viewport_row = 0, logical_line = 4, has_content = true}}

@(private = "file")
marker_test_lane :: proc(policy: Collision_Policy) -> Lane_Definition {
	return Lane_Definition {
		id = 21,
		provider = 9,
		provider_generation = 2,
		side = .Left,
		order = 1,
		attachments = {.Logical_Line, .Display_Row},
		width_policy = .Bounded_Automatic,
		minimum_cells = 1,
		maximum_cells = 8,
		alignment = .Left,
		visibility = .When_Content,
		collision = policy,
		priority = 100,
		style_role = .Ordinary,
	}
}

@(private = "file")
marker_test_value :: proc(id: Marker_ID, priority: u16, value, aggregate: string) -> Marker {
	return Marker {
		id = id,
		provider = 9,
		provider_generation = 2,
		lane = 21,
		attachment = {kind = .Logical_Line, logical_line = 4, buffer_revision = 7},
		style_role = .Diagnostic_Warning,
		priority = priority,
		representation = {kind = .Glyph, value = value, fallback = "!"},
		aggregation_label = aggregate,
		detail = "detail",
	}
}

@(private = "file")
marker_test_request :: proc(
	lanes: []Lane_Definition,
	publications: []Marker_Generation_View,
) -> Marker_Composition_Request {
	return Marker_Composition_Request {
		generation = 3,
		lanes = lanes,
		publications = publications,
		rows = MARKER_TEST_ROWS[:],
		buffer_revision = 7,
		view_identity = 12,
		view_generation = 2,
		projection_generation = 18,
		allocator = context.allocator,
		limits = DEFAULT_LIMITS,
	}
}

@(test)
/* marker_collisions_resolve_all_policies_with_stable_inspectable_members. */
collision_policies_keep_inspectable_members :: proc(t: ^testing.T) {
	markers := [3]Marker {
		marker_test_value(3, 10, "w", "+3"),
		marker_test_value(1, 30, "E", "+3"),
		marker_test_value(2, 20, "i", "+3"),
	}
	publication := Marker_Generation_View {
		id = 1, provider = 9, provider_generation = 2, complete = true, markers = markers[:],
	}
	cases := [?]struct{name: string, policy: Collision_Policy, text: string, role: Semantic_Role} {
		{"highest-priority", .Highest_Priority, "E", .Diagnostic_Warning},
		{"stack", .Stack, "Eiw", .Diagnostic_Warning},
		{"aggregate", .Aggregate, "+3", .Aggregate},
		{"primary-with-details", .Primary_With_Details, "E", .Diagnostic_Warning},
	}
	for test_case in cases {
		lane := marker_test_lane(test_case.policy)
		view, composed, failure := compose_markers(marker_test_request([]Lane_Definition{lane}, []Marker_Generation_View{publication}))
		testing.expectf(t, composed, "%s collision failed: %v", test_case.name, failure.code)
		if !composed do continue
		testing.expectf(t, len(view.markers) == 1, "%s collision returned the wrong marker count", test_case.name)
		if len(view.markers) == 1 {
			resolved := &view.markers[0]
			testing.expectf(t, resolved.primary == 1, "%s collision chose the wrong primary", test_case.name)
			testing.expectf(t, resolved.primary_provider == 9, "%s collision chose the wrong provider", test_case.name)
			testing.expectf(t, resolved.member_count == 3, "%s collision returned the wrong member count", test_case.name)
			testing.expectf(t, resolved.members[0] == 1, "%s collision reordered its primary", test_case.name)
			testing.expectf(t, resolved.member_providers[0] == 9, "%s collision changed member authority", test_case.name)
			testing.expectf(t, resolved.members[1] == 2, "%s collision reordered its second member", test_case.name)
			testing.expectf(t, resolved.members[2] == 3, "%s collision reordered its third member", test_case.name)
			testing.expectf(t, resolved_marker_text(resolved) == test_case.text, "%s collision returned the wrong text", test_case.name)
			testing.expectf(t, resolved.style_role == test_case.role, "%s collision returned the wrong role", test_case.name)
		}
		resolved_marker_view_close(&view)
	}
}

@(test)
/* marker_collision_order_is_independent_of_publication_order. */
collision_order_ignores_publish_order :: proc(t: ^testing.T) {
	forward := [2]Marker{marker_test_value(2, 20, "i", ""), marker_test_value(1, 20, "E", "")}
	reverse := [2]Marker{forward[1], forward[0]}
	lane := marker_test_lane(.Stack)
	publications := [2]Marker_Generation_View {
		{id = 1, provider = 9, provider_generation = 2, complete = true, markers = forward[:]},
		{id = 1, provider = 9, provider_generation = 2, complete = true, markers = reverse[:]},
	}
	texts: [2]string
	for &publication, index in publications {
		view, composed, _ := compose_markers(marker_test_request([]Lane_Definition{lane}, []Marker_Generation_View{publication}))
		testing.expect(t, composed)
		if composed {
			texts[index] = resolved_marker_text(&view.markers[0])
			resolved_marker_view_close(&view)
		}
	}
	testing.expect_value(t, texts[0], "Ei")
	testing.expect_value(t, texts[1], texts[0])
}

@(test)
/* display_markers_require_the_exact_view_projection_generation. */
display_markers_require_view_generation :: proc(t: ^testing.T) {
	marker := marker_test_value(1, 10, ">", "")
	marker.attachment = {
		kind = .Display_Row,
		display_row = 0,
		buffer_revision = 7,
		view_identity = 12,
		view_generation = 2,
		projection_generation = 19,
	}
	publication := Marker_Generation_View {
		id = 1, provider = 9, provider_generation = 2, complete = true, markers = []Marker{marker},
	}
	lane := marker_test_lane(.Highest_Priority)
	view, composed, _ := compose_markers(marker_test_request([]Lane_Definition{lane}, []Marker_Generation_View{publication}))
	testing.expect(t, composed)
	if composed {
		testing.expect_value(t, len(view.markers), 0)
		resolved_marker_view_close(&view)
	}
}

@(test)
/* incomplete_marker_publications_never_expose_partial_rows. */
incomplete_publish_hides_partial_rows :: proc(t: ^testing.T) {
	marker := marker_test_value(1, 10, "E", "")
	publication := Marker_Generation_View {
		id = 1, provider = 9, provider_generation = 2, complete = false, markers = []Marker{marker},
	}
	lane := marker_test_lane(.Highest_Priority)
	_, composed, failure := compose_markers(marker_test_request([]Lane_Definition{lane}, []Marker_Generation_View{publication}))
	testing.expect(t, !composed)
	testing.expect_value(t, failure.code, Failure_Code.Incomplete_Generation)
}

@(test)
/* programmable_logical_markers_apply_across_current_buffer_revisions. */
programmable_markers_follow_revisions :: proc(t: ^testing.T) {
	lane := marker_test_lane(.Highest_Priority)
	lane.id = PROGRAMMABLE_LANE_ID_BASE
	lane.provider = PROGRAMMABLE_PROVIDER_ID
	marker := marker_test_value(1, 10, "◆", "")
	marker.provider = PROGRAMMABLE_PROVIDER_ID
	marker.lane = PROGRAMMABLE_LANE_ID_BASE
	marker.attachment.buffer_revision = 0
	publication := Marker_Generation_View {
		id = 1,
		provider = PROGRAMMABLE_PROVIDER_ID,
		provider_generation = 2,
		complete = true,
		markers = []Marker{marker},
	}
	view, composed, failure := compose_markers(
		marker_test_request([]Lane_Definition{lane}, []Marker_Generation_View{publication}),
	)
	if !testing.expectf(t, composed, "programmable marker failed: %v", failure.code) do return
	defer resolved_marker_view_close(&view)
	testing.expect_value(t, len(view.markers), 1)
}
