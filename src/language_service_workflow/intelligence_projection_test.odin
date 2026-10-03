// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_service_workflow

import "../editor"
import "../language"
import "../language_service"
import "../result_set"
import "core:testing"

/* Verifies read-only results reuse popup text, result-set navigation, and syntax roles. */
@(test)
language_intelligence_projects_through_shared_owners :: proc(t: ^testing.T) {
	scope := language_service.Intelligence_Source_Scope {
		document_identity = 41,
		buffer_identity = 43,
		canonical_revision = 1,
		transmitted_revision = 1,
	}
	hover_text, _ := language_service.intelligence_text_copy("Callable docs")
	hover_blocks := [1]language_service.Intelligence_Hover_Block{{text = hover_text, markup = true}}
	hover := language_service.Intelligence_Result {
		descriptor = {
			request_id = 1,
			request_generation = 1,
			result_generation = 1,
			kind = .Hover,
			scope = scope,
		},
		hover = hover_blocks[:],
		allocator = context.allocator,
	}
	popup_storage: [64]u8
	popup, popup_ok := Language_Intelligence_Popup_Text(&hover, popup_storage[:])
	testing.expect(t, popup_ok)
	testing.expect_value(t, popup, "Callable docs")

	uri, _ := language_service.intelligence_uri_copy("file:///work/fixture/source.fixture")
	locations := [1]language_service.Intelligence_Location{{
		id = 7,
		uri = uri,
		range = {
			start = {line = 0, character = 0},
			end = {line = 0, character = 1},
			start_byte = 0,
			end_byte = 1,
			bytes_present = true,
		},
	}}
	navigation := language_service.Intelligence_Result {
		descriptor = {
			request_id = 2,
			request_generation = 2,
			result_generation = 2,
			kind = .References,
			scope = scope,
		},
		locations = locations[:],
		allocator = context.allocator,
	}
	registry: result_set.Registry
	ready, _ := result_set.registry_init(&registry, {
		limits = result_set.DEFAULT_LIMITS,
		allocator = context.allocator,
	})
	testing.expect(t, ready)
	if ready {
		defer result_set.registry_close(&registry)
		_, published, failure := Language_Intelligence_Publish_Results(
			&registry,
			&navigation,
			{
				set_id = 17,
				source_id = 19,
				targets = []Language_Intelligence_Target{{
					uri = "file:///work/fixture/source.fixture",
					buffer_id = editor.Buffer_ID(43),
					revision = editor.Revision(1),
				}},
			},
		)
		testing.expectf(t, published, "intelligence result publication failed: %v", failure.code)
		if published {
			view, viewed, _ := result_set.registry_view(&registry, 17)
			testing.expect(t, viewed)
			if viewed {
				testing.expect_value(t, view.source.kind, result_set.Source_Kind.Language_Navigation)
				testing.expect_value(t, len(view.locations), 1)
				testing.expect_value(t, view.locations[0].buffer_id, editor.Buffer_ID(43))
			}
		}
	}

	tokens := [2]language_service.Intelligence_Semantic_Token {
		{start_byte = 0, end_byte = 1, token_type = 0},
		{start_byte = 1, end_byte = 5, token_type = 1, provider_order = 1},
	}
	semantic := language_service.Intelligence_Result {
		descriptor = {
			request_id = 3,
			request_generation = 3,
			result_generation = 3,
			kind = .Semantic_Tokens_Full,
			scope = scope,
		},
		tokens = tokens[:],
		allocator = context.allocator,
	}
	function_name := language_service.Name_Text{length = 8}
	copy(function_name.bytes[:8], "function")
	variable_name := language_service.Name_Text{length = 8}
	copy(variable_name.bytes[:8], "variable")
	capabilities := language_service.Capability_Values {
		semantic_tokens = {available = true, token_count = 2},
	}
	capabilities.semantic_tokens.token_types[0] = function_name
	capabilities.semantic_tokens.token_types[1] = variable_name
	odin, odin_ok := language.factory_bundle_registration(language.FACTORY_ODIN_BUNDLE_IDENTITY)
	testing.expect(t, odin_ok)
	if !odin_ok do return
	snapshot := language.Syntax_Snapshot {
		generation = 1,
		buffer_id = editor.Buffer_ID(43),
		source_revision = editor.Revision(1),
		language = odin.language,
		provider = {
			registry_id = 1,
			language_id = odin.language.id,
			provider_id = 1,
			provider_generation = 1,
		},
		selection_generation = 1,
		parser_generation = 1,
		query_generation = 1,
	}
	span_storage: [2]language.Syntax_Span
	projected_snapshot, spans, projected := Language_Intelligence_Semantic_Projection(
		&semantic,
		capabilities,
		snapshot,
		span_storage[:],
	)
	testing.expect(t, projected)
	if projected {
		testing.expect_value(t, projected_snapshot.span_count, u32(2))
		testing.expect_value(t, spans[0].role, language.Syntax_Role.Function)
		testing.expect_value(t, spans[1].role, language.Syntax_Role.Variable)
	}
}
