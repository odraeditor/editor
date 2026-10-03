// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package terminal_frontend

import "../ui"
import "core:fmt"
import "core:os"
import "core:strings"

@(private)
Terminal_Color_Kind :: enum u8 {
	Default,
	Basic,
	Indexed,
	RGB,
}

@(private)
Terminal_Color :: struct {
	kind:  Terminal_Color_Kind,
	index: u8,
	color: ui.SRGB_Color,
}

@(private)
Terminal_Style :: struct {
	foreground: Terminal_Color,
	background: Terminal_Color,
	underline_color: Terminal_Color,
	attributes: ui.Style_Attributes,
}

/* renderer_color_capability_detect selects one bounded process-terminal profile. */
renderer_color_capability_detect :: proc() -> ui.Renderer_Color_Capability {
	_, no_color := os.lookup_env("NO_COLOR", context.temp_allocator)
	color_term := os.get_env("COLORTERM", context.temp_allocator)
	term := os.get_env("TERM", context.temp_allocator)
	return renderer_color_capability_select(no_color, color_term, term)
}

/* renderer_color_capability_select deterministically interprets terminal hints. */
renderer_color_capability_select :: proc(
	no_color: bool,
	color_term, term: string,
) -> ui.Renderer_Color_Capability {
	if no_color || strings.equal_fold(term, "dumb") do return .Monochrome
	if strings.equal_fold(color_term, "truecolor") || strings.equal_fold(color_term, "24bit") ||
	   strings.contains(term, "-direct") || strings.contains(term, "truecolor") {
		return .True_Color
	}
	if strings.contains(term, "256color") do return .Indexed_256
	if len(term) > 0 do return .Basic_16
	return .Monochrome
}

@(private)
terminal_style_lower :: proc(
	style: ui.Style_Definition,
	capability: ui.Renderer_Color_Capability,
) -> Terminal_Style {
	return Terminal_Style {
		foreground = terminal_color_lower(style.foreground, capability),
		background = terminal_color_lower(style.background, capability),
		attributes = style.attributes,
	}
}

@(private)
terminal_color_lower :: proc(
	color: ui.Optional_SRGB_Color,
	capability: ui.Renderer_Color_Capability,
) -> Terminal_Color {
	if !color.present || capability == .Monochrome do return {}
	switch capability {
	case .Basic_16:
		return {kind = .Basic, index = terminal_nearest_basic_color(color.color)}
	case .Indexed_256:
		return {kind = .Indexed, index = terminal_nearest_indexed_color(color.color)}
	case .True_Color:
		return {kind = .RGB, color = color.color}
	case .Monochrome:
		return {}
	}
	return {}
}

/* renderer_color_value_format reports one deterministic physical color value. */
renderer_color_value_format :: proc(
	color: ui.Optional_SRGB_Color,
	capability: ui.Renderer_Color_Capability,
	output: []u8,
) -> (string, bool) {
	if len(output) < 32 do return "", false
	lowered := terminal_color_lower(color, capability)
	switch lowered.kind {
	case .Default:
		value := "default"
		copy(output, transmute([]u8)value)
		return string(output[:len(value)]), true
	case .Basic:
		value := fmt.bprintf(output, "basic-%d", lowered.index)
		return value, true
	case .Indexed:
		value := fmt.bprintf(output, "indexed-%d", lowered.index)
		return value, true
	case .RGB:
		value := fmt.bprintf(
			output,
			"#%02X%02X%02X",
			lowered.color.red,
			lowered.color.green,
			lowered.color.blue,
		)
		return value, true
	}
	return "", false
}

@(private)
terminal_nearest_basic_color :: proc(color: ui.SRGB_Color) -> u8 {
	palette := [16]ui.SRGB_Color {
		{red = 0, green = 0, blue = 0},
		{red = 128, green = 0, blue = 0},
		{red = 0, green = 128, blue = 0},
		{red = 128, green = 128, blue = 0},
		{red = 0, green = 0, blue = 128},
		{red = 128, green = 0, blue = 128},
		{red = 0, green = 128, blue = 128},
		{red = 192, green = 192, blue = 192},
		{red = 128, green = 128, blue = 128},
		{red = 255, green = 0, blue = 0},
		{red = 0, green = 255, blue = 0},
		{red = 255, green = 255, blue = 0},
		{red = 0, green = 0, blue = 255},
		{red = 255, green = 0, blue = 255},
		{red = 0, green = 255, blue = 255},
		{red = 255, green = 255, blue = 255},
	}
	best_index := u8(0)
	best_distance := terminal_color_distance(color, palette[0])
	for candidate, index in palette[1:] {
		distance := terminal_color_distance(color, candidate)
		if distance < best_distance {
			best_distance = distance
			best_index = u8(index + 1)
		}
	}
	return best_index
}

@(private)
terminal_nearest_indexed_color :: proc(color: ui.SRGB_Color) -> u8 {
	best_index := u8(16)
	best_distance := terminal_color_distance(color, terminal_indexed_color(best_index))
	for candidate in 17 ..= 255 {
		index := u8(candidate)
		distance := terminal_color_distance(color, terminal_indexed_color(index))
		if distance < best_distance {
			best_distance = distance
			best_index = index
		}
	}
	return best_index
}

@(private)
terminal_indexed_color :: proc(index: u8) -> ui.SRGB_Color {
	assert(index >= 16)
	if index <= 231 {
		cube := u32(index - 16)
		return ui.SRGB_Color {
			red = terminal_cube_level(u8(cube / 36)),
			green = terminal_cube_level(u8(cube / 6 % 6)),
			blue = terminal_cube_level(u8(cube % 6)),
		}
	}
	level := u8(8 + 10 * u16(index - 232))
	return {red = level, green = level, blue = level}
}

