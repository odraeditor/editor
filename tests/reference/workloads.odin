// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package reference

import "../../src/editor"

Fixture :: struct {
	name: string,
	text: string,
}

FIXTURES :: [?]Fixture {
	{"empty", ""},
	{"ascii", "alpha\nbeta\ngamma\n"},
	{"multilingual", "Zażółć gęślą jaźń. Καλημέρα. こんにちは。\n"},
	{"combining", "Cafe\u0301 nai\u0308ve\n"},
	{"emoji", "editor 🧭 family 👨‍👩‍👧‍👦 flag 🇵🇱\n"},
}

REPLACEMENTS :: [?]string {
	"",
	"a",
	"\n",
	"λ",
	"e\u0301",
	"🙂",
}

Generator :: struct {
	state: u64,
}

Generated_Operation :: struct {
	start:       u64,
	end:         u64,
	replacement: string,
}

generator_init :: proc(seed: u64) -> Generator {
	assert(seed != 0, "a deterministic generator seed must be non-zero")
	return Generator{state = seed}
}

generator_next :: proc(generator: ^Generator, model: ^Model) -> Generated_Operation {
	left := generator_boundary(generator, model)
	right := generator_boundary(generator, model)
	start := min(left, right)
	end := max(left, right)
	replacement_index := int(generator_next_u64(generator) % u64(len(REPLACEMENTS)))
	replacements := REPLACEMENTS

	return Generated_Operation {
		start = start,
		end = end,
		replacement = replacements[replacement_index],
	}
}

operation_splice :: proc(
	model: ^Model,
	operation: Generated_Operation,
) -> (editor.Splice, bool) {
	start, start_ok := model_position(model, operation.start)
	end, end_ok := model_position(model, operation.end)
	if !start_ok || !end_ok {
		return {}, false
	}

	return editor.Splice {
		start = start,
		end = end,
		replacement = operation.replacement,
	}, true
}

@(private)
generator_boundary :: proc(generator: ^Generator, model: ^Model) -> u64 {
	if len(model.bytes) == 0 {
		return 0
	}

	offset := generator_next_u64(generator) % (u64(len(model.bytes)) + 1)
	for offset < u64(len(model.bytes)) && !model_boundary_is_valid(model, offset) {
		offset += 1
	}
	return offset
}

@(private)
generator_next_u64 :: proc(generator: ^Generator) -> u64 {
	value := generator.state
	value ~= value << 13
	value ~= value >> 7
	value ~= value << 17
	generator.state = value
	return value
}
