// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_output

import "core:strings"
import "core:unicode/utf8"

/* Publishing_Action identifies local generation and optional remote delivery. */
Publishing_Action :: enum u8 {
	Invalid,
	Build,
	Build_And_Upload,
}

/* Publishing_Failure_Policy controls deterministic multi-entry failure handling. */
Publishing_Failure_Policy :: enum u8 {
	Invalid,
	Stop,
	Continue,
}

/* Publishing_Link_Policy controls manifest-time link treatment. */
Publishing_Link_Policy :: enum u8 {
	Invalid,
	Preserve,
	Rewrite_Relative,
	Validate,
	Rewrite_And_Validate,
}

/* Publication_Entry_Kind identifies one planned output. */
Publication_Entry_Kind :: enum u8 {
	Invalid,
	Generated,
	Static_Copy,
	Sitemap,
	Index,
}

/* Stale_Output_Action identifies one checked obsolete-output decision. */
Stale_Output_Action :: enum u8 {
	Invalid,
	Preserve,
	Delete,
}

/* Publication_Run_State separates local generation from remote delivery. */
Publication_Run_State :: enum u8 {
	Invalid,
	Prepared,
	Local_In_Progress,
	Local_Complete,
	Remote_In_Progress,
	Remote_Partial,
	Retry_Ready,
	Published,
	Reconciliation_Required,
	Failed,
	Closed,
}

/* Publication_Run_Event identifies one externally confirmed workflow outcome. */
Publication_Run_Event :: enum u8 {
	Invalid,
	Start_Local,
	Local_Succeeded,
	Local_Failed,
	Start_Remote,
	Remote_Progress,
	Remote_Succeeded,
	Remote_Failed,
	Retry,
	Reconcile,
	Fail,
	Close,
}

/* Publishing_Source_Root identifies one admitted source root and discovery policy. */
Publishing_Source_Root :: struct {
	resource_id:       u64,
	resource_revision: u64,
	recursive:         bool,
	include_prefix:    string,
	exclude_prefix:    string,
	suffix:            string,
}

/* Publishing_Project_Definition is one bounded confirmed Racket project value. */
Publishing_Project_Definition :: struct {
	identity:             string,
	generation:           Configuration_Generation,
	component_identities: []string,
	source_roots:         []Publishing_Source_Root,
	destination_resource_id: u64,
	destination_revision: u64,
	action:               Publishing_Action,
	backend:              string,
	shared_options_digest:  [32]u8,
	backend_options_digest: [32]u8,
	copy_static:          bool,
	link_policy:          Publishing_Link_Policy,
	generate_sitemap:     bool,
	sitemap_resource_id:  u64,
	generate_index:       bool,
	index_resource_id:    u64,
	use_cache:            bool,
	use_timestamps:       bool,
	remote_provider_identity: string,
	remote_provider_generation: Provider_Generation,
	maximum_concurrency:  u16,
	failure_policy:       Publishing_Failure_Policy,
	cleanup_required:     bool,
	retention_generations: u16,
}

/* Publication_Source_Candidate is one copied discovery input. */
Publication_Source_Candidate :: struct {
	root_index:        u16,
	depth:             u16,
	resource_id:       u64,
	resource_revision: u64,
	relative_path:     string,
	output_resource_id: u64,
	output_revision:   u64,
	byte_count:        u64,
	static:            bool,
	source_digest:     [32]u8,
	dependency_digest: [32]u8,
	backend_digest:    [32]u8,
	filter_digest:     [32]u8,
	setting_digest:    [32]u8,
	tool_digest:       [32]u8,
	link_count:        u32,
}

/* Publication_Link_Record identifies one checked manifest-time link. */
Publication_Link_Record :: struct {
	source_resource_id: u64,
	target_resource_id: u64,
	rewritten_target_resource_id: u64,
	valid:              bool,
	external:           bool,
}

