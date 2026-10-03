// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package display owns versioned Unicode profiles and bounded display projection contracts.
package display

import "core:unicode/utf8"

/* UNICODE_17_PROFILE_ID identifies Odra's pinned Unicode 17.0.0 data profile. */
UNICODE_17_PROFILE_ID :: Unicode_Profile_ID(0x4F44_5241_0017_0000)
/* DEFAULT_TAB_WIDTH is the initial resolved tab-stop interval in display cells. */
DEFAULT_TAB_WIDTH :: u16(4)
/* MAX_TAB_WIDTH bounds tab expansion accepted by a Unicode profile. */
MAX_TAB_WIDTH :: u16(64)

/* Unicode_Profile_ID identifies one immutable Unicode data and width-policy profile. */
Unicode_Profile_ID :: distinct u64

/* Unicode_Version records the semantic version of one profile's Unicode data. */
Unicode_Version :: struct {
	major: u16,
	minor: u16,
	patch: u16,
}

/* Grapheme identifies one half-open extended-grapheme byte range. */
Grapheme :: struct {
	start: u64,
	end:   u64,
}

/* Cluster_Width reports the cell width and exceptional presentation policy used. */
Cluster_Width :: struct {
	cells:            u16,
	is_tab:           bool,
	is_line_break:    bool,
	used_replacement: bool,
}

/* Profile_Failure_Code classifies deterministic Unicode-profile failures. */
Profile_Failure_Code :: enum u8 {
	None,
	Invalid_Profile,
	Malformed_UTF8,
	Out_Of_Range,
	Mid_Encoding_Offset,
	End_Of_Text,
	Invalid_Tab_Width,
	Not_One_Grapheme,
}

/* Profile_Failure reports the rejected byte offset or policy bound. */
Profile_Failure :: struct {
	code:   Profile_Failure_Code,
	offset: u64,
	limit:  u64,
	actual: u64,
}

/* Next_Grapheme_Proc is the substitutable boundary operation of a Unicode profile. */
Next_Grapheme_Proc :: #type proc(
	text: string,
	start: u64,
) -> (grapheme: Grapheme, ok: bool, failure: Profile_Failure)

/* Cluster_Width_Proc is the substitutable cell-width operation of a Unicode profile. */
Cluster_Width_Proc :: #type proc(
	text: string,
	start_column: u32,
	tab_width: u16,
) -> (width: Cluster_Width, ok: bool, failure: Profile_Failure)

/* Unicode_Profile groups immutable version identity with segmentation and width behavior. */
Unicode_Profile :: struct {
	id:            Unicode_Profile_ID,
	version:       Unicode_Version,
	next_grapheme: Next_Grapheme_Proc,
	cluster_width: Cluster_Width_Proc,
}

/* unicode17_profile returns the pinned deterministic Unicode 17.0.0 profile. */
unicode17_profile :: proc() -> Unicode_Profile {
	return Unicode_Profile {
		id = UNICODE_17_PROFILE_ID,
		version = Unicode_Version{major = 17},
		next_grapheme = unicode17_next_grapheme,
		cluster_width = unicode17_cluster_width,
	}
}

/* profile_is_valid reports whether a profile has identity and complete operations. */
profile_is_valid :: proc(profile: Unicode_Profile) -> bool {
	return profile.id != Unicode_Profile_ID(0) && profile.version.major > 0 &&
	       profile.next_grapheme != nil && profile.cluster_width != nil
}

/* profile_next_grapheme dispatches through one checked versioned profile. */
profile_next_grapheme :: proc(
	profile: Unicode_Profile,
	text: string,
	start: u64,
) -> (grapheme: Grapheme, ok: bool, failure: Profile_Failure) {
	if !profile_is_valid(profile) {
		return {}, false, Profile_Failure{code = .Invalid_Profile}
	}
	return profile.next_grapheme(text, start)
}

