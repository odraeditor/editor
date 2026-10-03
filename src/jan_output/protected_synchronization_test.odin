// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_output

import "core:testing"

/* Verifies staging is deterministic and transport choice does not change entry semantics. */
@(test)
protected_synchronization_stages_selected_documents_and_attachments :: proc(t: ^testing.T) {
	providers := [2]Synchronization_Provider_Descriptor {
		{identity = "local-sync", generation = 17, transport = .Local, state = .Available, admitted = true},
		{identity = "hosted-sync", generation = 19, transport = .Hosted, state = .Available, admitted = true},
	}
	candidates := [3]Synchronization_Source_Candidate {
		synchronization_test_candidate(303, .Document, true, true, 1, 2),
		synchronization_test_candidate(205, .Attachment, false, true, 1, 1),
		synchronization_test_candidate(201, .Attachment, true, true, 1, 2),
	}
	request := synchronization_test_request("local-sync", 17, .Referenced)
	local_entries: [3]Synchronization_Manifest_Entry
	local, local_count, local_ok, _ := prepare_synchronization_manifest(request, providers[:], candidates[:], local_entries[:])
	testing.expect(t, local_ok)
	testing.expect_value(t, local_count, u32(2))
	testing.expect_value(t, local.document_count, u32(1))
	testing.expect_value(t, local.attachment_count, u32(1))
	testing.expect_value(t, local_entries[0].resource_id, u64(201))
	testing.expect_value(t, local_entries[1].resource_id, u64(303))

	request.provider_identity = "hosted-sync"
	request.provider_generation = 19
	hosted_entries: [3]Synchronization_Manifest_Entry
	hosted, hosted_count, hosted_ok, _ := prepare_synchronization_manifest(request, providers[:], candidates[:], hosted_entries[:])
	testing.expect(t, hosted_ok)
	testing.expect_value(t, hosted.transport, Synchronization_Transport_Kind.Hosted)
	testing.expect_value(t, hosted_count, local_count)
	for entry, index in local_entries[:local_count] do testing.expect_value(t, hosted_entries[index], entry)

	request.attachment_policy = .None
	document_entries: [3]Synchronization_Manifest_Entry
	documents, document_count, document_ok, _ := prepare_synchronization_manifest(request, providers[:], candidates[:], document_entries[:])
	testing.expect(t, document_ok)
	testing.expect_value(t, document_count, u32(1))
	testing.expect_value(t, documents.attachment_count, u32(0))
}