/* Cached_Publication_Output identifies one exact reusable output. */
Cached_Publication_Output :: struct {
	output_resource_id: u64,
	source_digest:      [32]u8,
	dependency_digest:  [32]u8,
	backend_digest:     [32]u8,
	filter_digest:      [32]u8,
	setting_digest:     [32]u8,
	tool_digest:        [32]u8,
	complete:           bool,
}

/* Existing_Publication_Output identifies one prior project-owned output. */
Existing_Publication_Output :: struct {
	resource_id:         u64,
	project_identity:    string,
	project_generation:  Configuration_Generation,
	generated_by_project: bool,
}

/* Publication_Manifest_Entry is one complete output or copy decision. */
Publication_Manifest_Entry :: struct {
	kind:                 Publication_Entry_Kind,
	source_resource_id:   u64,
	source_revision:      u64,
	output_resource_id:   u64,
	expected_output_revision: u64,
	relative_path:        string,
	byte_count:           u64,
	link_count:           u32,
	source_digest:        [32]u8,
	dependency_digest:    [32]u8,
	backend_digest:       [32]u8,
	filter_digest:        [32]u8,
	setting_digest:       [32]u8,
	tool_digest:          [32]u8,
	reuse:                bool,
}

/* Stale_Output_Decision records preservation or deletion before writes begin. */
Stale_Output_Decision :: struct {
	resource_id: u64,
	action:      Stale_Output_Action,
}

/* Publication_Manifest_Request identifies one explicit complete planning pass. */
Publication_Manifest_Request :: struct {
	operation_id: Operation_ID,
	manifest_id:  Manifest_ID,
	project_generation: Configuration_Generation,
	backend_generation: Backend_Generation,
	filter_generation:  Filter_Generation,
	synthetic_digest: [32]u8,
	limits:       Limits,
	explicit:     bool,
}

/* Publication_Manifest reports complete pre-effect output accounting. */
Publication_Manifest :: struct {
	record:       Publication_Manifest_Record,
	generated_count: u32,
	static_count:    u32,
	reused_count:    u32,
	stale_count:     u32,
	delete_count:    u32,
	link_count:      u32,
	complete:        bool,
}

/* Publication_Run records local and remote outcomes independently. */
Publication_Run :: struct {
	manifest_id:     Manifest_ID,
	entry_count:     u32,
	local_completed: u32,
	remote_uploaded: u32,
	remote_failed:   u32,
	attempt:         u16,
	maximum_attempts: u16,
	remote_required: bool,
	state:           Publication_Run_State,
}

/* Publication_Retention_Record identifies one generation cleanup decision. */
Publication_Retention_Record :: struct {
	resource_id: u64,
	generation:  Configuration_Generation,
	expired:     bool,
	protected:   bool,
	removed:     bool,
}

