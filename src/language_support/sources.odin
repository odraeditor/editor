// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package language_support owns declarative language-support source admission.
package language_support

import "../language"
import "../language_service"
import "../extension"
import "base:runtime"
import json "core:encoding/json"
import "core:strings"
import "core:unicode/utf8"

FACTORY_LANGUAGE_SUPPORT_CONFIGURATION :: `{"languages":[{"display-name":"Odin","filenames":[],"id":"odin","suffixes":[".odin"]},{"display-name":"Jan","filenames":[],"id":"jan","suffixes":[".org",".jan"]},{"display-name":"Racket","filenames":[],"id":"racket","suffixes":[".rkt"]},{"display-name":"Go","filenames":[],"id":"go","suffixes":[".go"]},{"display-name":"Rust","filenames":[],"id":"rust","suffixes":[".rs"]},{"display-name":"JavaScript","filenames":[],"id":"javascript","suffixes":[".js",".jsx",".mjs",".cjs"]},{"display-name":"TypeScript","filenames":[],"id":"typescript","suffixes":[".ts",".tsx",".mts",".cts"]},{"display-name":"HTML","filenames":[],"id":"html","suffixes":[".html",".htm"]},{"display-name":"CSS","filenames":[],"id":"css","suffixes":[".css"]}],"schema":1,"selections":[],"services":[{"command":["ols"],"default":true,"display-name":"OLS","enabled":true,"environment":[],"features":["diagnostics","completion"],"id":"ols","initialization-options":{},"languages":["odin"],"root-markers":["ols.json"],"settings":{}},{"command":["racket","-l","racket-langserver"],"default":true,"display-name":"Racket Language Server","enabled":true,"environment":[],"features":["diagnostics","completion","navigation","hover","references","symbols","signature-help","rename","formatting","semantic-tokens","code-actions"],"id":"racket-langserver","initialization-options":{},"languages":["racket"],"root-markers":["info.rkt"],"settings":{}},{"command":["gopls","serve"],"default":true,"display-name":"gopls","enabled":true,"environment":[],"features":["diagnostics","completion","navigation","hover","references","symbols","signature-help","rename","formatting","semantic-tokens","code-actions"],"id":"gopls","initialization-options":{},"languages":["go"],"root-markers":["go.work","go.mod"],"settings":{}},{"command":["rust-analyzer"],"default":true,"display-name":"rust-analyzer","enabled":true,"environment":[],"features":["diagnostics","completion","navigation","hover","references","symbols","signature-help","rename","formatting","semantic-tokens","code-actions"],"id":"rust-analyzer","initialization-options":{},"languages":["rust"],"root-markers":["Cargo.toml"],"settings":{}},{"command":["typescript-language-server","--stdio"],"default":true,"display-name":"TypeScript Language Server","enabled":true,"environment":[],"features":["diagnostics","completion","navigation","hover","references","symbols","signature-help","rename","formatting","semantic-tokens","code-actions"],"id":"typescript-language-server","initialization-options":{},"languages":["javascript","typescript"],"root-markers":["tsconfig.json","jsconfig.json","package.json"],"settings":{}},{"command":["vscode-html-language-server","--stdio"],"default":true,"display-name":"HTML Language Server","enabled":true,"environment":[],"features":["diagnostics","completion","hover","symbols","formatting"],"id":"vscode-html-language-server","initialization-options":{},"languages":["html"],"root-markers":["package.json"],"settings":{}},{"command":["vscode-css-language-server","--stdio"],"default":true,"display-name":"CSS Language Server","enabled":true,"environment":[],"features":["diagnostics","completion","hover","symbols","formatting"],"id":"vscode-css-language-server","initialization-options":{},"languages":["css"],"root-markers":["package.json"],"settings":{}}]}`

// EMPTY_LANGUAGE_SUPPORT_CONFIGURATION is the canonical complete empty source.
EMPTY_LANGUAGE_SUPPORT_CONFIGURATION :: `{"languages":[],"schema":1,"selections":[],"services":[]}`

@(private)
MAX_LANGUAGE_SUPPORT_SOURCE_PROVENANCE_BYTES :: 256

Language_Support_Source_Descriptor :: struct {
	source:     language_service.Service_Contribution_Source,
	scope_kind: language_service.Service_Scope_Kind,
	scope:      string,
	generation: language_service.Service_Source_Generation,
	trusted:    bool,
	provenance: string,
	executable_artifact: string,
}

