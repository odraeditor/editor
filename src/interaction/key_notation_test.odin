// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

import "core:testing"

/* Verifies complete normalized sequences use stable familiar notation. */
@(test)
notation_preserves_strokes_and_modifiers :: proc(t: ^testing.T) {
	sequence := Key_Sequence {
		strokes = {
			0 = {kind = .Unicode_Scalar, scalar = 'x', modifiers = {.Control}},
			1 = {kind = .Unicode_Scalar, scalar = 'c', modifiers = {.Control}},
		},
		stroke_count = 2,
	}
	storage: [MAX_KEY_SEQUENCE_NOTATION_BYTES]u8
	text, ok := key_sequence_notation(sequence, storage[:])
	testing.expect(t, ok)
	testing.expect_value(t, text, "C-x C-c")
	testing.expect_value(t, key_sequence_notation_length(sequence), len("C-x C-c"))

	modified := Key_Sequence {
		strokes = {
			0 = {
				kind = .Unicode_Scalar,
				scalar = '%',
				modifiers = {.Control, .Meta, .Alt, .Super, .Shift},
			},
			1 = {kind = .Unicode_Scalar, scalar = ' '},
			2 = {kind = .Enter},
			3 = {kind = .Tab},
			4 = {kind = .Escape},
		},
		stroke_count = 5,
	}
	text, ok = key_sequence_notation(modified, storage[:])
	testing.expect(t, ok)
	testing.expect_value(t, text, "C-M-A-s-S-% SPC RET TAB ESC")
}

/* Verifies invalid sequences and undersized outputs fail without truncation. */
@(test)
notation_rejects_invalid_or_short_output :: proc(t: ^testing.T) {
	storage: [2]u8
	_, empty_ok := key_sequence_notation({}, storage[:])
	testing.expect(t, !empty_ok)
	sequence := Key_Sequence {
		strokes = {0 = {kind = .Unicode_Scalar, scalar = 'x', modifiers = {.Meta}}},
		stroke_count = 1,
	}
	_, short_ok := key_sequence_notation(sequence, storage[:])
	testing.expect(t, !short_ok)
}
