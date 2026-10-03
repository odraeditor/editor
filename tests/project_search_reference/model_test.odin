// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package project_search_reference

import "core:testing"

/* Ensures multi-root search publication requires current Project generations. */
@(test)
publish_checks_generation_and_roots :: proc(t: ^testing.T) {
	model: Model
	sources := [?]Source {
		source(1, 11, "alpha/main.odin", "needle alpha"),
		source(2, 12, "beta/main.odin", "beta needle"),
	}
	testing.expect(t, publish_literal(&model, 7, 0, "needle", sources[:], 16, false))
	testing.expect_value(t, model.result_generation, u64(1))
	testing.expect_value(t, model.count, u16(2))
	testing.expect(t, revalidate(&model, 0, 7, 11))
	testing.expect(t, !revalidate(&model, 0, 8, 11))
	testing.expect(t, !revalidate(&model, 0, 7, 99))
	testing.expect(t, !publish_literal(&model, 7, 0, "needle", sources[:], 16, false))
}

/* Ensures bounded or cancelled searches report only actually published results. */
@(test)
bounded_cancelled_keep_publish_truth :: proc(t: ^testing.T) {
	model: Model
	sources := [?]Source {source(1, 21, "dense.txt", "x x x x")}
	testing.expect(t, publish_literal(&model, 1, 0, "x", sources[:], 2, false))
	testing.expect(t, !model.complete)
	testing.expect_value(t, model.count, u16(2))
	before := model
	testing.expect(t, !publish_literal(&model, 1, 1, "x", sources[:], 2, true))
	testing.expect_value(t, model, before)
}