/* Verifies three-way reconciliation never converts unresolved divergence into apply work. */
@(test)
protected_synchronization_requires_explicit_conflict_decisions :: proc(t: ^testing.T) {
	providers := [1]Synchronization_Provider_Descriptor {
		{identity = "local-sync", generation = 17, transport = .Local, state = .Available, admitted = true},
	}
	candidates := [3]Synchronization_Source_Candidate {
		synchronization_test_candidate(101, .Document, false, true, 1, 1),
		synchronization_test_candidate(103, .Document, false, true, 1, 2),
		synchronization_test_candidate(105, .Document, false, true, 1, 2),
	}
	entries: [3]Synchronization_Manifest_Entry
	manifest, count, prepared, _ := prepare_synchronization_manifest(
		synchronization_test_request("local-sync", 17, .None), providers[:], candidates[:], entries[:])
	testing.expect(t, prepared)
	remote := [3]Synchronization_Remote_Observation {
		synchronization_test_remote(101, entries[0].base_digest, 2, 7),
		synchronization_test_remote(103, entries[1].base_digest, 1, 8),
		synchronization_test_remote(105, entries[2].base_digest, 3, 9),
	}
	reconciled_entries: [3]Synchronization_Reconciliation_Entry
	no_resolutions := []Synchronization_Conflict_Resolution{}
	reconciliation, ok, _ := reconcile_synchronization_manifest(manifest, entries[:count], remote[:],
		no_resolutions, reconciled_entries[:])
	testing.expect(t, ok)
	testing.expect_value(t, reconciliation.state, Synchronization_State.Conflicted)
	testing.expect_value(t, reconciliation.conflict_count, u32(1))
	testing.expect_value(t, reconciliation.applicable_count, u32(1))
	order: [3]u16
	_, apply_ok, apply_failure := prepare_synchronization_apply(reconciliation, reconciled_entries[:], order[:])
	testing.expect(t, !apply_ok)
	testing.expect_value(t, apply_failure.code, Failure_Code.Reconciliation_Required)

	resolution := Synchronization_Conflict_Resolution {resource_id = 105, decision = .Manual_Merge,
		merged_revision = 11, explicit = true}
	resolution.merged_digest[0] = 4
	resolutions := [1]Synchronization_Conflict_Resolution {resolution}
	reconciliation, ok, _ = reconcile_synchronization_manifest(manifest, entries[:count], remote[:],
		resolutions[:], reconciled_entries[:])
	testing.expect(t, ok)
	testing.expect_value(t, reconciliation.state, Synchronization_State.Received)
	testing.expect_value(t, reconciliation.conflict_count, u32(0))
	testing.expect_value(t, reconciliation.applicable_count, u32(2))
	apply, apply_ready, _ := prepare_synchronization_apply(reconciliation, reconciled_entries[:], order[:])
	testing.expect(t, apply_ready)
	testing.expect_value(t, apply.entry_count, u32(2))
	testing.expect_value(t, reconciled_entries[order[0]].resource_id, u64(101))
	testing.expect_value(t, reconciled_entries[order[1]].resource_id, u64(105))
	first := reconciled_entries[order[0]]
	apply_result := Synchronization_Apply_Result {manifest_id = apply.manifest_id,
		resource_id = first.resource_id, expected_revision = first.local_revision,
		result_revision = first.result_revision, result_digest = first.result_digest,
		applied = true, complete = true}
	testing.expect(t, synchronization_apply_result_is_valid(apply, first, apply_result))
	apply_result.expected_revision += 1
	testing.expect(t, !synchronization_apply_result_is_valid(apply, first, apply_result))
}

/* Verifies interruption recovery preserves the last durable synchronization state. */
@(test)
protected_synchronization_recovers_durable_workflow_state :: proc(t: ^testing.T) {
	record := Synchronization_Manifest_Record {schema_version = OUTPUT_SCHEMA_VERSION,
		manifest_id = 501, provider_generation = 17, entry_count = 3, state = .Prepared}
	run := Protected_Synchronization_Run {record = record, push_generation = 7, pull_generation = 9}
	ok: bool
	run, ok, _ = synchronization_run_advance(run, .Push_Confirmed, 3)
	testing.expect(t, ok)
	testing.expect_value(t, run.record.state, Synchronization_State.Pushed)
	run, ok, _ = synchronization_run_advance(run, .Pull_Confirmed, 3)
	testing.expect(t, ok)
	run, ok, _ = synchronization_run_advance(run, .Reconcile, 2, 1)
	testing.expect(t, ok)
	testing.expect_value(t, run.record.state, Synchronization_State.Conflicted)
	_, silent_apply, _ := synchronization_run_advance(run, .Apply_Confirmed, 2)
	testing.expect(t, !silent_apply)
	run, ok, _ = synchronization_run_advance(run, .Interrupt)
	testing.expect(t, ok)
	testing.expect_value(t, run.record.state, Synchronization_State.Reconciliation_Required)
	run, ok, _ = synchronization_run_advance(run, .Recover)
	testing.expect(t, ok)
	testing.expect_value(t, run.record.state, Synchronization_State.Conflicted)
	run, ok, _ = synchronization_run_advance(run, .Reconcile, 2, 0)
	testing.expect(t, ok)
	run, ok, _ = synchronization_run_advance(run, .Apply_Confirmed, 2)
	testing.expect(t, ok)
	testing.expect_value(t, run.record.state, Synchronization_State.Applied)
}

