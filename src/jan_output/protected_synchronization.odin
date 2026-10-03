// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_output

/* Synchronization_Attachment_Policy controls staged attachment inclusion. */
Synchronization_Attachment_Policy :: enum u8 {
	Invalid,
	None,
	Referenced,
	All,
}

/* Synchronization_Entry_Kind distinguishes documents from attachments. */
Synchronization_Entry_Kind :: enum u8 {
	Invalid,
	Document,
	Attachment,
}

/* Synchronization_Transport_Kind identifies transport without changing semantics. */
Synchronization_Transport_Kind :: enum u8 {
	Invalid,
	Local,
	Pola,
	Peer_To_Peer,
	Hosted,
}

/* Synchronization_Change_Kind classifies exact three-way content state. */
Synchronization_Change_Kind :: enum u8 {
	Invalid,
	Unchanged,
	Local_Only,
	Remote_Only,
	Converged,
	Conflict,
}

/* Synchronization_Conflict_Decision records one explicit divergent-entry decision. */
Synchronization_Conflict_Decision :: enum u8 {
	Invalid,
	Unresolved,
	Keep_Local,
	Accept_Remote,
	Manual_Merge,
}

/* Synchronization_Run_Event identifies one externally confirmed durable transition. */
Synchronization_Run_Event :: enum u8 {
	Invalid,
	Push_Confirmed,
	Pull_Confirmed,
	Reconcile,
	Apply_Confirmed,
	Interrupt,
	Recover,
	Expire,
}

/* Synchronization_Provider_Descriptor is one copied transport observation. */
Synchronization_Provider_Descriptor :: struct {
	identity:   string,
	generation: Provider_Generation,
	transport:  Synchronization_Transport_Kind,
	state:      Availability_State,
	admitted:   bool,
}

/* Synchronization_Project_Request binds staging and transport generations. */
Synchronization_Project_Request :: struct {
	operation_id:          Operation_ID,
	manifest_id:           Manifest_ID,
	provider_identity:     string,
	provider_generation:   Provider_Generation,
	staging_resource_id:   u64,
	staging_revision:      u64,
	push_generation:       u64,
	pull_generation:       u64,
	attachment_policy:     Synchronization_Attachment_Policy,
	entry_limit:           u32,
	retention_generations: u16,
	explicit:               bool,
	cancelled:              bool,
}

/* Synchronization_Source_Candidate is one exact local staging input. */
Synchronization_Source_Candidate :: struct {
	resource_id:    u64,
	base_revision:  u64,
	local_revision: u64,
	kind:           Synchronization_Entry_Kind,
	referenced:     bool,
	selected:       bool,
	base_digest:    [32]u8,
	local_digest:   [32]u8,
}

/* Synchronization_Manifest_Entry is one deterministic staged entry. */
Synchronization_Manifest_Entry :: struct {
	resource_id:      u64,
	base_revision:    u64,
	local_revision:   u64,
	kind:             Synchronization_Entry_Kind,
	base_digest:      [32]u8,
	local_digest:     [32]u8,
	staging_checksum: [32]u8,
}

/* Protected_Synchronization_Manifest extends the stable recoverable manifest record. */
Protected_Synchronization_Manifest :: struct {
	record:                Synchronization_Manifest_Record,
	operation_id:          Operation_ID,
	provider_identity:     string,
	transport:             Synchronization_Transport_Kind,
	staging_resource_id:   u64,
	staging_revision:      u64,
	push_generation:       u64,
	pull_generation:       u64,
	attachment_policy:     Synchronization_Attachment_Policy,
	entry_limit:           u32,
	retention_generations: u16,
	document_count:        u32,
	attachment_count:      u32,
	complete:              bool,
}

/* Synchronization_Remote_Observation is one checked pulled entry. */
Synchronization_Remote_Observation :: struct {
	resource_id:     u64,
	remote_revision: u64,
	base_digest:     [32]u8,
	remote_digest:   [32]u8,
	checksum_valid:  bool,
}

/* Synchronization_Conflict_Resolution is one explicit divergent-entry decision. */
Synchronization_Conflict_Resolution :: struct {
	resource_id:     u64,
	decision:        Synchronization_Conflict_Decision,
	merged_revision: u64,
	merged_digest:   [32]u8,
	explicit:        bool,
}