@(private)
terminal_cube_level :: proc(index: u8) -> u8 {
	levels := [6]u8{0, 95, 135, 175, 215, 255}
	return levels[index]
}

@(private)
terminal_color_distance :: proc(first, second: ui.SRGB_Color) -> u32 {
	red := i32(first.red) - i32(second.red)
	green := i32(first.green) - i32(second.green)
	blue := i32(first.blue) - i32(second.blue)
	return u32(red * red + green * green + blue * blue)
}

@(private)
frame_transition_style :: proc(frame: ^Render_Frame, target: Terminal_Style) {
	if frame.style == target do return
	current := frame.style
	intensity_reset :=
		(.Bold in current.attributes && .Bold not_in target.attributes) ||
		(.Dim in current.attributes && .Dim not_in target.attributes)
	if intensity_reset {
		frame_append_string(frame, "\x1b[22m")
		current.attributes -= {.Bold, .Dim}
	}
	if .Underline in current.attributes && .Underline not_in target.attributes {
		frame_append_string(frame, "\x1b[24m")
		current.attributes -= {.Underline}
	}
	if .Italic in current.attributes && .Italic not_in target.attributes {
		frame_append_string(frame, "\x1b[23m")
		current.attributes -= {.Italic}
	}
	if .Blink in current.attributes && .Blink not_in target.attributes {
		frame_append_string(frame, "\x1b[25m")
		current.attributes -= {.Blink}
	}
	if .Reverse in current.attributes && .Reverse not_in target.attributes {
		frame_append_string(frame, "\x1b[27m")
		current.attributes -= {.Reverse}
	}
	if .Strikethrough in current.attributes && .Strikethrough not_in target.attributes {
		frame_append_string(frame, "\x1b[29m")
		current.attributes -= {.Strikethrough}
	}
	if .Overline in current.attributes && .Overline not_in target.attributes {
		frame_append_string(frame, "\x1b[55m")
		current.attributes -= {.Overline}
	}
	if .Bold in target.attributes && .Bold not_in current.attributes {
		frame_append_string(frame, "\x1b[1m")
	}
	if .Dim in target.attributes && .Dim not_in current.attributes {
		frame_append_string(frame, "\x1b[2m")
	}
	if .Underline in target.attributes && .Underline not_in current.attributes {
		frame_append_string(frame, "\x1b[4m")
	}
	if .Italic in target.attributes && .Italic not_in current.attributes {
		frame_append_string(frame, "\x1b[3m")
	}
	if .Blink in target.attributes && .Blink not_in current.attributes {
		frame_append_string(frame, "\x1b[5m")
	}
	if .Reverse in target.attributes && .Reverse not_in current.attributes {
		frame_append_string(frame, "\x1b[7m")
	}
	if .Strikethrough in target.attributes && .Strikethrough not_in current.attributes {
		frame_append_string(frame, "\x1b[9m")
	}
	if .Overline in target.attributes && .Overline not_in current.attributes {
		frame_append_string(frame, "\x1b[53m")
	}
	if current.foreground != target.foreground {
		frame_append_terminal_color(frame, target.foreground, false)
	}
	if current.background != target.background {
		frame_append_terminal_color(frame, target.background, true)
	}
	if current.underline_color != target.underline_color {
		frame_append_terminal_underline_color(frame, target.underline_color)
	}
	frame.style = target
}

@(private)
frame_append_terminal_color :: proc(
	frame: ^Render_Frame,
	color: Terminal_Color,
	background: bool,
) {
	switch color.kind {
	case .Default:
		frame_append_string(frame, "\x1b[49m" if background else "\x1b[39m")
	case .Basic:
		code := u32(40 if background else 30) + u32(color.index)
		if color.index >= 8 do code = u32(100 if background else 90) + u32(color.index - 8)
		frame_append_string(frame, "\x1b[")
		frame_append_decimal(frame, code)
		frame_append_byte(frame, 'm')
	case .Indexed:
		frame_append_string(frame, "\x1b[48;5;" if background else "\x1b[38;5;")
		frame_append_decimal(frame, u32(color.index))
		frame_append_byte(frame, 'm')
	case .RGB:
		frame_append_string(frame, "\x1b[48;2;" if background else "\x1b[38;2;")
		frame_append_decimal(frame, u32(color.color.red))
		frame_append_byte(frame, ';')
		frame_append_decimal(frame, u32(color.color.green))
		frame_append_byte(frame, ';')
		frame_append_decimal(frame, u32(color.color.blue))
		frame_append_byte(frame, 'm')
	}
}

@(private)
frame_append_terminal_underline_color :: proc(frame: ^Render_Frame, color: Terminal_Color) {
	switch color.kind {
	case .Default:
		frame_append_string(frame, "\x1b[59m")
	case .Basic, .Indexed:
		frame_append_string(frame, "\x1b[58;5;")
		frame_append_decimal(frame, u32(color.index))
		frame_append_byte(frame, 'm')
	case .RGB:
		frame_append_string(frame, "\x1b[58;2;")
		frame_append_decimal(frame, u32(color.color.red))
		frame_append_byte(frame, ';')
		frame_append_decimal(frame, u32(color.color.green))
		frame_append_byte(frame, ';')
		frame_append_decimal(frame, u32(color.color.blue))
		frame_append_byte(frame, 'm')
	}
}