/* Verifies corrupt input, unavailable providers, duplicate resources, and cleanup failures reject. */
@(test)
protected_synchronization_failures_preserve_staging_and_local_state :: proc(t: ^testing.T) {
	providers := [1]Synchronization_Provider_Descriptor {
		{identity = "local-sync", generation = 17, transport = .Local, state = .Unavailable, admitted = true},
	}
	candidates := [2]Synchronization_Source_Candidate {
		synchronization_test_candidate(101, .Document, false, true, 1, 1),
		synchronization_test_candidate(103, .Document, false, true, 1, 1),
	}
	entries: [2]Synchronization_Manifest_Entry
	request := synchronization_test_request("local-sync", 17, .None)
	_, _, unavailable_ok, unavailable_failure := prepare_synchronization_manifest(request, providers[:], candidates[:], entries[:])
	testing.expect(t, !unavailable_ok)
	testing.expect_value(t, unavailable_failure.code, Failure_Code.Unavailable)
	providers[0].state = .Available
	candidates[1].resource_id = candidates[0].resource_id
	_, _, duplicate_ok, duplicate_failure := prepare_synchronization_manifest(request, providers[:], candidates[:], entries[:])
	testing.expect(t, !duplicate_ok)
	testing.expect_value(t, duplicate_failure.code, Failure_Code.Conflict)
	candidates[1].resource_id = 103
	manifest, count, prepared, _ := prepare_synchronization_manifest(request, providers[:], candidates[:], entries[:])
	testing.expect(t, prepared)
	remote := [2]Synchronization_Remote_Observation {
		synchronization_test_remote(101, entries[0].base_digest, 1, 3),
		synchronization_test_remote(103, entries[1].base_digest, 1, 5),
	}
	remote[1].checksum_valid = false
	reconciled: [2]Synchronization_Reconciliation_Entry
	_, corrupt_ok, corrupt_failure := reconcile_synchronization_manifest(manifest, entries[:count], remote[:], nil, reconciled[:])
	testing.expect(t, !corrupt_ok)
	testing.expect_value(t, corrupt_failure.code, Failure_Code.Validation)

	temporaries := []Temporary_Resource {{resource_id = 701, kind = .Directory, created = true, cleaned = true}}
	retention := []Synchronization_Retention_Record {
		{resource_id = 701, generation = 7, expired = true, removed = true},
		{resource_id = 703, generation = 9, expired = true, protected = true},
	}
	testing.expect(t, synchronization_cleanup_complete(temporaries, retention))
	retention[1].removed = true
	testing.expect(t, !synchronization_cleanup_complete(temporaries, retention))
}

@(private = "file")
synchronization_test_request :: proc(
	provider: string,
	generation: Provider_Generation,
	attachments: Synchronization_Attachment_Policy,
) -> Synchronization_Project_Request {
	return {operation_id = 401, manifest_id = 403, provider_identity = provider,
		provider_generation = generation, staging_resource_id = 405, staging_revision = 11,
		push_generation = 7, pull_generation = 9, attachment_policy = attachments,
		entry_limit = 16, retention_generations = 3, explicit = true}
}

@(private = "file")
synchronization_test_candidate :: proc(
	resource_id: u64,
	kind: Synchronization_Entry_Kind,
	referenced, selected: bool,
	base_value, local_value: u8,
) -> Synchronization_Source_Candidate {
	candidate := Synchronization_Source_Candidate {resource_id = resource_id,
		base_revision = 3, local_revision = 5, kind = kind, referenced = referenced, selected = selected}
	candidate.base_digest[0] = base_value
	candidate.local_digest[0] = local_value
	return candidate
}

@(private = "file")
synchronization_test_remote :: proc(
	resource_id: u64,
	base_digest: [32]u8,
	remote_value: u8,
	revision: u64,
) -> Synchronization_Remote_Observation {
	remote := Synchronization_Remote_Observation {resource_id = resource_id,
		remote_revision = revision, base_digest = base_digest, checksum_valid = true}
	remote.remote_digest[0] = remote_value
	return remote
}
