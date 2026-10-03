// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language

import "../editor"
import "../transaction"
import "core:strings"
import "core:testing"

/* Verifies Odin retains its exact factory identity and provider contract. */
@(test)
factory_odin_registration_remains_unchanged :: proc(t: ^testing.T) {
	registration, registered := factory_bundle_registration(FACTORY_ODIN_BUNDLE_IDENTITY)
	testing.expect(t, registered)
	if !registered do return
	testing.expect_value(t, registration.bundle_identity, FACTORY_ODIN_BUNDLE_IDENTITY)
	testing.expect_value(t, registration.language.id, FACTORY_ODIN_LANGUAGE_ID)
	testing.expect_value(t, registration.language.generation, FACTORY_LANGUAGE_GENERATION)
	testing.expect_value(t, string(registration.language.name.bytes[:registration.language.name.length]), "odin")
	testing.expect_value(t, registration.provider.name, "factory-odin-tree-sitter")
	testing.expect_value(t, registration.provider.parser_name, "tree-sitter-odin")
	testing.expect_value(t, registration.provider.grammar_abi, TREE_SITTER_ODIN_ABI)
}

/* Verifies both Jan suffixes resolve to one identical factory contract. */
@(test)
factory_jan_suffixes_share_one_registration :: proc(t: ^testing.T) {
	catalog: Language_Catalog
	initialized, _ := language_catalog_init(&catalog, 72)
	testing.expect(t, initialized)
	if !initialized do return
	defer language_catalog_close(&catalog)
	_, confirmed, _ := factory_bundle_catalog_confirm(&catalog)
	org, org_selected, _ := language_catalog_resolve(&catalog, "/work/notes.org")
	jan, jan_selected, _ := language_catalog_resolve(&catalog, "/work/notes.jan")
	registration, registered := factory_bundle_registration(FACTORY_JAN_BUNDLE_IDENTITY)
	testing.expect(t, confirmed && org_selected && jan_selected)
	testing.expect(t, registered)
	if !confirmed || !org_selected || !jan_selected || !registered do return
	testing.expect_value(t, org.language, jan.language)
	testing.expect_value(t, org.language.id, FACTORY_JAN_LANGUAGE_ID)
	testing.expect_value(t, string(org.language.name.bytes[:org.language.name.length]), "jan")
	testing.expect_value(t, registration.bundle_identity, FACTORY_JAN_BUNDLE_IDENTITY)
	testing.expect_value(t, registration.provider.name, "factory-jan-tree-sitter")
	testing.expect_value(t, registration.provider.parser_name, "tree-sitter-jan")
	testing.expect_value(t, registration.provider.grammar_abi, TREE_SITTER_JAN_ABI)
	testing.expect(t, jan_baseline_identity_is_valid(registration.jan_baseline))
	testing.expect(t, jan_configuration_is_valid(registration.jan_configuration))
	testing.expect_value(t, string(org.selector.bytes[:org.selector.length]), ".org")
	testing.expect_value(t, string(jan.selector.bytes[:jan.selector.length]), ".jan")
}

/* Verifies explicit Jan selection overrides an otherwise unsupported suffix. */
@(test)
factory_jan_explicit_selection_is_bounded :: proc(t: ^testing.T) {
	catalog: Language_Catalog
	initialized, _ := language_catalog_init(&catalog, 74)
	testing.expect(t, initialized)
	if !initialized do return
	defer language_catalog_close(&catalog)
	_, confirmed, _ := factory_bundle_catalog_confirm(&catalog)
	selection, selected, _ := language_catalog_resolve(&catalog, "/work/notes.txt", "jan")
	testing.expect(t, confirmed)
	testing.expect(t, selected)
	if selected {
		testing.expect_value(t, selection.language.id, FACTORY_JAN_LANGUAGE_ID)
		testing.expect_value(t, selection.kind, Language_Selector_Kind.Explicit)
		testing.expect_value(t, string(selection.selector.bytes[:selection.selector.length]), "jan")
	}
	_, upper_suffix, _ := language_catalog_resolve(&catalog, "/work/notes.ORG")
	_, upper_request, _ := language_catalog_resolve(&catalog, "/work/notes.txt", "JAN")
	_, unsupported, _ := language_catalog_resolve(&catalog, "/work/notes.txt")
	testing.expect(t, !upper_suffix && !upper_request && !unsupported)
}

