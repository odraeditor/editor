// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_service

import "core:os"
import "core:path/filepath"
import "core:testing"

/* Verifies nearest marker selection is bounded by the trusted membership. */
@(test)
service_root_resolution_selects_nearest_marker :: proc(t: ^testing.T) {
	membership, directory_error := os.make_directory_temp(
		"",
		"odra-language-root-*",
		context.allocator,
	)
	testing.expect(t, directory_error == nil)
	if directory_error != nil do return
	defer {os.remove_all(membership); delete(membership)}
	package_root, package_error := filepath.join([]string{membership, "workspace", "package"}, context.allocator)
	testing.expect(t, package_error == nil)
	if package_error != nil do return
	defer delete(package_root)
	source_root, source_error := filepath.join([]string{package_root, "src"}, context.allocator)
	testing.expect(t, source_error == nil)
	if source_error != nil do return
	defer delete(source_root)
	document_path, document_error := filepath.join([]string{source_root, "main.fixture"}, context.allocator)
	testing.expect(t, document_error == nil)
	if document_error != nil do return
	defer delete(document_path)
	package_marker, package_marker_error := filepath.join([]string{package_root, "package.json"}, context.allocator)
	testing.expect(t, package_marker_error == nil)
	if package_marker_error != nil do return
	defer delete(package_marker)
	membership_marker, membership_marker_error := filepath.join([]string{membership, "workspace.json"}, context.allocator)
	testing.expect(t, membership_marker_error == nil)
	if membership_marker_error != nil do return
	defer delete(membership_marker)
	testing.expect(t, os.make_directory(filepath.dir(package_root)) == nil)
	testing.expect(t, os.make_directory(package_root) == nil)
	testing.expect(t, os.make_directory(source_root) == nil)
	testing.expect(t, os.write_entire_file(document_path, "fixture") == nil)
	testing.expect(t, os.write_entire_file(package_marker, "{}") == nil)
	testing.expect(t, os.write_entire_file(membership_marker, "{}") == nil)
	markers := [?]string{"workspace.json", "package.json"}
	resolution, resolved, failure := service_root_resolve({
		membership_root = membership,
		document_path = document_path,
		root_markers = markers[:],
		limits = DEFAULT_LIMITS,
	})
	testing.expectf(t, resolved, "root resolution failed: %v", failure.code)
	if resolved {
		testing.expect_value(t, root_resolution_text(&resolution), package_root)
		testing.expect_value(t, root_resolution_marker_text(&resolution), "package.json")
	}
}

/* Verifies explicit roots and marker fallback retain one containment boundary. */
@(test)
service_root_resolution_enforces_containment_and_fallback :: proc(t: ^testing.T) {
	membership, membership_error := os.make_directory_temp("", "odra-language-membership-*", context.allocator)
	external, external_error := os.make_directory_temp("", "odra-language-external-*", context.allocator)
	testing.expect(t, membership_error == nil)
	testing.expect(t, external_error == nil)
	if membership_error != nil || external_error != nil do return
	defer {
		os.remove_all(membership)
		os.remove_all(external)
		delete(membership)
		delete(external)
	}
	workspace, workspace_error := filepath.join([]string{membership, "workspace"}, context.allocator)
	testing.expect(t, workspace_error == nil)
	if workspace_error != nil do return
	defer delete(workspace)
	document_path, document_error := filepath.join([]string{workspace, "main.fixture"}, context.allocator)
	testing.expect(t, document_error == nil)
	if document_error != nil do return
	defer delete(document_path)
	testing.expect(t, os.make_directory(workspace) == nil)
	testing.expect(t, os.write_entire_file(document_path, "fixture") == nil)
	fallback, fallback_ok, _ := service_root_resolve({
		membership_root = membership,
		document_path = document_path,
		limits = DEFAULT_LIMITS,
	})
	testing.expect(t, fallback_ok)
	if fallback_ok do testing.expect_value(t, root_resolution_text(&fallback), membership)
	explicit, explicit_ok, _ := service_root_resolve({
		membership_root = membership,
		document_path = document_path,
		explicit_root = workspace,
		limits = DEFAULT_LIMITS,
	})
	testing.expect(t, explicit_ok)
	if explicit_ok {
		testing.expect(t, explicit.explicit)
		testing.expect_value(t, root_resolution_text(&explicit), workspace)
	}
	_, outside_ok, outside_failure := service_root_resolve({
		membership_root = membership,
		document_path = document_path,
		explicit_root = external,
		limits = DEFAULT_LIMITS,
	})
	testing.expect(t, !outside_ok)
	testing.expect_value(t, outside_failure.code, Failure_Code.Outside_Root)
}

/* Verifies invalid or order-sensitive marker syntax never reaches traversal. */
@(test)
service_root_resolution_rejects_invalid_markers :: proc(t: ^testing.T) {
	invalid := [?]string{"../escape", "valid"}
	duplicate := [?]string{"package.json", "package.json"}
	testing.expect(t, !service_root_markers_valid(invalid[:], DEFAULT_LIMITS))
	testing.expect(t, !service_root_markers_valid(duplicate[:], DEFAULT_LIMITS))
	testing.expect(t, !service_root_markers_valid([]string{"*.json"}, DEFAULT_LIMITS))
}
