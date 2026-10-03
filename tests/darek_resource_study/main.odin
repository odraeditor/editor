// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../../src/darek"
import "../../src/filesystem"
import "../../src/project"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:time"

DENSE_ENTRY_COUNT :: 1_024
DEEP_DIRECTORY_COUNT :: 32
REPEATED_PROJECTIONS :: 64
EXPECTED_DENSE_NODES :: 1 + DENSE_ENTRY_COUNT + 1 + DEEP_DIRECTORY_COUNT + 1
LATENCY_GATE_NS :: i64(2_000_000_000)
MEMORY_GATE_BYTES :: i64(64 * 1_024 * 1_024)

main :: proc() {
	root, root_error := os.make_directory_temp("", "odra-darek-resource-*", context.allocator)
	second_root, second_error := os.make_directory_temp("", "odra-darek-project-*", context.allocator)
	if root_error != nil || second_error != nil do os.exit(1)
	defer {
		os.remove_all(second_root)
		os.remove_all(root)
		delete(second_root)
		delete(root)
	}
	long_path, deep_file, populated := populate_dense_root(root)
	if !populated do os.exit(1)
	defer {delete(deep_file); delete(long_path)}
	second_file, second_file_error := os.join_path({second_root, "guide.md"}, context.allocator)
	if second_file_error != nil do os.exit(1)
	defer delete(second_file)
	if os.write_entire_file(second_file, "# Darek resource study\n") != nil do os.exit(1)

	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	started := time.tick_now()
	batch, observed, _ := filesystem.directory_observe(
		root, 1, {persistent = allocator, temporary = context.temp_allocator},
	)
	second_batch, second_observed, _ := filesystem.directory_observe(
		second_root, 1, {persistent = allocator, temporary = context.temp_allocator},
	)
	valid := observed && second_observed
	peak_nodes: u32
	peak_retained_bytes: u64

	instance: darek.Instance
	if valid {
		opened, _ := darek.instance_open(
			&instance,
			darek.Config{id = 1, generation = 1, policy = darek.DEFAULT_POLICY, allocator = allocator},
			darek.Root_Request {
				mode = .Directory,
				path = root,
				resource = batch.directory_identity,
			},
		)
		valid = opened && valid
	}
	if instance.state != nil {
		published, _ := darek.instance_publish_local_root(&instance)
		expanded, expanded_ok, _ := darek.instance_toggle_selected(&instance)
		revealed_long, reveal_long_ok, _ := darek.instance_reveal_path(&instance, long_path)
		preview_enabled, _, preview_ok, _ := darek.instance_toggle_preview(&instance)
		preview_request, preview_requested, _ := darek.instance_preview_request(&instance)
		revealed_deep, reveal_deep_ok, _ := darek.instance_reveal_path(&instance, deep_file)
		preview_stale, _ := darek.instance_preview_request_validate(&instance, preview_request)
		preview_disabled, _, preview_disable_ok, _ := darek.instance_toggle_preview(&instance)
		_, preview_after_cancel, _ := darek.instance_preview_request(&instance)
		follow_enabled, _, follow_ok, _ := darek.instance_toggle_file_follow(&instance)
		first_follow, first_followed, first_follow_ok, _ := darek.instance_follow_observe(&instance, 7)
		second_follow, second_followed, second_follow_ok, _ := darek.instance_follow_observe(&instance, 7)
		new_follow, new_followed, new_follow_ok, _ := darek.instance_follow_observe(&instance, 8)
		view, usage, viewed, _ := darek.instance_inspect(&instance)
		valid = published && expanded && expanded_ok && revealed_long && reveal_long_ok &&
			preview_enabled && preview_ok && preview_requested && revealed_deep && reveal_deep_ok &&
			!preview_stale && !preview_disabled && preview_disable_ok && !preview_after_cancel &&
			follow_enabled && follow_ok && first_followed && first_follow_ok &&
			!second_followed && second_follow_ok && new_followed && new_follow_ok &&
			second_follow == first_follow && new_follow > first_follow && viewed &&
			len(view.nodes) == EXPECTED_DENSE_NODES && valid
		peak_nodes = max(peak_nodes, usage.nodes)
		peak_retained_bytes = max(peak_retained_bytes, usage.retained_bytes)
	}
	projection: darek.Tree_Projection
	for index in 0 ..< REPEATED_PROJECTIONS {
		if !valid do break
		_, _, _ = darek.instance_resize_viewport(&instance, 4 if index % 2 == 0 else 40)
		_, _, _, _ = darek.instance_toggle_directory_compression(&instance)
		_, _, _ = darek.instance_set_panel_side(&instance, .Left if index % 2 == 0 else .Right)
		_, _, _, _ = darek.instance_fit_panel_width(&instance)
		_, _, _, _, _ = darek.instance_toggle_extra_width(&instance)
		_, _, _, _, _ = darek.instance_toggle_extra_width(&instance)
		_, _, _, _ = darek.instance_toggle_width_lock(&instance)
		_, _, _, _ = darek.instance_toggle_width_lock(&instance)
		_, _, _ = darek.instance_move_visible(&instance, 1)
		built, _ := darek.tree_projection_build(&projection, &instance, allocator)
		projection_view, projected := darek.tree_projection_view(&projection)
		valid = built && projected && len(projection_view.nodes) == EXPECTED_DENSE_NODES && valid
		if projection.state != nil do valid = darek.tree_projection_close(&projection) && valid
	}
	if instance.state != nil do _, _ = darek.instance_close(&instance)

	workspace_instance: darek.Instance
	if valid {
		opened, _ := darek.instance_open(
			&workspace_instance,
			darek.Config{id = 2, generation = 1, policy = darek.DEFAULT_POLICY, allocator = allocator},
			darek.Root_Request{mode = .Workspace, workspace = {id = "resource-study", generation = 1, root_generation = 1}},
		)
		valid = opened && valid
	}
	if workspace_instance.state != nil {
		owner := project.Owner_Handle{id = 1, generation = 1}
		roots := [2]darek.Project_Root_Source {
			{project = {owner = owner, id = 1, generation = 1}, resource = batch.directory_identity,
				label = "Dense", path = root, provider_generation = 1, available = true},
			{project = {owner = owner, id = 2, generation = 1}, resource = second_batch.directory_identity,
				label = "Documentation", path = second_root, provider_generation = 1, available = true},
		}
		published, _ := darek.instance_publish_project_roots(&workspace_instance, roots[:])
		expanded, expand_ok, _ := darek.instance_toggle_selected(&workspace_instance)
		view, usage, viewed, _ := darek.instance_inspect(&workspace_instance)
		valid = published && expanded && expand_ok && viewed && len(view.nodes) > DENSE_ENTRY_COUNT && valid
		peak_nodes = max(peak_nodes, usage.nodes)
		peak_retained_bytes = max(peak_retained_bytes, usage.retained_bytes)
		built, _ := darek.tree_projection_build(&projection, &workspace_instance, allocator)
		projection_view, projected := darek.tree_projection_view(&projection)
		valid = built && projected && len(projection_view.nodes) == len(view.nodes) && valid
		if projection.state != nil do valid = darek.tree_projection_close(&projection) && valid
		_, _ = darek.instance_close(&workspace_instance)
	}

	latency_ns := time.duration_nanoseconds(time.tick_since(started))
	peak_bytes := tracking.peak_memory_allocated
	valid = latency_ns <= LATENCY_GATE_NS && peak_bytes <= MEMORY_GATE_BYTES && valid
	if projection.state != nil do _ = darek.tree_projection_close(&projection)
	if workspace_instance.state != nil do _, _ = darek.instance_close(&workspace_instance)
	if instance.state != nil do _, _ = darek.instance_close(&instance)
	if second_batch.state != nil do _, _ = filesystem.directory_batch_close(&second_batch)
	if batch.state != nil do _, _ = filesystem.directory_batch_close(&batch)
	cleanup_bytes := tracking.current_memory_allocated
	valid = cleanup_bytes == 0 && valid
	mem.tracking_allocator_destroy(&tracking)
	fmt.printf(
		"study=darek-explorer-core valid=%v dense_entries=%d deep_directories=%d repeated_projections=%d peak_nodes=%d peak_retained_bytes=%d latency_ns=%d latency_gate_ns=%d peak_bytes=%d memory_gate_bytes=%d cleanup_bytes=%d\n",
		valid, DENSE_ENTRY_COUNT, DEEP_DIRECTORY_COUNT, REPEATED_PROJECTIONS,
		peak_nodes, peak_retained_bytes, latency_ns, LATENCY_GATE_NS,
		peak_bytes, MEMORY_GATE_BYTES, cleanup_bytes,
	)
	if !valid do os.exit(1)
}