/* publishing_project_is_valid checks one confirmed project without reading resources. */
publishing_project_is_valid :: proc(project: Publishing_Project_Definition, limits := DEFAULT_LIMITS) -> bool {
	if !output_text_is_valid(project.identity, MAX_IDENTITY_BYTES) || project.generation == Configuration_Generation(0) ||
	   len(project.source_roots) == 0 || len(project.source_roots) > int(limits.included_resources) ||
	   len(project.component_identities) > int(limits.provider_operations) || project.destination_resource_id == 0 ||
	   project.destination_revision == 0 || project.action == .Invalid ||
	   !output_text_is_valid(project.backend, MAX_IDENTITY_BYTES) || !publication_digest_present(project.shared_options_digest) ||
	   !publication_digest_present(project.backend_options_digest) || project.link_policy == .Invalid ||
	   project.maximum_concurrency == 0 || project.maximum_concurrency > limits.provider_operations ||
	   project.failure_policy == .Invalid || project.retention_generations == 0 ||
	   u32(project.retention_generations) > limits.publication_targets { return false }
	if project.generate_sitemap != (project.sitemap_resource_id != 0) ||
	   project.generate_index != (project.index_resource_id != 0) { return false }
	if project.action == .Build_And_Upload {
		if !output_text_is_valid(project.remote_provider_identity, MAX_IDENTITY_BYTES) ||
		   project.remote_provider_generation == Provider_Generation(0) { return false }
	} else if len(project.remote_provider_identity) != 0 || project.remote_provider_generation != Provider_Generation(0) {
		return false
	}
	for component, index in project.component_identities {
		if !output_text_is_valid(component, MAX_IDENTITY_BYTES) || component == project.identity do return false
		for prior in project.component_identities[:index] do if prior == component do return false
	}
	for root, index in project.source_roots {
		if root.resource_id == 0 || root.resource_revision == 0 ||
		   (len(root.include_prefix) > 0 && !publication_relative_path_is_valid(root.include_prefix)) ||
		   (len(root.exclude_prefix) > 0 && !publication_relative_path_is_valid(root.exclude_prefix)) ||
		   !output_text_is_valid(root.suffix, MAX_IDENTITY_BYTES) || !strings.has_prefix(root.suffix, ".") { return false }
		for prior in project.source_roots[:index] do if prior.resource_id == root.resource_id do return false
	}
	return true
}

/* order_publishing_projects validates component references and returns deterministic dependency order. */
order_publishing_projects :: proc(projects: []Publishing_Project_Definition, ordered: []u16, resolved: []bool) -> (u16, bool, Failure) {
	if len(projects) == 0 || len(projects) > int(DEFAULT_LIMITS.provider_operations) ||
	   len(ordered) < len(projects) || len(resolved) < len(projects) {
		return 0, false, publishing_failure(0, .Invalid_Request, .Manifest)
	}
	for index in 0..<len(projects) do resolved[index] = false
	for project, index in projects {
		if !publishing_project_is_valid(project) do return 0, false, publishing_failure(0, .Malformed, .Manifest)
		for prior in projects[:index] do if prior.identity == project.identity {
			return 0, false, publishing_failure(0, .Conflict, .Manifest)
		}
		for component in project.component_identities {
			found := false
			for candidate in projects do if candidate.identity == component {
				found = true
				break
			}
			if !found do return 0, false, publishing_failure(0, .Missing, .Manifest)
		}
	}
	count := 0
	for count < len(projects) {
		selected := -1
		for project, index in projects {
			if resolved[index] do continue
			ready := true
			for component in project.component_identities {
				component_ready := false
				for candidate, candidate_index in projects do if candidate.identity == component && resolved[candidate_index] {
					component_ready = true
					break
				}
				if !component_ready {
					ready = false
					break
				}
			}
			if ready && (selected < 0 || strings.compare(project.identity, projects[selected].identity) < 0) do selected = index
		}
		if selected < 0 do return 0, false, publishing_failure(0, .Cycle, .Manifest)
		resolved[selected] = true
		ordered[count] = u16(selected)
		count += 1
	}
	return u16(count), true, {}
}

/* discover_publication_sources filters and path-sorts copied candidates within admitted roots. */
discover_publication_sources :: proc(project: Publishing_Project_Definition, candidates: []Publication_Source_Candidate, selected: []u16) -> (u16, bool, Failure) {
	if !publishing_project_is_valid(project) || len(candidates) > int(DEFAULT_LIMITS.manifest_entries) || len(selected) < len(candidates) {
		return 0, false, publishing_failure(0, .Invalid_Request, .Manifest)
	}
	count := 0
	for candidate, index in candidates {
		if !publication_candidate_is_valid(candidate, project) do return 0, false, publishing_failure(0, .Malformed, .Resource)
		for prior in candidates[:index] do if prior.resource_id == candidate.resource_id || prior.relative_path == candidate.relative_path {
			return 0, false, publishing_failure(0, .Conflict, .Resource)
		}
		root := project.source_roots[candidate.root_index]
		if len(root.include_prefix) > 0 && !strings.has_prefix(candidate.relative_path, root.include_prefix) do continue
		if len(root.exclude_prefix) > 0 && strings.has_prefix(candidate.relative_path, root.exclude_prefix) do continue
		if !strings.has_suffix(candidate.relative_path, root.suffix) && !(candidate.static && project.copy_static) do continue
		selected[count] = u16(index)
		count += 1
	}
	for index in 1..<count {
		value := selected[index]
		cursor := index
		for cursor > 0 && strings.compare(candidates[value].relative_path, candidates[selected[cursor - 1]].relative_path) < 0 {
			selected[cursor] = selected[cursor - 1]
			cursor -= 1
		}
		selected[cursor] = value
	}
	return u16(count), true, {}
}

