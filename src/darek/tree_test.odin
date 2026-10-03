// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package darek

import "../filesystem"
import "../project"
import "../ui"
import "base:runtime"
import "core:mem"
import "core:os"
import "core:testing"

@(test)
/* local_tree_expands_navigates_refreshes_projects_and_cleans_up_exactly. */
local_tree_expands_navigates_refreshes_projects :: proc(t: ^testing.T) {
	root, root_error := os.make_directory_temp("", "odra-darek-tree-*", context.allocator)
	testing.expect(t, root_error == nil)
	if root_error != nil do return
	defer {
		os.remove_all(root)
		delete(root)
	}
	directory, directory_error := os.join_path({root, "alpha"}, context.allocator)
	nested, nested_error := os.join_path({directory, "nested.odin"}, context.allocator)
	file, file_error := os.join_path({root, "zeta.odin"}, context.allocator)
	added, added_error := os.join_path({root, "later.rkt"}, context.allocator)
	testing.expect(t, directory_error == nil && nested_error == nil && file_error == nil && added_error == nil)
	if directory_error != nil || nested_error != nil || file_error != nil || added_error != nil do return
	defer {
		delete(added)
		delete(file)
		delete(nested)
		delete(directory)
	}
	testing.expect(t, os.make_directory(directory) == nil)
	testing.expect(t, os.write_entire_file(nested, "package nested") == nil)
	testing.expect(t, os.write_entire_file(file, "package root") == nil)
	identity_batch, identified, identity_failure := filesystem.directory_observe(
		root,
		1,
		{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expectf(t, identified, "root identity failed with %v", identity_failure.code)
	if !identified do return
	root_identity := identity_batch.directory_identity
	_, _ = filesystem.directory_batch_close(&identity_batch)

	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, runtime.default_allocator())
	allocator := mem.tracking_allocator(&tracking)
	instance: Instance
	opened, _ := instance_open(
		&instance,
		Config{id = 1, generation = 1, policy = DEFAULT_POLICY, allocator = allocator},
		Root_Request{mode = .Directory, path = root, resource = root_identity},
	)
	testing.expect(t, opened)
	if !opened {
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	published, publish_failure := instance_publish_local_root(&instance)
	testing.expectf(t, published, "root publication failed with %v", publish_failure.code)
	expanded, expand_ok, expand_failure := instance_expand_roots(&instance)
	testing.expectf(t, expanded && expand_ok, "root expansion failed with %v", expand_failure.code)
	view, _, viewed, _ := instance_inspect(&instance)
	testing.expect(t, viewed)
	testing.expect_value(t, len(view.nodes), 3)
	first_move, first_move_ok, _ := instance_move_visible(&instance, 1)
	child_expanded, child_expand_ok, child_expand_failure := instance_toggle_selected(&instance)
	testing.expectf(
		t,
		first_move && first_move_ok && child_expanded && child_expand_ok,
		"child expansion failed with %v",
		child_expand_failure.code,
	)
	expanded_view, _, expanded_viewed, _ := instance_inspect(&instance)
	testing.expect(t, expanded_viewed)
	testing.expect_value(t, len(expanded_view.nodes), 4)
	_, _, _ = instance_move_visible(&instance, 1)
	parent_moved, parent_ok, _ := instance_move_parent(&instance)
	sibling_moved, sibling_ok, _ := instance_move_sibling(&instance, 1)
	testing.expect(t, parent_moved && parent_ok && sibling_moved && sibling_ok)
	selected, selected_ok, _ := instance_selected_target(&instance)
	testing.expect(t, selected_ok)
	testing.expect_value(t, selected.label, "zeta.odin")
	preview_enabled, preview_changed, preview_ok, _ := instance_toggle_preview(&instance)
	preview_request, preview_requested, _ := instance_preview_request(&instance)
	preview_current, _ := instance_preview_request_validate(&instance, preview_request)
	testing.expect(t, preview_enabled && preview_changed && preview_ok && preview_requested && preview_current)
	testing.expect_value(t, preview_request.path, file)
	_, _, _ = instance_move_parent(&instance)
	preview_stale, stale_preview_failure := instance_preview_request_validate(&instance, preview_request)
	testing.expect(t, !preview_stale)
	testing.expect_value(t, stale_preview_failure.code, Failure_Code.Stale_Generation)
	testing.expect(t, os.write_entire_file(added, "#lang racket/base") == nil)
	refreshed, refresh_ok, refresh_failure := instance_refresh_selected(&instance)
	testing.expectf(t, refreshed && refresh_ok, "refresh failed with %v", refresh_failure.code)
	refreshed_view, _, refreshed_viewed, _ := instance_inspect(&instance)
	testing.expect(t, refreshed_viewed)
	testing.expect_value(t, len(refreshed_view.nodes), 4)
	testing.expect_value(t, refreshed_view.selected, refreshed_view.nodes[0].handle.id)
	revealed, reveal_ok, reveal_failure := instance_reveal_path(&instance, added)
	revealed_target, selected_revealed, _ := instance_selected_target(&instance)
	testing.expectf(t, revealed && reveal_ok, "reveal failed with %v", reveal_failure.code)
	testing.expect(t, selected_revealed)
	testing.expect_value(t, revealed_target.path, added)
	follow_enabled, follow_changed, follow_ok, _ := instance_toggle_file_follow(&instance)
	first_follow, first_accepted, first_follow_ok, _ := instance_follow_observe(&instance, 8)
	second_follow, second_accepted, second_follow_ok, _ := instance_follow_observe(&instance, 8)
	newest_follow, newest_accepted, newest_follow_ok, _ := instance_follow_observe(&instance, 9)
	testing.expect(t, follow_enabled && follow_changed && follow_ok)
	testing.expect(t, first_accepted && first_follow_ok && !second_accepted && second_follow_ok)
	testing.expect(t, newest_accepted && newest_follow_ok)
	testing.expect_value(t, second_follow, first_follow)
	testing.expect(t, newest_follow > first_follow)

	projection: Tree_Projection
	projected, projection_failure := tree_projection_build(&projection, &instance, allocator)
	testing.expectf(t, projected, "projection failed with %v", projection_failure.code)
	projection_view, projection_viewed := tree_projection_view(&projection)
	testing.expect(t, projection_viewed)
	testing.expect_value(t, len(projection_view.nodes), 4)
	testing.expect_value(t, projection_view.current_node, i32(2))
	testing.expect_value(t, projection_view.nodes[0].expanded, true)
	testing.expect_value(t, projection_view.nodes[0].icon_role, ui.Tree_Icon_Role.Directory_Open)
	testing.expect_value(t, projection_view.nodes[1].style_spans[0].style_role, ui.Style_Role.Tree_Directory)
	testing.expect_value(t, projection_view.nodes[3].icon_role, ui.Tree_Icon_Role.File_Source)
	testing.expect_value(t, projection_view.nodes[3].style_spans[0].style_role, ui.Style_Role.Tree_File_Source)
	testing.expect(t, tree_projection_close(&projection))
	closed, _ := instance_close(&instance)
	cleanup_bytes := tracking.current_memory_allocated
	mem.tracking_allocator_destroy(&tracking)
	testing.expect(t, closed)
	testing.expect_value(t, cleanup_bytes, i64(0))
}

@(test)
/* project_roots_publish_as_ordered_siblings_and_preserve_checked_subtrees. */
project_roots_publish_as_ordered_siblings :: proc(t: ^testing.T) {
	root, root_error := os.make_directory_temp("", "odra-darek-projects-*", context.allocator)
	testing.expect(t, root_error == nil)
	if root_error != nil do return
	defer {os.remove_all(root); delete(root)}
	first, first_error := os.join_path({root, "first"}, context.allocator)
	second, second_error := os.join_path({root, "second"}, context.allocator)
	child, child_error := os.join_path({first, "main.odin"}, context.allocator)
	second_child, second_child_error := os.join_path({second, "guide.md"}, context.allocator)
	testing.expect(
		t,
		first_error == nil && second_error == nil && child_error == nil && second_child_error == nil,
	)
	if first_error != nil || second_error != nil || child_error != nil || second_child_error != nil do return
	defer {delete(second_child); delete(child); delete(second); delete(first)}
	testing.expect(t, os.make_directory(first) == nil && os.make_directory(second) == nil)
	testing.expect(t, os.write_entire_file(child, "package main\n") == nil)
	testing.expect(t, os.write_entire_file(second_child, "# Guide\n") == nil)
	first_batch, first_observed, _ := filesystem.directory_observe(
		first, 1, {persistent = context.allocator, temporary = context.temp_allocator},
	)
	second_batch, second_observed, _ := filesystem.directory_observe(
		second, 1, {persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, first_observed && second_observed)
	if !first_observed || !second_observed do return
	first_identity := first_batch.directory_identity
	second_identity := second_batch.directory_identity
	filesystem.directory_batch_close(&first_batch)
	filesystem.directory_batch_close(&second_batch)
	owner := project.Owner_Handle{id = 7, generation = 1}
	first_project := project.Project_Handle{owner = owner, id = 11, generation = 3}
	second_project := project.Project_Handle{owner = owner, id = 12, generation = 4}

	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, runtime.default_allocator())
	allocator := mem.tracking_allocator(&tracking)
	instance: Instance
	opened, _ := instance_open(
		&instance,
		Config{id = 2, generation = 1, policy = DEFAULT_POLICY, allocator = allocator},
		Root_Request {
			mode = .Workspace,
			workspace = {id = "daily", generation = 9, root_generation = 5},
		},
	)
	testing.expect(t, opened)
	if !opened {
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	roots := [2]Project_Root_Source {
		{
			project = first_project,
			resource = first_identity,
			label = "First",
			path = first,
			provider_generation = 5,
			available = true,
		},
		{
			project = second_project,
			resource = second_identity,
			label = "Second",
			path = second,
			provider_generation = 5,
			available = true,
		},
	}
	published, _ := instance_publish_project_roots(&instance, roots[:])
	testing.expect(t, published)
	expanded, expand_ok, _ := instance_expand_roots(&instance)
	testing.expect(t, expanded && expand_ok)
	view, _, viewed, _ := instance_inspect(&instance)
	testing.expect(t, viewed)
	testing.expect_value(t, len(view.nodes), 4)
	testing.expect_value(t, view.nodes[0].parent, Node_ID(0))
	testing.expect_value(t, view.nodes[2].parent, Node_ID(0))
	_, _, _ = instance_move_visible(&instance, 1)
	selected, selected_ok, _ := instance_selected_target(&instance)
	testing.expect(t, selected_ok)
	testing.expect_value(t, selected.label, "main.odin")
	reordered := [2]Project_Root_Source{roots[1], roots[0]}
	replaced, _ := instance_publish_project_roots(&instance, reordered[:])
	testing.expect(t, replaced)
	reconciled, _, reconciled_ok, _ := instance_inspect(&instance)
	testing.expect(t, reconciled_ok)
	testing.expect_value(t, reconciled.nodes[0].project, second_project)
	testing.expect_value(t, reconciled.nodes[2].project, first_project)
	testing.expect_value(t, reconciled.nodes[2].children, Child_State.Expanded)
	testing.expect_value(t, reconciled.selected, selected.handle.id)

	_, moved_to_second, _ := instance_move_project(&instance, -1)
	second_collapsed, second_collapse_ok, _ := instance_toggle_selected(&instance)
	second_expanded, second_expand_ok, _ := instance_toggle_selected(&instance)
	testing.expect(
		t,
		moved_to_second && second_collapsed && second_collapse_ok &&
			second_expanded && second_expand_ok,
	)
	_, moved_to_first, _ := instance_move_project(&instance, 1)
	others_collapsed, others_ok, _ := instance_collapse_projects(&instance, .Others)
	testing.expect(t, moved_to_first && others_collapsed && others_ok)
	collapsed_view, _, collapsed_ok, _ := instance_inspect(&instance)
	testing.expect(t, collapsed_ok)
	testing.expect_value(t, collapsed_view.nodes[0].project, second_project)
	testing.expect_value(t, collapsed_view.nodes[0].children, Child_State.Collapsed)
	current_collapsed, current_ok, _ := instance_collapse_projects(&instance, .Current)
	testing.expect(t, current_collapsed && current_ok)
	all_collapsed_view, _, all_collapsed_ok, _ := instance_inspect(&instance)
	testing.expect(t, all_collapsed_ok)
	testing.expect_value(t, len(all_collapsed_view.nodes), 2)
	for node in all_collapsed_view.nodes do testing.expect_value(t, node.children, Child_State.Collapsed)

	unavailable := roots[1]
	unavailable.available = false
	unavailable.resource = {}
	unavailable.provider_generation = 6
	missing_set := [2]Project_Root_Source{roots[0], unavailable}
	missing_published, _ := instance_publish_project_roots(&instance, missing_set[:])
	testing.expect(t, missing_published)
	missing_view, _, missing_ok, _ := instance_inspect(&instance)
	testing.expect(t, missing_ok)
	testing.expect_value(t, missing_view.nodes[len(missing_view.nodes) - 1].children, Child_State.Unavailable)
	narrowed, narrow_ok, _ := instance_set_current_project_only(&instance, true)
	compressed, _, compression_ok, _ := instance_toggle_directory_compression(&instance)
	narrow_projection: Tree_Projection
	narrow_projected, _ := tree_projection_build(&narrow_projection, &instance, allocator)
	narrow_view, narrow_viewed := tree_projection_view(&narrow_projection)
	testing.expect(t, narrowed && narrow_ok && compressed && compression_ok)
	testing.expect(t, narrow_projected && narrow_viewed)
	testing.expect_value(t, len(narrow_view.nodes), 1)
	testing.expect(t, tree_projection_close(&narrow_projection))

	closed, _ := instance_close(&instance)
	cleanup_bytes := tracking.current_memory_allocated
	mem.tracking_allocator_destroy(&tracking)
	testing.expect(t, closed)
	testing.expect_value(t, cleanup_bytes, i64(0))
}

@(test)
/* instance_open_contains_allocation_failure_without_retained_state. */
open_alloc_failure_retains_no_state :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, runtime.default_allocator())
	failing := Darek_Failing_Allocator {
		backing = mem.tracking_allocator(&tracking),
		fail_after = 0,
	}
	instance: Instance
	opened, failure := instance_open(
		&instance,
		Config {
			id = 3,
			generation = 1,
			policy = DEFAULT_POLICY,
			allocator = darek_failing_allocator(&failing),
		},
		Root_Request {
			mode = .Workspace,
			workspace = {id = "allocation-study", generation = 1, root_generation = 1},
		},
	)
	testing.expect(t, !opened)
	testing.expect_value(t, failure.code, Failure_Code.Allocation)
	testing.expect(t, instance.state == nil)
	testing.expect_value(t, tracking.current_memory_allocated, 0)
	mem.tracking_allocator_destroy(&tracking)
}

@(private)
Darek_Failing_Allocator :: struct {
	backing:                runtime.Allocator,
	fail_after:             u64,
	successful_allocations: u64,
}

@(private)
darek_failing_allocator :: proc(data: ^Darek_Failing_Allocator) -> runtime.Allocator {
	return runtime.Allocator{procedure = darek_failing_allocator_proc, data = data}
}

@(private)
darek_failing_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location: runtime.Source_Code_Location,
) -> ([]byte, runtime.Allocator_Error) {
	allocator := cast(^Darek_Failing_Allocator)allocator_data
	if mode == .Alloc || mode == .Resize || mode == .Resize_Non_Zeroed {
		if allocator.successful_allocations >= allocator.fail_after {
			return nil, .Out_Of_Memory
		}
		allocator.successful_allocations += 1
	}
	return allocator.backing.procedure(
		allocator.backing.data,
		mode,
		size,
		alignment,
		old_memory,
		old_size,
		location,
	)
}
