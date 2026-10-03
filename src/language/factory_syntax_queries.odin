// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language

@(private)
GO_FACTORY_HIGHLIGHT_QUERY :: #load(
	"../../third_party/tree-sitter-go/0.25.0/queries/highlights.scm",
)

@(private)
RACKET_FACTORY_HIGHLIGHT_QUERY :: #load(
	"../../third_party/tree-sitter-racket/0.25.0/queries/highlights.scm",
)

@(private)
RUST_FACTORY_SYNTAX_QUERY :: #load(
	"../../assets/language-bundles/factory/rust/highlights-and-structure.scm",
)

@(private)
JAVASCRIPT_FACTORY_HIGHLIGHT_QUERY :: #load(
	"../../assets/language-bundles/factory/javascript/highlights.scm",
)

@(private)
JAVASCRIPT_JSX_FACTORY_HIGHLIGHT_QUERY :: #load(
	"../../assets/language-bundles/factory/javascript/highlights-jsx.scm",
)

@(private)
TYPESCRIPT_FACTORY_HIGHLIGHT_QUERY :: #load(
	"../../assets/language-bundles/factory/typescript/highlights.scm",
)

@(private)
TYPESCRIPT_TSX_FACTORY_HIGHLIGHT_QUERY :: #load(
	"../../assets/language-bundles/factory/typescript/highlights-tsx.scm",
)

@(private)
HTML_FACTORY_HIGHLIGHT_QUERY :: #load(
	"../../assets/language-bundles/factory/html/highlights.scm",
)

@(private)
HTML_FACTORY_INJECTION_QUERY :: #load(
	"../../assets/language-bundles/factory/html/injections.scm",
)

@(private)
CSS_FACTORY_HIGHLIGHT_QUERY :: #load(
	"../../assets/language-bundles/factory/css/highlights.scm",
)

@(private)
GO_FACTORY_CAPTURE_MAPPINGS := [?]Syntax_Capture_Mapping_Proposal {
	{capture = "comment", role = .Comment, precedence = 100},
	{capture = "constant.builtin", role = .Constant, precedence = 120},
	{capture = "escape", role = .String, precedence = 120},
	{capture = "function", role = .Function, precedence = 110},
	{capture = "function.builtin", role = .Function_Builtin, precedence = 120},
	{capture = "function.method", role = .Function, precedence = 120},
	{capture = "keyword", role = .Keyword, precedence = 100},
	{capture = "number", role = .Number, precedence = 100},
	{capture = "operator", role = .Operator, precedence = 100},
	{capture = "property", role = .Variable, precedence = 110},
	{capture = "punctuation.bracket", role = .Punctuation, precedence = 100},
	{capture = "string", role = .String, precedence = 100},
	{capture = "type", role = .Type, precedence = 100},
	{capture = "variable", role = .Variable, precedence = 100},
}

@(private)
RACKET_FACTORY_CAPTURE_MAPPINGS := [?]Syntax_Capture_Mapping_Proposal {
	{capture = "comment", role = .Comment, precedence = 100},
	{capture = "constant", role = .Constant, precedence = 100},
	{capture = "constant.builtin", role = .Constant, precedence = 120},
	{capture = "escape", role = .String, precedence = 120},
	{capture = "function", role = .Function, precedence = 110},
	{capture = "function.builtin", role = .Function_Builtin, precedence = 120},
	{capture = "keyword", role = .Keyword, precedence = 100},
	{capture = "number", role = .Number, precedence = 100},
	{capture = "operator", role = .Operator, precedence = 100},
	{capture = "punctuation.bracket", role = .Punctuation, precedence = 100},
	{capture = "string", role = .String, precedence = 100},
	{capture = "string.special", role = .String, precedence = 110},
	{capture = "variable", role = .Variable, precedence = 100},
	{capture = "variable.builtin", role = .Variable, precedence = 120},
	{capture = "variable.parameter", role = .Variable_Parameter, precedence = 120},
}

