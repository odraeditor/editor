// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package symbol_navigation_reference provides an independent bounded symbol-provider oracle.
package symbol_navigation_reference

MAX_SYMBOLS :: 256
MAX_NAME_BYTES :: 64

Symbol :: struct {
	id:         u64,
	provider:   u64,
	revision:   u64,
	start:      u64,
	end:        u64,
	name:       [MAX_NAME_BYTES]u8,
	name_bytes: u8,
	kind:       u8,
	parent:     u64,
}

Model :: struct {
	provider:   u64,
	revision:   u64,
	generation: u64,
	symbols:    [MAX_SYMBOLS]Symbol,
	count:      u16,
	cancelled:  bool,
}

publish :: proc(model: ^Model, provider, revision, expected_generation: u64,
	definitions: []Symbol) -> bool {
	if model == nil || provider == 0 || revision == 0 || model.cancelled ||
	   expected_generation != model.generation || len(definitions) > MAX_SYMBOLS {
		return false
	}
	seen: [MAX_SYMBOLS]u64
	for definition, index in definitions {
		if definition.id == 0 || definition.provider != provider ||
		   definition.revision != revision || definition.start >= definition.end ||
		   definition.name_bytes == 0 || definition.name_bytes > MAX_NAME_BYTES {
			return false
		}
		for prior in 0 ..< index do if seen[prior] == definition.id do return false
		seen[index] = definition.id
	}
	model.provider = provider
	model.revision = revision
	model.generation += 1
	model.count = u16(len(definitions))
	copy(model.symbols[:], definitions)
	return true
}

filter :: proc(model: ^Model, query: string, output: ^[MAX_SYMBOLS]u16) -> u16 {
	if model == nil || output == nil do return 0
	count: u16
	for _, index in model.symbols[:model.count] {
		symbol := &model.symbols[index]
		name := string(symbol.name[:symbol.name_bytes])
		if len(query) == 0 || contains(name, query) {
			output[count] = u16(index)
			count += 1
		}
	}
	return count
}

contains :: proc(text, query: string) -> bool {
	if len(query) == 0 do return true
	if len(query) > len(text) do return false
	for start in 0 ..= len(text) - len(query) {
		if text[start:start + len(query)] == query do return true
	}
	return false
}

symbol :: proc(id, provider, revision, start: u64, name: string, parent := u64(0)) -> Symbol {
	result := Symbol{id = id, provider = provider, revision = revision,
		start = start, end = start + u64(len(name)), parent = parent, kind = 1}
	result.name_bytes = u8(copy(result.name[:], name))
	return result
}