/* Synchronization_Reconciliation_Entry retains exact three-way classification. */
Synchronization_Reconciliation_Entry :: struct {
	resource_id:     u64,
	base_revision:   u64,
	local_revision:  u64,
	remote_revision: u64,
	change:          Synchronization_Change_Kind,
	decision:        Synchronization_Conflict_Decision,
	result_revision: u64,
	result_digest:   [32]u8,
}

/* Synchronization_Reconciliation summarizes conflict and apply accounting. */
Synchronization_Reconciliation :: struct {
	manifest_id:      Manifest_ID,
	entry_count:      u32,
	changed_count:    u32,
	conflict_count:   u32,
	applicable_count: u32,
	state:            Synchronization_State,
	complete:         bool,
}

/* Synchronization_Apply_Plan is one deterministic no-conflict application order. */
Synchronization_Apply_Plan :: struct {
	manifest_id: Manifest_ID,
	entry_count: u32,
	complete:    bool,
}

/* Synchronization_Apply_Result records one exact checked Resource application. */
Synchronization_Apply_Result :: struct {
	manifest_id:       Manifest_ID,
	resource_id:       u64,
	expected_revision: u64,
	result_revision:   u64,
	result_digest:     [32]u8,
	applied:           bool,
	complete:          bool,
}

/* Protected_Synchronization_Run records durable push, pull, reconcile, and apply outcomes. */
Protected_Synchronization_Run :: struct {
	record:           Synchronization_Manifest_Record,
	push_generation:  u64,
	pull_generation:  u64,
	pushed_count:     u32,
	received_count:   u32,
	conflict_count:   u32,
	applicable_count: u32,
	applied_count:    u32,
	previous_state:   Synchronization_State,
}

/* Synchronization_Retention_Record identifies one staging cleanup decision. */
Synchronization_Retention_Record :: struct {
	resource_id: u64,
	generation:  u64,
	expired:     bool,
	protected:   bool,
	removed:     bool,
}