@(private)
RUST_FACTORY_CAPTURE_MAPPINGS := [?]Syntax_Capture_Mapping_Proposal {
	{capture = "attribute", role = .Attribute, precedence = 100},
	{capture = "comment", role = .Comment, precedence = 100},
	{capture = "constant", role = .Constant, precedence = 100},
	{capture = "constant.builtin", role = .Constant, precedence = 120},
	{capture = "constructor", role = .Constructor, precedence = 110},
	{capture = "escape", role = .String, precedence = 120},
	{capture = "function", role = .Function, precedence = 110},
	{capture = "function.macro", role = .Function, precedence = 120},
	{capture = "function.method", role = .Function, precedence = 120},
	{capture = "keyword", role = .Keyword, precedence = 100},
	{capture = "label", role = .Label, precedence = 100},
	{capture = "operator", role = .Operator, precedence = 100},
	{capture = "property", role = .Variable, precedence = 110},
	{capture = "punctuation.bracket", role = .Punctuation, precedence = 100},
	{capture = "punctuation.delimiter", role = .Punctuation, precedence = 100},
	{capture = "string", role = .String, precedence = 100},
	{capture = "type", role = .Type, precedence = 100},
	{capture = "type.builtin", role = .Type, precedence = 120},
	{capture = "variable.builtin", role = .Variable, precedence = 120},
	{capture = "variable.parameter", role = .Variable_Parameter, precedence = 120},
	{
		capture = "structure.declaration",
		role = .Type,
		structural_role = .Declaration,
		precedence = 10,
	},
	{
		capture = "structure.definition",
		role = .Function,
		structural_role = .Definition,
		precedence = 10,
	},
	{
		capture = "structure.name",
		role = .Variable,
		structural_role = .Name,
		precedence = 20,
	},
	{
		capture = "structure.reference",
		role = .Variable,
		structural_role = .Reference,
		precedence = 10,
	},
}

@(private)
JAVASCRIPT_FACTORY_CAPTURE_MAPPINGS := [?]Syntax_Capture_Mapping_Proposal {
	{capture = "attribute", role = .Attribute, precedence = 110},
	{capture = "comment", role = .Comment, precedence = 100},
	{capture = "constant", role = .Constant, precedence = 100},
	{capture = "constant.builtin", role = .Constant, precedence = 120},
	{capture = "constructor", role = .Constructor, precedence = 110},
	{capture = "embedded", role = .String, precedence = 90},
	{capture = "function", role = .Function, precedence = 110},
	{capture = "function.builtin", role = .Function_Builtin, precedence = 120},
	{capture = "function.method", role = .Function, precedence = 120},
	{capture = "keyword", role = .Keyword, precedence = 100},
	{capture = "number", role = .Number, precedence = 100},
	{capture = "operator", role = .Operator, precedence = 100},
	{capture = "property", role = .Variable, precedence = 110},
	{capture = "punctuation.bracket", role = .Punctuation, precedence = 100},
	{capture = "punctuation.delimiter", role = .Punctuation, precedence = 100},
	{capture = "punctuation.special", role = .Punctuation, precedence = 110},
	{capture = "string", role = .String, precedence = 100},
	{capture = "string.special", role = .String, precedence = 110},
	{capture = "tag", role = .Type, precedence = 110},
	{capture = "variable", role = .Variable, precedence = 100},
	{capture = "variable.builtin", role = .Variable, precedence = 120},
}