/* Verifies the factory catalog carries every maintained language identity. */
@(test)
factory_catalog_confirms_maintained_language_identities :: proc(t: ^testing.T) {
	catalog: Language_Catalog
	initialized, _ := language_catalog_init(&catalog, 73)
	testing.expect(t, initialized)
	if !initialized do return
	defer language_catalog_close(&catalog)

	inspection, confirmed, failure := factory_bundle_catalog_confirm(&catalog)
	testing.expect(t, confirmed)
	testing.expect_value(t, failure.code, Language_Catalog_Failure_Code.None)
	testing.expect_value(t, inspection.definition_count, u16(9))
	odin, odin_ok, _ := language_catalog_resolve(&catalog, "/work/main.odin")
	jan, jan_ok, _ := language_catalog_resolve(&catalog, "/work/notes.org")
	racket, racket_ok, _ := language_catalog_resolve(&catalog, "/work/main.rkt")
	go_selection, go_ok, _ := language_catalog_resolve(&catalog, "/work/main.go")
	rust, rust_ok, _ := language_catalog_resolve(&catalog, "/work/main.rs")
	javascript, javascript_ok, _ := language_catalog_resolve(&catalog, "/work/main.jsx")
	typescript, typescript_ok, _ := language_catalog_resolve(&catalog, "/work/main.tsx")
	html, html_ok, _ := language_catalog_resolve(&catalog, "/work/index.html")
	css, css_ok, _ := language_catalog_resolve(&catalog, "/work/site.css")
	testing.expect(t, odin_ok && jan_ok && racket_ok && go_ok && rust_ok &&
	               javascript_ok && typescript_ok && html_ok && css_ok)
	testing.expect_value(t, odin.language.id, FACTORY_ODIN_LANGUAGE_ID)
	testing.expect_value(t, jan.language.id, FACTORY_JAN_LANGUAGE_ID)
	testing.expect_value(t, racket.language.id, FACTORY_RACKET_LANGUAGE_ID)
	testing.expect_value(t, language_name_string(&racket.language.name), "racket")
	testing.expect_value(t, go_selection.language.id, FACTORY_GO_LANGUAGE_ID)
	testing.expect_value(t, language_name_string(&go_selection.language.name), "go")
	testing.expect_value(t, rust.language.id, FACTORY_RUST_LANGUAGE_ID)
	testing.expect_value(t, language_name_string(&rust.language.name), "rust")
	testing.expect_value(t, javascript.language.id, FACTORY_JAVASCRIPT_LANGUAGE_ID)
	testing.expect_value(t, typescript.language.id, FACTORY_TYPESCRIPT_LANGUAGE_ID)
	testing.expect_value(t, html.language.id, FACTORY_HTML_LANGUAGE_ID)
	testing.expect_value(t, css.language.id, FACTORY_CSS_LANGUAGE_ID)
}

