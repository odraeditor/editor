// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../interaction"
import "core:testing"

@(test)
/* Verifies copied language keymaps decode exact checked bindings. */
language_keymap_projection_decodes_checked_bindings :: proc(t: ^testing.T) {
	projection := "odra-language-keymap\t1\tjan.direct\t7\t2\n" +
	              "11,0,0\tjan-cycle\n" +
	              "1,99,1;1,116,1\tjan-todo"
	bindings: [interaction.MAX_CONTEXT_BINDINGS]interaction.Binding_Definition
	identity, priority, count, decoded := language_keymap_parse_projection(
		projection,
		bindings[:],
	)
	testing.expect(t, decoded)
	testing.expect_value(t, identity, "jan.direct")
	testing.expect_value(t, priority, i32(7))
	testing.expect_value(t, count, 2)
	testing.expect_value(t, bindings[0].stroke_count, u8(1))
	testing.expect_value(t, bindings[0].strokes[0].kind, interaction.Logical_Key_Kind.Tab)
	testing.expect_value(t, bindings[0].command_name, "jan-cycle")
	testing.expect_value(t, bindings[1].stroke_count, u8(2))
	testing.expect_value(t, bindings[1].strokes[0].modifiers, interaction.Modifiers{.Control})
	testing.expect_value(t, bindings[1].command_name, "jan-todo")
}

@(test)
/* Verifies malformed and truncated language keymaps reject atomically. */
language_keymap_projection_rejects_malformed_or_truncated_maps :: proc(t: ^testing.T) {
	bindings: [interaction.MAX_CONTEXT_BINDINGS]interaction.Binding_Definition
	_, _, _, malformed := language_keymap_parse_projection(
		"odra-language-keymap\t1\tjan.direct\t0\t1\n11,0\tjan-cycle",
		bindings[:],
	)
	testing.expect(t, !malformed)
	_, _, _, truncated := language_keymap_parse_projection(
		"odra-language-keymap\t1\tjan.direct\t0\t2\n11,0,0\tjan-cycle",
		bindings[:],
	)
	testing.expect(t, !truncated)
}
