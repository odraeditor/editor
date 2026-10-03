// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package project_reference

import "core:testing"

/* Ensures Project roots may overlap but cannot duplicate exact membership. */
@(test)
membership_allows_overlap_no_duplicates :: proc(t: ^testing.T) {
	model, ready := model_init(4)
	testing.expect(t, ready)
	defer model_deinit(&model)

	root, root_ok, _ := model_add(&model, "/work")
	nested, nested_ok, _ := model_add(&model, "/work/odra", .Trusted)
	_, duplicate_ok, duplicate_failure := model_add(&model, "/work")

	testing.expect(t, root_ok)
	testing.expect(t, nested_ok)
	testing.expect(t, !duplicate_ok)
	testing.expect_value(t, duplicate_failure.code, Failure_Code.Duplicate_Path)
	results: [4]Handle
	count, contained := model_containing(&model, "/work/odra/src/main.odin", results[:])
	testing.expect(t, contained)
	testing.expect_value(t, count, 2)
	testing.expect_value(t, results[0], root)
	testing.expect_value(t, results[1], nested)
	testing.expect(t, model_validate(&model))
}

/* Ensures membership updates reject stale Project generations atomically. */
@(test)
membership_rejects_stale_generation :: proc(t: ^testing.T) {
	model, ready := model_init(1)
	testing.expect(t, ready)
	defer model_deinit(&model)

	first, first_ok, _ := model_add(&model, "/one")
	testing.expect(t, first_ok)
	removed, _ := model_remove(&model, first)
	testing.expect(t, removed)
	second, second_ok, _ := model_add(&model, "/two")
	testing.expect(t, second_ok)
	testing.expect(t, second.generation > first.generation)

	_, stale_failure := model_set_trust(&model, first, .Trusted)
	testing.expect_value(t, stale_failure.code, Failure_Code.Invalid_Handle)
	descriptor, described := model_descriptor(&model, second)
	testing.expect(t, described)
	testing.expect_value(t, descriptor.path, "/two")
	testing.expect(t, model_validate(&model))
}

/* Ensures path containment cannot confuse textual prefixes with directory ancestry. */
@(test)
path_containment_observes_directory_boundaries :: proc(t: ^testing.T) {
	testing.expect(t, path_contains("/work", "/work"))
	testing.expect(t, path_contains("/work", "/work/file"))
	testing.expect(t, !path_contains("/work", "/workspace/file"))
	testing.expect(t, path_contains("/", "/anything"))
}