/* Verifies the maintained bundle set and native grammar resolver share stable identities. */
@(test)
factory_bundle_grammar_resolution_is_stable :: proc(t: ^testing.T) {
	registrations, registered := factory_syntax_bundle_registrations()
	testing.expect(t, registered)
	if !registered do return
	testing.expect_value(t, registrations[0].bundle_identity, FACTORY_ODIN_BUNDLE_IDENTITY)
	testing.expect_value(t, registrations[1].bundle_identity, FACTORY_JAN_BUNDLE_IDENTITY)
	testing.expect_value(t, registrations[2].bundle_identity, FACTORY_RACKET_BUNDLE_IDENTITY)
	testing.expect_value(t, registrations[3].bundle_identity, FACTORY_GO_BUNDLE_IDENTITY)
	testing.expect_value(t, registrations[4].bundle_identity, FACTORY_RUST_BUNDLE_IDENTITY)
	testing.expect_value(t, registrations[5].bundle_identity, FACTORY_JAVASCRIPT_BUNDLE_IDENTITY)
	testing.expect_value(t, registrations[6].bundle_identity, FACTORY_TYPESCRIPT_BUNDLE_IDENTITY)
	testing.expect_value(t, registrations[7].bundle_identity, FACTORY_HTML_BUNDLE_IDENTITY)
	testing.expect_value(t, registrations[8].bundle_identity, FACTORY_CSS_BUNDLE_IDENTITY)
	testing.expect(t, tree_sitter_factory_language(registrations[0].bundle_identity) != nil)
	testing.expect(t, tree_sitter_factory_language(registrations[1].bundle_identity) != nil)
	testing.expect(t, tree_sitter_factory_language(registrations[2].bundle_identity) != nil)
	testing.expect(t, tree_sitter_factory_language(registrations[3].bundle_identity) != nil)
	testing.expect(t, tree_sitter_factory_language(registrations[4].bundle_identity) != nil)
	for registration in registrations[5:] {
		testing.expect(t, tree_sitter_factory_language(registration.bundle_identity) != nil)
	}
	testing.expect(t, tree_sitter_factory_language("org.odra.unknown") == nil)
	_, unknown := factory_bundle_registration("org.odra.unknown")
	testing.expect(t, !unknown)
}

/* Verifies maintained factory owners compile their own pinned queries. */
@(test)
factory_maintained_queries_compile :: proc(t: ^testing.T) {
	identities := [?]string {
		FACTORY_RACKET_BUNDLE_IDENTITY,
		FACTORY_GO_BUNDLE_IDENTITY,
		FACTORY_RUST_BUNDLE_IDENTITY,
		FACTORY_JAVASCRIPT_BUNDLE_IDENTITY,
		FACTORY_JAVASCRIPT_JSX_IDENTITY,
		FACTORY_TYPESCRIPT_BUNDLE_IDENTITY,
		FACTORY_TYPESCRIPT_TSX_IDENTITY,
		FACTORY_HTML_BUNDLE_IDENTITY,
		FACTORY_CSS_BUNDLE_IDENTITY,
	}
	for identity, index in identities {
		owner: Tree_Sitter_Owner
		initialized, init_failure := tree_sitter_owner_init_factory(
			&owner,
			identity,
			Parser_Generation(index + 1),
		)
		testing.expect(t, initialized)
		testing.expect_value(t, init_failure.code, Failure_Code.None)
		if !initialized do continue
		compiled, query_failure := tree_sitter_owner_compile_factory_query(
			&owner,
			identity,
			Query_Generation(1),
		)
		testing.expect(t, compiled)
		testing.expect_value(t, query_failure.code, Failure_Code.None)
		stats, inspected, _ := tree_sitter_owner_stats(&owner)
		testing.expect(t, inspected)
		if inspected {
			expected_abi, _ := factory_syntax_grammar_abi(identity)
			testing.expect_value(t, stats.grammar_abi, expected_abi)
			testing.expect(t, stats.has_query)
			testing.expect(t, stats.query_captures > 0)
		}
		closed, _ := tree_sitter_owner_close(&owner)
		testing.expect(t, closed)
	}
}