populate_dense_root :: proc(root: string) -> (long_path, deep_file: string, ok: bool) {
	for index in 0 ..< DENSE_ENTRY_COUNT {
		name := fmt.aprintf("entry-%04d.odin", index)
		if index % 19 == 0 {
			delete(name)
			name = fmt.aprintf("zażółć-%04d-資料.odin", index)
		}
		path, path_error := os.join_path({root, name}, context.allocator)
		delete(name)
		if path_error != nil do return "", "", false
		write_error := os.write_entire_file(path, "package resource_study\n")
		delete(path)
		if write_error != nil do return "", "", false
	}
	long_name := fmt.aprintf("%s.odin", "long-file-name-for-width-calibration-that-remains-readable-across-narrow-and-wide-panels")
	joined_long, long_error := os.join_path({root, long_name}, context.allocator)
	long_path = joined_long
	delete(long_name)
	if long_error != nil || os.write_entire_file(long_path, "package long_name\n") != nil {
		if long_path != "" do delete(long_path)
		return "", "", false
	}

	parent := root
	owned_parent := false
	for depth in 0 ..< DEEP_DIRECTORY_COUNT {
		name := fmt.aprintf("level-%02d", depth)
		next, next_error := os.join_path({parent, name}, context.allocator)
		delete(name)
		if owned_parent do delete(parent)
		if next_error != nil do return long_path, "", false
		if os.make_directory(next) != nil {
			delete(next)
			return long_path, "", false
		}
		parent = next
		owned_parent = true
	}
	joined_deep, deep_error := os.join_path({parent, "deep.odin"}, context.allocator)
	deep_file = joined_deep
	if owned_parent do delete(parent)
	if deep_error != nil || os.write_entire_file(deep_file, "package deep\n") != nil {
		if deep_file != "" do delete(deep_file)
		return long_path, "", false
	}
	return long_path, deep_file, true
}
