// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_support

import "../language"
import "../language_service"
import "base:runtime"
import json "core:encoding/json"
import "core:fmt"

/* MAX_RUNTIME_PACKAGE_SOURCES bounds one atomic activated-package generation. */
MAX_RUNTIME_PACKAGE_SOURCES :: 16

/* Runtime_Catalog_Candidate owns one prepared atomic language and service publication. */
Runtime_Catalog_Candidate :: struct {
	language_catalog: language.Language_Catalog,
	service_catalog:  language_service.Service_Catalog,
	new_definitions:  [language_service.MAX_SERVICE_CATALOG_DEFINITIONS]language_service.Definition_Handle,
	new_definition_count: u16,
	retired_definitions: [language_service.MAX_SERVICE_CATALOG_DEFINITIONS]language_service.Definition_Handle,
	retired_definition_count: u16,
	live:      bool,
	published: bool,
}

/* runtime_catalog_prepare validates and copies one complete personal runtime generation. */
runtime_catalog_prepare :: proc(
	language_catalog: ^language.Language_Catalog,
	registry: ^language_service.Provider_Registry,
	service_catalog: ^language_service.Service_Catalog,
	factory_definition: language_service.Definition_Handle,
	input: []u8,
	source_generation: u64,
	allocator := context.allocator,
) -> (candidate: Runtime_Catalog_Candidate, ok: bool) {
	return runtime_catalog_prepare_with_packages(
		language_catalog,
		registry,
		service_catalog,
		factory_definition,
		input,
		source_generation,
		nil,
		allocator,
	)
}

/* runtime_catalog_prepare_with_packages validates one complete source generation. */
runtime_catalog_prepare_with_packages :: proc(
	language_catalog: ^language.Language_Catalog,
	registry: ^language_service.Provider_Registry,
	service_catalog: ^language_service.Service_Catalog,
	factory_definition: language_service.Definition_Handle,
	input: []u8,
	source_generation: u64,
	packages: []^Language_Support_Source_Candidate,
	allocator := context.allocator,
) -> (candidate: Runtime_Catalog_Candidate, ok: bool) {
	if language_catalog == nil || language_catalog.state == nil || registry == nil ||
	   registry.state == nil || service_catalog == nil || service_catalog.state == nil ||
	   factory_definition.id == language_service.Definition_ID(0) ||
	   source_generation == 0 || len(packages) > MAX_RUNTIME_PACKAGE_SOURCES ||
	   allocator.procedure == nil {
		return {}, false
	}
	factory, factory_ok := factory_source_prepare(context.temp_allocator)
	if !factory_ok do return {}, false
	defer source_candidate_close(&factory)
	personal, personal_ok := personal_source_prepare(
		input,
		source_generation,
		context.temp_allocator,
	)
	if !personal_ok do return {}, false
	defer source_candidate_close(&personal)
	source_storage: [MAX_RUNTIME_PACKAGE_SOURCES + 2]^Language_Support_Source_Candidate
	source_storage[0] = &factory
	position := 1
	for contribution in packages {
		if contribution == nil || !contribution.live || contribution.descriptor.source != .Package {
			return {}, false
		}
		source_storage[position] = contribution
		position += 1
	}
	source_storage[position] = &personal
	position += 1
	sources := source_storage[:position]

	if !language_support_workflow_prepare_language_catalog(
		&candidate,
		language_catalog,
		sources,
		allocator,
	) {
		runtime_catalog_candidate_close(&candidate, registry)
		return {}, false
	}
	if !language_support_workflow_prepare_service_catalog(
		&candidate,
		registry,
		service_catalog,
		factory_definition,
		sources,
		allocator,
	) {
		runtime_catalog_candidate_close(&candidate, registry)
		return {}, false
	}
	candidate.live = true
	return candidate, true
}

/* runtime_catalog_publish atomically swaps both prepared catalogs into their owners. */
runtime_catalog_publish :: proc(
	candidate: ^Runtime_Catalog_Candidate,
	language_catalog: ^language.Language_Catalog,
	service_catalog: ^language_service.Service_Catalog,
) -> bool {
	if candidate == nil || !candidate.live || candidate.published ||
	   language_catalog == nil || language_catalog.state == nil ||
	   service_catalog == nil || service_catalog.state == nil {
		return false
	}
	old_language_catalog := language_catalog^
	language_catalog^ = candidate.language_catalog
	candidate.language_catalog = old_language_catalog
	old_service_catalog := service_catalog^
	service_catalog^ = candidate.service_catalog
	candidate.service_catalog = old_service_catalog
	candidate.published = true
	return true
}