/* prepare_publication_manifest validates all outputs, links, reuse, and stale decisions before effects. */
prepare_publication_manifest :: proc(
	request: Publication_Manifest_Request,
	project: Publishing_Project_Definition,
	candidates: []Publication_Source_Candidate,
	selected: []u16,
	links: []Publication_Link_Record,
	cached: []Cached_Publication_Output,
	existing: []Existing_Publication_Output,
	entries: []Publication_Manifest_Entry,
	stale: []Stale_Output_Decision,
) -> (Publication_Manifest, bool, Failure) {
	if request.operation_id == Operation_ID(0) || request.manifest_id == Manifest_ID(0) || !request.explicit ||
	   !limits_are_valid(request.limits) || !publishing_project_is_valid(project, request.limits) ||
	   request.project_generation != project.generation || len(selected) == 0 ||
	   request.backend_generation == Backend_Generation(0) || request.filter_generation == Filter_Generation(0) ||
	   len(selected) + int(project.generate_sitemap) + int(project.generate_index) > len(entries) ||
	   len(existing) > len(stale) || len(selected) > int(request.limits.manifest_entries) ||
	   len(links) > int(request.limits.links) ||
	   ((project.generate_sitemap || project.generate_index) && !publication_digest_present(request.synthetic_digest)) {
		return {}, false, publishing_failure(request.operation_id, .Invalid_Request, .Manifest)
	}
	manifest := Publication_Manifest {link_count = u32(len(links))}
	for cached_output, index in cached {
		if !cached_publication_output_is_valid(cached_output) do return {}, false, publishing_failure(request.operation_id, .Malformed, .Manifest)
		for prior in cached[:index] do if prior.output_resource_id == cached_output.output_resource_id {
			return {}, false, publishing_failure(request.operation_id, .Conflict, .Manifest)
		}
	}
	for link in links {
		if link.source_resource_id == 0 || link.target_resource_id == 0 ||
		   (project.link_policy == .Validate && !link.valid) ||
		   ((project.link_policy == .Rewrite_Relative || project.link_policy == .Rewrite_And_Validate) &&
		    !link.external && link.rewritten_target_resource_id == 0) ||
		   (project.link_policy == .Rewrite_And_Validate && !link.valid) {
			return {}, false, publishing_failure(request.operation_id, .Validation, .Manifest)
		}
	}
	entry_count := 0
	for selected_index in selected {
		if int(selected_index) >= len(candidates) do return {}, false, publishing_failure(request.operation_id, .Stale, .Manifest)
		candidate := candidates[selected_index]
		if !publication_candidate_is_valid(candidate, project) || !publication_candidate_is_selected(candidate, project) do return {}, false, publishing_failure(request.operation_id, .Malformed, .Resource)
		for prior in entries[:entry_count] do if prior.output_resource_id == candidate.output_resource_id {
			return {}, false, publishing_failure(request.operation_id, .Conflict, .Destination)
		}
		reuse := false
		for cached_output in cached {
			if cached_output.output_resource_id == candidate.output_resource_id {
				reuse = project.use_cache && publication_output_matches(candidate, cached_output)
			}
		}
		kind := Publication_Entry_Kind.Generated
		if candidate.static do kind = .Static_Copy
		entries[entry_count] = {kind = kind, source_resource_id = candidate.resource_id,
			source_revision = candidate.resource_revision, output_resource_id = candidate.output_resource_id,
			expected_output_revision = candidate.output_revision, relative_path = candidate.relative_path,
			byte_count = candidate.byte_count, link_count = candidate.link_count,
			source_digest = candidate.source_digest, dependency_digest = candidate.dependency_digest,
			backend_digest = candidate.backend_digest, filter_digest = candidate.filter_digest,
			setting_digest = candidate.setting_digest, tool_digest = candidate.tool_digest, reuse = reuse}
		if kind == .Static_Copy do manifest.static_count += 1
		if kind == .Generated do manifest.generated_count += 1
		if reuse do manifest.reused_count += 1
		entry_count += 1
	}
	for link in links {
		source_found, target_found, rewrite_found := false, false, false
		for selected_index in selected {
			candidate := candidates[selected_index]
			if candidate.resource_id == link.source_resource_id do source_found = true
			if candidate.resource_id == link.target_resource_id do target_found = true
		}
		if !source_found do return {}, false, publishing_failure(request.operation_id, .Validation, .Manifest)
		if link.external do continue
		for entry in entries[:entry_count] do if entry.output_resource_id == link.rewritten_target_resource_id {
			rewrite_found = true
			break
		}
		if !source_found || !target_found ||
		   ((project.link_policy == .Rewrite_Relative || project.link_policy == .Rewrite_And_Validate) && !rewrite_found) {
			return {}, false, publishing_failure(request.operation_id, .Validation, .Manifest)
		}
	}
	if project.generate_sitemap {
		for entry in entries[:entry_count] do if entry.output_resource_id == project.sitemap_resource_id {
			return {}, false, publishing_failure(request.operation_id, .Conflict, .Destination)
		}
		entries[entry_count] = {kind = .Sitemap, output_resource_id = project.sitemap_resource_id,
			expected_output_revision = project.destination_revision, relative_path = "sitemap.xml",
			source_digest = request.synthetic_digest, dependency_digest = request.synthetic_digest,
			backend_digest = project.backend_options_digest, filter_digest = request.synthetic_digest,
			setting_digest = project.shared_options_digest, tool_digest = request.synthetic_digest}
		entry_count += 1
		manifest.generated_count += 1
	}
	if project.generate_index {
		for entry in entries[:entry_count] do if entry.output_resource_id == project.index_resource_id {
			return {}, false, publishing_failure(request.operation_id, .Conflict, .Destination)
		}
		entries[entry_count] = {kind = .Index, output_resource_id = project.index_resource_id,
			expected_output_revision = project.destination_revision, relative_path = "index.html",
			source_digest = request.synthetic_digest, dependency_digest = request.synthetic_digest,
			backend_digest = project.backend_options_digest, filter_digest = request.synthetic_digest,
			setting_digest = project.shared_options_digest, tool_digest = request.synthetic_digest}
		entry_count += 1
		manifest.generated_count += 1
	}
	for prior_output, index in existing {
		if prior_output.resource_id == 0 || !output_text_is_valid(prior_output.project_identity, MAX_IDENTITY_BYTES) ||
		   prior_output.project_generation == Configuration_Generation(0) { return {}, false, publishing_failure(request.operation_id, .Malformed, .Manifest) }
		for prior in existing[:index] do if prior.resource_id == prior_output.resource_id do return {}, false, publishing_failure(request.operation_id, .Conflict, .Manifest)
		found := false
		for entry in entries[:entry_count] do if entry.output_resource_id == prior_output.resource_id {
			found = true
			break
		}
		if !found {
			action := Stale_Output_Action.Preserve
			if prior_output.generated_by_project && prior_output.project_identity == project.identity do action = .Delete
			stale[manifest.stale_count] = {resource_id = prior_output.resource_id, action = action}
			manifest.stale_count += 1
			if action == .Delete do manifest.delete_count += 1
		}
	}
	manifest.record = {schema_version = OUTPUT_SCHEMA_VERSION, manifest_id = request.manifest_id,
		operation_id = request.operation_id, configuration_generation = project.generation,
		backend_generation = request.backend_generation, filter_generation = request.filter_generation, entry_count = u32(entry_count),
		target_count = u32(entry_count), state = .Candidate}
	manifest.complete = publication_manifest_is_valid(manifest.record, request.limits)
	if !manifest.complete do return {}, false, publishing_failure(request.operation_id, .Validation, .Manifest)
	return manifest, true, {}
}