/* Verifies JSX and TSX select exact grammar variants without changing language identity. */
@(test)
factory_web_variants_route_exact_selectors :: proc(t: ^testing.T) {
	javascript, javascript_ok := factory_syntax_identity_for_selector(
		FACTORY_JAVASCRIPT_LANGUAGE_ID,
		".js",
	)
	jsx, jsx_ok := factory_syntax_identity_for_selector(FACTORY_JAVASCRIPT_LANGUAGE_ID, ".jsx")
	typescript, typescript_ok := factory_syntax_identity_for_selector(
		FACTORY_TYPESCRIPT_LANGUAGE_ID,
		".ts",
	)
	tsx, tsx_ok := factory_syntax_identity_for_selector(FACTORY_TYPESCRIPT_LANGUAGE_ID, ".tsx")
	testing.expect(t, javascript_ok && jsx_ok && typescript_ok && tsx_ok)
	testing.expect_value(t, javascript, FACTORY_JAVASCRIPT_BUNDLE_IDENTITY)
	testing.expect_value(t, jsx, FACTORY_JAVASCRIPT_JSX_IDENTITY)
	testing.expect_value(t, typescript, FACTORY_TYPESCRIPT_BUNDLE_IDENTITY)
	testing.expect_value(t, tsx, FACTORY_TYPESCRIPT_TSX_IDENTITY)
	_, unknown := factory_syntax_identity_for_selector(Language_ID(99), ".tsx")
	testing.expect(t, !unknown)
}