/* runtime_catalog_candidate_close releases catalogs and rolls back unpublished definitions. */
runtime_catalog_candidate_close :: proc(
	candidate: ^Runtime_Catalog_Candidate,
	registry: ^language_service.Provider_Registry,
) -> bool {
	if candidate == nil do return false
	if candidate.language_catalog.state != nil {
		_, _ = language.language_catalog_close(&candidate.language_catalog)
	}
	if candidate.service_catalog.state != nil {
		_, _ = language_service.service_catalog_close(&candidate.service_catalog)
	}
	if !candidate.published && registry != nil && registry.state != nil {
		for handle in candidate.new_definitions[:candidate.new_definition_count] {
			_, _ = language_service.provider_registry_discard_definition(registry, handle)
		}
	}
	candidate^ = {}
	return true
}

/* runtime_catalog_candidate_retired_definitions borrows handles replaced by this publication. */
runtime_catalog_candidate_retired_definitions :: proc(
	candidate: ^Runtime_Catalog_Candidate,
) -> []language_service.Definition_Handle {
	if candidate == nil || !candidate.live do return nil
	return candidate.retired_definitions[:candidate.retired_definition_count]
}

@(private)
language_support_workflow_prepare_language_catalog :: proc(
	candidate: ^Runtime_Catalog_Candidate,
	language_catalog: ^language.Language_Catalog,
	sources: []^Language_Support_Source_Candidate,
	allocator: runtime.Allocator,
) -> bool {
	current, current_ok, _ := language.language_catalog_inspect(language_catalog)
	if !current_ok || current.catalog_generation == language.Language_Catalog_Generation(max(u64)) {
		return false
	}
	cloned, _ := language.language_catalog_clone(
		language_catalog,
		&candidate.language_catalog,
		allocator,
	)
	if !cloned do return false
	count := 0
	for source in sources {
		languages, _, _, counted := source_counts(source)
		if !counted || count > language.MAX_LANGUAGES - languages do return false
		count += languages
	}
	views, views_error := make(
		[]Language_Support_Language_View,
		count,
		context.temp_allocator,
	)
	if views_error != nil do return false
	definitions, definitions_error := make(
		[]language.Language_Definition_Candidate,
		count,
		context.temp_allocator,
	)
	if definitions_error != nil do return false
	position := 0
	for source in sources {
		languages, _, _, _ := source_counts(source)
		for index in 0 ..< languages {
			view, viewed := source_language(source, index)
			if !viewed do return false
			views[position] = view
			position += 1
		}
	}
	for &view, index in views {
		definitions[index] = language.Language_Definition_Candidate {
			language_id = language_support_workflow_factory_language_id(view),
			identity = view.identity,
			display_name = view.display_name,
			source = language_support_workflow_language_source(view.source),
			scope = view.scope,
			source_generation = language.Language_Source_Generation(view.source_generation),
			exact_filenames = view.exact_filenames[:view.exact_filename_count],
			suffixes = view.suffixes[:view.suffix_count],
			provenance = view.provenance,
		}
	}
	_, confirmed, _ := language.language_catalog_confirm(
		&candidate.language_catalog,
		current.catalog_generation,
		{
			generation = current.catalog_generation + 1,
			definitions = definitions,
		},
	)
	return confirmed
}

