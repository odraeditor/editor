// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package darek

import "../filesystem"
import "base:runtime"
import "core:os"
import "core:testing"

@(test)
/* Publishes hierarchical symbols only against the exact observed file generation. */
symbol_projection_preserves_language_ownership_and_rejects_stale_updates :: proc(t: ^testing.T) {
	root, root_error := os.make_directory_temp("", "odra-darek-symbols-*", context.allocator)
	testing.expect(t, root_error == nil)
	if root_error != nil do return
	defer delete(root)
	defer os.remove_all(root)
	path, path_error := os.join_path({root, "symbols.odin"}, context.allocator)
	testing.expect(t, path_error == nil)
	if path_error != nil do return
	defer delete(path)
	testing.expect(t, os.write_entire_file(path, "run :: proc() {}\n") == nil)
	root_observation, observed, _ := filesystem.directory_observe(
		root, 1, {persistent = context.allocator, temporary = context.temp_allocator}, true,
	)
	testing.expect(t, observed)
	if !observed do return
	defer filesystem.directory_batch_close(&root_observation)
	instance: Instance
	opened, _ := instance_open(
		&instance,
		{id = 1, generation = 1, policy = DEFAULT_POLICY, allocator = runtime.default_allocator()},
		{mode = .Directory, path = root, resource = root_observation.directory_identity},
	)
	testing.expect(t, opened)
	if !opened do return
	defer instance_close(&instance)
	published, _ := instance_publish_local_root(&instance)
	testing.expect(t, published)
	_, expanded, _ := instance_toggle_selected(&instance)
	testing.expect(t, expanded)
	view, _, inspected, _ := instance_inspect(&instance)
	testing.expect(t, inspected && len(view.nodes) == 2)
	if !inspected || len(view.nodes) != 2 do return
	file := view.nodes[1]
	symbols := [?]Symbol_Source {
		{id = 1, name = "run", start = 0, end = 16},
		{id = 2, parent_id = 1, hierarchy_depth = 1, name = "value", start = 8, end = 13},
	}
	changed, symbols_ok, _ := instance_publish_symbols(
		&instance,
		view.node_generation,
		4,
		file.resource,
		file.path,
		7,
		symbols[:],
	)
	testing.expect(t, changed && symbols_ok)
	projected, _, projected_ok, _ := instance_inspect(&instance)
	testing.expect(t, projected_ok && len(projected.nodes) == 4)
	if projected_ok && len(projected.nodes) == 4 {
		testing.expect_value(t, projected.nodes[2].kind, Node_Kind.Symbol)
		testing.expect_value(t, projected.nodes[3].parent, projected.nodes[2].handle.id)
		testing.expect_value(t, projected.nodes[3].source_revision, u64(7))
	}
	_, stale_ok, stale_failure := instance_publish_symbols(
		&instance,
		view.node_generation,
		5,
		file.resource,
		file.path,
		8,
		symbols[:],
	)
	testing.expect(t, !stale_ok)
	testing.expect_value(t, stale_failure.code, Failure_Code.Stale_Generation)
}