@(private)
TYPESCRIPT_FACTORY_CAPTURE_MAPPINGS := [?]Syntax_Capture_Mapping_Proposal {
	{capture = "attribute", role = .Attribute, precedence = 110},
	{capture = "comment", role = .Comment, precedence = 100},
	{capture = "constant", role = .Constant, precedence = 100},
	{capture = "constant.builtin", role = .Constant, precedence = 120},
	{capture = "constructor", role = .Constructor, precedence = 110},
	{capture = "embedded", role = .String, precedence = 90},
	{capture = "function", role = .Function, precedence = 110},
	{capture = "function.builtin", role = .Function_Builtin, precedence = 120},
	{capture = "function.method", role = .Function, precedence = 120},
	{capture = "keyword", role = .Keyword, precedence = 100},
	{capture = "number", role = .Number, precedence = 100},
	{capture = "operator", role = .Operator, precedence = 100},
	{capture = "property", role = .Variable, precedence = 110},
	{capture = "punctuation.bracket", role = .Punctuation, precedence = 100},
	{capture = "punctuation.delimiter", role = .Punctuation, precedence = 100},
	{capture = "punctuation.special", role = .Punctuation, precedence = 110},
	{capture = "string", role = .String, precedence = 100},
	{capture = "string.special", role = .String, precedence = 110},
	{capture = "tag", role = .Type, precedence = 110},
	{capture = "type", role = .Type, precedence = 100},
	{capture = "type.builtin", role = .Type, precedence = 120},
	{capture = "variable", role = .Variable, precedence = 100},
	{capture = "variable.builtin", role = .Variable, precedence = 120},
	{capture = "variable.parameter", role = .Variable_Parameter, precedence = 120},
}

@(private)
HTML_FACTORY_CAPTURE_MAPPINGS := [?]Syntax_Capture_Mapping_Proposal {
	{capture = "attribute", role = .Attribute, precedence = 110},
	{capture = "comment", role = .Comment, precedence = 100},
	{capture = "constant", role = .Constant, precedence = 100},
	{capture = "punctuation.bracket", role = .Punctuation, precedence = 100},
	{capture = "string", role = .String, precedence = 100},
	{capture = "tag", role = .Type, precedence = 110},
	{capture = "tag.error", role = .Type, precedence = 120},
	{capture = "injection.javascript", role = .String, precedence = 200},
	{capture = "injection.css", role = .String, precedence = 190},
}

@(private)
CSS_FACTORY_CAPTURE_MAPPINGS := [?]Syntax_Capture_Mapping_Proposal {
	{capture = "attribute", role = .Attribute, precedence = 110},
	{capture = "charset", role = .Keyword, precedence = 110},
	{capture = "comment", role = .Comment, precedence = 100},
	{capture = "function", role = .Function, precedence = 110},
	{capture = "import", role = .Keyword, precedence = 110},
	{capture = "keyframes", role = .Keyword, precedence = 110},
	{capture = "keyword", role = .Keyword, precedence = 100},
	{capture = "media", role = .Keyword, precedence = 110},
	{capture = "namespace", role = .Type, precedence = 110},
	{capture = "number", role = .Number, precedence = 100},
	{capture = "operator", role = .Operator, precedence = 100},
	{capture = "property", role = .Variable, precedence = 110},
	{capture = "punctuation.bracket", role = .Punctuation, precedence = 100},
	{capture = "punctuation.delimiter", role = .Punctuation, precedence = 100},
	{capture = "string", role = .String, precedence = 100},
	{capture = "string.special", role = .String, precedence = 110},
	{capture = "supports", role = .Keyword, precedence = 110},
	{capture = "tag", role = .Type, precedence = 110},
	{capture = "type", role = .Type, precedence = 100},
	{capture = "variable", role = .Variable, precedence = 100},
}

