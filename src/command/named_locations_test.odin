// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../hosting"
import "core:os"
import "core:testing"

/* verify_named_location_commands covers persistence and duplicate replacement through hosting. */
@(private)
verify_named_location_commands :: proc(t: ^testing.T, racket_runtime: ^hosting.Runtime) {
	root, root_error := os.make_directory_temp("", "odra-named-location-*", context.allocator)
	testing.expect(t, root_error == nil)
	if root_error != nil do return
	defer {
		os.remove_all(root)
		delete(root)
	}
	permissions_error := os.chmod(
		root,
		os.Permissions{.Read_User, .Write_User, .Execute_User},
	)
	testing.expect(t, permissions_error == nil)
	if permissions_error != nil do return

	saved, saved_ok, saved_failure := named_location_save(
		racket_runtime,
		root,
		"entry",
		"/tmp/first.odin",
		3,
		0,
		false,
		false,
		"first.odin",
		context.allocator,
	)
	testing.expectf(t, saved_ok, "Named location save failed: %v", saved_failure.code)
	if saved_ok {
		testing.expect_value(t, saved.generation, u64(1))
		testing.expect_value(t, len(saved.locations), 1)
		testing.expect_value(t, saved.locations[0].name, "entry")
		named_location_batch_close(&saved)
	}

	replaced, replaced_ok, replaced_failure := named_location_save(
		racket_runtime,
		root,
		" entry ",
		"/tmp/second.odin",
		8,
		2,
		true,
		true,
		"second.odin",
		context.allocator,
	)
	testing.expectf(t, replaced_ok, "Named location replacement failed: %v", replaced_failure.code)
	if replaced_ok do named_location_batch_close(&replaced)

	listed, listed_ok, listed_failure := named_locations_list(
		racket_runtime,
		root,
		context.allocator,
	)
	testing.expectf(t, listed_ok, "Named location list failed: %v", listed_failure.code)
	if listed_ok {
		testing.expect_value(t, listed.generation, u64(2))
		testing.expect_value(t, len(listed.locations), 1)
		if len(listed.locations) == 1 {
			location := listed.locations[0]
			testing.expect_value(t, location.name, "entry")
			testing.expect_value(t, location.target, "/tmp/second.odin")
			testing.expect_value(t, location.point, u64(8))
			testing.expect(t, location.has_mark)
			testing.expect_value(t, location.mark, u64(2))
			testing.expect(t, location.region_active)
		}
		named_location_batch_close(&listed)
	}

	_, invalid_ok, invalid_failure := named_location_save(
		racket_runtime,
		root,
		"invalid",
		"/tmp/invalid.odin",
		0,
		0,
		false,
		true,
		"invalid.odin",
		context.allocator,
	)
	testing.expect(t, !invalid_ok)
	testing.expect_value(t, invalid_failure.code, Failure_Code.Invalid_Request)
}
