// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language

/* FACTORY_ODIN_LANGUAGE_ID identifies the maintained Odin language. */
FACTORY_ODIN_LANGUAGE_ID :: Language_ID(1)
/* FACTORY_JAN_LANGUAGE_ID identifies the maintained Jan language. */
FACTORY_JAN_LANGUAGE_ID :: Language_ID(2)
/* FACTORY_RACKET_LANGUAGE_ID identifies the maintained Racket language. */
FACTORY_RACKET_LANGUAGE_ID :: Language_ID(3)
/* FACTORY_GO_LANGUAGE_ID identifies the maintained Go language. */
FACTORY_GO_LANGUAGE_ID :: Language_ID(4)
/* FACTORY_RUST_LANGUAGE_ID identifies the maintained Rust language. */
FACTORY_RUST_LANGUAGE_ID :: Language_ID(5)
/* FACTORY_JAVASCRIPT_LANGUAGE_ID identifies the maintained JavaScript language. */
FACTORY_JAVASCRIPT_LANGUAGE_ID :: Language_ID(6)
/* FACTORY_TYPESCRIPT_LANGUAGE_ID identifies the maintained TypeScript language. */
FACTORY_TYPESCRIPT_LANGUAGE_ID :: Language_ID(7)
/* FACTORY_HTML_LANGUAGE_ID identifies the maintained HTML language. */
FACTORY_HTML_LANGUAGE_ID :: Language_ID(8)
/* FACTORY_CSS_LANGUAGE_ID identifies the maintained CSS language. */
FACTORY_CSS_LANGUAGE_ID :: Language_ID(9)
/* FACTORY_LANGUAGE_GENERATION identifies the initial factory contracts. */
FACTORY_LANGUAGE_GENERATION :: Language_Generation(1)
/* FACTORY_ODIN_BUNDLE_IDENTITY identifies the maintained Odin bundle. */
FACTORY_ODIN_BUNDLE_IDENTITY :: "org.odra.odin"
/* FACTORY_JAN_BUNDLE_IDENTITY identifies the maintained Jan bundle. */
FACTORY_JAN_BUNDLE_IDENTITY :: "org.odra.jan"
/* FACTORY_RACKET_BUNDLE_IDENTITY identifies the maintained Racket bundle. */
FACTORY_RACKET_BUNDLE_IDENTITY :: "org.odra.racket"
/* FACTORY_GO_BUNDLE_IDENTITY identifies the maintained Go bundle. */
FACTORY_GO_BUNDLE_IDENTITY :: "org.odra.go"
/* FACTORY_RUST_BUNDLE_IDENTITY identifies the maintained Rust bundle. */
FACTORY_RUST_BUNDLE_IDENTITY :: "org.odra.rust"
/* FACTORY_JAVASCRIPT_BUNDLE_IDENTITY identifies the maintained JavaScript bundle. */
FACTORY_JAVASCRIPT_BUNDLE_IDENTITY :: "org.odra.javascript"
/* FACTORY_JAVASCRIPT_JSX_IDENTITY identifies the JSX grammar variant. */
FACTORY_JAVASCRIPT_JSX_IDENTITY :: "org.odra.javascript.jsx"
/* FACTORY_TYPESCRIPT_BUNDLE_IDENTITY identifies the maintained TypeScript bundle. */
FACTORY_TYPESCRIPT_BUNDLE_IDENTITY :: "org.odra.typescript"
/* FACTORY_TYPESCRIPT_TSX_IDENTITY identifies the TSX grammar variant. */
FACTORY_TYPESCRIPT_TSX_IDENTITY :: "org.odra.typescript.tsx"
/* FACTORY_HTML_BUNDLE_IDENTITY identifies the maintained HTML bundle. */
FACTORY_HTML_BUNDLE_IDENTITY :: "org.odra.html"
/* FACTORY_CSS_BUNDLE_IDENTITY identifies the maintained CSS bundle. */
FACTORY_CSS_BUNDLE_IDENTITY :: "org.odra.css"
/* FACTORY_SYNTAX_BUNDLE_COUNT bounds maintained visible-language registrations. */
FACTORY_SYNTAX_BUNDLE_COUNT :: 9

/* Factory_Bundle_Registration copies one complete maintained bundle contract. */
Factory_Bundle_Registration :: struct {
	bundle_identity:   string,
	language:          Language_Identity,
	provider:          Provider_Definition,
	jan_baseline:      Jan_Baseline_Identity,
	jan_configuration: Jan_Configuration,
}

