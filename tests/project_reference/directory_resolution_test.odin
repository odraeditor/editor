// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package project_reference

import "core:testing"

/* Ensures exact resolution distinguishes absent, unique, and ambiguous directories. */
@(test)
dir_resolution_counts_matches :: proc(t: ^testing.T) {
	target := "/work/odra"
	other := [?]string{"/work/other"}
	exact_a := [?]string{target}
	exact_b := [?]string{target}
	multi := [?]string{target, "/work/shared"}
	entries := [?]Catalog_Entry {
		{directories = other[:], valid = true},
		{directories = exact_a[:], valid = true},
		{directories = multi[:], valid = true},
		{directories = exact_b[:], valid = false},
	}
	matches: [4]int

	kind, count, ok := resolve_exact_single_directory(entries[:], target, matches[:])
	testing.expect(t, ok)
	testing.expect_value(t, kind, Directory_Resolution_Kind.Registered)
	testing.expect_value(t, count, 1)
	testing.expect_value(t, matches[0], 1)

	kind, count, ok = resolve_exact_single_directory(entries[:], "/work/missing", matches[:])
	testing.expect(t, ok)
	testing.expect_value(t, kind, Directory_Resolution_Kind.Unregistered)
	testing.expect_value(t, count, 0)

	entries[3].valid = true
	kind, count, ok = resolve_exact_single_directory(entries[:], target, matches[:])
	testing.expect(t, ok)
	testing.expect_value(t, kind, Directory_Resolution_Kind.Ambiguous)
	testing.expect_value(t, count, 2)
	testing.expect_value(t, matches[0], 1)
	testing.expect_value(t, matches[1], 3)
}

/* Ensures Unicode paths resolve without crossing directory boundaries. */
@(test)
dir_resolution_keeps_path_boundaries :: proc(t: ^testing.T) {
	target := "/work/Zażółć/odra"
	exact := [?]string{target}
	prefix := [?]string{"/work/Zażółć"}
	child := [?]string{"/work/Zażółć/odra/src"}
	entries := [?]Catalog_Entry {
		{directories = prefix[:], valid = true},
		{directories = child[:], valid = true},
		{directories = exact[:], valid = true},
	}
	matches: [3]int

	kind, count, ok := resolve_exact_single_directory(entries[:], target, matches[:])
	testing.expect(t, ok)
	testing.expect_value(t, kind, Directory_Resolution_Kind.Registered)
	testing.expect_value(t, count, 1)
	testing.expect_value(t, matches[0], 2)

	_, _, empty_ok := resolve_exact_single_directory(entries[:], "", matches[:])
	_, _, relative_ok := resolve_exact_single_directory(entries[:], "work/odra", matches[:])
	testing.expect(t, !empty_ok)
	testing.expect(t, !relative_ok)
}

/* Ensures resolution reports required capacity without partial output. */
@(test)
dir_resolution_checks_capacity :: proc(t: ^testing.T) {
	target := "/work/odra"
	first := [?]string{target}
	second := [?]string{target}
	entries := [?]Catalog_Entry {
		{directories = first[:], valid = true},
		{directories = second[:], valid = true},
	}
	matches: [1]int

	kind, count, ok := resolve_exact_single_directory(entries[:], target, matches[:])
	testing.expect(t, !ok)
	testing.expect_value(t, kind, Directory_Resolution_Kind.Ambiguous)
	testing.expect_value(t, count, 1)
	testing.expect_value(t, matches[0], 0)
}
