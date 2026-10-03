// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package symbol_navigation_reference

import "core:testing"

/* Ensures symbol publication retains provider order, duplicates, and hierarchy. */
@(test)
symbol_publish_keeps_order_and_hierarchy :: proc(t: ^testing.T) {
	model: Model
	definitions := [?]Symbol {
		symbol(1, 7, 4, 0, "outer"),
		symbol(2, 7, 4, 10, "value", 1),
		symbol(3, 7, 4, 20, "value", 1),
	}
	published := publish(&model, 7, 4, 0, definitions[:])
	indices: [MAX_SYMBOLS]u16
	count := filter(&model, "value", &indices)
	testing.expect(t, published)
	testing.expect_value(t, model.generation, u64(1))
	testing.expect_value(t, count, u16(2))
	testing.expect_value(t, model.symbols[indices[1]].parent, u64(1))
}

/* Ensures invalid or excessive symbol publications leave confirmed state intact. */
@(test)
symbol_rejects_bad_publications :: proc(t: ^testing.T) {
	model: Model
	first := [?]Symbol {symbol(1, 3, 1, 0, "alpha")}
	testing.expect(t, publish(&model, 3, 1, 0, first[:]))
	testing.expect(t, !publish(&model, 3, 2, 0, first[:]))
	duplicates := [?]Symbol {symbol(1, 3, 2, 0, "a"), symbol(1, 3, 2, 2, "b")}
	testing.expect(t, !publish(&model, 3, 2, 1, duplicates[:]))
	model.cancelled = true
	testing.expect(t, !publish(&model, 3, 2, 1, first[:]))
	dense := make([]Symbol, MAX_SYMBOLS + 1)
	defer delete(dense)
	testing.expect(t, !publish(&Model{}, 3, 2, 0, dense))
}