Language_Support_Source_Candidate :: struct {
	descriptor: Language_Support_Source_Descriptor,
	value:      json.Value,
	allocator:  runtime.Allocator,
	live:       bool,
}

Language_Support_Language_View :: struct {
	identity:             string,
	display_name:         string,
	exact_filenames:      [language.MAX_LANGUAGE_EXACT_FILENAMES]string,
	exact_filename_count: u8,
	suffixes:             [language.MAX_LANGUAGE_SUFFIXES]string,
	suffix_count:         u8,
	source:               language_service.Service_Contribution_Source,
	scope:                string,
	source_generation:    language_service.Service_Source_Generation,
	provenance:           string,
}

Language_Support_Environment_View :: struct {
	key:   string,
	value: string,
}

Language_Support_Service_View :: struct {
	identity:          string,
	display_name:      string,
	languages:         [language_service.MAX_LANGUAGE_IDENTITIES]string,
	language_count:    u8,
	command:           [language_service.DEFAULT_LIMITS.arguments]string,
	command_count:     u8,
	root_markers:      [MAX_ROOT_MARKERS]string,
	root_marker_count: u8,
	initialization_options: json.Value,
	settings:               json.Value,
	environment: [language_service.DEFAULT_LIMITS.environment_entries]Language_Support_Environment_View,
	environment_count: u8,
	features:          [MAX_FEATURES]language_service.Service_Feature,
	feature_count:     u8,
	enabled:           bool,
	default_selection: bool,
	source:            language_service.Service_Contribution_Source,
	scope_kind:        language_service.Service_Scope_Kind,
	scope:             string,
	source_generation: language_service.Service_Source_Generation,
	provenance:        string,
	package_artifact:  string,
}

Language_Support_Selection_View :: struct {
	language_identity: string,
	service_identity:  string,
	source:            language_service.Service_Contribution_Source,
	scope_kind:        language_service.Service_Scope_Kind,
	scope:             string,
	source_generation: language_service.Service_Source_Generation,
}

factory_source_prepare :: proc(
	allocator := context.allocator,
) -> (Language_Support_Source_Candidate, bool) {
	return source_prepare(
		transmute([]u8)(string(FACTORY_LANGUAGE_SUPPORT_CONFIGURATION)),
		.Factory,
		.Global,
		"",
		1,
		true,
		"Odra maintained language support",
		allocator,
	)
}

personal_source_prepare :: proc(
	input: []u8,
	generation: u64,
	allocator := context.allocator,
) -> (Language_Support_Source_Candidate, bool) {
	return source_prepare(
		input,
		.Personal,
		.Global,
		"",
		language_service.Service_Source_Generation(generation),
		true,
		"Personal init.rkt",
		allocator,
	)
}

project_source_prepare :: proc(
	input: []u8,
	membership: string,
	generation: u64,
	trusted: bool,
	allocator := context.allocator,
) -> (Language_Support_Source_Candidate, bool) {
	return source_prepare(
		input,
		.Project,
		.Project_Membership,
		membership,
		language_service.Service_Source_Generation(generation),
		trusted,
		"Trusted Project language support",
		allocator,
	)
}

package_fixture_prepare :: proc(
	input: []u8,
	package_identity: string,
	generation: u64,
	allocator := context.allocator,
) -> (Language_Support_Source_Candidate, bool) {
	return source_prepare(
		input,
		.Package,
		.Package,
		package_identity,
		language_service.Service_Source_Generation(generation),
		true,
		"Deterministic package fixture",
		allocator,
	)
}

/* package_source_prepare admits one activated package through its validated manifest. */
package_source_prepare :: proc(
	contribution: ^extension.Package_Language_Support_Candidate,
	allocator := context.allocator,
) -> (candidate: Language_Support_Source_Candidate, ok: bool) {
	discovery, discovered := extension.package_language_support_discovery(contribution)
	if !discovered do return {}, false
	identity := extension.package_identity_text_view(&discovery.package_identity)
	provenance := extension.package_provenance_text_view(&discovery.provenance)
	candidate, ok = source_prepare(
		contribution.payload,
		.Package,
		.Package,
		identity,
		language_service.Service_Source_Generation(discovery.generation),
		true,
		provenance,
		allocator,
	)
	if !ok do return {}, false
	if !package_source_manifest_matches(&candidate, &discovery) {
		source_candidate_close(&candidate)
		return {}, false
	}
	artifact := extension.package_executable_artifact_view(&discovery)
	if len(artifact) > 0 {
		candidate.descriptor.executable_artifact, _ = strings.clone(artifact, allocator)
		if candidate.descriptor.executable_artifact == "" {
			source_candidate_close(&candidate)
			return {}, false
		}
	}
	return candidate, true
}

