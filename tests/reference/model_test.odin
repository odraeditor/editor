// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package reference

import "../../src/editor"
import "core:testing"

/* Ensures reference fixtures survive loading without normalization or loss. */
@(test)
fixtures_are_preserved_byte_for_byte :: proc(t: ^testing.T) {
	for fixture in FIXTURES {
		model, failure, ok := model_init(fixture.text)
		testing.expectf(t, ok, "fixture %s failed with %v", fixture.name, failure.code)
		if !ok {
			continue
		}
		testing.expect_value(t, model_text(&model), fixture.text)
		testing.expect_value(t, model.revision, editor.Revision(0))
		model_deinit(&model)
	}
}

/* Ensures insertion, deletion, and replacement share one splice contract. */
@(test)
one_contract_covers_insert_delete_and_replace :: proc(t: ^testing.T) {
	model, _, ok := model_init("abc")
	testing.expect(t, ok)
	defer model_deinit(&model)

	apply_test_splice(t, &model, 1, 1, "🙂")
	testing.expect_value(t, model_text(&model), "a🙂bc")

	apply_test_splice(t, &model, 1, 5, "")
	testing.expect_value(t, model_text(&model), "abc")

	apply_test_splice(t, &model, 1, 2, "λ")
	testing.expect_value(t, model_text(&model), "aλc")
	testing.expect_value(t, model.revision, editor.Revision(3))
}

/* Ensures invalid reference splices cannot mutate confirmed model state. */
@(test)
invalid_splices_preserve_confirmed_state :: proc(t: ^testing.T) {
	model, _, ok := model_init("a🙂b")
	testing.expect(t, ok)
	defer model_deinit(&model)

	start, _ := model_position(&model, 2)
	end, _ := model_position(&model, 5)
	failure, splice_ok := model_splice(&model, editor.Splice {
		start = start,
		end = end,
		replacement = "x",
	})
	testing.expect(t, !splice_ok)
	testing.expect_value(t, failure.code, editor.Failure_Code.Mid_Encoding_Offset)
	testing.expect_value(t, model_text(&model), "a🙂b")
	testing.expect_value(t, model.revision, editor.Revision(0))

	stale_start := editor.Position {
		buffer_id = model.buffer_id,
		revision = editor.Revision(9),
		byte_offset = editor.Byte_Offset(0),
	}
	stale_end := stale_start
	failure, splice_ok = model_splice(&model, editor.Splice {
		start = stale_start,
		end = stale_end,
		replacement = "x",
	})
	testing.expect(t, !splice_ok)
	testing.expect_value(t, failure.code, editor.Failure_Code.Stale_Revision)
	testing.expect_value(t, model_text(&model), "a🙂b")
}

/* Ensures seeded generation is reproducible for regression diagnosis. */
@(test)
generator_replays_identically_for_one_seed :: proc(t: ^testing.T) {
	first, _, first_ok := model_init("alpha🙂omega")
	second, _, second_ok := model_init("alpha🙂omega")
	testing.expect(t, first_ok && second_ok)
	defer model_deinit(&first)
	defer model_deinit(&second)

	first_generator := generator_init(0x4f44_5241_0000_0001)
	second_generator := generator_init(0x4f44_5241_0000_0001)

	for _ in 0 ..< 128 {
		first_operation := generator_next(&first_generator, &first)
		second_operation := generator_next(&second_generator, &second)
		testing.expect_value(t, first_operation, second_operation)

		first_splice, first_splice_ok := operation_splice(&first, first_operation)
		second_splice, second_splice_ok := operation_splice(&second, second_operation)
		testing.expect(t, first_splice_ok && second_splice_ok)

		_, first_apply_ok := model_splice(&first, first_splice)
		_, second_apply_ok := model_splice(&second, second_splice)
		testing.expect(t, first_apply_ok && second_apply_ok)
		testing.expect_value(t, model_text(&first), model_text(&second))
	}
}

@(private)
apply_test_splice :: proc(
	t: ^testing.T,
	model: ^Model,
	start_offset: u64,
	end_offset: u64,
	replacement: string,
) {
	start, start_ok := model_position(model, start_offset)
	end, end_ok := model_position(model, end_offset)
	testing.expect(t, start_ok && end_ok)

	_, ok := model_splice(model, editor.Splice {
		start = start,
		end = end,
		replacement = replacement,
	})
	testing.expect(t, ok)
}