/* profile_cluster_width dispatches width policy through one checked profile. */
profile_cluster_width :: proc(
	profile: Unicode_Profile,
	text: string,
	start_column: u32,
	tab_width: u16,
) -> (width: Cluster_Width, ok: bool, failure: Profile_Failure) {
	if !profile_is_valid(profile) {
		return {}, false, Profile_Failure{code = .Invalid_Profile}
	}
	return profile.cluster_width(text, start_column, tab_width)
}

@(private)
Grapheme_Class :: enum u8 {
	Other,
	CR,
	LF,
	Control,
	Extend,
	ZWJ,
	Regional_Indicator,
	Prepend,
	Spacing_Mark,
	L,
	V,
	T,
	LV,
	LVT,
}

@(private)
InCB_Class :: enum u8 {
	None,
	Consonant,
	Extend,
	Linker,
}

@(private)
Boundary_State :: struct {
	previous:              Grapheme_Class,
	regional_count:        u32,
	incb_has_consonant:    bool,
	incb_has_linker:       bool,
	emoji_has_base:        bool,
	emoji_zwj_ready:       bool,
}

@(private)
unicode17_next_grapheme :: proc(
	text: string,
	start: u64,
) -> (grapheme: Grapheme, ok: bool, failure: Profile_Failure) {
	if start > u64(len(text)) {
		return {}, false, Profile_Failure {
			code = .Out_Of_Range,
			offset = start,
			limit = u64(len(text)),
			actual = start,
		}
	}
	if start == u64(len(text)) {
		return {}, false, Profile_Failure{code = .End_Of_Text, offset = start}
	}
	if (transmute([]u8)text)[int(start)] & 0xC0 == 0x80 {
		return {}, false, Profile_Failure{code = .Mid_Encoding_Offset, offset = start}
	}
	first_byte := (transmute([]u8)text)[int(start)]
	if first_byte < utf8.RUNE_SELF {
		end := start + 1
		if first_byte == '\r' && end < u64(len(text)) && text[int(end)] == '\n' {
			end += 1
			return Grapheme{start = start, end = end}, true, {}
		}
		if end == u64(len(text)) || text[int(end)] < utf8.RUNE_SELF {
			return Grapheme{start = start, end = end}, true, {}
		}
	}

	offset := int(start)
	first, first_bytes := utf8.decode_rune(text[offset:])
	if first_bytes == 0 || first == utf8.RUNE_ERROR && first_bytes == 1 {
		return {}, false, Profile_Failure{code = .Malformed_UTF8, offset = start}
	}
	state: Boundary_State
	boundary_state_consume(&state, first)
	offset += first_bytes
	for offset < len(text) {
		current, current_bytes := utf8.decode_rune(text[offset:])
		if current_bytes == 0 || current == utf8.RUNE_ERROR && current_bytes == 1 {
			return {}, false, Profile_Failure {
				code = .Malformed_UTF8,
				offset = u64(offset),
			}
		}
		current_class := unicode17_grapheme_class(current)
		if unicode17_should_break(state, current, current_class) {
			return Grapheme{start = start, end = u64(offset)}, true, {}
		}
		boundary_state_consume(&state, current)
		offset += current_bytes
	}
	return Grapheme{start = start, end = u64(offset)}, true, {}
}