/* factory_bundle_catalog_confirm publishes maintained identity data without providers. */
factory_bundle_catalog_confirm :: proc(
	catalog: ^Language_Catalog,
) -> (inspection: Language_Catalog_Inspection, ok: bool, failure: Language_Catalog_Failure) {
	odin_suffixes := [?]string{".odin"}
	jan_suffixes := [?]string{".org", ".jan"}
	racket_suffixes := [?]string{".rkt"}
	go_suffixes := [?]string{".go"}
	rust_suffixes := [?]string{".rs"}
	javascript_suffixes := [?]string{".js", ".jsx", ".mjs", ".cjs"}
	typescript_suffixes := [?]string{".ts", ".tsx", ".mts", ".cts"}
	html_suffixes := [?]string{".html", ".htm"}
	css_suffixes := [?]string{".css"}
	definitions := [?]Language_Definition_Candidate {
		{
			language_id = FACTORY_ODIN_LANGUAGE_ID,
			identity = "odin",
			display_name = "Odin",
			source = .Factory,
			source_generation = 1,
			suffixes = odin_suffixes[:],
			provenance = "Odra factory",
		},
		{
			language_id = FACTORY_JAN_LANGUAGE_ID,
			identity = "jan",
			display_name = "Jan",
			source = .Factory,
			source_generation = 1,
			suffixes = jan_suffixes[:],
			provenance = "Odra factory; jan-org-9.8.10-v1",
		},
		{
			language_id = FACTORY_RACKET_LANGUAGE_ID,
			identity = "racket",
			display_name = "Racket",
			source = .Factory,
			source_generation = 1,
			suffixes = racket_suffixes[:],
			provenance = "Odra factory",
		},
		{
			language_id = FACTORY_GO_LANGUAGE_ID,
			identity = "go",
			display_name = "Go",
			source = .Factory,
			source_generation = 1,
			suffixes = go_suffixes[:],
			provenance = "Odra factory",
		},
		{
			language_id = FACTORY_RUST_LANGUAGE_ID,
			identity = "rust",
			display_name = "Rust",
			source = .Factory,
			source_generation = 1,
			suffixes = rust_suffixes[:],
			provenance = "Odra factory",
		},
		{
			language_id = FACTORY_JAVASCRIPT_LANGUAGE_ID,
			identity = "javascript",
			display_name = "JavaScript",
			source = .Factory,
			source_generation = 1,
			suffixes = javascript_suffixes[:],
			provenance = "Odra factory",
		},
		{
			language_id = FACTORY_TYPESCRIPT_LANGUAGE_ID,
			identity = "typescript",
			display_name = "TypeScript",
			source = .Factory,
			source_generation = 1,
			suffixes = typescript_suffixes[:],
			provenance = "Odra factory",
		},
		{
			language_id = FACTORY_HTML_LANGUAGE_ID,
			identity = "html",
			display_name = "HTML",
			source = .Factory,
			source_generation = 1,
			suffixes = html_suffixes[:],
			provenance = "Odra factory",
		},
		{
			language_id = FACTORY_CSS_LANGUAGE_ID,
			identity = "css",
			display_name = "CSS",
			source = .Factory,
			source_generation = 1,
			suffixes = css_suffixes[:],
			provenance = "Odra factory",
		},
	}
	return language_catalog_confirm(
		catalog,
		0,
		Language_Catalog_Candidate {
			generation = 1,
			definitions = definitions[:],
		},
	)
}