/* publication_output_matches requires every semantic and tool input to match. */
publication_output_matches :: proc(candidate: Publication_Source_Candidate, cached: Cached_Publication_Output) -> bool {
	return cached.complete && cached.output_resource_id == candidate.output_resource_id &&
	       cached.source_digest == candidate.source_digest && cached.dependency_digest == candidate.dependency_digest &&
	       cached.backend_digest == candidate.backend_digest && cached.filter_digest == candidate.filter_digest &&
	       cached.setting_digest == candidate.setting_digest && cached.tool_digest == candidate.tool_digest
}

/* publication_run_advance records confirmed local and remote outcomes without performing effects. */
publication_run_advance :: proc(run: Publication_Run, event: Publication_Run_Event, count: u32 = 0) -> (Publication_Run, bool, Failure) {
	if run.manifest_id == Manifest_ID(0) || run.entry_count == 0 || run.state == .Invalid ||
	   run.maximum_attempts == 0 || run.attempt > run.maximum_attempts ||
	   run.local_completed > run.entry_count || run.remote_uploaded > run.entry_count || run.remote_failed > run.entry_count {
		return run, false, publishing_failure(0, .Malformed, .Manifest)
	}
	next := run
	switch run.state {
	case .Prepared:
		if event == .Start_Local {
			next.state = .Local_In_Progress
			return next, true, {}
		}
	case .Local_In_Progress:
		if event == .Local_Succeeded && count == run.entry_count {
			next.local_completed = count
			next.state = .Local_Complete
			return next, true, {}
		}
		if event == .Local_Failed && count <= run.entry_count {
			next.local_completed = count
			next.state = .Failed
			return next, true, {}
		}
	case .Local_Complete:
		if event == .Start_Remote && run.remote_required && run.attempt < run.maximum_attempts {
			next.state = .Remote_In_Progress
			next.attempt += 1
			return next, true, {}
		}
		if event == .Close && !run.remote_required {
			next.state = .Closed
			return next, true, {}
		}
	case .Remote_In_Progress:
		if event == .Remote_Progress && run.remote_uploaded + count <= run.entry_count {
			next.remote_uploaded += count
			return next, true, {}
		}
		if event == .Remote_Succeeded && count == run.entry_count {
			next.remote_uploaded = count
			next.remote_failed = 0
			next.state = .Published
			return next, true, {}
		}
		if event == .Remote_Failed && count > 0 && count <= run.entry_count - run.remote_uploaded {
			next.remote_failed = count
			next.state = .Retry_Ready
			if run.remote_uploaded > 0 do next.state = .Remote_Partial
			return next, true, {}
		}
	case .Remote_Partial:
		if event == .Retry && run.attempt < run.maximum_attempts {
			next.state = .Remote_In_Progress
			next.remote_failed = 0
			next.attempt += 1
			return next, true, {}
		}
		if event == .Reconcile {
			next.state = .Reconciliation_Required
			return next, true, {}
		}
	case .Retry_Ready:
		if event == .Retry && run.attempt < run.maximum_attempts {
			next.state = .Remote_In_Progress
			next.remote_failed = 0
			next.attempt += 1
			return next, true, {}
		}
	case .Published, .Failed, .Reconciliation_Required:
		if event == .Close {
			next.state = .Closed
			return next, true, {}
		}
	case .Closed, .Invalid:
	}
	if event == .Fail && run.state != .Closed {
		next.state = .Failed
		return next, true, {}
	}
	return run, false, publishing_failure(0, .Conflict, .Manifest)
}