@(private)
unicode17_cluster_width :: proc(
	text: string,
	start_column: u32,
	tab_width: u16,
) -> (width: Cluster_Width, ok: bool, failure: Profile_Failure) {
	if tab_width == 0 || tab_width > MAX_TAB_WIDTH {
		return {}, false, Profile_Failure {
			code = .Invalid_Tab_Width,
			limit = u64(MAX_TAB_WIDTH),
			actual = u64(tab_width),
		}
	}
	if len(text) == 1 && text[0] < utf8.RUNE_SELF {
		if text == "\t" {
			cells := u16(u32(tab_width) - start_column % u32(tab_width))
			return Cluster_Width{cells = cells, is_tab = true}, true, {}
		}
		if text == "\n" || text == "\r" {
			return Cluster_Width{is_line_break = true}, true, {}
		}
		if text[0] < ' ' || text[0] == 0x7F {
			return Cluster_Width{cells = 1, used_replacement = true}, true, {}
		}
		return Cluster_Width{cells = 1}, true, {}
	}
	grapheme, grapheme_ok, grapheme_failure := unicode17_next_grapheme(text, 0)
	if !grapheme_ok {
		return {}, false, grapheme_failure
	}
	if grapheme.end != u64(len(text)) {
		return {}, false, Profile_Failure {
			code = .Not_One_Grapheme,
			offset = grapheme.end,
			limit = grapheme.end,
			actual = u64(len(text)),
		}
	}
	if text == "\t" {
		cells := u16(u32(tab_width) - start_column % u32(tab_width))
		return Cluster_Width{cells = cells, is_tab = true}, true, {}
	}
	if text == "\n" || text == "\r" || text == "\r\n" {
		return Cluster_Width{is_line_break = true}, true, {}
	}

	has_emoji := false
	has_emoji_presentation := false
	has_extended_pictographic := false
	has_zwj := false
	has_vs16 := false
	has_keycap := false
	regional_count: u32
	base_cells: u16
	base_found := false
	used_replacement := false
	for current in text {
		value := u32(current)
		class := unicode17_grapheme_class(current)
		has_emoji = has_emoji || range_contains(unicode17_emoji_ranges[:], value)
		has_emoji_presentation = has_emoji_presentation ||
		                         range_contains(unicode17_emoji_presentation_ranges[:], value)
		has_extended_pictographic = has_extended_pictographic ||
		                            range_contains(unicode17_extended_pictographic_ranges[:], value)
		has_zwj = has_zwj || current == '\u200D'
		has_vs16 = has_vs16 || current == '\uFE0F'
		has_keycap = has_keycap || current == '\u20E3'
		if class == .Regional_Indicator {
			regional_count += 1
		}
		if class == .Extend || class == .ZWJ {
			continue
		}
		if class == .Control || class == .CR || class == .LF {
			used_replacement = true
			continue
		}
		base_found = true
		if range_contains(unicode17_east_asian_wide_ranges[:], value) {
			base_cells = max(base_cells, 2)
		} else {
			base_cells = max(base_cells, 1)
		}
	}

	recognized_emoji := has_emoji_presentation ||
	                    (has_emoji && has_vs16) ||
	                    (has_extended_pictographic && has_zwj) ||
	                    (regional_count == 2) ||
	                    (has_emoji && has_keycap)
	if recognized_emoji {
		return Cluster_Width{cells = 2}, true, {}
	}
	if !base_found || used_replacement {
		return Cluster_Width{cells = 1, used_replacement = true}, true, {}
	}
	return Cluster_Width{cells = base_cells}, true, {}
}

@(private)
unicode17_should_break :: proc(
	state: Boundary_State,
	current: rune,
	current_class: Grapheme_Class,
) -> bool {
	previous := state.previous
	if previous == .CR && current_class == .LF {
		return false
	}
	if previous == .Control || previous == .CR || previous == .LF {
		return true
	}
	if current_class == .Control || current_class == .CR || current_class == .LF {
		return true
	}
	if previous == .L &&
	   (current_class == .L || current_class == .V || current_class == .LV ||
	    current_class == .LVT) {
		return false
	}
	if (previous == .LV || previous == .V) &&
	   (current_class == .V || current_class == .T) {
		return false
	}
	if (previous == .LVT || previous == .T) && current_class == .T {
		return false
	}
	if current_class == .Extend || current_class == .ZWJ || current_class == .Spacing_Mark {
		return false
	}
	if previous == .Prepend {
		return false
	}
	if unicode17_incb_class(current) == .Consonant &&
	   state.incb_has_consonant && state.incb_has_linker {
		return false
	}
	if range_contains(unicode17_extended_pictographic_ranges[:], u32(current)) &&
	   state.emoji_zwj_ready {
		return false
	}
	if previous == .Regional_Indicator && current_class == .Regional_Indicator &&
	   state.regional_count & 1 == 1 {
		return false
	}
	return true
}

