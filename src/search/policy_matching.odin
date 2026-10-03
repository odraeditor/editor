// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package search

import "core:unicode"
import "core:unicode/utf8"

@(private)
match_respects_boundary :: proc(
	bytes: []byte,
	start, end: int,
	mode: Boundary_Mode,
) -> bool {
	if mode == .Unrestricted {
		return true
	}
	if start > 0 {
		previous, width := utf8.decode_last_rune(bytes[:start])
		if width <= 0 || boundary_contains(mode, previous) {
			return false
		}
	}
	if end < len(bytes) {
		next, width := utf8.decode_rune(bytes[end:])
		if width <= 0 || boundary_contains(mode, next) {
			return false
		}
	}
	return true
}

@(private)
boundary_contains :: proc(mode: Boundary_Mode, value: rune) -> bool {
	base := unicode.is_letter(value) || unicode.is_number(value) || value == '_'
	if mode == .Word {
		return base
	}
	if mode == .Symbol {
		return base || value == '-' || value == '?' || value == '!'
	}
	return false
}