/* prepare_synchronization_manifest validates selected entries before staging. */
prepare_synchronization_manifest :: proc(
	request: Synchronization_Project_Request,
	providers: []Synchronization_Provider_Descriptor,
	candidates: []Synchronization_Source_Candidate,
	entries: []Synchronization_Manifest_Entry,
	limits := DEFAULT_LIMITS,
) -> (Protected_Synchronization_Manifest, u32, bool, Failure) {
	if !limits_are_valid(limits) || request.operation_id == Operation_ID(0) || request.manifest_id == Manifest_ID(0) ||
	   !output_text_is_valid(request.provider_identity, MAX_IDENTITY_BYTES) ||
	   request.provider_generation == Provider_Generation(0) || request.staging_resource_id == 0 ||
	   request.staging_revision == 0 || request.push_generation == 0 || request.pull_generation == 0 ||
	   request.attachment_policy == .Invalid || request.entry_limit == 0 ||
	   request.entry_limit > limits.manifest_entries || request.retention_generations == 0 || !request.explicit {
		return {}, 0, false, synchronization_failure(request.operation_id, .Invalid_Request, .Synchronization)
	}
	if request.cancelled do return {}, 0, false, synchronization_failure(request.operation_id, .Cancelled, .Synchronization)
	provider, found, failure := select_synchronization_provider(request, providers)
	if failure.code != .None do return {}, 0, false, failure
	if !found do return {}, 0, false, synchronization_failure(request.operation_id, .Missing, .Synchronization)
	if len(candidates) > int(request.entry_limit) || len(entries) < len(candidates) {
		return {}, 0, false, synchronization_failure(request.operation_id, .Limited, .Limit)
	}
	selected_count := 0
	document_count: u32
	attachment_count: u32
	for candidate, index in candidates {
		if !synchronization_candidate_is_valid(candidate) {
			return {}, 0, false, synchronization_failure(request.operation_id, .Malformed, .Resource)
		}
		for prior in candidates[:index] do if prior.resource_id == candidate.resource_id {
			return {}, 0, false, synchronization_failure(request.operation_id, .Conflict, .Resource)
		}
		if !candidate.selected do continue
		if candidate.kind == .Attachment && request.attachment_policy == .None do continue
		if candidate.kind == .Attachment && request.attachment_policy == .Referenced && !candidate.referenced do continue
		entries[selected_count] = {resource_id = candidate.resource_id,
			base_revision = candidate.base_revision, local_revision = candidate.local_revision,
			kind = candidate.kind, base_digest = candidate.base_digest,
			local_digest = candidate.local_digest, staging_checksum = candidate.local_digest}
		if candidate.kind == .Document do document_count += 1
		if candidate.kind == .Attachment do attachment_count += 1
		selected_count += 1
	}
	if selected_count == 0 do return {}, 0, false, synchronization_failure(request.operation_id, .Missing, .Resource)
	for index in 1..<selected_count {
		value := entries[index]
		cursor := index
		for cursor > 0 && value.resource_id < entries[cursor - 1].resource_id {
			entries[cursor] = entries[cursor - 1]
			cursor -= 1
		}
		entries[cursor] = value
	}
	if document_count == 0 do return {}, 0, false, synchronization_failure(request.operation_id, .Missing, .Resource)
	record := Synchronization_Manifest_Record {schema_version = OUTPUT_SCHEMA_VERSION,
		manifest_id = request.manifest_id, provider_generation = provider.generation,
		entry_count = u32(selected_count), state = .Prepared}
	manifest := Protected_Synchronization_Manifest {record = record, operation_id = request.operation_id,
		provider_identity = provider.identity, transport = provider.transport,
		staging_resource_id = request.staging_resource_id, staging_revision = request.staging_revision,
		push_generation = request.push_generation, pull_generation = request.pull_generation,
		attachment_policy = request.attachment_policy, entry_limit = request.entry_limit,
		retention_generations = request.retention_generations,
		document_count = document_count, attachment_count = attachment_count, complete = true}
	if !synchronization_manifest_is_valid(record, limits) {
		return {}, 0, false, synchronization_failure(request.operation_id, .Validation, .Synchronization)
	}
	return manifest, u32(selected_count), true, {}
}

