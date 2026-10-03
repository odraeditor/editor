// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ui

import "../language"
import "core:testing"

/* Verifies every language syntax role maps to one exact shared UI role. */
@(test)
syntax_role_mapping_is_complete :: proc(t: ^testing.T) {
	expected := [?]Style_Role {
		.Syntax_Attribute,
		.Syntax_Boolean,
		.Syntax_Comment,
		.Syntax_Constant,
		.Syntax_Constructor,
		.Syntax_Function,
		.Syntax_Function_Builtin,
		.Syntax_Keyword,
		.Syntax_Label,
		.Syntax_Number,
		.Syntax_Operator,
		.Syntax_Punctuation,
		.Syntax_String,
		.Syntax_Type,
		.Syntax_Variable,
		.Syntax_Variable_Parameter,
	}
	for role_value in int(language.Syntax_Role.Attribute) ..=
	                  int(language.Syntax_Role.Variable_Parameter) {
		mapped, ok := syntax_style_role(language.Syntax_Role(role_value))
		testing.expect(t, ok)
		testing.expect_value(t, mapped, expected[role_value - 1])
	}
	invalid, ok := syntax_style_role(.Invalid)
	testing.expect(t, !ok)
	testing.expect_value(t, invalid, Style_Role.Invalid)
}

/* Verifies exact syntax spans survive the generic decoration snapshot path. */
@(test)
syntax_spans_project_as_decorations :: proc(t: ^testing.T) {
	registry: Registry
	proposal: Proposal
	text_view, ready := syntax_projection_test_prepare(&registry, &proposal, DEFAULT_RESOURCE_LIMITS)
	testing.expect(t, ready)
	if !ready do return
	defer registry_close(&registry)

	provider := syntax_projection_test_provider()
	spans := [2]language.Syntax_Span {
		{
			start = 0,
			end = 3,
			role = .Keyword,
			precedence = 20,
			provider = provider,
			source_revision = 3,
		},
		{
			start = 4,
			end = 9,
			role = .Function,
			precedence = 10,
			provider = provider,
			source_revision = 3,
		},
	}
	syntax_snapshot := syntax_projection_test_snapshot(provider, len(spans))
	count, projected, projection_failure := proposal_project_syntax_decorations(
		&proposal,
		text_view,
		syntax_snapshot,
		spans[:],
		703,
	)
	testing.expectf(t, projected, "syntax projection failed with %v", projection_failure.code)
	testing.expect_value(t, count, u32(2))

	state := proposal_state(&proposal)
	testing.expect(t, state != nil)
	if state != nil && state.decoration_count == 2 {
		first := state.decorations[0]
		second := state.decorations[1]
		testing.expect_value(t, first.owner_id, Owner_ID(703))
		testing.expect_value(t, first.kind, Decoration_Kind.Text_Range)
		testing.expect_value(t, first.projection, state.views[text_view.slot].projection)
		testing.expect_value(t, first.source_revision, u64(3))
		testing.expect_value(t, first.start, u64(0))
		testing.expect_value(t, first.end, u64(3))
		testing.expect_value(t, first.style_role, Style_Role.Syntax_Keyword)
		testing.expect_value(t, first.precedence, u16(20))
		testing.expect_value(t, second.style_role, Style_Role.Syntax_Function)
		testing.expect_value(t, second.precedence, u16(10))
	}

	surface, surface_ok, _ := proposal_add_surface(
		&proposal,
		Surface_Descriptor {
			owner_id = 703,
			view = text_view,
			focusable = true,
			visible = true,
			required_profile = 1,
		},
	)
	node, node_ok, _ := proposal_add_surface_node(&proposal, surface)
	root_set, _ := proposal_set_root(&proposal, node, surface)
	root, published, publish_failure := proposal_publish(
		&registry,
		&proposal,
		syntax_projection_test_renderer(),
	)
	snapshot, copied, copy_failure := registry_snapshot(
		&registry,
		root,
		syntax_projection_test_renderer(),
	)
	testing.expect(t, surface_ok && node_ok && root_set)
	testing.expectf(t, published, "publication failed with %v", publish_failure.code)
	testing.expectf(t, copied, "snapshot failed with %v", copy_failure.code)
	if copied {
		view, viewed := snapshot_view(&snapshot)
		testing.expect(t, viewed)
		testing.expect_value(t, len(view.decorations), 2)
		if len(view.decorations) == 2 {
			testing.expect_value(t, view.decorations[0].style_role, Style_Role.Syntax_Keyword)
			testing.expect_value(t, view.decorations[1].style_role, Style_Role.Syntax_Function)
		}
		snapshot_close(&snapshot)
	}
}