source_prepare :: proc(
	input: []u8,
	source: language_service.Service_Contribution_Source,
	scope_kind: language_service.Service_Scope_Kind,
	scope: string,
	generation: language_service.Service_Source_Generation,
	trusted: bool,
	provenance: string,
	allocator: runtime.Allocator,
) -> (candidate: Language_Support_Source_Candidate, ok: bool) {
	if allocator.procedure == nil || generation == 0 ||
	   !source_scope_valid(source, scope_kind, scope, trusted) ||
	   !text_valid(
		provenance, MAX_LANGUAGE_SUPPORT_SOURCE_PROVENANCE_BYTES, false,
	   ) || !configuration_valid(input) {
		return {}, false
	}
	parsed, parse_error := json.parse_bytes(input, .JSON, true, context.temp_allocator)
	if parse_error != .None {
		return {}, false
	}
	defer json.destroy_value(parsed, context.temp_allocator)
	value, value_ok := source_value_clone(parsed, allocator)
	if !value_ok do return {}, false
	owned_scope, scope_error := strings.clone(scope, allocator)
	if scope_error != nil {
		json.destroy_value(value, allocator)
		return {}, false
	}
	owned_provenance, provenance_error := strings.clone(provenance, allocator)
	if provenance_error != nil {
		delete(owned_scope, allocator)
		json.destroy_value(value, allocator)
		return {}, false
	}
	candidate = {
		descriptor = {
			source = source,
			scope_kind = scope_kind,
			scope = owned_scope,
			generation = generation,
			trusted = trusted,
			provenance = owned_provenance,
		},
		value = value,
		allocator = allocator,
		live = true,
	}
	return candidate, true
}

@(private)
source_value_clone :: proc(
	value: json.Value,
	allocator: runtime.Allocator,
) -> (cloned: json.Value, ok: bool) {
	#partial switch current in value {
	case json.Object:
		object, allocation_error := make(json.Object, len(current), allocator)
		if allocation_error != nil do return {}, false
		for key, element in current {
			owned_key, key_error := strings.clone(key, allocator)
			if key_error != nil {
				json.destroy_value(object, allocator)
				return {}, false
			}
			owned_element, element_ok := source_value_clone(element, allocator)
			if !element_ok {
				delete(owned_key, allocator)
				json.destroy_value(object, allocator)
				return {}, false
			}
			reserve_error := reserve(&object, len(object) + 1)
			if reserve_error != nil {
				delete(owned_key, allocator)
				json.destroy_value(owned_element, allocator)
				json.destroy_value(object, allocator)
				return {}, false
			}
			object[owned_key] = owned_element
		}
		return object, true
	case json.Array:
		array, allocation_error := make(json.Array, len(current), allocator)
		if allocation_error != nil do return {}, false
		for element, index in current {
			owned_element, element_ok := source_value_clone(element, allocator)
			if !element_ok {
				json.destroy_value(array, allocator)
				return {}, false
			}
			array[index] = owned_element
		}
		return array, true
	case json.String:
		owned, allocation_error := strings.clone(string(current), allocator)
		if allocation_error != nil do return {}, false
		return json.String(owned), true
	}
	return value, true
}

source_candidate_close :: proc(
	candidate: ^Language_Support_Source_Candidate,
) -> bool {
	if candidate == nil || !candidate.live || candidate.allocator.procedure == nil {
		return false
	}
	json.destroy_value(candidate.value, candidate.allocator)
	delete(candidate.descriptor.scope, candidate.allocator)
	delete(candidate.descriptor.provenance, candidate.allocator)
	delete(candidate.descriptor.executable_artifact, candidate.allocator)
	candidate^ = {}
	return true
}

