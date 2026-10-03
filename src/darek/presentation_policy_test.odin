// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package darek

import "../filesystem"
import "../ui"
import "base:runtime"
import "core:mem"
import "core:os"
import "core:testing"

@(test)
/* presentation_policy_retains_identity_across_visibility_sort_filter_annotations_and_watch. */
presentation_policy_retains_identity :: proc(t: ^testing.T) {
	root, root_error := os.make_directory_temp("", "odra-darek-presentation-*", context.allocator)
	testing.expect(t, root_error == nil)
	if root_error != nil do return
	defer {
		os.remove_all(root)
		delete(root)
	}
	hidden, hidden_error := os.join_path({root, ".secret"}, context.allocator)
	ignored, ignored_error := os.join_path({root, "ignored.tmp"}, context.allocator)
	visible, visible_error := os.join_path({root, "visible.odin"}, context.allocator)
	testing.expect(t, hidden_error == nil && ignored_error == nil && visible_error == nil)
	if hidden_error != nil || ignored_error != nil || visible_error != nil do return
	defer {
		delete(visible)
		delete(ignored)
		delete(hidden)
	}
	testing.expect(t, os.write_entire_file(hidden, "hidden") == nil)
	testing.expect(t, os.write_entire_file(ignored, "ignored") == nil)
	testing.expect(t, os.write_entire_file(visible, "package visible") == nil)
	identity_batch, identified, _ := filesystem.directory_observe(
		root, 1, {persistent = context.allocator, temporary = context.temp_allocator}, true,
	)
	testing.expect(t, identified)
	if !identified do return
	root_identity := identity_batch.directory_identity
	_, _ = filesystem.directory_batch_close(&identity_batch)

	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, runtime.default_allocator())
	allocator := mem.tracking_allocator(&tracking)
	instance: Instance
	opened, _ := instance_open(
		&instance,
		Config{id = 41, generation = 1, policy = DEFAULT_POLICY, allocator = allocator},
		Root_Request{mode = .Directory, path = root, resource = root_identity},
	)
	testing.expect(t, opened)
	if !opened {
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	_, _ = instance_publish_local_root(&instance)
	_, _, _ = instance_expand_roots(&instance)
	view, _, viewed, _ := instance_inspect(&instance)
	testing.expect(t, viewed)
	testing.expect_value(t, len(view.nodes), 4)
	ignored_resource: filesystem.Resource_ID
	visible_resource: filesystem.Resource_ID
	for node in view.nodes {
		if node.label == "ignored.tmp" do ignored_resource = node.resource
		if node.label == "visible.odin" do visible_resource = node.resource
	}
	annotations := [?]Node_Annotation {
		{
			resource = ignored_resource,
			provider_generation = 7,
			version_control = .Modified,
			ignored = true,
		},
		{
			resource = visible_resource,
			provider_generation = 7,
			diagnostic = .Error,
		},
	}
	annotated, annotation_ok, _ := instance_publish_annotations(&instance, 7, annotations[:])
	testing.expect(t, annotated && annotation_ok)

	projection: Tree_Projection
	projected, _ := tree_projection_build(&projection, &instance, allocator)
	testing.expect(t, projected)
	projection_view, projection_viewed := tree_projection_view(&projection)
	testing.expect(t, projection_viewed)
	testing.expect_value(t, len(projection_view.nodes), 2)
	testing.expect_value(t, projection_view.nodes[1].icon_role, ui.Tree_Icon_Role.Failure)
	testing.expect(t, tree_projection_close(&projection))

	_, hidden_ok, _ := instance_set_hidden_visible(&instance, true)
	_, ignored_ok, _ := instance_set_ignored_visible(&instance, true)
	testing.expect(t, hidden_ok && ignored_ok)
	projected, _ = tree_projection_build(&projection, &instance, allocator)
	projection_view, projection_viewed = tree_projection_view(&projection)
	testing.expect(t, projected && projection_viewed)
	testing.expect_value(t, len(projection_view.nodes), 4)
	testing.expect(t, tree_projection_close(&projection))

	filtered, filter_ok, _ := instance_set_name_filter(&instance, "visible")
	testing.expect(t, filtered && filter_ok)
	projected, _ = tree_projection_build(&projection, &instance, allocator)
	projection_view, projection_viewed = tree_projection_view(&projection)
	testing.expect(t, projected && projection_viewed)
	testing.expect_value(t, len(projection_view.nodes), 2)
	testing.expect(t, tree_projection_close(&projection))
	_, _, _ = instance_set_name_filter(&instance, "")

	sorted, sort_ok, _ := instance_set_sort_mode(&instance, .Name_Descending)
	testing.expect(t, sorted && sort_ok)
	projected, _ = tree_projection_build(&projection, &instance, allocator)
	projection_view, projection_viewed = tree_projection_view(&projection)
	testing.expect(t, projected && projection_viewed)
	testing.expect_value(t, projection_view.nodes[1].text, "visible.odin")
	testing.expect(t, tree_projection_close(&projection))

	watch_enabled, watch_ok, _ := instance_set_watch_enabled(&instance, true, 9)
	hinted, hint_ok, _ := instance_observe_watch_hint(&instance, 9, .Overflow)
	watch_view, _, watch_viewed, _ := instance_inspect(&instance)
	testing.expect(t, watch_enabled && watch_ok && hinted && hint_ok && watch_viewed)
	testing.expect_value(t, watch_view.watch.status, Watch_Status.Refresh_Required)
	_, reconciled, _ := instance_reconcile_watch(&instance)
	watch_view, _, watch_viewed, _ = instance_inspect(&instance)
	testing.expect(t, reconciled && watch_viewed)
	testing.expect_value(t, watch_view.watch.status, Watch_Status.Watching)
	testing.expect_value(t, watch_view.watch.pending_hints, u32(0))

	closed, _ := instance_close(&instance)
	cleanup_bytes := tracking.current_memory_allocated
	mem.tracking_allocator_destroy(&tracking)
	testing.expect(t, closed)
	testing.expect_value(t, cleanup_bytes, i64(0))
}