/* Verifies stale and unsorted syntax sets reject without partial decorations. */
@(test)
invalid_syntax_sets_reject_atomically :: proc(t: ^testing.T) {
	registry: Registry
	proposal: Proposal
	text_view, ready := syntax_projection_test_prepare(&registry, &proposal, DEFAULT_RESOURCE_LIMITS)
	testing.expect(t, ready)
	if !ready do return
	defer registry_close(&registry)
	defer proposal_abort(&proposal)

	provider := syntax_projection_test_provider()
	spans := [2]language.Syntax_Span {
		{start = 4, end = 7, role = .Function, provider = provider, source_revision = 3},
		{start = 0, end = 3, role = .Keyword, provider = provider, source_revision = 3},
	}
	syntax_snapshot := syntax_projection_test_snapshot(provider, len(spans))
	_, projected, failure := proposal_project_syntax_decorations(
		&proposal,
		text_view,
		syntax_snapshot,
		spans[:],
		703,
	)
	testing.expect(t, !projected)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_Decoration)
	state := proposal_state(&proposal)
	testing.expect(t, state != nil)
	if state != nil {
		testing.expect_value(t, state.decoration_count, 0)
		testing.expect_value(t, state.accounting.decoration_bytes, u64(0))
	}

	spans[0] = {start = 0, end = 3, role = .Keyword, provider = provider, source_revision = 3}
	spans[1] = {start = 4, end = 7, role = .Function, provider = provider, source_revision = 3}
	syntax_snapshot.source_revision = 2
	_, projected, failure = proposal_project_syntax_decorations(
		&proposal,
		text_view,
		syntax_snapshot,
		spans[:],
		703,
	)
	testing.expect(t, !projected)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_Decoration)
	if state != nil do testing.expect_value(t, state.decoration_count, 0)

	syntax_snapshot.source_revision = 3
	spans[0] = {start = 0, end = 5, role = .Keyword, provider = provider, source_revision = 3}
	spans[1] = {start = 4, end = 7, role = .Function, provider = provider, source_revision = 3}
	_, projected, failure = proposal_project_syntax_decorations(
		&proposal,
		text_view,
		syntax_snapshot,
		spans[:],
		703,
	)
	testing.expect(t, !projected)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_Decoration)
	if state != nil do testing.expect_value(t, state.decoration_count, 0)
}

/* Verifies a decoration limit rejects the complete syntax set before mutation. */
@(test)
syntax_limits_reject_atomically :: proc(t: ^testing.T) {
	limits := DEFAULT_RESOURCE_LIMITS
	limits.decorations = 1
	registry: Registry
	proposal: Proposal
	text_view, ready := syntax_projection_test_prepare(&registry, &proposal, limits)
	testing.expect(t, ready)
	if !ready do return
	defer registry_close(&registry)
	defer proposal_abort(&proposal)

	provider := syntax_projection_test_provider()
	spans := [2]language.Syntax_Span {
		{start = 0, end = 3, role = .Keyword, provider = provider, source_revision = 3},
		{start = 4, end = 7, role = .Function, provider = provider, source_revision = 3},
	}
	syntax_snapshot := syntax_projection_test_snapshot(provider, len(spans))
	_, projected, failure := proposal_project_syntax_decorations(
		&proposal,
		text_view,
		syntax_snapshot,
		spans[:],
		703,
	)
	testing.expect(t, !projected)
	testing.expect_value(t, failure.code, Failure_Code.Decoration_Limit)
	testing.expect_value(t, failure.limit, u64(1))
	testing.expect_value(t, failure.actual, u64(2))
	state := proposal_state(&proposal)
	if state != nil {
		testing.expect_value(t, state.decoration_count, 0)
		testing.expect_value(t, state.accounting.decoration_bytes, u64(0))
	}
}

@(private)
syntax_projection_test_prepare :: proc(
	registry: ^Registry,
	proposal: ^Proposal,
	limits: Resource_Limits,
) -> (Object_Handle, bool) {
	registry_ok, _ := registry_init(registry, 703, limits)
	if !registry_ok do return {}, false
	prepared, proposal_ok, _ := proposal_begin(registry)
	if !proposal_ok do return {}, false
	proposal^ = prepared
	projection, projection_ok, _ := proposal_add_projection(
		proposal,
		Model_Reference {owner_id = 703, model_id = 701, generation = 4},
		u64(size_of(Text_View_State)),
	)
	if !projection_ok do return {}, false
	text_view, view_ok, _ := proposal_add_view(
		proposal,
		Visual_View_Descriptor {
			kind = .Text_View,
			projection = projection,
			text = Text_View_State {
				present = true,
				source = {
					registry_id = 7,
					view_id = 1,
					view_generation = 1,
					state_generation = 1,
					selection_generation = 1,
				},
				buffer_id = 701,
				revision = 3,
				source_text_bytes = 12,
				tab_width = 4,
				display_profile_id = 1,
				presentation_ownership = .Retained_Primary,
			},
		},
	)
	if !view_ok do return {}, false
	_, normal_ok, _ := proposal_add_style(proposal, .Text_Normal)
	styles_ok, _ := proposal_add_factory_syntax_styles(proposal)
	return text_view, normal_ok && styles_ok
}

@(private)
syntax_projection_test_provider :: proc() -> language.Provider_Handle {
	return language.Provider_Handle {
		registry_id = 1,
		language_id = 7,
		provider_id = 1,
		provider_generation = 1,
	}
}

@(private)
syntax_projection_test_snapshot :: proc(
	provider: language.Provider_Handle,
	span_count: int,
) -> language.Syntax_Snapshot {
	return language.Syntax_Snapshot {
		generation = 1,
		buffer_id = 701,
		source_revision = 3,
		language = {id = 7, generation = 1},
		provider = provider,
		selection_generation = 1,
		parser_generation = 1,
		query_generation = 1,
		span_count = u32(span_count),
		usage = {
			spans = u32(span_count),
			retained_span_bytes = u64(span_count) * u64(size_of(language.Syntax_Span)),
		},
	}
}

@(private)
syntax_projection_test_renderer :: proc() -> Renderer_Profile {
	return Renderer_Profile {
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
		color = .True_Color,
		unicode_profile = 17,
		max_rows = 80,
		max_columns = 240,
		max_cells = 19_200,
		attributes = {.Bold, .Dim, .Underline, .Reverse},
	}
}
