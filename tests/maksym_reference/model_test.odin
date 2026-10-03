// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package maksym_reference

import "core:testing"

resource :: proc(object: u64, scope := u64(41)) -> Resource_ID {
	return {provider = 1, scope = scope, object = object}
}

/* Ensures directory projection is ordered and navigation stops at both bounds. */
@(test)
dir_projection_orders_and_bounds :: proc(t: ^testing.T) {
	model, ready := model_init()
	testing.expect(t, ready)
	defer model_close(&model)
	definitions := []Definition {
		{resource = resource(3), name = "zeta.odin", kind = .Regular_File},
		{resource = resource(2), name = "src", kind = .Directory},
		{resource = resource(1), name = "README.md", kind = .Regular_File},
	}
	published, failure := model_publish(&model, 1, definitions)
	testing.expect(t, published)
	testing.expect_value(t, failure, Failure_Code.None)
	testing.expect_value(t, model.entries[0].name, "src")
	testing.expect_value(t, model.entries[1].name, "README.md")
	testing.expect_value(t, model.entries[2].name, "zeta.odin")
	testing.expect(t, !model_move(&model, -1))
	testing.expect(t, model_move(&model, 1))
	selected, selected_ok := model_selected(&model)
	testing.expect(t, selected_ok)
	testing.expect_value(t, selected.name, "README.md")
	testing.expect(t, model_validate(&model))
}

/* Ensures refresh follows selected identity across rename and reorder. */
@(test)
refresh_keeps_selection_across_rename :: proc(t: ^testing.T) {
	model, ready := model_init()
	testing.expect(t, ready)
	defer model_close(&model)
	first := []Definition {
		{resource = resource(1), name = "alpha", kind = .Regular_File},
		{resource = resource(2), name = "beta", kind = .Regular_File},
	}
	second := []Definition {
		{resource = resource(3), name = "aardvark", kind = .Directory},
		{resource = resource(2), name = "zeta", kind = .Regular_File},
	}
	first_ok, _ := model_publish(&model, 1, first)
	selected := model_select(&model, resource(2))
	second_ok, _ := model_publish(&model, 2, second)
	entry, entry_ok := model_selected(&model)
	testing.expect(t, first_ok && selected && second_ok && entry_ok)
	testing.expect_value(t, entry.resource, resource(2))
	testing.expect_value(t, entry.name, "zeta")
	testing.expect_value(t, model.entries[0].resource, resource(3))
	testing.expect(t, model_validate(&model))
}

/* Ensures invalid listings leave the previous generation authoritative. */
@(test)
rejected_publish_keeps_generation :: proc(t: ^testing.T) {
	model, ready := model_init()
	testing.expect(t, ready)
	defer model_close(&model)
	baseline := []Definition {{resource = resource(1), name = "stable", kind = .Regular_File}}
	published, _ := model_publish(&model, 7, baseline)
	testing.expect(t, published)
	duplicate := []Definition {
		{resource = resource(2), name = "one", kind = .Regular_File},
		{resource = resource(2), name = "two", kind = .Directory},
	}
	duplicate_ok, duplicate_failure := model_publish(&model, 8, duplicate)
	stale_ok, stale_failure := model_publish(&model, 7, baseline)
	overflow: [MAX_ENTRIES + 1]Definition
	for &definition, index in overflow {
		definition = {resource = resource(u64(index + 10)), name = "entry", kind = .Regular_File}
	}
	overflow_ok, overflow_failure := model_publish(&model, 9, overflow[:])
	testing.expect(t, !duplicate_ok && !stale_ok && !overflow_ok)
	testing.expect_value(t, duplicate_failure, Failure_Code.Duplicate_Identity)
	testing.expect_value(t, stale_failure, Failure_Code.Invalid_Generation)
	testing.expect_value(t, overflow_failure, Failure_Code.Entry_Limit)
	testing.expect_value(t, model.generation, u64(7))
	testing.expect_value(t, model.entries[0].name, "stable")
	testing.expect(t, model_validate(&model))
}

/* Exercises generated refresh and navigation traces against model invariants. */
@(test)
refresh_navigation_keep_invariants :: proc(t: ^testing.T) {
	model, ready := model_init()
	testing.expect(t, ready)
	defer model_close(&model)
	seed := u64(0x6a09e667f3bcc909)
	for generation in 1 ..= 512 {
		seed = seed * 6_364_136_223_846_793_005 + 1_442_695_040_888_963_407
		count := int(seed % 8) + 1
		definitions: [8]Definition
		for &definition, index in definitions[:count] {
			object := u64(index + 1)
			definition = {
				resource = resource(object),
				name = "entry",
				kind = .Directory if (seed >> u64(index)) & 1 == 1 else .Regular_File,
			}
		}
		published, _ := model_publish(&model, u64(generation), definitions[:count])
		testing.expectf(t, published, "generation %d was rejected", generation)
		if seed & 1 == 1 {
			_ = model_move(&model, 1)
		} else {
			_ = model_move(&model, -1)
		}
		testing.expectf(t, model_validate(&model), "generation %d invalid", generation)
	}
	model_close(&model)
	testing.expect_value(t, model, Model{})
}

/* Ensures editable projection derives a complete, collision-safe rename set. */
@(test)
projection_builds_rename_sets :: proc(t: ^testing.T) {
	model, ready := model_init()
	testing.expect(t, ready)
	defer model_close(&model)
	definitions := []Definition {
		{resource = resource(1), name = "alpha", kind = .Regular_File},
		{resource = resource(2), name = "beta", kind = .Regular_File},
	}
	published, _ := model_publish(&model, 1, definitions)
	testing.expect(t, published)
	changes: [MAX_ENTRIES]Rename
	count, calculated, failure := model_calculate_renames(&model, []string{"beta", "alpha"}, &changes)
	testing.expect(t, calculated)
	testing.expect_value(t, failure, Failure_Code.None)
	testing.expect_value(t, count, 2)
	testing.expect_value(t, changes[0].from, "alpha")
	testing.expect_value(t, changes[0].to, "beta")
	_, duplicate_ok, duplicate_failure := model_calculate_renames(
		&model,
		[]string{"same", "same"},
		&changes,
	)
	testing.expect(t, !duplicate_ok)
	testing.expect_value(t, duplicate_failure, Failure_Code.Duplicate_Destination)
	_, invalid_ok, invalid_failure := model_calculate_renames(
		&model,
		[]string{"../escape", "beta"},
		&changes,
	)
	testing.expect(t, !invalid_ok)
	testing.expect_value(t, invalid_failure, Failure_Code.Invalid_Editable_Projection)
}

/* Ensures edited names distinguish relative moves from deletions. */
@(test)
projection_classifies_moves_deletions :: proc(t: ^testing.T) {
	model, ready := model_init()
	defer model_close(&model)
	definitions := []Definition {
		{resource = resource(1), name = "move-me", kind = .Regular_File},
		{resource = resource(2), name = "delete-me", kind = .Regular_File},
	}
	published, _ := model_publish(&model, 1, definitions)
	changes: [MAX_ENTRIES]Rename
	count, calculated, failure := model_calculate_renames(
		&model, []string{"archive/moved", ""}, &changes,
	)
	testing.expect(t, ready && published && calculated)
	testing.expect_value(t, failure, Failure_Code.None)
	testing.expect_value(t, count, 2)
	testing.expect_value(t, changes[0].kind, Change_Kind.Move)
	testing.expect_value(t, changes[1].kind, Change_Kind.Delete)
}