source_scope_valid :: proc(
	source: language_service.Service_Contribution_Source,
	scope_kind: language_service.Service_Scope_Kind,
	scope: string,
	trusted: bool,
) -> bool {
	if len(scope) > language_service.MAX_SERVICE_SCOPE_BYTES ||
	   !utf8.valid_string(scope) || strings.index_byte(scope, 0) >= 0 {
		return false
	}
	switch source {
	case .Factory, .Personal:
		return scope_kind == .Global && len(scope) == 0
	case .Package:
		return scope_kind == .Package && len(scope) > 0
	case .Project:
		return scope_kind == .Project_Membership && len(scope) > 0 && trusted
	case .Invalid:
		return false
	}
	return false
}

source_counts :: proc(
	candidate: ^Language_Support_Source_Candidate,
) -> (languages, services, selections: int, ok: bool) {
	root, root_ok := source_root(candidate)
	if !root_ok do return 0, 0, 0, false
	language_values, languages_ok := root["languages"].(json.Array)
	service_values, services_ok := root["services"].(json.Array)
	selection_values, selections_ok := root["selections"].(json.Array)
	if !languages_ok || !services_ok || !selections_ok do return 0, 0, 0, false
	return len(language_values), len(service_values), len(selection_values), true
}

source_language :: proc(
	candidate: ^Language_Support_Source_Candidate,
	index: int,
) -> (view: Language_Support_Language_View, ok: bool) {
	root, root_ok := source_root(candidate)
	if !root_ok do return {}, false
	values, values_ok := root["languages"].(json.Array)
	if !values_ok || index < 0 || index >= len(values) do return {}, false
	value := values[index]
	object, object_ok := value.(json.Object)
	if !object_ok do return {}, false
	identity, identity_ok := object_string(value, "id")
	display_name, display_ok := object_string(value, "display-name")
	filenames, filenames_ok := object["filenames"].(json.Array)
	suffixes, suffixes_ok := object["suffixes"].(json.Array)
	if !identity_ok || !display_ok || !filenames_ok || !suffixes_ok do return {}, false
	view.identity = identity
	view.display_name = display_name
	view.exact_filename_count = u8(len(filenames))
	view.suffix_count = u8(len(suffixes))
	view.source = candidate.descriptor.source
	view.scope = candidate.descriptor.scope
	view.source_generation = candidate.descriptor.generation
	view.provenance = candidate.descriptor.provenance
	for filename, position in filenames {
		text, text_ok := filename.(json.String)
		if !text_ok do return {}, false
		view.exact_filenames[position] = string(text)
	}
	for suffix, position in suffixes {
		text, text_ok := suffix.(json.String)
		if !text_ok do return {}, false
		view.suffixes[position] = string(text)
	}
	return view, true
}

@(private)
package_source_manifest_matches :: proc(
	candidate: ^Language_Support_Source_Candidate,
	discovery: ^extension.Package_Language_Support_Descriptor,
) -> bool {
	if candidate == nil || discovery == nil do return false
	language_count, service_count, selection_count, counted := source_counts(candidate)
	if !counted || selection_count != 0 do return false
	if (language_count > 0) != (.Language in discovery.facets) ||
	   (service_count > 0) != (.Language_Service in discovery.facets) {
		return false
	}
	affected: [extension.MAX_AFFECTED_LANGUAGES]string
	affected_count := 0
	for index in 0 ..< language_count {
		view, viewed := source_language(candidate, index)
		if !viewed || !package_source_collect_identity(&affected, &affected_count, view.identity) {
			return false
		}
	}
	for index in 0 ..< service_count {
		view, viewed := source_service(candidate, index)
		if !viewed do return false
		if .Process not_in discovery.authorities do return false
		if view.environment_count > 0 && .Environment not_in discovery.authorities do return false
		for language in view.languages[:view.language_count] {
			if !package_source_collect_identity(&affected, &affected_count, language) do return false
		}
	}
	if affected_count != int(discovery.affected_language_count) do return false
	for identity in affected[:affected_count] {
		found := false
		for &expected in discovery.affected_languages[:discovery.affected_language_count] {
			if identity == extension.language_identity_text_view(&expected) {
				found = true
				break
			}
		}
		if !found do return false
	}
	return true
}

@(private)
package_source_collect_identity :: proc(
	identities: ^[extension.MAX_AFFECTED_LANGUAGES]string,
	count: ^int,
	identity: string,
) -> bool {
	if identities == nil || count == nil do return false
	for present in identities[:count^] do if present == identity do return true
	if count^ >= len(identities) do return false
	identities[count^] = identity
	count^ += 1
	return true
}