/* factory_bundle_registration resolves one maintained contract by stable bundle identity. */
factory_bundle_registration :: proc(
	bundle_identity: string,
) -> (registration: Factory_Bundle_Registration, ok: bool) {
	switch bundle_identity {
	case FACTORY_ODIN_BUNDLE_IDENTITY:
		return Factory_Bundle_Registration {
			bundle_identity = FACTORY_ODIN_BUNDLE_IDENTITY,
			language = factory_bundle_language_identity(FACTORY_ODIN_LANGUAGE_ID, "odin"),
			provider = {
				name = "factory-odin-tree-sitter",
				parser_name = "tree-sitter-odin",
				grammar_abi = TREE_SITTER_ODIN_ABI,
				capabilities = {
					.Initial_Parse,
					.Incremental_Parse,
					.Visible_Query,
					.Syntax_Roles,
					.Structural_Syntax,
					.Symbols,
				},
				provenance = "tree-sitter v0.26.12; tree-sitter-odin v1.3.0",
			},
		}, true
	case FACTORY_JAN_BUNDLE_IDENTITY:
		return Factory_Bundle_Registration {
			bundle_identity = FACTORY_JAN_BUNDLE_IDENTITY,
			language = factory_bundle_language_identity(FACTORY_JAN_LANGUAGE_ID, "jan"),
			provider = {
				name = "factory-jan-tree-sitter",
				parser_name = "tree-sitter-jan",
				grammar_abi = TREE_SITTER_JAN_ABI,
				capabilities = {
					.Initial_Parse,
					.Incremental_Parse,
					.Visible_Query,
					.Syntax_Roles,
					.Structural_Syntax,
				},
				provenance = "tree-sitter v0.26.12; jan-org-9.8.10-v1",
			},
			jan_baseline = jan_factory_baseline(),
			jan_configuration = jan_factory_configuration(1),
		}, true
	case FACTORY_RACKET_BUNDLE_IDENTITY:
		return Factory_Bundle_Registration {
			bundle_identity = FACTORY_RACKET_BUNDLE_IDENTITY,
			language = factory_bundle_language_identity(FACTORY_RACKET_LANGUAGE_ID, "racket"),
			provider = {
				name = "factory-racket-tree-sitter",
				parser_name = "tree-sitter-racket",
				grammar_abi = TREE_SITTER_RACKET_ABI,
				capabilities = {
					.Initial_Parse,
					.Incremental_Parse,
					.Visible_Query,
					.Syntax_Roles,
				},
				provenance = "tree-sitter v0.26.12; tree-sitter-racket v0.25.0; default readtable",
			},
		}, true
	case FACTORY_GO_BUNDLE_IDENTITY:
		return Factory_Bundle_Registration {
			bundle_identity = FACTORY_GO_BUNDLE_IDENTITY,
			language = factory_bundle_language_identity(FACTORY_GO_LANGUAGE_ID, "go"),
			provider = {
				name = "factory-go-tree-sitter",
				parser_name = "tree-sitter-go",
				grammar_abi = TREE_SITTER_GO_ABI,
				capabilities = {
					.Initial_Parse,
					.Incremental_Parse,
					.Visible_Query,
					.Syntax_Roles,
				},
				provenance = "tree-sitter v0.26.12; tree-sitter-go v0.25.0",
			},
		}, true
	case FACTORY_RUST_BUNDLE_IDENTITY:
		return Factory_Bundle_Registration {
			bundle_identity = FACTORY_RUST_BUNDLE_IDENTITY,
			language = factory_bundle_language_identity(FACTORY_RUST_LANGUAGE_ID, "rust"),
			provider = {
				name = "factory-rust-tree-sitter",
				parser_name = "tree-sitter-rust",
				grammar_abi = TREE_SITTER_RUST_ABI,
				capabilities = {
					.Initial_Parse,
					.Incremental_Parse,
					.Visible_Query,
					.Syntax_Roles,
					.Structural_Syntax,
					.Symbols,
				},
				provenance = "tree-sitter v0.26.12; tree-sitter-rust v0.24.2",
			},
		}, true
	case FACTORY_JAVASCRIPT_BUNDLE_IDENTITY, FACTORY_JAVASCRIPT_JSX_IDENTITY:
		jsx := bundle_identity == FACTORY_JAVASCRIPT_JSX_IDENTITY
		parser_name := "tree-sitter-javascript"
		provider_name := "factory-javascript-tree-sitter"
		if jsx {
			parser_name = "tree-sitter-javascript-jsx"
			provider_name = "factory-javascript-jsx-tree-sitter"
		}
		return Factory_Bundle_Registration {
			bundle_identity = bundle_identity,
			language = factory_bundle_language_identity(FACTORY_JAVASCRIPT_LANGUAGE_ID, "javascript"),
			provider = {
				name = provider_name,
				parser_name = parser_name,
				grammar_abi = TREE_SITTER_JAVASCRIPT_ABI,
				capabilities = {.Initial_Parse, .Incremental_Parse, .Visible_Query, .Syntax_Roles},
				provenance = "tree-sitter v0.26.12; tree-sitter-javascript v0.25.0",
			},
		}, true
	case FACTORY_TYPESCRIPT_BUNDLE_IDENTITY, FACTORY_TYPESCRIPT_TSX_IDENTITY:
		tsx := bundle_identity == FACTORY_TYPESCRIPT_TSX_IDENTITY
		parser_name := "tree-sitter-typescript"
		provider_name := "factory-typescript-tree-sitter"
		if tsx {
			parser_name = "tree-sitter-tsx"
			provider_name = "factory-typescript-tsx-tree-sitter"
		}
		return Factory_Bundle_Registration {
			bundle_identity = bundle_identity,
			language = factory_bundle_language_identity(FACTORY_TYPESCRIPT_LANGUAGE_ID, "typescript"),
			provider = {
				name = provider_name,
				parser_name = parser_name,
				grammar_abi = TREE_SITTER_TYPESCRIPT_ABI,
				capabilities = {.Initial_Parse, .Incremental_Parse, .Visible_Query, .Syntax_Roles},
				provenance = "tree-sitter v0.26.12; tree-sitter-typescript v0.23.2",
			},
		}, true
	case FACTORY_HTML_BUNDLE_IDENTITY:
		return Factory_Bundle_Registration {
			bundle_identity = bundle_identity,
			language = factory_bundle_language_identity(FACTORY_HTML_LANGUAGE_ID, "html"),
			provider = {
				name = "factory-html-tree-sitter",
				parser_name = "tree-sitter-html",
				grammar_abi = TREE_SITTER_HTML_ABI,
				capabilities = {.Initial_Parse, .Incremental_Parse, .Visible_Query, .Syntax_Roles},
				provenance = "tree-sitter v0.26.12; tree-sitter-html v0.23.2",
			},
		}, true
	case FACTORY_CSS_BUNDLE_IDENTITY:
		return Factory_Bundle_Registration {
			bundle_identity = bundle_identity,
			language = factory_bundle_language_identity(FACTORY_CSS_LANGUAGE_ID, "css"),
			provider = {
				name = "factory-css-tree-sitter",
				parser_name = "tree-sitter-css",
				grammar_abi = TREE_SITTER_CSS_ABI,
				capabilities = {.Initial_Parse, .Incremental_Parse, .Visible_Query, .Syntax_Roles},
				provenance = "tree-sitter v0.26.12; tree-sitter-css v0.25.0",
			},
		}, true
	}
	return {}, false
}