/* publication_cleanup_complete checks temporary and retention obligations. */
publication_cleanup_complete :: proc(temporaries: []Temporary_Resource, retention: []Publication_Retention_Record) -> bool {
	for temporary in temporaries do if temporary.resource_id == 0 || temporary.kind == .Invalid || (temporary.created && !temporary.cleaned) do return false
	for record in retention {
		if record.resource_id == 0 || record.generation == Configuration_Generation(0) ||
		   (record.protected && record.removed) || (record.expired && !record.protected && !record.removed) ||
		   (!record.expired && record.removed) { return false }
	}
	return true
}

@(private)
publication_candidate_is_valid :: proc(candidate: Publication_Source_Candidate, project: Publishing_Project_Definition) -> bool {
	return int(candidate.root_index) < len(project.source_roots) && candidate.resource_id != 0 &&
	       candidate.depth > 0 && (project.source_roots[candidate.root_index].recursive || candidate.depth == 1) &&
	       candidate.resource_revision != 0 && publication_relative_path_is_valid(candidate.relative_path) &&
	       candidate.output_resource_id != 0 && candidate.output_revision != 0 && candidate.byte_count <= MAX_OUTPUT_BYTES &&
	       (!candidate.static || project.copy_static) && publication_digest_present(candidate.source_digest) &&
	       publication_digest_present(candidate.dependency_digest) && publication_digest_present(candidate.backend_digest) &&
	       publication_digest_present(candidate.filter_digest) && publication_digest_present(candidate.setting_digest) &&
	       publication_digest_present(candidate.tool_digest) && candidate.link_count <= MAX_LINKS
}

