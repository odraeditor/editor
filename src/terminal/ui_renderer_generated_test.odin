// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package terminal_frontend

import "../display"
import "../editor"
import "../language"
import "../ui"
import editor_view "../view"
import "core:testing"

@(test)
/* generated_text_ui_roots_remain_bounded_and_reject_stale_projections. */
generated_text_ui_roots_remain_bounded :: proc(t: ^testing.T) {
	contents := "alpha\t界 beta\ngamma"
	fixture: Renderer_Fixture
	if !renderer_fixture_init(t, &fixture, 118, contents) {
		return
	}
	defer renderer_fixture_close(&fixture)
	logical, logical_ok, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	testing.expect(t, logical_ok)
	if !logical_ok do return
	provider := language.Provider_Handle {
		registry_id = 1,
		language_id = 1,
		provider_id = 1,
		provider_generation = 1,
	}
	spans := [1]language.Syntax_Span {{
		start = 0,
		end = editor.Byte_Offset(len(contents)),
		role = .Keyword,
		precedence = 10,
		provider = provider,
		source_revision = logical.revision,
	}}
	syntax_snapshot := language.Syntax_Snapshot {
		generation = 1,
		buffer_id = logical.buffer_id,
		source_revision = logical.revision,
		language = {id = 1, generation = 1},
		provider = provider,
		selection_generation = 1,
		parser_generation = 1,
		query_generation = 1,
		span_count = 1,
		usage = {
			spans = 1,
			retained_span_bytes = u64(size_of(language.Syntax_Span)),
		},
	}
	case_id := u64(1)
	for height in u32(1) ..= 3 {
		for width in u32(1) ..= 16 {
			constraints := display.Viewport_Constraints {
				width_cells = width,
				height_rows = height,
			}
			display_snapshot, projected, projection_failure := display.project(
				&fixture.buffer,
				renderer_projection_request(1_000 + case_id, logical, constraints),
			)
			testing.expectf(t, projected, "generated projection %d failed with %v", case_id, projection_failure.code)
			if !projected {
				return
			}
			renderer: Renderer
			config := renderer_config(constraints)
			config.color = ui.Renderer_Color_Capability(case_id % 4)
			renderer_ok, _ := renderer_init(&renderer, config)
			root: Text_UI_Test_Root
			root_ok := renderer_ok && text_ui_test_root_init(
				t,
				&root,
				&fixture,
				&renderer,
				display_snapshot,
				logical,
				constraints,
				nil,
				nil,
				{.Reverse},
				{.Reverse},
				&syntax_snapshot,
				spans[:],
			)
			if !root_ok {
				if renderer_ok do renderer_close(&renderer)
				display.snapshot_close(&display_snapshot)
				return
			}
			frame, prepared, prepare_failure := renderer_prepare_ui(
				renderer_state(&renderer), text_ui_test_root_presentation(&root),
			)
			testing.expectf(t, prepared, "generated root %d failed with %v", case_id, prepare_failure.code)
			if prepared {
				testing.expect(t, frame.used <= u32(len(frame.output)))
				frame_close(&frame)
			}
			root.projections[0].logical.state_generation += 1
			_, stale_ok, stale_failure := renderer_prepare_ui(
				renderer_state(&renderer), text_ui_test_root_presentation(&root),
			)
			testing.expect(t, !stale_ok)
			testing.expect_value(t, stale_failure.code, Failure_Code.Invalid_UI_Presentation)
			text_ui_test_root_close(&root)
			renderer_close(&renderer)
			display.snapshot_close(&display_snapshot)
			case_id += 1
		}
	}
}

@(test)
/* text_ui_root_rejects_insufficient_surface_geometry_before_frame_allocation. */
ui_rejects_geometry_before_allocation :: proc(t: ^testing.T) {
	fixture: Renderer_Fixture
	if !renderer_fixture_init(t, &fixture, 119, "insufficient") {
		return
	}
	defer renderer_fixture_close(&fixture)
	logical, _, _ := editor_view.snapshot(&fixture.registry, fixture.handle)
	constraints := display.Viewport_Constraints{width_cells = 12, height_rows = 2}
	display_snapshot, projected, _ := display.project(
		&fixture.buffer,
		renderer_projection_request(2_000, logical, constraints),
	)
	if !projected {
		testing.expect(t, false)
		return
	}
	defer display.snapshot_close(&display_snapshot)
	renderer: Renderer
	renderer_ok, _ := renderer_init(&renderer, renderer_config(constraints))
	if !renderer_ok {
		testing.expect(t, false)
		return
	}
	defer renderer_close(&renderer)
	insufficient_geometry: ui.Cell_Rect
	root: Text_UI_Test_Root
	root_ok := text_ui_test_root_init(
		t,
		&root,
		&fixture,
		&renderer,
		display_snapshot,
		logical,
		constraints,
		nil,
		&insufficient_geometry,
	)
	if !root_ok do return
	defer text_ui_test_root_close(&root)
	_, prepared, failure := renderer_prepare_ui(
		renderer_state(&renderer), text_ui_test_root_presentation(&root),
	)
	testing.expect(t, !prepared)
	testing.expect_value(t, failure.code, Failure_Code.Invalid_UI_Presentation)
}
