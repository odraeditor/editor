// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package terminal_frontend

import "core:strings"
import "core:testing"
import "../display"
import "../ui"

@(test)
/* Ensures parsed terminal cells lower to physical color, attributes, and focused cursor state. */
ui_terminal_view_lowers_parsed_cells :: proc(t: ^testing.T) {
	constraints := display.Viewport_Constraints{width_cells = 4, height_rows = 2}
	config := renderer_config(constraints)
	config.color = .True_Color
	renderer: Renderer
	renderer_ok, _ := renderer_init(&renderer, config)
	testing.expect(t, renderer_ok)
	if !renderer_ok do return
	defer renderer_close(&renderer)
	profile := renderer_state_ui_profile(renderer_state(&renderer))
	registry: ui.Registry
	registry_ok, _ := ui.registry_init(&registry, 801)
	testing.expect(t, registry_ok)
	if !registry_ok do return
	defer ui.registry_close(&registry)
	proposal, prepared, _ := ui.proposal_begin(&registry)
	_, style_ok, _ := ui.proposal_add_style(&proposal, .Text_Normal)
	rows := []ui.Terminal_Row {{row = 0, dirty = true}, {row = 1}}
	cells := []ui.Terminal_Cell {{column = 0, row = 0, text_length = 1}}
	cells[0].text[0] = 'A'
	cells[0].style.foreground = {
		kind = .RGB,
		rgb = {red = 10, green = 20, blue = 30},
	}
	cells[0].style.attributes = {.Bold, .Italic}
	request := ui.Terminal_Projection_Request {
		model = {owner_id = 8, model_id = 9, generation = 10},
		session_id = 11,
		session_generation = 12,
		revision = 13,
		columns = 4,
		rows = 2,
		damage = .Partial,
		cursor = {
			column = 1,
			row = 0,
			style = .Bar,
			in_viewport = true,
			visible = true,
		},
		foreground = {red = 240, green = 240, blue = 240},
		background = {red = 1, green = 2, blue = 3},
		lifecycle = .Running,
		activity_generation = 14,
		audible_attention = true,
		visual_attention = true,
		title = "shell",
	}
	view, view_ok, _ := ui.proposal_project_terminal_view(&proposal, request, rows, cells)
	surface, surface_ok, _ := ui.proposal_add_surface(&proposal, ui.Surface_Descriptor {
		owner_id = 8,
		view = view,
		focusable = true,
		visible = true,
		required_profile = profile.id,
		geometry = {height = 2, width = 4},
	})
	node, node_ok, _ := ui.proposal_add_surface_node(&proposal, surface)
	root_ok, _ := ui.proposal_set_root(&proposal, node, surface)
	root, published, _ := ui.proposal_publish(&registry, &proposal, profile)
	testing.expect(t, prepared && style_ok && view_ok && surface_ok && node_ok && root_ok && published)
	if !published do return
	snapshot, copied, _ := ui.registry_snapshot(&registry, root, profile)
	testing.expect(t, copied)
	if !copied do return
	defer ui.snapshot_close(&snapshot)
	frame, rendered, failure := renderer_prepare_ui(
		renderer_state(&renderer),
		UI_Presentation{root = &snapshot},
	)
	testing.expectf(t, rendered, "terminal UI frame failed with %v", failure.code)
	if !rendered do return
	defer frame_close(&frame)
	output := string(frame.output[:frame.used])
	testing.expect(t, frame.used < 2_048)
	testing.expect_value(t, ui_terminal_view_output_count(output, "\x1b[?25l"), 1)
	testing.expect_value(t, ui_terminal_view_output_count(output, "\x1b[2J"), 1)
	testing.expect_value(t, ui_terminal_view_output_count(output, "\x1b[?25h"), 1)
	testing.expect(t, strings.contains(output, "\x1b[38;2;10;20;30m"))
	testing.expect(t, strings.contains(output, "\x1b[1m"))
	testing.expect(t, strings.contains(output, "\x1b[3m"))
	testing.expect(t, strings.contains(output, "\x1b[7m"))
	testing.expect_value(t, ui_terminal_view_output_count(output, "\x07"), 1)
	testing.expect(t, strings.contains(output, "A"))
	testing.expect(t, strings.contains(output, "\x1b[6 q"))
	testing.expect(t, strings.has_suffix(output, "\x1b[?25h"))
}

@(test)
/* Ensures child palette colors retain theme meaning across physical color fallbacks. */
ui_terminal_cell_color_follows_renderer_capability :: proc(t: ^testing.T) {
	view: ui.Terminal_View_State
	view.foreground = {red = 220, green = 220, blue = 220}
	view.background = {red = 5, green = 5, blue = 5}
	view.palette[9] = {red = 255, green = 0, blue = 0}
	cell := ui.Terminal_Cell {
		style = {
			foreground = {kind = .Palette, palette = 9},
			background = {kind = .Default},
			underline_color = {kind = .RGB, rgb = {red = 1, green = 2, blue = 3}},
			attributes = {.Underline},
		},
	}
	true_color := terminal_cell_style_lower(view, cell, .True_Color)
	indexed := terminal_cell_style_lower(view, cell, .Indexed_256)
	basic := terminal_cell_style_lower(view, cell, .Basic_16)
	mono := terminal_cell_style_lower(view, cell, .Monochrome)
	testing.expect_value(t, true_color.foreground.kind, Terminal_Color_Kind.RGB)
	testing.expect_value(t, true_color.foreground.color, ui.SRGB_Color{red = 255})
	testing.expect_value(t, true_color.underline_color.color, ui.SRGB_Color{red = 1, green = 2, blue = 3})
	testing.expect_value(t, indexed.foreground.kind, Terminal_Color_Kind.Indexed)
	testing.expect_value(t, basic.foreground.kind, Terminal_Color_Kind.Basic)
	testing.expect_value(t, mono.foreground.kind, Terminal_Color_Kind.Default)
}

@(test)
/* Ensures a visible child cursor cannot take focus from another logical surface. */
ui_terminal_cursor_requires_surface_focus :: proc(t: ^testing.T) {
	terminal_surface := ui.Surface_Descriptor {
		handle = {registry_id = 1, object_id = 1, root_generation = 1},
		geometry = {height = 2, width = 4},
	}
	other_surface := ui.Object_Handle{registry_id = 1, object_id = 2, root_generation = 1}
	view := ui.Visual_View_Descriptor {
		kind = .Terminal_View,
		terminal = {
			present = true,
			cursor = {column = 1, row = 1, in_viewport = true, visible = true},
		},
	}
	unfocused := ui.Snapshot_View{focus = {target = other_surface}}
	focused := ui.Snapshot_View{focus = {target = terminal_surface.handle}}
	testing.expect(t, !terminal_view_cursor_is_active(unfocused, terminal_surface, view))
	testing.expect(t, terminal_view_cursor_is_active(focused, terminal_surface, view))
}

@(private = "file")
ui_terminal_view_output_count :: proc(value, target: string) -> int {
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