/* Verifies maintained HTML queries identify JavaScript and CSS child regions. */
@(test)
factory_html_injections_select_child_languages :: proc(t: ^testing.T) {
	contents := "<main><script>const saludo = 'héllo';</script><style>main { color: red; }</style></main>"
	buffer: editor.Buffer
	initialized, _ := editor.buffer_init(
		&buffer,
		930,
		contents,
		{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, initialized)
	if !initialized do return
	defer editor.buffer_close(&buffer)
	snapshot: editor.Buffer_Snapshot
	opened, _ := editor.buffer_snapshot_open(&buffer, &snapshot)
	testing.expect(t, opened)
	if !opened do return
	defer editor.buffer_snapshot_close(&snapshot)
	owner: Tree_Sitter_Owner
	owner_ready, _ := tree_sitter_owner_init_factory(&owner, FACTORY_HTML_BUNDLE_IDENTITY, 1)
	testing.expect(t, owner_ready)
	if !owner_ready do return
	defer tree_sitter_owner_close(&owner)
	query_ready, _ := tree_sitter_owner_compile_factory_query(&owner, FACTORY_HTML_BUNDLE_IDENTITY, 1)
	testing.expect(t, query_ready)
	if !query_ready do return
	identity := factory_bundle_language_identity(FACTORY_HTML_LANGUAGE_ID, "html")
	provider := Provider_Handle {
		registry_id = 1,
		language_id = FACTORY_HTML_LANGUAGE_ID,
		provider_id = 1,
		provider_generation = 1,
	}
	_, parsed, _ := tree_sitter_owner_parse_snapshot(&owner, &snapshot, identity, provider, 1, 1)
	testing.expect(t, parsed)
	if !parsed do return
	injections, queried, failure := tree_sitter_owner_query_factory_injections(&owner, &snapshot)
	testing.expect(t, queried)
	testing.expect_value(t, failure.code, Failure_Code.None)
	testing.expect_value(t, injections.count, u16(2))
	javascript_found := false
	css_found := false
	for injection in injections.captures[:injections.count] {
		javascript_found = javascript_found || injection.language_id == FACTORY_JAVASCRIPT_LANGUAGE_ID
		css_found = css_found || injection.language_id == FACTORY_CSS_LANGUAGE_ID
		testing.expect(t, injection.start < injection.end)
	}
	testing.expect(t, javascript_found && css_found)
}

/* Verifies maintained languages publish semantic spans for Unicode source and clean up. */
@(test)
factory_maintained_queries_publish_spans :: proc(t: ^testing.T) {
	cases := [?]struct {
		bundle_identity: string,
		language_id:     Language_ID,
		contents:        string,
		primary:         string,
		primary_role:    Syntax_Role,
		function:        string,
		function_role:   Syntax_Role,
		string_value:    string,
		language_name:   string,
		structural_role: Syntax_Structural_Role,
	} {
		{
			bundle_identity = FACTORY_RACKET_BUNDLE_IDENTITY,
			language_id = FACTORY_RACKET_LANGUAGE_ID,
			contents = "#lang racket/base\n; Unicode λ\n(define (saludo nombre) (displayln \"héllo\") 42)\n",
			primary = "#lang",
			primary_role = .Keyword,
			function = "",
			string_value = "héllo",
			language_name = "racket",
		},
		{
			bundle_identity = FACTORY_GO_BUNDLE_IDENTITY,
			language_id = FACTORY_GO_LANGUAGE_ID,
			contents = "package main\n// Unicode λ\nfunc saludo(nombre string) string { return \"héllo\" }\n",
			primary = "func",
			primary_role = .Keyword,
			function = "saludo",
			function_role = .Function,
			string_value = "héllo",
			language_name = "go",
		},
		{
			bundle_identity = FACTORY_RACKET_BUNDLE_IDENTITY,
			language_id = FACTORY_RACKET_LANGUAGE_ID,
			contents = "#lang scribble/manual\n@title{Unicode λ}\n(define (broken \"héllo\"\n",
			primary = "#lang",
			primary_role = .Keyword,
			function = "",
			string_value = "héllo",
			language_name = "racket",
		},
		{
			bundle_identity = FACTORY_RUST_BUNDLE_IDENTITY,
			language_id = FACTORY_RUST_LANGUAGE_ID,
			contents = "struct Saludo { nombre: String }\nfn saludo(nombre: &str) -> String { format!(\"héllo {nombre}\") }\n",
			primary = "fn",
			primary_role = .Keyword,
			function = "saludo",
			function_role = .Function,
			string_value = "héllo {nombre}",
			language_name = "rust",
			structural_role = .Definition,
		},
		{
			bundle_identity = FACTORY_JAVASCRIPT_BUNDLE_IDENTITY,
			language_id = FACTORY_JAVASCRIPT_LANGUAGE_ID,
			contents = "const greeting = (name) => `héllo ${name}`; // Unicode λ\n",
			primary = "const",
			primary_role = .Keyword,
			string_value = "héllo ${name}",
			language_name = "javascript",
		},
		{
			bundle_identity = FACTORY_JAVASCRIPT_JSX_IDENTITY,
			language_id = FACTORY_JAVASCRIPT_LANGUAGE_ID,
			contents = "const View = () => <main title=\"héllo\">λ</main>;\n",
			primary = "const",
			primary_role = .Keyword,
			string_value = "héllo",
			language_name = "javascript",
		},
		{
			bundle_identity = FACTORY_TYPESCRIPT_BUNDLE_IDENTITY,
			language_id = FACTORY_TYPESCRIPT_LANGUAGE_ID,
			contents = "interface Saludo { text: string }\nconst value: Saludo = { text: \"héllo λ\" };\n",
			primary = "interface",
			primary_role = .Keyword,
			string_value = "héllo λ",
			language_name = "typescript",
		},
		{
			bundle_identity = FACTORY_TYPESCRIPT_TSX_IDENTITY,
			language_id = FACTORY_TYPESCRIPT_LANGUAGE_ID,
			contents = "const View = (): JSX.Element => <main title=\"héllo\">λ</main\n",
			primary = "const",
			primary_role = .Keyword,
			string_value = "héllo",
			language_name = "typescript",
		},
		{
			bundle_identity = FACTORY_HTML_BUNDLE_IDENTITY,
			language_id = FACTORY_HTML_LANGUAGE_ID,
			contents = "<main title=\"héllo λ\"><span>text</span></main>\n",
			primary = "main",
			primary_role = .Type,
			string_value = "héllo λ",
			language_name = "html",
		},
		{
			bundle_identity = FACTORY_CSS_BUNDLE_IDENTITY,
			language_id = FACTORY_CSS_LANGUAGE_ID,
			contents = "@media screen { .saludo::before { content: \"héllo λ\"; } }\n",
			primary = "@media",
			primary_role = .Keyword,
			string_value = "héllo λ",
			language_name = "css",
		},
	}
	for test_case, index in cases {
		buffer: editor.Buffer
		initialized, _ := editor.buffer_init(
			&buffer,
			editor.Buffer_ID(910 + index),
			test_case.contents,
			{persistent = context.allocator, temporary = context.temp_allocator},
		)
		testing.expect(t, initialized)
		if !initialized do continue
		snapshot: editor.Buffer_Snapshot
		opened, _ := editor.buffer_snapshot_open(&buffer, &snapshot)
		testing.expect(t, opened)
		if !opened {
			_, _ = editor.buffer_close(&buffer)
			continue
		}
		owner: Tree_Sitter_Owner
		owner_ready, _ := tree_sitter_owner_init_factory(
			&owner,
			test_case.bundle_identity,
			Parser_Generation(index + 1),
		)
		query_ready, _ := tree_sitter_owner_compile_factory_query(
			&owner,
			test_case.bundle_identity,
			1,
		)
		testing.expect(t, owner_ready && query_ready)
		if owner_ready && query_ready {
			language_identity := factory_bundle_language_identity(
				test_case.language_id,
				test_case.language_name,
			)
			provider := Provider_Handle {
				registry_id = 1,
				language_id = test_case.language_id,
				provider_id = Provider_ID(index + 1),
				provider_generation = 1,
			}
			_, parsed, _ := tree_sitter_owner_parse_snapshot(
				&owner, &snapshot, language_identity, provider, 1, Tree_Generation(index + 1),
			)
			testing.expect(t, parsed)
			if parsed {
				result, queried, failure := tree_sitter_owner_query_spans(
					&owner, &snapshot, 0, u64(len(test_case.contents)), 0, 1,
				)
				testing.expectf(t, queried, "factory query failed with %v", failure.code)
				if queried {
					primary_offset := strings.index(test_case.contents, test_case.primary)
					string_offset := strings.index(test_case.contents, test_case.string_value)
					testing.expect_value(t, factory_syntax_test_role_at(result.spans[:], primary_offset), test_case.primary_role)
					if len(test_case.function) > 0 {
						function_offset := strings.index(test_case.contents, test_case.function)
						testing.expect_value(t, factory_syntax_test_role_at(result.spans[:], function_offset), test_case.function_role)
					}
					if test_case.structural_role != .None {
						testing.expect(t, factory_syntax_test_has_structural_role(
							result.structures[:], test_case.structural_role,
						))
					}
					testing.expect_value(t, factory_syntax_test_role_at(result.spans[:], string_offset), Syntax_Role.String)
					testing.expect(t, result.snapshot.usage.captures > 0)
					syntax_query_result_close(&result)
				}
			}
		}
		if owner_ready do _, _ = tree_sitter_owner_close(&owner)
		_, _ = editor.buffer_snapshot_close(&snapshot)
		_, _ = editor.buffer_close(&buffer)
	}
}

/* Verifies Rust macros, malformed recovery, and Unicode survive an incremental edit. */
@(test)
factory_rust_incremental_corpus_matches_full_parse :: proc(t: ^testing.T) {
	base := "macro_rules! greet { ($name:expr) => { format!(\"héllo {}\", $name) }; }\nfn saludo(nombre: &str) -> String { greet!(nombre) }\nfn broken( {\n"
	buffer: editor.Buffer
	initialized, _ := editor.buffer_init(
		&buffer,
		930,
		base,
		{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, initialized)
	if !initialized do return
	defer editor.buffer_close(&buffer)
	base_snapshot: editor.Buffer_Snapshot
	base_open, _ := editor.buffer_snapshot_open(&buffer, &base_snapshot)
	testing.expect(t, base_open)
	if !base_open do return
	defer editor.buffer_snapshot_close(&base_snapshot)
	language_identity := factory_bundle_language_identity(FACTORY_RUST_LANGUAGE_ID, "rust")
	provider := Provider_Handle {
		registry_id = 1,
		language_id = FACTORY_RUST_LANGUAGE_ID,
		provider_id = 1,
		provider_generation = 1,
	}
	incremental_owner: Tree_Sitter_Owner
	owner_ready, _ := tree_sitter_owner_init_factory(
		&incremental_owner,
		FACTORY_RUST_BUNDLE_IDENTITY,
		1,
	)
	testing.expect(t, owner_ready)
	if !owner_ready do return
	defer tree_sitter_owner_close(&incremental_owner)
	query_ready, _ := tree_sitter_owner_compile_factory_query(
		&incremental_owner,
		FACTORY_RUST_BUNDLE_IDENTITY,
		1,
	)
	testing.expect(t, query_ready)
	_, initial_parsed, _ := tree_sitter_owner_parse_snapshot(
		&incremental_owner, &base_snapshot, language_identity, provider, 1, 1,
	)
	testing.expect(t, initial_parsed)

	name_offset := strings.index(base, "saludo")
	testing.expect(t, name_offset >= 0)
	if name_offset < 0 do return
	start, _, _ := editor.buffer_position(&buffer, editor.Byte_Offset(name_offset))
	end, _, _ := editor.buffer_position(
		&buffer, editor.Byte_Offset(name_offset + len("saludo")),
	)
	change, _, published, _ := editor.buffer_splice(
		&buffer,
		editor.Splice{start = start, end = end, replacement = "bienvenida"},
		context.temp_allocator,
	)
	testing.expect(t, published)
	if !published do return
	result_snapshot: editor.Buffer_Snapshot
	result_open, _ := editor.buffer_snapshot_open(&buffer, &result_snapshot)
	testing.expect(t, result_open)
	if !result_open do return
	defer editor.buffer_snapshot_close(&result_snapshot)
	splices := [1]transaction.Normalized_Splice {{
		start = change.start,
		end = editor.Byte_Offset(u64(change.start) + change.removed_bytes),
		replacement_text = change.replacement_text,
		removed_text = "saludo",
	}}
	event := transaction.Commit_Event {
		buffer_id = change.buffer_id,
		base_revision = change.base_revision,
		result_revision = change.result_revision,
		splices = splices[:],
	}
	_, incrementally_parsed, incremental_failure := tree_sitter_owner_parse_incremental(
		&incremental_owner, &base_snapshot, &result_snapshot, event, 2,
	)
	testing.expectf(t, incrementally_parsed, "Rust incremental parse failed with %v", incremental_failure.code)
	if !incrementally_parsed do return
	result_stats, result_stats_ok, _ := editor.buffer_snapshot_stats(&result_snapshot)
	testing.expect(t, result_stats_ok)
	if !result_stats_ok do return
	incremental_result, incremental_queried, _ := tree_sitter_owner_query_spans(
		&incremental_owner, &result_snapshot, 0, result_stats.text_bytes, 0, 1,
	)
	testing.expect(t, incremental_queried)
	if !incremental_queried do return
	defer syntax_query_result_close(&incremental_result)

	full_owner: Tree_Sitter_Owner
	full_ready, _ := tree_sitter_owner_init_factory(&full_owner, FACTORY_RUST_BUNDLE_IDENTITY, 2)
	testing.expect(t, full_ready)
	if !full_ready do return
	defer tree_sitter_owner_close(&full_owner)
	full_query_ready, _ := tree_sitter_owner_compile_factory_query(
		&full_owner, FACTORY_RUST_BUNDLE_IDENTITY, 1,
	)
	testing.expect(t, full_query_ready)
	_, full_parsed, _ := tree_sitter_owner_parse_snapshot(
		&full_owner, &result_snapshot, language_identity, provider, 1, 1,
	)
	testing.expect(t, full_parsed)
	full_result, full_queried, _ := tree_sitter_owner_query_spans(
		&full_owner, &result_snapshot, 0, result_stats.text_bytes, 0, 1,
	)
	testing.expect(t, full_queried)
	if !full_queried do return
	defer syntax_query_result_close(&full_result)
	testing.expect_value(t, len(incremental_result.spans), len(full_result.spans))
	for span, index in incremental_result.spans {
		testing.expect_value(t, span.start, full_result.spans[index].start)
		testing.expect_value(t, span.end, full_result.spans[index].end)
		testing.expect_value(t, span.role, full_result.spans[index].role)
	}
	testing.expect(t, factory_syntax_test_has_structural_role(
		incremental_result.structures[:], .Definition,
	))
}

/* Verifies a large Rust buffer remains inside the maintained analysis bound. */
@(test)
factory_rust_large_source_is_bounded :: proc(t: ^testing.T) {
	SOURCE_BYTES :: 512 * 1024
	source, allocation_error := make([]u8, SOURCE_BYTES, context.allocator)
	testing.expect(t, allocation_error == nil)
	if allocation_error != nil do return
	defer delete(source)
	for index in 0 ..< len(source) do source[index] = ' '
	tail := "fn main() { println!(\"large\"); }\n"
	copy(source[len(source) - len(tail):], transmute([]u8)(tail))
	buffer: editor.Buffer
	initialized, _ := editor.buffer_init(
		&buffer, 931, string(source),
		{persistent = context.allocator, temporary = context.temp_allocator},
	)
	testing.expect(t, initialized)
	if !initialized do return
	defer editor.buffer_close(&buffer)
	snapshot: editor.Buffer_Snapshot
	opened, _ := editor.buffer_snapshot_open(&buffer, &snapshot)
	testing.expect(t, opened)
	if !opened do return
	defer editor.buffer_snapshot_close(&snapshot)
	owner: Tree_Sitter_Owner
	owner_ready, _ := tree_sitter_owner_init_factory(&owner, FACTORY_RUST_BUNDLE_IDENTITY, 1)
	testing.expect(t, owner_ready)
	if !owner_ready do return
	defer tree_sitter_owner_close(&owner)
	query_ready, _ := tree_sitter_owner_compile_factory_query(
		&owner, FACTORY_RUST_BUNDLE_IDENTITY, 1,
	)
	testing.expect(t, query_ready)
	language_identity := factory_bundle_language_identity(FACTORY_RUST_LANGUAGE_ID, "rust")
	provider := Provider_Handle {
		registry_id = 1, language_id = FACTORY_RUST_LANGUAGE_ID,
		provider_id = 1, provider_generation = 1,
	}
	analysis, parsed, failure := tree_sitter_owner_parse_snapshot(
		&owner, &snapshot, language_identity, provider, 1, 1,
	)
	testing.expectf(t, parsed, "large Rust parse failed with %v", failure.code)
	if parsed {
		testing.expect_value(t, analysis.usage.retained_source_bytes, u64(SOURCE_BYTES))
		testing.expect(t, analysis.usage.retained_source_bytes < MAX_ANALYZED_SOURCE_BYTES)
	}
}

@(private)
factory_syntax_test_has_structural_role :: proc(
	projections: []Syntax_Structural_Projection,
	role: Syntax_Structural_Role,
) -> bool {
	for projection in projections do if projection.role == role do return true
	return false
}

@(private)
factory_syntax_test_role_at :: proc(spans: []Syntax_Span, offset: int) -> Syntax_Role {
	if offset < 0 do return .Invalid
	for span in spans {
		if u64(offset) >= u64(span.start) && u64(offset) < u64(span.end) do return span.role
	}
	return .Invalid
}