/* factory_syntax_bundle_registrations returns the stable maintained syntax set. */
factory_syntax_bundle_registrations :: proc() -> (
	registrations: [FACTORY_SYNTAX_BUNDLE_COUNT]Factory_Bundle_Registration,
	ok: bool,
) {
	odin, odin_ok := factory_bundle_registration(FACTORY_ODIN_BUNDLE_IDENTITY)
	jan, jan_ok := factory_bundle_registration(FACTORY_JAN_BUNDLE_IDENTITY)
	racket, racket_ok := factory_bundle_registration(FACTORY_RACKET_BUNDLE_IDENTITY)
	go_registration, go_ok := factory_bundle_registration(FACTORY_GO_BUNDLE_IDENTITY)
	rust, rust_ok := factory_bundle_registration(FACTORY_RUST_BUNDLE_IDENTITY)
	javascript, javascript_ok := factory_bundle_registration(FACTORY_JAVASCRIPT_BUNDLE_IDENTITY)
	typescript, typescript_ok := factory_bundle_registration(FACTORY_TYPESCRIPT_BUNDLE_IDENTITY)
	html, html_ok := factory_bundle_registration(FACTORY_HTML_BUNDLE_IDENTITY)
	css, css_ok := factory_bundle_registration(FACTORY_CSS_BUNDLE_IDENTITY)
	if !odin_ok || !jan_ok || !racket_ok || !go_ok || !rust_ok ||
	   !javascript_ok || !typescript_ok || !html_ok || !css_ok {
		return {}, false
	}
	registrations = {odin, jan, racket, go_registration, rust, javascript, typescript, html, css}
	return registrations, true
}

/* factory_syntax_identity_for_selector resolves grammar variants without changing language identity. */
factory_syntax_identity_for_selector :: proc(
	language_id: Language_ID,
	selector: string,
) -> (bundle_identity: string, ok: bool) {
	switch language_id {
	case FACTORY_JAVASCRIPT_LANGUAGE_ID:
		if selector == ".jsx" do return FACTORY_JAVASCRIPT_JSX_IDENTITY, true
		return FACTORY_JAVASCRIPT_BUNDLE_IDENTITY, true
	case FACTORY_TYPESCRIPT_LANGUAGE_ID:
		if selector == ".tsx" do return FACTORY_TYPESCRIPT_TSX_IDENTITY, true
		return FACTORY_TYPESCRIPT_BUNDLE_IDENTITY, true
	case FACTORY_ODIN_LANGUAGE_ID:
		return FACTORY_ODIN_BUNDLE_IDENTITY, true
	case FACTORY_JAN_LANGUAGE_ID:
		return FACTORY_JAN_BUNDLE_IDENTITY, true
	case FACTORY_RACKET_LANGUAGE_ID:
		return FACTORY_RACKET_BUNDLE_IDENTITY, true
	case FACTORY_GO_LANGUAGE_ID:
		return FACTORY_GO_BUNDLE_IDENTITY, true
	case FACTORY_RUST_LANGUAGE_ID:
		return FACTORY_RUST_BUNDLE_IDENTITY, true
	case FACTORY_HTML_LANGUAGE_ID:
		return FACTORY_HTML_BUNDLE_IDENTITY, true
	case FACTORY_CSS_LANGUAGE_ID:
		return FACTORY_CSS_BUNDLE_IDENTITY, true
	}
	return "", false
}

@(private)
factory_bundle_language_identity :: proc(id: Language_ID, name: string) -> Language_Identity {
	identity: Language_Identity
	identity.id = id
	identity.generation = FACTORY_LANGUAGE_GENERATION
	identity.name.length = u16(copy(identity.name.bytes[:], name))
	return identity
}