@(private)
boundary_state_consume :: proc(state: ^Boundary_State, current: rune) {
	class := unicode17_grapheme_class(current)
	incb := unicode17_incb_class(current)
	switch incb {
	case .Consonant:
		state.incb_has_consonant = true
		state.incb_has_linker = false
	case .Extend:
		if !state.incb_has_consonant {
			state.incb_has_linker = false
		}
	case .Linker:
		if state.incb_has_consonant {
			state.incb_has_linker = true
		} else {
			state.incb_has_linker = false
		}
	case .None:
		state.incb_has_consonant = false
		state.incb_has_linker = false
	}

	is_extended_pictographic := range_contains(
		unicode17_extended_pictographic_ranges[:],
		u32(current),
	)
	if is_extended_pictographic {
		state.emoji_has_base = true
		state.emoji_zwj_ready = false
	} else if class == .Extend && state.emoji_has_base {
		state.emoji_zwj_ready = false
	} else if class == .ZWJ && state.emoji_has_base {
		state.emoji_has_base = false
		state.emoji_zwj_ready = true
	} else {
		state.emoji_has_base = false
		state.emoji_zwj_ready = false
	}

	if class == .Regional_Indicator {
		state.regional_count += 1
	} else {
		state.regional_count = 0
	}
	state.previous = class
}

@(private)
unicode17_grapheme_class :: proc(value: rune) -> Grapheme_Class {
	codepoint := u32(value)
	if range_contains(unicode17_gcb_cr_ranges[:], codepoint) do return .CR
	if range_contains(unicode17_gcb_lf_ranges[:], codepoint) do return .LF
	if range_contains(unicode17_gcb_control_ranges[:], codepoint) do return .Control
	if range_contains(unicode17_gcb_extend_ranges[:], codepoint) do return .Extend
	if range_contains(unicode17_gcb_zwj_ranges[:], codepoint) do return .ZWJ
	if range_contains(unicode17_gcb_regional_indicator_ranges[:], codepoint) do return .Regional_Indicator
	if range_contains(unicode17_gcb_prepend_ranges[:], codepoint) do return .Prepend
	if range_contains(unicode17_gcb_spacing_mark_ranges[:], codepoint) do return .Spacing_Mark
	if range_contains(unicode17_gcb_l_ranges[:], codepoint) do return .L
	if range_contains(unicode17_gcb_v_ranges[:], codepoint) do return .V
	if range_contains(unicode17_gcb_t_ranges[:], codepoint) do return .T
	if range_contains(unicode17_gcb_lv_ranges[:], codepoint) do return .LV
	if range_contains(unicode17_gcb_lvt_ranges[:], codepoint) do return .LVT
	return .Other
}

@(private)
unicode17_incb_class :: proc(value: rune) -> InCB_Class {
	codepoint := u32(value)
	if range_contains(unicode17_incb_consonant_ranges[:], codepoint) do return .Consonant
	if range_contains(unicode17_incb_extend_ranges[:], codepoint) do return .Extend
	if range_contains(unicode17_incb_linker_ranges[:], codepoint) do return .Linker
	return .None
}

@(private)
range_contains :: proc(ranges: []u32, codepoint: u32) -> bool {
	assert(len(ranges) & 1 == 0)
	low := 0
	high := len(ranges) / 2
	for low < high {
		middle := low + (high - low) / 2
		first := ranges[middle * 2]
		last := ranges[middle * 2 + 1]
		if codepoint < first {
			high = middle
		} else if codepoint > last {
			low = middle + 1
		} else {
			return true
		}
	}
	return false
}