@(private)
language_support_workflow_prepare_service_catalog :: proc(
	candidate: ^Runtime_Catalog_Candidate,
	registry: ^language_service.Provider_Registry,
	service_catalog: ^language_service.Service_Catalog,
	factory_definition: language_service.Definition_Handle,
	sources: []^Language_Support_Source_Candidate,
	allocator: runtime.Allocator,
) -> bool {
	language_catalog, language_ok, _ := language.language_catalog_inspect(
		&candidate.language_catalog,
	)
	current: language_service.Service_Catalog_Inspection
	current_ok, _ := language_service.service_catalog_inspect(service_catalog, &current)
	if !language_ok || !current_ok ||
	   current.catalog_generation == language_service.Service_Catalog_Generation(max(u64)) {
		return false
	}
	cloned, _ := language_service.service_catalog_clone(
		service_catalog,
		&candidate.service_catalog,
		allocator,
	)
	if !cloned do return false

	service_count := 0
	selection_count := 0
	for source in sources {
		_, services, selections, counted := source_counts(source)
		if !counted || service_count > language_service.MAX_SERVICE_CATALOG_DEFINITIONS - services ||
		   selection_count > language_service.MAX_SERVICE_CATALOG_SELECTIONS - selections {
			return false
		}
		service_count += services
		selection_count += selections
	}
	views, views_error := make(
		[]Language_Support_Service_View,
		service_count,
		context.temp_allocator,
	)
	if views_error != nil do return false
	position := 0
	for source in sources {
		_, services, _, _ := source_counts(source)
		for index in 0 ..< services {
			view, viewed := source_service(source, index)
			if !viewed do return false
			views[position] = view
			position += 1
		}
	}
	language_storage, language_storage_error := make(
		[]language.Language_Identity,
		service_count * language_service.MAX_LANGUAGE_IDENTITIES,
		context.temp_allocator,
	)
	if language_storage_error != nil do return false
	definitions, definitions_error := make(
		[]language_service.Service_Catalog_Definition_Candidate,
		service_count,
		context.temp_allocator,
	)
	if definitions_error != nil do return false
	for &view, index in views {
		first := index * language_service.MAX_LANGUAGE_IDENTITIES
		languages := language_storage[first:first + int(view.language_count)]
		for name, language_index in view.languages[:view.language_count] {
			identity, found := language_support_workflow_language_identity(&language_catalog, name)
			if !found do return false
			languages[language_index] = identity
		}
		proposal, proposal_ok := language_support_workflow_service_proposal(&view)
		if !proposal_ok do return false
		handle: language_service.Definition_Handle
		if view.source == .Factory && view.identity == language_service.FACTORY_OLS_IDENTITY {
			handle = factory_definition
		} else {
			handle = language_support_workflow_reusable_definition(registry, &current, &view, proposal)
			if handle.id == language_service.Definition_ID(0) {
				proposed, confirmed: bool
				handle, proposed, _ = language_service.provider_registry_propose(
					registry,
					proposal,
				)
				if !proposed do return false
				candidate.new_definitions[candidate.new_definition_count] = handle
				candidate.new_definition_count += 1
				confirmed, _ = language_service.provider_registry_confirm(registry, handle)
				if !confirmed do return false
			}
		}
		definitions[index] = language_service.Service_Catalog_Definition_Candidate {
			definition = handle,
			identity = view.identity,
			languages = languages,
			source = view.source,
			scope_kind = view.scope_kind,
			scope = view.scope,
			source_generation = view.source_generation,
			policy = {
				enabled = view.enabled,
				default_selection = view.default_selection,
			},
			provenance = view.provenance,
		}
	}

	selection_views, selection_views_error := make(
		[]Language_Support_Selection_View,
		selection_count,
		context.temp_allocator,
	)
	if selection_views_error != nil do return false
	selections, selections_error := make(
		[]language_service.Service_Explicit_Selection_Candidate,
		selection_count,
		context.temp_allocator,
	)
	if selections_error != nil do return false
	position = 0
	for source in sources {
		_, _, source_selections, _ := source_counts(source)
		for index in 0 ..< source_selections {
			view, viewed := source_selection(source, index)
			if !viewed do return false
			selection_views[position] = view
			position += 1
		}
	}
	for &view, index in selection_views {
		identity, found := language_support_workflow_language_identity(
			&language_catalog,
			view.language_identity,
		)
		if !found do return false
		selections[index] = language_service.Service_Explicit_Selection_Candidate {
			language = identity,
			service_identity = view.service_identity,
			source = view.source,
			scope_kind = view.scope_kind,
			scope = view.scope,
			source_generation = view.source_generation,
		}
	}

	confirmed, _ := language_service.service_catalog_confirm(
		&candidate.service_catalog,
		current.catalog_generation,
		{
			generation = current.catalog_generation + 1,
			language_catalog_generation = language_catalog.catalog_generation,
			definitions = definitions,
			selections = selections,
		},
	)
	if !confirmed do return false
	language_support_workflow_collect_retired_candidate(candidate, &current)
	return true
}

