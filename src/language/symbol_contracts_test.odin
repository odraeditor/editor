// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language

import "../editor"
import "core:testing"

/* Verifies the selected symbol policy remains bounded and internally valid. */
@(test)
symbol_limits_are_bounded :: proc(t: ^testing.T) {
	testing.expect(t, symbol_limits_are_valid(DEFAULT_SYMBOL_LIMITS))
	testing.expect_value(t, DEFAULT_SYMBOL_LIMITS.symbols, u32(65_536))
	testing.expect_value(t, DEFAULT_SYMBOL_LIMITS.retained_bytes, u64(32 * MEBIBYTE))

	invalid := DEFAULT_SYMBOL_LIMITS
	invalid.symbols = 0
	testing.expect(t, !symbol_limits_are_valid(invalid))
	invalid = DEFAULT_SYMBOL_LIMITS
	invalid.annotation_bytes = MAX_SYMBOL_ANNOTATION_BYTES + 1
	testing.expect(t, !symbol_limits_are_valid(invalid))
}

/* Verifies descriptors require exact provider, revision, hierarchy, and range evidence. */
@(test)
symbol_descriptors_are_exact_and_bounded :: proc(t: ^testing.T) {
	scope := symbol_test_scope()
	descriptor := symbol_test_descriptor(scope)
	testing.expect(t, symbol_descriptor_is_valid(descriptor, scope, 128))

	invalid := descriptor
	invalid.parent_id = invalid.id
	testing.expect(t, !symbol_descriptor_is_valid(invalid, scope, 128))
	invalid = descriptor
	invalid.location.source_revision += 1
	testing.expect(t, !symbol_descriptor_is_valid(invalid, scope, 128))
	invalid = descriptor
	invalid.location.end = 129
	testing.expect(t, !symbol_descriptor_is_valid(invalid, scope, 128))
	invalid = descriptor
	invalid.name.length = MAX_SYMBOL_NAME_BYTES + 1
	testing.expect(t, !symbol_descriptor_is_valid(invalid, scope, 128))
}

/* Verifies registry inspection reports only confirmed active symbol providers. */
@(test)
symbol_inspection_checks_generation :: proc(t: ^testing.T) {
	registry: Provider_Registry
	factory := symbol_test_provider_definition("factory-symbols")
	factory.capabilities = {
		.Initial_Parse,
		.Incremental_Parse,
		.Visible_Query,
		.Syntax_Roles,
		.Symbols,
	}
	initialized, _ := provider_registry_init(&registry, 71, symbol_test_language(), factory)
	testing.expect(t, initialized)
	if !initialized do return
	defer provider_registry_close(&registry)

	factory_inspection, inspected, _ := provider_registry_symbol_inspection(&registry)
	testing.expect(t, inspected && factory_inspection.available)
	testing.expect_value(t, factory_inspection.provider.handle, factory_inspection.selection.active)

	native := symbol_test_provider_definition("symbols-unavailable")
	registered, added, _ := provider_registry_register_native(&registry, native)
	confirmed, confirmed_ok, _ := provider_registry_confirm_native(&registry, registered)
	before, selected, _ := provider_registry_selection(&registry)
	_, replaced, _ := provider_registry_replace(&registry, before, confirmed)
	native_inspection, native_inspected, _ := provider_registry_symbol_inspection(&registry)

	testing.expect(t, added && confirmed_ok && selected && replaced && native_inspected)
	testing.expect(t, !native_inspection.available)
	testing.expect_value(t, native_inspection.provider.handle, confirmed)
}

@(private = "file")
symbol_test_scope :: proc() -> Symbol_Query_Scope {
	provider := Provider_Handle {
		registry_id = 1,
		language_id = 1,
		provider_id = 1,
		provider_generation = 1,
	}
	return Symbol_Query_Scope {
		kind = .Active_Buffer,
		buffer_id = 3,
		document_id = 5,
		has_document = true,
		source_revision = 7,
		language = symbol_test_language(),
		provider = provider,
		selection_generation = 9,
		request_generation = 11,
	}
}

@(private = "file")
symbol_test_language :: proc() -> Language_Identity {
	name: Language_Name
	name.length = u16(copy(name.bytes[:], "odin"))
	return Language_Identity{id = 1, generation = 1, name = name}
}

@(private = "file")
symbol_test_provider_definition :: proc(name: string) -> Provider_Definition {
	return Provider_Definition {
		name = name,
		parser_name = "tree-sitter-odin",
		grammar_abi = 14,
		capabilities = {.Initial_Parse, .Incremental_Parse, .Visible_Query, .Syntax_Roles},
		provenance = "symbol contract test provider",
	}
}

@(private = "file")
symbol_test_descriptor :: proc(scope: Symbol_Query_Scope) -> Symbol_Descriptor {
	name: Symbol_Name
	name.length = u16(copy(name.bytes[:], "draw-frame"))
	container: Symbol_Container
	container.length = u16(copy(container.bytes[:], "renderer"))
	annotation: Symbol_Annotation
	annotation.length = u16(copy(annotation.bytes[:], "proc(frame: ^Frame)"))
	return Symbol_Descriptor {
		id = 13,
		provider = scope.provider,
		result_generation = 17,
		location = Symbol_Range {
			buffer_id = scope.buffer_id,
			document_id = scope.document_id,
			has_document = scope.has_document,
			source_revision = scope.source_revision,
			start = editor.Byte_Offset(16),
			end = editor.Byte_Offset(26),
		},
		name = name,
		kind = .Function,
		container = container,
		annotation = annotation,
	}
}