source_service :: proc(
	candidate: ^Language_Support_Source_Candidate,
	index: int,
) -> (view: Language_Support_Service_View, ok: bool) {
	root, root_ok := source_root(candidate)
	if !root_ok do return {}, false
	values, values_ok := root["services"].(json.Array)
	if !values_ok || index < 0 || index >= len(values) do return {}, false
	value := values[index]
	object, object_ok := value.(json.Object)
	if !object_ok do return {}, false
	view.identity, ok = object_string(value, "id")
	if !ok do return {}, false
	view.display_name, ok = object_string(value, "display-name")
	if !ok do return {}, false
	languages, languages_ok := object["languages"].(json.Array)
	command, command_ok := object["command"].(json.Array)
	root_markers, root_markers_ok := object["root-markers"].(json.Array)
	environment, environment_ok := object["environment"].(json.Array)
	features, features_ok := object["features"].(json.Array)
	initialization_options, initialization_ok := object["initialization-options"]
	settings, settings_ok := object["settings"]
	enabled_value, enabled_ok := object["enabled"].(json.Boolean)
	default_value, default_ok := object["default"].(json.Boolean)
	if !languages_ok || !command_ok || !root_markers_ok || !environment_ok ||
	   !features_ok || !initialization_ok || !settings_ok || !enabled_ok || !default_ok {
		return {}, false
	}
	view.language_count = u8(len(languages))
	view.command_count = u8(len(command))
	view.root_marker_count = u8(len(root_markers))
	view.environment_count = u8(len(environment))
	view.feature_count = u8(len(features))
	view.initialization_options = initialization_options
	view.settings = settings
	view.enabled = bool(enabled_value)
	view.default_selection = bool(default_value)
	view.source = candidate.descriptor.source
	view.scope_kind = candidate.descriptor.scope_kind
	view.scope = candidate.descriptor.scope
	view.source_generation = candidate.descriptor.generation
	view.provenance = candidate.descriptor.provenance
	view.package_artifact = candidate.descriptor.executable_artifact
	for entry, position in languages {
		text, text_ok := entry.(json.String)
		if !text_ok do return {}, false
		view.languages[position] = string(text)
	}
	for entry, position in command {
		text, text_ok := entry.(json.String)
		if !text_ok do return {}, false
		view.command[position] = string(text)
	}
	for entry, position in root_markers {
		text, text_ok := entry.(json.String)
		if !text_ok do return {}, false
		view.root_markers[position] = string(text)
	}
	for entry, position in environment {
		view.environment[position].key, ok = object_string(entry, "key")
		if !ok do return {}, false
		view.environment[position].value, ok = object_string(entry, "value")
		if !ok do return {}, false
	}
	for entry, position in features {
		text, text_ok := entry.(json.String)
		if !text_ok do return {}, false
		view.features[position], ok = feature_from_string(string(text))
		if !ok do return {}, false
	}
	return view, true
}

source_selection :: proc(
	candidate: ^Language_Support_Source_Candidate,
	index: int,
) -> (view: Language_Support_Selection_View, ok: bool) {
	root, root_ok := source_root(candidate)
	if !root_ok do return {}, false
	values, values_ok := root["selections"].(json.Array)
	if !values_ok || index < 0 || index >= len(values) do return {}, false
	view.language_identity, ok = object_string(values[index], "language")
	if !ok do return {}, false
	view.service_identity, ok = object_string(values[index], "service")
	if !ok do return {}, false
	view.source = candidate.descriptor.source
	view.scope_kind = candidate.descriptor.scope_kind
	view.scope = candidate.descriptor.scope
	view.source_generation = candidate.descriptor.generation
	return view, true
}

source_root :: proc(
	candidate: ^Language_Support_Source_Candidate,
) -> (json.Object, bool) {
	if candidate == nil || !candidate.live do return nil, false
	return candidate.value.(json.Object)
}

feature_from_string :: proc(value: string) -> (language_service.Service_Feature, bool) {
	switch value {
	case "diagnostics":     return .Diagnostics, true
	case "completion":      return .Completion, true
	case "navigation":      return .Navigation, true
	case "hover":           return .Hover, true
	case "references":      return .References, true
	case "symbols":         return .Symbols, true
	case "signature-help":  return .Signature_Help, true
	case "rename":          return .Rename, true
	case "formatting":      return .Formatting, true
	case "semantic-tokens": return .Semantic_Tokens, true
	case "code-actions":    return .Code_Actions, true
	}
	return {}, false
}
