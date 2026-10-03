// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package terminal_frontend

import "../display"
import "../ui"
import "core:testing"

/* Verifies Replace cursor intent lowers to the non-blinking terminal underline. */
@(test)
replace_cursor_uses_terminal_underline :: proc(t: ^testing.T) {
	output, allocation_error := make([]u8, 16)
	testing.expect(t, allocation_error == nil)
	if allocation_error != nil do return
	frame := Render_Frame{allocator = context.allocator, output = output}
	frame_append_terminal_cursor_style(&frame, .Underline, false)
	testing.expect_value(t, string(frame.output[:frame.used]), "\x1b[4 q")
	frame_close(&frame)
}

/* Verifies process hints select one deterministic bounded color capability. */
@(test)
renderer_color_capability_selection_is_stable :: proc(t: ^testing.T) {
	testing.expect_value(
		t,
		renderer_color_capability_select(true, "truecolor", "xterm-256color"),
		ui.Renderer_Color_Capability.Monochrome,
	)
	testing.expect_value(
		t,
		renderer_color_capability_select(false, "truecolor", "xterm"),
		ui.Renderer_Color_Capability.True_Color,
	)
	testing.expect_value(
		t,
		renderer_color_capability_select(false, "", "xterm-256color"),
		ui.Renderer_Color_Capability.Indexed_256,
	)
	testing.expect_value(
		t,
		renderer_color_capability_select(false, "", "xterm"),
		ui.Renderer_Color_Capability.Basic_16,
	)
	testing.expect_value(
		t,
		renderer_color_capability_select(false, "truecolor", "dumb"),
		ui.Renderer_Color_Capability.Monochrome,
	)
	testing.expect_value(
		t,
		renderer_color_capability_select(false, "", ""),
		ui.Renderer_Color_Capability.Monochrome,
	)
}

/* Verifies copied inspection text reports the same deterministic lowering. */
@(test)
color_format_matches_renderer_profiles :: proc(t: ^testing.T) {
	color := ui.Optional_SRGB_Color {
		present = true,
		color = {red = 255, green = 0, blue = 0},
	}
	cases := []struct {
		capability: ui.Renderer_Color_Capability,
		expected:   string,
	} {
		{.Monochrome, "default"},
		{.Basic_16, "basic-9"},
		{.Indexed_256, "indexed-196"},
		{.True_Color, "#FF0000"},
	}
	for test_case in cases {
		storage: [32]u8
		value, formatted := renderer_color_value_format(
			color,
			test_case.capability,
			storage[:],
		)
		testing.expect(t, formatted)
		testing.expect_value(t, value, test_case.expected)
	}
}

/* Verifies all color profiles lower exactly once and reset every active field. */
@(test)
style_lowering_profiles_and_resets_are_exact :: proc(t: ^testing.T) {
	style := ui.Style_Definition {
		role = .Syntax_Keyword,
		foreground = {
			present = true,
			color = {red = 255, green = 0, blue = 0},
		},
		background = {
			present = true,
			color = {red = 0, green = 0, blue = 255},
		},
		attributes = {.Bold},
	}
	cases := []struct {
		capability: ui.Renderer_Color_Capability,
		expected:   string,
	} {
		{
			.True_Color,
			"\x1b[1m\x1b[38;2;255;0;0m\x1b[48;2;0;0;255m\x1b[22m\x1b[39m\x1b[49m",
		},
		{
			.Indexed_256,
			"\x1b[1m\x1b[38;5;196m\x1b[48;5;21m\x1b[22m\x1b[39m\x1b[49m",
		},
		{
			.Basic_16,
			"\x1b[1m\x1b[91m\x1b[104m\x1b[22m\x1b[39m\x1b[49m",
		},
		{
			.Monochrome,
			"\x1b[1m\x1b[22m",
		},
	}
	for test_case in cases {
		output, allocation_error := make([]u8, 256)
		testing.expect(t, allocation_error == nil)
		if allocation_error != nil do continue
		frame := Render_Frame {
			allocator = context.allocator,
			output = output,
			color = test_case.capability,
		}
		frame_append_style(&frame, style)
		first_used := frame.used
		frame_append_style(&frame, style)
		testing.expect_value(t, frame.used, first_used)
		frame_reset_style(&frame)
		testing.expect_value(t, string(frame.output[:frame.used]), test_case.expected)
		frame_close(&frame)
	}
}

/* Verifies renderer profiles preserve the selected color capability exactly. */
@(test)
profile_reports_color_capability :: proc(t: ^testing.T) {
	for capability_value in int(ui.Renderer_Color_Capability.Monochrome) ..=
	                         int(ui.Renderer_Color_Capability.True_Color) {
		capability := ui.Renderer_Color_Capability(capability_value)
		renderer: Renderer
		initialized, _ := renderer_init(
			&renderer,
			Renderer_Config {
				constraints = {width_cells = 80, height_rows = 24},
				profile = display.terminal_unicode17_profile(),
				color = capability,
				max_output_bytes = MAX_OUTPUT_BYTES,
				allocator = context.allocator,
			},
		)
		testing.expect(t, initialized)
		if !initialized do continue
		profile, ok := renderer_ui_profile(&renderer)
		testing.expect(t, ok)
		testing.expect_value(t, profile.color, capability)
		renderer_close(&renderer)
	}
}