/* reconcile_synchronization_manifest performs exact three-way classification and decisions. */
reconcile_synchronization_manifest :: proc(
	manifest: Protected_Synchronization_Manifest,
	entries: []Synchronization_Manifest_Entry,
	remote: []Synchronization_Remote_Observation,
	resolutions: []Synchronization_Conflict_Resolution,
	output: []Synchronization_Reconciliation_Entry,
) -> (Synchronization_Reconciliation, bool, Failure) {
	operation_id := manifest.operation_id
	entry_count := int(manifest.record.entry_count)
	if !manifest.complete || !synchronization_manifest_is_valid(manifest.record) ||
	   len(entries) != entry_count || len(remote) != entry_count || len(output) < entry_count {
		return {}, false, synchronization_failure(operation_id, .Invalid_Request, .Synchronization)
	}
	for resolution, index in resolutions {
		if resolution.resource_id == 0 || !resolution.explicit || resolution.decision == .Invalid ||
		   resolution.decision == .Unresolved {
			return {}, false, synchronization_failure(operation_id, .Malformed, .Synchronization)
		}
		for prior in resolutions[:index] do if prior.resource_id == resolution.resource_id {
			return {}, false, synchronization_failure(operation_id, .Conflict, .Synchronization)
		}
		if resolution.decision == .Manual_Merge &&
		   (resolution.merged_revision == 0 || !synchronization_digest_present(resolution.merged_digest)) {
			return {}, false, synchronization_failure(operation_id, .Malformed, .Synchronization)
		}
		if resolution.decision != .Manual_Merge &&
		   (resolution.merged_revision != 0 || synchronization_digest_present(resolution.merged_digest)) {
			return {}, false, synchronization_failure(operation_id, .Malformed, .Synchronization)
		}
	}
	result := Synchronization_Reconciliation {manifest_id = manifest.record.manifest_id,
		entry_count = manifest.record.entry_count, state = .Received, complete = true}
	for entry, index in entries {
		if !synchronization_manifest_entry_is_valid(entry) {
			return {}, false, synchronization_failure(operation_id, .Malformed, .Manifest)
		}
		for prior in entries[:index] do if prior.resource_id == entry.resource_id {
			return {}, false, synchronization_failure(operation_id, .Conflict, .Manifest)
		}
		observation_found := false
		observation: Synchronization_Remote_Observation
		for candidate, candidate_index in remote {
			if candidate.resource_id == entry.resource_id {
				for prior in remote[:candidate_index] do if prior.resource_id == candidate.resource_id {
					return {}, false, synchronization_failure(operation_id, .Conflict, .Resource)
				}
				observation = candidate
				observation_found = true
			}
		}
		if !observation_found || observation.remote_revision == 0 || !observation.checksum_valid ||
		   observation.base_digest != entry.base_digest || !synchronization_digest_present(observation.remote_digest) {
			return {}, false, synchronization_failure(operation_id, .Validation, .Resource)
		}
		change := classify_synchronization_change(entry, observation)
		decision := Synchronization_Conflict_Decision.Unresolved
		result_revision := entry.local_revision
		result_digest := entry.local_digest
		switch change {
		case .Unchanged, .Local_Only, .Converged:
			decision = .Keep_Local
		case .Remote_Only:
			decision = .Accept_Remote
			result_revision = observation.remote_revision
			result_digest = observation.remote_digest
			result.applicable_count += 1
		case .Conflict:
			for resolution in resolutions do if resolution.resource_id == entry.resource_id {
				decision = resolution.decision
				if decision == .Accept_Remote {
					result_revision = observation.remote_revision
					result_digest = observation.remote_digest
					result.applicable_count += 1
				} else if decision == .Manual_Merge {
					if resolution.merged_revision <= entry.local_revision ||
					   resolution.merged_revision <= observation.remote_revision {
						return {}, false, synchronization_failure(operation_id, .Stale, .Synchronization)
					}
					result_revision = resolution.merged_revision
					result_digest = resolution.merged_digest
					result.applicable_count += 1
				}
			}
			if decision == .Unresolved {
				result.conflict_count += 1
				result.state = .Conflicted
			}
		case .Invalid:
			return {}, false, synchronization_failure(operation_id, .Malformed, .Synchronization)
		}
		if change != .Unchanged do result.changed_count += 1
		output[index] = {resource_id = entry.resource_id, base_revision = entry.base_revision,
			local_revision = entry.local_revision, remote_revision = observation.remote_revision,
			change = change, decision = decision, result_revision = result_revision,
			result_digest = result_digest}
	}
	for resolution in resolutions {
		found := false
		for entry in output[:entry_count] do if entry.resource_id == resolution.resource_id && entry.change == .Conflict {
			found = true
			break
		}
		if !found do return {}, false, synchronization_failure(operation_id, .Conflict, .Synchronization)
	}
	return result, true, {}
}

/* synchronization_apply_result_is_valid checks exact Resource application or no-effect failure. */
synchronization_apply_result_is_valid :: proc(
	plan: Synchronization_Apply_Plan,
	entry: Synchronization_Reconciliation_Entry,
	result: Synchronization_Apply_Result,
) -> bool {
	if !plan.complete || result.manifest_id != plan.manifest_id || result.resource_id != entry.resource_id ||
	   (entry.decision != .Accept_Remote && entry.decision != .Manual_Merge) { return false }
	if !result.complete || !result.applied {
		return !result.complete && !result.applied && result.expected_revision == entry.local_revision &&
		       result.result_revision == 0 && !synchronization_digest_present(result.result_digest)
	}
	return result.expected_revision == entry.local_revision && result.result_revision == entry.result_revision &&
	       result.result_digest == entry.result_digest
}