/* tree_sitter_owner_compile_factory_query selects embedded data by bundle identity. */
tree_sitter_owner_compile_factory_query :: proc(
	owner: ^Tree_Sitter_Owner,
	bundle_identity: string,
	generation: Query_Generation,
) -> (ok: bool, failure: Failure) {
	switch bundle_identity {
	case FACTORY_ODIN_BUNDLE_IDENTITY:
		return tree_sitter_owner_compile_odin_query(owner, generation)
	case FACTORY_GO_BUNDLE_IDENTITY:
		query := transmute([]u8)(string(GO_FACTORY_HIGHLIGHT_QUERY))
		return tree_sitter_owner_compile_mapped_query(
			owner, query, GO_FACTORY_CAPTURE_MAPPINGS[:], generation,
		)
	case FACTORY_RACKET_BUNDLE_IDENTITY:
		query := transmute([]u8)(string(RACKET_FACTORY_HIGHLIGHT_QUERY))
		return tree_sitter_owner_compile_mapped_query(
			owner, query, RACKET_FACTORY_CAPTURE_MAPPINGS[:], generation,
		)
	case FACTORY_RUST_BUNDLE_IDENTITY:
		query := transmute([]u8)(string(RUST_FACTORY_SYNTAX_QUERY))
		return tree_sitter_owner_compile_mapped_query(
			owner, query, RUST_FACTORY_CAPTURE_MAPPINGS[:], generation,
		)
	case FACTORY_JAVASCRIPT_BUNDLE_IDENTITY:
		query := transmute([]u8)(string(JAVASCRIPT_FACTORY_HIGHLIGHT_QUERY))
		return tree_sitter_owner_compile_mapped_query(owner, query, JAVASCRIPT_FACTORY_CAPTURE_MAPPINGS[:], generation)
	case FACTORY_JAVASCRIPT_JSX_IDENTITY:
		query := transmute([]u8)(string(JAVASCRIPT_JSX_FACTORY_HIGHLIGHT_QUERY))
		return tree_sitter_owner_compile_mapped_query(owner, query, JAVASCRIPT_FACTORY_CAPTURE_MAPPINGS[:], generation)
	case FACTORY_TYPESCRIPT_BUNDLE_IDENTITY:
		query := transmute([]u8)(string(TYPESCRIPT_FACTORY_HIGHLIGHT_QUERY))
		return tree_sitter_owner_compile_mapped_query(owner, query, TYPESCRIPT_FACTORY_CAPTURE_MAPPINGS[:], generation)
	case FACTORY_TYPESCRIPT_TSX_IDENTITY:
		query := transmute([]u8)(string(TYPESCRIPT_TSX_FACTORY_HIGHLIGHT_QUERY))
		return tree_sitter_owner_compile_mapped_query(owner, query, TYPESCRIPT_FACTORY_CAPTURE_MAPPINGS[:], generation)
	case FACTORY_HTML_BUNDLE_IDENTITY:
		return tree_sitter_owner_compile_html_queries(owner, generation)
	case FACTORY_CSS_BUNDLE_IDENTITY:
		query := transmute([]u8)(string(CSS_FACTORY_HIGHLIGHT_QUERY))
		return tree_sitter_owner_compile_mapped_query(owner, query, CSS_FACTORY_CAPTURE_MAPPINGS[:], generation)
	}
	return false, tree_sitter_failure(.Compile_Queries, .Invalid_Language)
}

@(private)
tree_sitter_owner_compile_html_queries :: proc(
	owner: ^Tree_Sitter_Owner,
	generation: Query_Generation,
) -> (ok: bool, failure: Failure) {
	highlights := transmute([]u8)(string(HTML_FACTORY_HIGHLIGHT_QUERY))
	injections := transmute([]u8)(string(HTML_FACTORY_INJECTION_QUERY))
	if generation == Query_Generation(0) do return false, tree_sitter_failure(.Compile_Queries, .Generation_Limit)
	record: Syntax_Provider_Record
	record.query_count = 2
	record.queries[0] = {kind = .Highlights, size = u64(len(highlights)), generation = generation}
	record.queries[1] = {kind = .Injections, size = u64(len(injections)), generation = generation}
	record.resources.query_bytes = u64(len(highlights) + len(injections))
	for mapping, index in HTML_FACTORY_CAPTURE_MAPPINGS {
		if !syntax_mapping_proposal_valid(mapping) {
			return false, tree_sitter_failure(.Compile_Queries, .Invalid_Capture_Mapping)
		}
		record.mappings[index] = syntax_mapping_copy(mapping)
	}
	record.mapping_count = u16(len(HTML_FACTORY_CAPTURE_MAPPINGS))
	sources := [?][]u8{highlights, injections}
	return tree_sitter_owner_compile_provider_queries(owner, &record, sources[:])
}
