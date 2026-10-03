// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package recovery

import "core:path/filepath"
import "core:strings"

/* startup_source_matches selects launch-relevant normalized absolute identities without reading or modifying sources. */
startup_source_matches :: proc(source, exact_file: string, roots: []string) -> bool {
	if !filepath.is_abs(source) do return false
	if len(exact_file) > 0 do return source == exact_file
	for root in roots {
		if !filepath.is_abs(root) do continue
		if source == root do return true
		if !strings.has_prefix(source, root) || len(source) <= len(root) do continue
		if filepath.is_separator(root[len(root) - 1]) do return true
		if filepath.is_separator(source[len(root)]) do return true
	}
	return false
}