/* prepare_synchronization_apply returns stable resource order only after every conflict decision. */
prepare_synchronization_apply :: proc(
	reconciliation: Synchronization_Reconciliation,
	entries: []Synchronization_Reconciliation_Entry,
	order: []u16,
) -> (Synchronization_Apply_Plan, bool, Failure) {
	if !reconciliation.complete || reconciliation.manifest_id == Manifest_ID(0) ||
	   reconciliation.state != .Received || reconciliation.conflict_count != 0 ||
	   len(entries) != int(reconciliation.entry_count) || len(order) < int(reconciliation.applicable_count) {
		return {}, false, synchronization_failure(0, .Reconciliation_Required, .Synchronization)
	}
	count := 0
	for entry, index in entries {
		if !synchronization_reconciliation_entry_is_valid(entry) do return {}, false, synchronization_failure(0, .Malformed, .Synchronization)
		if entry.decision == .Accept_Remote || entry.decision == .Manual_Merge {
			order[count] = u16(index)
			count += 1
		}
	}
	if count != int(reconciliation.applicable_count) do return {}, false, synchronization_failure(0, .Conflict, .Synchronization)
	for index in 1..<count {
		value := order[index]
		cursor := index
		for cursor > 0 && entries[value].resource_id < entries[order[cursor - 1]].resource_id {
			order[cursor] = order[cursor - 1]
			cursor -= 1
		}
		order[cursor] = value
	}
	return {manifest_id = reconciliation.manifest_id, entry_count = u32(count), complete = true}, true, {}
}

/* synchronization_run_advance records durable transport, recovery, and apply outcomes. */
synchronization_run_advance :: proc(
	run: Protected_Synchronization_Run,
	event: Synchronization_Run_Event,
	count: u32 = 0,
	conflicts: u32 = 0,
) -> (Protected_Synchronization_Run, bool, Failure) {
	if !synchronization_manifest_is_valid(run.record) || run.push_generation == 0 || run.pull_generation == 0 ||
	   run.pushed_count > run.record.entry_count || run.received_count > run.record.entry_count ||
	   run.conflict_count > run.record.entry_count || run.applicable_count > run.record.entry_count ||
	   run.applied_count > run.applicable_count || run.record.conflict_count != run.conflict_count {
		return run, false, synchronization_failure(0, .Malformed, .Synchronization)
	}
	next := run
	if event == .Interrupt && run.record.state != .Applied && run.record.state != .Expired &&
	   run.record.state != .Reconciliation_Required {
		next.previous_state = run.record.state
		next.record.state = .Reconciliation_Required
		return next, true, {}
	}
	switch run.record.state {
	case .Prepared:
		if event == .Push_Confirmed && count == run.record.entry_count {
			next.pushed_count = count
			next.record.state = .Pushed
			return next, true, {}
		}
	case .Pushed:
		if event == .Pull_Confirmed && count == run.record.entry_count {
			next.received_count = count
			next.record.state = .Received
			return next, true, {}
		}
	case .Received, .Conflicted:
		if event == .Reconcile && conflicts <= run.record.entry_count && count <= run.record.entry_count {
			next.conflict_count = conflicts
			next.applicable_count = count
			next.record.conflict_count = conflicts
			next.record.state = .Received
			if conflicts > 0 do next.record.state = .Conflicted
			return next, true, {}
		}
		if run.record.state == .Received && event == .Apply_Confirmed && run.conflict_count == 0 &&
		   count == run.applicable_count {
			next.applied_count = count
			next.record.state = .Applied
			return next, true, {}
		}
	case .Reconciliation_Required:
		if event == .Recover && run.previous_state != .Invalid && run.previous_state != .Reconciliation_Required {
			next.record.state = run.previous_state
			next.previous_state = .Invalid
			return next, true, {}
		}
	case .Applied, .Expired, .Invalid:
	}
	if event == .Expire && run.record.state != .Expired {
		next.record.state = .Expired
		return next, true, {}
	}
	return run, false, synchronization_failure(0, .Conflict, .Synchronization)
}

/* synchronization_cleanup_complete checks temporary staging and retention obligations. */
synchronization_cleanup_complete :: proc(
	temporaries: []Temporary_Resource,
	retention: []Synchronization_Retention_Record,
) -> bool {
	for temporary in temporaries do if temporary.resource_id == 0 || temporary.kind == .Invalid ||
	   (temporary.created && !temporary.cleaned) { return false }
	for record in retention {
		if record.resource_id == 0 || record.generation == 0 || (record.protected && record.removed) ||
		   (record.expired && !record.protected && !record.removed) || (!record.expired && record.removed) { return false }
	}
	return true
}