@(private)
language_support_workflow_service_proposal :: proc(
	view: ^Language_Support_Service_View,
) -> (language_service.Definition_Proposal, bool) {
	if view == nil || view.command_count == 0 do return {}, false
	environment, allocation_error := make(
		[]string,
		int(view.environment_count),
		context.temp_allocator,
	)
	if allocation_error != nil do return {}, false
	for entry, index in view.environment[:view.environment_count] {
		environment[index] = fmt.aprintf(
			"%s=%s",
			entry.key,
			entry.value,
			allocator = context.temp_allocator,
		)
		if environment[index] == "" do return {}, false
	}
	initialization_options, initialization_error := json.marshal(
		view.initialization_options,
		{},
		context.temp_allocator,
	)
	settings, settings_error := json.marshal(view.settings, {}, context.temp_allocator)
	if initialization_error != nil || settings_error != nil do return {}, false
	features: language_service.Service_Features
	capabilities: language_service.Capabilities = {
		.Initialize,
		.Shutdown,
		.Cancellation,
		.Full_Synchronization,
		.Incremental_Synchronization,
		.Save_Notification,
		.Log_Message,
	}
	for feature in view.features[:view.feature_count] {
		features += {feature}
		if feature == .Diagnostics do capabilities += {.Push_Diagnostics}
		if feature == .Completion do capabilities += {.Completion}
		if feature == .Navigation do capabilities += {.Definition}
		if feature == .Hover do capabilities += {.Hover}
		if feature == .References do capabilities += {.References}
		if feature == .Symbols do capabilities += {.Document_Symbols, .Workspace_Symbols}
		if feature == .Signature_Help do capabilities += {.Signature_Help}
		if feature == .Semantic_Tokens do capabilities += {.Semantic_Tokens}
	}
	return language_service.Definition_Proposal {
		kind = language_support_workflow_provider_kind(view.source),
		name = view.display_name,
		executable = view.command[0],
		package_artifact = view.package_artifact,
		arguments = view.command[1:view.command_count],
		environment = environment,
		root_policy = .Project_Membership,
		root_markers = view.root_markers[:view.root_marker_count],
		languages = view.languages[:view.language_count],
		initialization_options = string(initialization_options),
		client_settings = string(settings),
		feature_policy = features,
		requested_capabilities = capabilities,
		preferred_encoding = .UTF_16,
		preferred_sync = .Incremental,
		limits = language_service.DEFAULT_LIMITS,
		deadlines = language_service.DEFAULT_DEADLINES,
		restart = language_service.DEFAULT_RESTART_POLICY,
	}, true
}

@(private)
language_support_workflow_reusable_definition :: proc(
	registry: ^language_service.Provider_Registry,
	current: ^language_service.Service_Catalog_Inspection,
	view: ^Language_Support_Service_View,
	proposal: language_service.Definition_Proposal,
) -> language_service.Definition_Handle {
	if current == nil || view == nil do return {}
	for &definition in current.definitions[:current.definition_count] {
		if language_service.service_identity_text_view(&definition.identity) != view.identity ||
		   definition.scope.source != view.source || definition.scope.kind != view.scope_kind ||
		   language_service.service_scope_text_view(&definition.scope.name) != view.scope {
			continue
		}
		stored, found, _ := language_service.provider_registry_definition(
			registry,
			definition.definition,
		)
		if found && language_support_workflow_definition_matches(stored, proposal) {
			return definition.definition
		}
	}
	return {}
}

@(private)
language_support_workflow_definition_matches :: proc(
	stored: language_service.Definition_View,
	proposal: language_service.Definition_Proposal,
) -> bool {
		return stored.provider.kind == proposal.kind && stored.name == proposal.name &&
		stored.executable == proposal.executable && stored.package_artifact == proposal.package_artifact &&
		stored.distributed_artifact == proposal.distributed_artifact &&
		stored.root_policy == proposal.root_policy &&
		stored.root == proposal.root &&
		language_support_workflow_json_equal(
			stored.initialization_options,
			proposal.initialization_options,
		) &&
		language_support_workflow_json_equal(stored.client_settings, proposal.client_settings) &&
		stored.feature_policy == proposal.feature_policy &&
		stored.definition.requested_capabilities == proposal.requested_capabilities &&
		stored.definition.preferred_encoding == proposal.preferred_encoding &&
		stored.definition.preferred_sync == proposal.preferred_sync &&
		stored.definition.limits == proposal.limits && stored.definition.deadlines == proposal.deadlines &&
		stored.definition.restart == proposal.restart &&
		language_support_workflow_strings_equal(stored.arguments, proposal.arguments) &&
		language_support_workflow_strings_equal(stored.environment, proposal.environment) &&
		language_support_workflow_strings_equal(stored.root_markers, proposal.root_markers) &&
		language_support_workflow_strings_equal(stored.languages, proposal.languages)
}

