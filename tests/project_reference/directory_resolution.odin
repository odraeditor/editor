// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package project_reference

import "core:strings"
import "core:unicode/utf8"

/* Directory_Resolution_Kind identifies the user-visible outcome of one exact lookup. */
Directory_Resolution_Kind :: enum u8 {
	Unregistered,
	Registered,
	Ambiguous,
}

/* Catalog_Entry is the oracle's deliberately simple contiguous Project record. */
Catalog_Entry :: struct {
	directories: []string,
	valid:       bool,
}

/* resolve_exact_single_directory scans valid records in catalog order. */
resolve_exact_single_directory :: proc(
	entries: []Catalog_Entry,
	normalized_path: string,
	matches: []int,
) -> (kind: Directory_Resolution_Kind, count: int, ok: bool) {
	if !resolution_path_valid(normalized_path) {
		return .Unregistered, 0, false
	}

	for entry, index in entries {
		if !entry.valid || len(entry.directories) != 1 ||
		   entry.directories[0] != normalized_path {
			continue
		}
		if count >= len(matches) {
			return .Ambiguous, count, false
		}
		matches[count] = index
		count += 1
	}

	switch count {
	case 0:
		return .Unregistered, 0, true
	case 1:
		return .Registered, 1, true
	case:
		return .Ambiguous, count, true
	}
}

@(private)
resolution_path_valid :: proc(path: string) -> bool {
	return len(path) > 0 && path[0] == '/' && utf8.valid_string(path) &&
	       strings.index_byte(path, 0) < 0
}
