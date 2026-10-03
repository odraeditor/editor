// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_service

import "core:os"
import "core:path/filepath"
import "core:testing"

/* Verifies shared web service packages retain exact executable profiles. */
@(test)
factory_web_language_profiles_are_pinned :: proc(t: ^testing.T) {
	testing.expect_value(t, FACTORY_TYPESCRIPT_LANGUAGE_SERVER_IDENTITY, "typescript-language-server")
	testing.expect_value(t, FACTORY_TYPESCRIPT_LANGUAGE_SERVER_EXECUTABLE, "typescript-language-server")
	testing.expect_value(t, FACTORY_TYPESCRIPT_LANGUAGE_SERVER_VERSION, "6.0.0")
	testing.expect_value(t, FACTORY_TYPESCRIPT_VERSION, "6.0.3")
	testing.expect_value(t, FACTORY_TYPESCRIPT_LANGUAGE_SERVER_ARGUMENTS[0], "--stdio")
	testing.expect_value(t, FACTORY_TYPESCRIPT_ROOT_MARKERS[0], "tsconfig.json")
	testing.expect_value(t, FACTORY_HTML_LANGUAGE_SERVER_IDENTITY, "vscode-html-language-server")
	testing.expect_value(t, FACTORY_CSS_LANGUAGE_SERVER_IDENTITY, "vscode-css-language-server")
	testing.expect_value(t, FACTORY_VSCODE_LANGSERVERS_VERSION, "4.10.0")
	testing.expect_value(t, FACTORY_VSCODE_LANGSERVER_ARGUMENTS[0], "--stdio")
	testing.expect_value(t, FACTORY_WEB_ROOT_MARKERS[0], "package.json")
}

/* Verifies JS and TS share nearest configured roots without escaping membership. */
@(test)
factory_typescript_language_server_selects_nearest_configured_root :: proc(t: ^testing.T) {
	membership, directory_error := os.make_directory_temp("", "odra-typescript-root-*", context.allocator)
	testing.expect(t, directory_error == nil)
	if directory_error != nil do return
	defer {os.remove_all(membership); delete(membership)}
	package_root, package_error := filepath.join([]string{membership, "web"}, context.allocator)
	source_root, source_error := filepath.join([]string{package_root, "src"}, context.allocator)
	config_path, config_error := filepath.join([]string{package_root, "tsconfig.json"}, context.allocator)
	document_path, document_error := filepath.join([]string{source_root, "view.tsx"}, context.allocator)
	testing.expect(t, package_error == nil && source_error == nil && config_error == nil && document_error == nil)
	if package_error != nil || source_error != nil || config_error != nil || document_error != nil do return
	defer {delete(package_root); delete(source_root); delete(config_path); delete(document_path)}
	testing.expect(t, os.make_directory(package_root) == nil)
	testing.expect(t, os.make_directory(source_root) == nil)
	testing.expect(t, os.write_entire_file(config_path, "{}\n") == nil)
	testing.expect(t, os.write_entire_file(document_path, "export const value = 1;\n") == nil)
	resolution, resolved, failure := service_root_resolve({
		membership_root = membership,
		document_path = document_path,
		root_markers = FACTORY_TYPESCRIPT_ROOT_MARKERS[:],
		limits = DEFAULT_LIMITS,
	})
	testing.expectf(t, resolved, "TypeScript root resolution failed with %v", failure.code)
	if resolved {
		testing.expect_value(t, root_resolution_text(&resolution), package_root)
		testing.expect_value(t, root_resolution_marker_text(&resolution), "tsconfig.json")
	}
}
