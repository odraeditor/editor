// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_service

import "core:os"
import "core:path/filepath"
import "core:testing"

/* Verifies the maintained Rust profile pins executable, release, and root evidence. */
@(test)
factory_rust_analyzer_profile_is_pinned :: proc(t: ^testing.T) {
	testing.expect_value(t, FACTORY_RUST_ANALYZER_IDENTITY, "rust-analyzer")
	testing.expect_value(t, FACTORY_RUST_ANALYZER_EXECUTABLE, "rust-analyzer")
	testing.expect_value(t, FACTORY_RUST_ANALYZER_RELEASE, "2026-09-14")
	testing.expect_value(t, len(FACTORY_RUST_ANALYZER_RELEASE_DIGEST), 64)
	testing.expect_value(t, FACTORY_RUST_ANALYZER_ROOT_MARKERS[0], "Cargo.toml")
}

/* Verifies nested Cargo packages select the nearest Rust service root. */
@(test)
factory_rust_analyzer_selects_nearest_cargo_root :: proc(t: ^testing.T) {
	membership, directory_error := os.make_directory_temp(
		"", "odra-rust-root-*", context.allocator,
	)
	testing.expect(t, directory_error == nil)
	if directory_error != nil do return
	defer {os.remove_all(membership); delete(membership)}
	workspace, workspace_error := filepath.join(
		[]string{membership, "workspace"}, context.allocator,
	)
	package_root, package_error := filepath.join(
		[]string{workspace, "nested"}, context.allocator,
	)
	source_root, source_error := filepath.join(
		[]string{package_root, "src"}, context.allocator,
	)
	testing.expect(t, workspace_error == nil && package_error == nil && source_error == nil)
	if workspace_error != nil || package_error != nil || source_error != nil do return
	defer {delete(workspace); delete(package_root); delete(source_root)}
	document_path, document_error := filepath.join(
		[]string{source_root, "lib.rs"}, context.allocator,
	)
	workspace_marker, workspace_marker_error := filepath.join(
		[]string{workspace, "Cargo.toml"}, context.allocator,
	)
	package_marker, package_marker_error := filepath.join(
		[]string{package_root, "Cargo.toml"}, context.allocator,
	)
	testing.expect(t, document_error == nil && workspace_marker_error == nil && package_marker_error == nil)
	if document_error != nil || workspace_marker_error != nil || package_marker_error != nil do return
	defer {delete(document_path); delete(workspace_marker); delete(package_marker)}
	testing.expect(t, os.make_directory(workspace) == nil)
	testing.expect(t, os.make_directory(package_root) == nil)
	testing.expect(t, os.make_directory(source_root) == nil)
	testing.expect(t, os.write_entire_file(workspace_marker, "[workspace]\n") == nil)
	testing.expect(t, os.write_entire_file(package_marker, "[package]\n") == nil)
	testing.expect(t, os.write_entire_file(document_path, "pub fn fixture() {}\n") == nil)
	resolution, resolved, failure := service_root_resolve({
		membership_root = membership,
		document_path = document_path,
		root_markers = FACTORY_RUST_ANALYZER_ROOT_MARKERS[:],
		limits = DEFAULT_LIMITS,
	})
	testing.expectf(t, resolved, "Rust root resolution failed with %v", failure.code)
	if resolved {
		testing.expect_value(t, root_resolution_text(&resolution), package_root)
		testing.expect_value(t, root_resolution_marker_text(&resolution), "Cargo.toml")
	}
}