@(private)
classify_synchronization_change :: proc(
	entry: Synchronization_Manifest_Entry,
	remote: Synchronization_Remote_Observation,
) -> Synchronization_Change_Kind {
	local_changed := entry.local_digest != entry.base_digest
	remote_changed := remote.remote_digest != entry.base_digest
	if !local_changed && !remote_changed do return .Unchanged
	if local_changed && !remote_changed do return .Local_Only
	if !local_changed && remote_changed do return .Remote_Only
	if entry.local_digest == remote.remote_digest do return .Converged
	return .Conflict
}

@(private)
synchronization_candidate_is_valid :: proc(candidate: Synchronization_Source_Candidate) -> bool {
	return candidate.resource_id != 0 && candidate.base_revision != 0 &&
	       candidate.local_revision >= candidate.base_revision && candidate.kind != .Invalid &&
	       synchronization_digest_present(candidate.base_digest) &&
	       synchronization_digest_present(candidate.local_digest)
}

@(private)
synchronization_manifest_entry_is_valid :: proc(entry: Synchronization_Manifest_Entry) -> bool {
	return entry.resource_id != 0 && entry.base_revision != 0 && entry.local_revision >= entry.base_revision &&
	       entry.kind != .Invalid && synchronization_digest_present(entry.base_digest) &&
	       synchronization_digest_present(entry.local_digest) &&
	       entry.staging_checksum == entry.local_digest
}

@(private)
synchronization_reconciliation_entry_is_valid :: proc(entry: Synchronization_Reconciliation_Entry) -> bool {
	if entry.resource_id == 0 || entry.base_revision == 0 || entry.local_revision < entry.base_revision ||
	   entry.remote_revision == 0 || entry.change == .Invalid || entry.decision == .Invalid ||
	   entry.decision == .Unresolved || entry.result_revision == 0 ||
	   !synchronization_digest_present(entry.result_digest) { return false }
	switch entry.change {
	case .Unchanged, .Local_Only, .Converged:
		return entry.decision == .Keep_Local
	case .Remote_Only:
		return entry.decision == .Accept_Remote
	case .Conflict:
		return entry.decision == .Keep_Local || entry.decision == .Accept_Remote || entry.decision == .Manual_Merge
	case .Invalid:
	}
	return false
}

@(private)
select_synchronization_provider :: proc(
	request: Synchronization_Project_Request,
	providers: []Synchronization_Provider_Descriptor,
) -> (Synchronization_Provider_Descriptor, bool, Failure) {
	matching_identity := false
	found := false
	selected: Synchronization_Provider_Descriptor
	for provider, index in providers {
		if !synchronization_provider_is_valid(provider) do return {}, false, synchronization_failure(request.operation_id, .Malformed, .Synchronization)
		for prior in providers[:index] do if prior.identity == provider.identity && prior.generation == provider.generation {
			return {}, false, synchronization_failure(request.operation_id, .Conflict, .Synchronization)
		}
		if provider.identity != request.provider_identity do continue
		matching_identity = true
		if provider.generation != request.provider_generation do continue
		selected = provider
		found = true
	}
	if !found && matching_identity do return {}, false, synchronization_failure(request.operation_id, .Stale, .Generation)
	if !found do return {}, false, {}
	if selected.state != .Available do return {}, false, synchronization_failure(request.operation_id, .Unavailable, .Synchronization)
	if !selected.admitted do return {}, false, synchronization_failure(request.operation_id, .Unauthorized, .Synchronization)
	return selected, true, {}
}

@(private)
synchronization_provider_is_valid :: proc(provider: Synchronization_Provider_Descriptor) -> bool {
	return output_text_is_valid(provider.identity, MAX_IDENTITY_BYTES) &&
	       provider.generation != Provider_Generation(0) && provider.transport != .Invalid && provider.state != .Invalid
}

@(private)
synchronization_digest_present :: proc(digest: [32]u8) -> bool {
	for value in digest do if value != 0 do return true
	return false
}

@(private)
synchronization_failure :: proc(operation_id: Operation_ID, code: Failure_Code, field: Failure_Field) -> Failure {
	return {operation_id = operation_id, kind = .Synchronize, code = code, field = field}
}
