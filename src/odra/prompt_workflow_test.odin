// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "core:testing"

/* Verifies interactive home-relative paths expand without reinterpreting named users. */
@(test)
home_paths_expand_from_runtime_home :: proc(t: ^testing.T) {
	commands := Command_Context{home_directory = "/home/example"}
	storage: [64]u8

	expanded, expanded_ok := command_context_expand_home_path(&commands, "~", storage[:])
	testing.expect(t, expanded_ok)
	testing.expect_value(t, expanded, "/home/example")

	expanded, expanded_ok = command_context_expand_home_path(
		&commands,
		"~/work/file.odin",
		storage[:],
	)
	testing.expect(t, expanded_ok)
	testing.expect_value(t, expanded, "/home/example/work/file.odin")

	expanded, expanded_ok = command_context_expand_home_path(&commands, "relative/file.odin", storage[:])
	testing.expect(t, expanded_ok)
	testing.expect_value(t, expanded, "relative/file.odin")

	expanded, expanded_ok = command_context_expand_home_path(&commands, "~other/file.odin", storage[:])
	testing.expect(t, expanded_ok)
	testing.expect_value(t, expanded, "~other/file.odin")

	short_storage: [4]u8
	_, expanded_ok = command_context_expand_home_path(&commands, "~/work", short_storage[:])
	testing.expect(t, !expanded_ok)
}