@(private)
cached_publication_output_is_valid :: proc(cached: Cached_Publication_Output) -> bool {
	return cached.output_resource_id != 0 && publication_digest_present(cached.source_digest) &&
	       publication_digest_present(cached.dependency_digest) && publication_digest_present(cached.backend_digest) &&
	       publication_digest_present(cached.filter_digest) && publication_digest_present(cached.setting_digest) &&
	       publication_digest_present(cached.tool_digest)
}

@(private)
publication_candidate_is_selected :: proc(candidate: Publication_Source_Candidate, project: Publishing_Project_Definition) -> bool {
	root := project.source_roots[candidate.root_index]
	if len(root.include_prefix) > 0 && !strings.has_prefix(candidate.relative_path, root.include_prefix) do return false
	if len(root.exclude_prefix) > 0 && strings.has_prefix(candidate.relative_path, root.exclude_prefix) do return false
	return strings.has_suffix(candidate.relative_path, root.suffix) || (candidate.static && project.copy_static)
}

@(private)
publication_relative_path_is_valid :: proc(path: string) -> bool {
	return output_text_is_valid(path, MAX_SETTING_VALUE_BYTES) && !strings.has_prefix(path, "/") &&
	       path != ".." && !strings.has_prefix(path, "../") && !strings.contains(path, "/../") &&
	       !strings.has_suffix(path, "/..") && utf8.valid_string(path)
}

@(private)
publication_digest_present :: proc(digest: [32]u8) -> bool {
	for value in digest do if value != 0 do return true
	return false
}

@(private)
publishing_failure :: proc(operation_id: Operation_ID, code: Failure_Code, field: Failure_Field) -> Failure {
	return {operation_id = operation_id, kind = .Publish, code = code, field = field}
}
