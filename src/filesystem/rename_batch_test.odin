// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package filesystem

import "core:os"
import "core:testing"

/* Ensures batch renames support swaps without admitting conflicting targets. */
@(test)
checked_rename_batches_support_swaps :: proc(t: ^testing.T) {
	root, root_error := os.make_directory_temp("", "odra-filesystem-rename-*", context.allocator)
	testing.expect(t, root_error == nil)
	if root_error != nil do return
	defer { os.remove_all(root); delete(root) }
	alpha, _ := os.join_path({root, "alpha"}, context.allocator)
	beta, _ := os.join_path({root, "beta"}, context.allocator)
	gamma, _ := os.join_path({root, "gamma"}, context.allocator)
	defer { delete(gamma); delete(beta); delete(alpha) }
	testing.expect(t, os.write_entire_file(alpha, "alpha") == nil)
	testing.expect(t, os.write_entire_file(beta, "beta") == nil)
	testing.expect(t, os.write_entire_file(gamma, "gamma") == nil)
	batch, observed, _ := directory_observe(root, 1, {persistent = context.allocator, temporary = context.temp_allocator})
	testing.expect(t, observed)
	if !observed do return
	defer directory_batch_close(&batch)
	requests := [?]Rename_Request {
		{identity = batch.descriptors[0].identity, from = "alpha", to = "beta"},
		{identity = batch.descriptors[1].identity, from = "beta", to = "alpha"},
	}
	results: [2]Rename_Result
	applied, failure := directory_rename_batch_apply(
		root, batch.directory_identity, requests[:], results[:],
		{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expectf(t, applied, "swap failed: %v", failure.code)
	testing.expect_value(t, results[0].outcome, Rename_Outcome.Applied)
	alpha_text, alpha_error := os.read_entire_file(alpha, context.allocator)
	beta_text, beta_error := os.read_entire_file(beta, context.allocator)
	testing.expect(t, alpha_error == nil && beta_error == nil)
	if alpha_error == nil do defer delete(alpha_text)
	if beta_error == nil do defer delete(beta_text)
	if alpha_error == nil do testing.expect_value(t, string(alpha_text), "beta")
	if beta_error == nil do testing.expect_value(t, string(beta_text), "alpha")
	current, current_ok, _ := directory_observe(root, 2, {persistent = context.allocator, temporary = context.temp_allocator})
	testing.expect(t, current_ok)
	if current_ok {
		defer directory_batch_close(&current)
		collision := [?]Rename_Request {
			{identity = current.descriptors[0].identity, from = "alpha", to = "gamma"},
		}
		collision_results: [1]Rename_Result
		collision_ok, collision_failure := directory_rename_batch_apply(
			root, current.directory_identity, collision[:], collision_results[:],
			{persistent = context.allocator, temporary = context.temp_allocator},
		)
		testing.expect(t, !collision_ok)
		testing.expect_value(t, collision_failure.code, Failure_Code.Destination_Exists)
	}
}