@(private)
language_support_workflow_strings_equal :: proc(left, right: []string) -> bool {
	if len(left) != len(right) do return false
	for value, index in left do if value != right[index] do return false
	return true
}

@(private)
language_support_workflow_json_equal :: proc(left, right: string) -> bool {
	left_value, left_error := json.parse_string(left, .JSON, true, context.temp_allocator)
	if left_error != .None do return false
	defer json.destroy_value(left_value, context.temp_allocator)
	right_value, right_error := json.parse_string(right, .JSON, true, context.temp_allocator)
	if right_error != .None do return false
	defer json.destroy_value(right_value, context.temp_allocator)
	return language_support_workflow_json_value_equal(left_value, right_value, 1)
}

@(private)
language_support_workflow_json_value_equal :: proc(
	left, right: json.Value,
	depth: int,
) -> bool {
	if depth > int(language_service.DEFAULT_LIMITS.json_depth) do return false
	#partial switch current in left {
	case json.Null:
		_, ok := right.(json.Null)
		return ok
	case json.Integer:
		value, ok := right.(json.Integer)
		return ok && current == value
	case json.Float:
		value, ok := right.(json.Float)
		return ok && current == value
	case json.Boolean:
		value, ok := right.(json.Boolean)
		return ok && current == value
	case json.String:
		value, ok := right.(json.String)
		return ok && current == value
	case json.Array:
		value, ok := right.(json.Array)
		if !ok || len(current) != len(value) do return false
		for entry, index in current {
			if !language_support_workflow_json_value_equal(entry, value[index], depth + 1) {
				return false
			}
		}
		return true
	case json.Object:
		value, ok := right.(json.Object)
		if !ok || len(current) != len(value) do return false
		for key, entry in current {
			other, present := value[key]
			if !present ||
			   !language_support_workflow_json_value_equal(entry, other, depth + 1) {
				return false
			}
		}
		return true
	}
	return false
}

@(private)
language_support_workflow_language_identity :: proc(
	catalog: ^language.Language_Catalog_Inspection,
	name: string,
) -> (language.Language_Identity, bool) {
	if catalog == nil do return {}, false
	for &definition in catalog.definitions[:catalog.definition_count] {
		if string(definition.language.name.bytes[:definition.language.name.length]) == name {
			return definition.language, true
		}
	}
	return {}, false
}

@(private)
language_support_workflow_factory_language_id :: proc(
	view: Language_Support_Language_View,
) -> language.Language_ID {
	if view.source != .Factory do return 0
	switch view.identity {
	case "odin":   return language.FACTORY_ODIN_LANGUAGE_ID
	case "jan":    return language.FACTORY_JAN_LANGUAGE_ID
	case "racket": return language.FACTORY_RACKET_LANGUAGE_ID
	case "go":     return language.FACTORY_GO_LANGUAGE_ID
	}
	return 0
}

@(private)
language_support_workflow_language_source :: proc(
	source: language_service.Service_Contribution_Source,
) -> language.Language_Contribution_Source {
	switch source {
	case .Factory:  return .Factory
	case .Package:  return .Package
	case .Personal: return .Personal
	case .Project:  return .Project
	case .Invalid:  return .Invalid
	}
	return .Invalid
}

@(private)
language_support_workflow_provider_kind :: proc(
	source: language_service.Service_Contribution_Source,
) -> language_service.Provider_Kind {
	if source == .Factory do return .Factory
	if source == .Personal do return .Programmable
	if source == .Package || source == .Project do return .Native
	return .Invalid
}

@(private)
language_support_workflow_collect_retired_candidate :: proc(
	candidate: ^Runtime_Catalog_Candidate,
	current: ^language_service.Service_Catalog_Inspection,
) {
	if candidate == nil || current == nil do return
	next: language_service.Service_Catalog_Inspection
	next_ok, _ := language_service.service_catalog_inspect(&candidate.service_catalog, &next)
	if !next_ok do return
	for &definition in current.definitions[:current.definition_count] {
		present := false
		for &next_definition in next.definitions[:next.definition_count] {
			if definition.definition == next_definition.definition {
				present = true
				break
			}
		}
		if present do continue
		candidate.retired_definitions[candidate.retired_definition_count] = definition.definition
		candidate.retired_definition_count += 1
	}
}
