// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_service

import project_core "../project"
import "core:mem"
import "core:strings"
import "core:testing"

@(private)
SYNCHRONIZATION_TEST_LANGUAGES := [1]string{"fixture"}

@(private)
synchronization_test_session :: proc(seed: u64) -> Session_Handle {
	registry := Registry_Handle{id = Registry_ID(seed), generation = Registry_Generation(1)}
	definition := Definition_Handle{registry = registry, id = Definition_ID(seed + 1), generation = Definition_Generation(1)}
	provider := Provider_Handle{definition = definition, id = Provider_ID(seed + 2), generation = Provider_Generation(1)}
	return Session_Handle{provider = provider, id = Session_ID(seed + 3), generation = Session_Generation(1)}
}

@(private)
synchronization_test_project :: proc(
	registry: ^project_core.Registry,
	root: string,
	trust: project_core.Trust_State,
	seed: u64,
	allocator := context.allocator,
) -> (project_core.Owner_Handle, project_core.Project_Handle, project_core.Membership_Handle, bool) {
	owner := project_core.Owner_Handle{
		id = project_core.Owner_ID(seed),
		generation = project_core.Owner_Generation(1),
	}
	initialized, _ := project_core.registry_init(
		registry,
		owner,
		project_core.DEFAULT_POLICY,
		project_core.Allocator_Set{persistent = allocator, temporary = context.temp_allocator},
	)
	if !initialized do return {}, {}, {}, false
	directories := [1]project_core.Directory_Proposal{{path = root, trust = trust}}
	prepared: project_core.Prepared_Snapshot
	prepared_ok, _ := project_core.registry_prepare_snapshot(
		registry,
		project_core.Snapshot_Request{
			owner = owner,
			project_id = project_core.Project_ID(seed + 1),
			name = "Synchronization Test",
			directories = directories[:],
			temporary = true,
		},
		&prepared,
	)
	if !prepared_ok {
		project_core.registry_close(registry)
		return {}, {}, {}, false
	}
	descriptor, published, _ := project_core.prepared_snapshot_publish(registry, &prepared)
	if !published {
		project_core.registry_close(registry)
		return {}, {}, {}, false
	}
	batch, copied, _ := project_core.registry_membership_descriptors(registry, descriptor.handle)
	if !copied || len(batch.descriptors) != 1 {
		if copied do project_core.descriptor_batch_close(&batch)
		project_core.registry_close(registry)
		return {}, {}, {}, false
	}
	membership := batch.descriptors[0].handle
	project_core.descriptor_batch_close(&batch)
	return owner, descriptor.handle, membership, true
}

@(private)
synchronization_test_request :: proc(
	session: Session_Handle,
	project_handle: project_core.Project_Handle,
	membership: project_core.Membership_Handle,
	mode: Synchronization_Mode,
) -> Synchronizer_Request {
	return Synchronizer_Request{
		session = session,
		project = project_handle,
		membership = membership,
		root_policy = .Project_Membership,
		languages = SYNCHRONIZATION_TEST_LANGUAGES[:],
		capabilities = {
			.Initialize,
			.Shutdown,
			.Full_Synchronization,
			.Incremental_Synchronization,
			.Save_Notification,
		},
		position_encoding = .UTF_16,
		synchronization_mode = mode,
		limits = DEFAULT_LIMITS,
	}
}

@(private)
synchronization_test_open_request :: proc(revision: u64 = 1) -> Document_Open_Request {
	return Document_Open_Request{
		document_identity = 41,
		buffer_identity = 43,
		canonical_revision = revision,
		path = "/work/fixture/source.fixture",
		uri = "file:///work/fixture/source.fixture",
		language = "fixture",
		text = "a😀b\n",
	}
}

@(private)
synchronization_test_expect_method :: proc(
	t: ^testing.T,
	view: Synchronization_Message_View,
	expected: string,
) {
	message, decoded, failure := message_decode(view.body)
	testing.expectf(t, decoded, "queued JSON-RPC decode failed: %v", failure.code)
	if !decoded do return
	method := string(message.record.method.bytes[:int(message.record.method.length)])
	testing.expect_value(t, method, expected)
	message_close(&message)
}

/* Verifies a trusted exact Project membership admits one versioned didOpen binding. */
@(test)
trusted_membership_opens_versioned_doc :: proc(t: ^testing.T) {
	project_registry: project_core.Registry
	_, project_handle, membership, project_ok := synchronization_test_project(
		&project_registry, "/work/fixture", .Trusted, 101,
	)
	testing.expect(t, project_ok)
	if !project_ok do return
	defer project_core.registry_close(&project_registry)

	synchronizer: Document_Synchronizer
	initialized, failure := document_synchronizer_init(
		&synchronizer,
		&project_registry,
		synchronization_test_request(synchronization_test_session(111), project_handle, membership, .Incremental),
	)
	testing.expectf(t, initialized, "synchronizer init failed: %v", failure.code)
	if !initialized do return
	defer document_synchronizer_close(&synchronizer)

	binding, opened, open_failure := document_synchronizer_open(&synchronizer, synchronization_test_open_request())
	testing.expectf(t, opened, "document open failed: %v", open_failure.code)
	descriptor, described, _ := document_synchronizer_binding(&synchronizer, binding)
	testing.expect(t, described)
	if described {
		testing.expect_value(t, descriptor.document_version, i64(1))
		testing.expect_value(t, descriptor.canonical_revision, u64(1))
		testing.expect_value(t, descriptor.synchronization_mode, Synchronization_Mode.Incremental)
	}
	view, queued := document_synchronizer_peek(&synchronizer)
	testing.expect(t, queued)
	if queued {
		testing.expect_value(t, view.operation, Synchronization_Operation.Open)
		synchronization_test_expect_method(t, view, "textDocument/didOpen")
		testing.expect(t, document_synchronizer_ack(&synchronizer, view.record.generation))
	}
}

/* Verifies full and incremental modes reach identical canonical text and versions. */
@(test)
change_modes_have_equivalent_state :: proc(t: ^testing.T) {
	project_registry: project_core.Registry
	_, project_handle, membership, project_ok := synchronization_test_project(
		&project_registry, "/work/fixture", .Trusted, 131,
	)
	testing.expect(t, project_ok)
	if !project_ok do return
	defer project_core.registry_close(&project_registry)

	full, incremental: Document_Synchronizer
	full_ok, _ := document_synchronizer_init(
		&full, &project_registry,
		synchronization_test_request(synchronization_test_session(137), project_handle, membership, .Full),
	)
	incremental_ok, _ := document_synchronizer_init(
		&incremental, &project_registry,
		synchronization_test_request(synchronization_test_session(149), project_handle, membership, .Incremental),
	)
	testing.expect(t, full_ok && incremental_ok)
	if !full_ok || !incremental_ok {
		if full_ok do document_synchronizer_close(&full)
		if incremental_ok do document_synchronizer_close(&incremental)
		return
	}
	defer document_synchronizer_close(&full)
	defer document_synchronizer_close(&incremental)
	full_binding, full_opened, _ := document_synchronizer_open(&full, synchronization_test_open_request())
	incremental_binding, incremental_opened, _ := document_synchronizer_open(&incremental, synchronization_test_open_request())
	testing.expect(t, full_opened && incremental_opened)
	synchronizers := [2]^Document_Synchronizer{&full, &incremental}
	for synchronizer in synchronizers {
		view, queued := document_synchronizer_peek(synchronizer)
		if queued do document_synchronizer_ack(synchronizer, view.record.generation)
	}

	full_changed, full_failure := document_synchronizer_change(
		&full,
		Document_Change_Request{
			binding = full_binding,
			base_revision = 1,
			target_revision = 2,
			start = 1,
			end = 5,
			replacement = "Z",
			target_text = "aZb\n",
		},
	)
	incremental_changed, incremental_failure := document_synchronizer_change(
		&incremental,
		Document_Change_Request{
			binding = incremental_binding,
			base_revision = 1,
			target_revision = 2,
			start = 1,
			end = 5,
			replacement = "Z",
			target_text = "aZb\n",
		},
	)
	testing.expectf(t, full_changed, "full change failed: %v", full_failure.code)
	testing.expectf(t, incremental_changed, "incremental change failed: %v", incremental_failure.code)
	full_text, full_text_ok, _ := document_synchronizer_text(&full, full_binding)
	incremental_text, incremental_text_ok, _ := document_synchronizer_text(&incremental, incremental_binding)
	testing.expect(t, full_text_ok && incremental_text_ok)
	testing.expect_value(t, full_text, incremental_text)
	testing.expect_value(t, full_text, "aZb\n")
	full_descriptor, _, _ := document_synchronizer_binding(&full, full_binding)
	incremental_descriptor, _, _ := document_synchronizer_binding(&incremental, incremental_binding)
	testing.expect_value(t, full_descriptor.document_version, incremental_descriptor.document_version)
	testing.expect_value(t, full_descriptor.document_version, i64(2))

	full_view, full_queued := document_synchronizer_peek(&full)
	incremental_view, incremental_queued := document_synchronizer_peek(&incremental)
	testing.expect(t, full_queued && incremental_queued)
	if full_queued {
		synchronization_test_expect_method(t, full_view, "textDocument/didChange")
		testing.expect(t, strings.contains(string(full_view.body), `"text":"aZb\n"`))
	}
	if incremental_queued {
		synchronization_test_expect_method(t, incremental_view, "textDocument/didChange")
		testing.expect(t, strings.contains(string(incremental_view.body), `"character":3`))
		testing.expect(t, strings.contains(string(incremental_view.body), `"text":"Z"`))
	}
}

/* Verifies recovery coalesces queued work before save and close complete the lifecycle. */
@(test)
recovery_publishes_full_current_update :: proc(t: ^testing.T) {
	project_registry: project_core.Registry
	_, project_handle, membership, project_ok := synchronization_test_project(
		&project_registry, "/work/fixture", .Trusted, 163,
	)
	testing.expect(t, project_ok)
	if !project_ok do return
	defer project_core.registry_close(&project_registry)
	synchronizer: Document_Synchronizer
	initialized, _ := document_synchronizer_init(
		&synchronizer, &project_registry,
		synchronization_test_request(synchronization_test_session(167), project_handle, membership, .Incremental),
	)
	testing.expect(t, initialized)
	if !initialized do return
	defer document_synchronizer_close(&synchronizer)
	binding, opened, _ := document_synchronizer_open(&synchronizer, synchronization_test_open_request())
	testing.expect(t, opened)
	open_view, _ := document_synchronizer_peek(&synchronizer)
	document_synchronizer_ack(&synchronizer, open_view.record.generation)
	changed, _ := document_synchronizer_change(
		&synchronizer,
		Document_Change_Request{
			binding = binding, base_revision = 1, target_revision = 2,
			start = 1, end = 5, replacement = "Z", target_text = "aZb\n",
		},
	)
	testing.expect(t, changed)
	saved, _ := document_synchronizer_save(&synchronizer, binding, 2)
	testing.expect(t, saved)
	recovered, recovery_failure := document_synchronizer_recover(&synchronizer, binding, 2, "aZb\n")
	testing.expectf(t, recovered, "recovery failed: %v", recovery_failure.code)
	inspection, _ := document_synchronizer_inspect(&synchronizer)
	testing.expect_value(t, inspection.queue_depth, u32(1))
	view, queued := document_synchronizer_peek(&synchronizer)
	testing.expect(t, queued)
	if queued {
		testing.expect_value(t, view.operation, Synchronization_Operation.Recover)
		synchronization_test_expect_method(t, view, "textDocument/didChange")
		document_synchronizer_ack(&synchronizer, view.record.generation)
	}
	closed, close_failure := document_synchronizer_close_document(&synchronizer, binding, 2)
	testing.expectf(t, closed, "close failed: %v", close_failure.code)
	close_view, close_queued := document_synchronizer_peek(&synchronizer)
	testing.expect(t, close_queued)
	if close_queued do synchronization_test_expect_method(t, close_view, "textDocument/didClose")
}

/* Verifies untrusted, external, and revoked Project scopes cannot synchronize documents. */
@(test)
each_op_revalidates_trust_and_membership :: proc(t: ^testing.T) {
	untrusted_registry: project_core.Registry
	_, untrusted_project, untrusted_membership, untrusted_ok := synchronization_test_project(
		&untrusted_registry, "/work/untrusted", .Untrusted, 181,
	)
	testing.expect(t, untrusted_ok)
	if untrusted_ok {
		synchronizer: Document_Synchronizer
		initialized, failure := document_synchronizer_init(
			&synchronizer, &untrusted_registry,
			synchronization_test_request(synchronization_test_session(191), untrusted_project, untrusted_membership, .Full),
		)
		testing.expect(t, !initialized)
		testing.expect_value(t, failure.code, Failure_Code.Untrusted_Root)
		project_core.registry_close(&untrusted_registry)
	}

	project_registry: project_core.Registry
	owner, project_handle, membership, project_ok := synchronization_test_project(
		&project_registry, "/work/fixture", .Trusted, 193,
	)
	testing.expect(t, project_ok)
	if !project_ok do return
	defer project_core.registry_close(&project_registry)
	synchronizer: Document_Synchronizer
	initialized, _ := document_synchronizer_init(
		&synchronizer, &project_registry,
		synchronization_test_request(synchronization_test_session(197), project_handle, membership, .Full),
	)
	testing.expect(t, initialized)
	if !initialized do return
	defer document_synchronizer_close(&synchronizer)
	external := synchronization_test_open_request()
	external.path = "/outside/source.fixture"
	external.uri = "file:///outside/source.fixture"
	_, external_opened, external_failure := document_synchronizer_open(&synchronizer, external)
	testing.expect(t, !external_opened)
	testing.expect_value(t, external_failure.code, Failure_Code.Outside_Root)

	replacement := [1]project_core.Directory_Proposal{{path = "/work/fixture", trust = .Untrusted}}
	prepared: project_core.Prepared_Snapshot
	prepared_ok, _ := project_core.registry_prepare_snapshot(
		&project_registry,
		project_core.Snapshot_Request{
			owner = owner,
			project_id = project_handle.id,
			name = "Synchronization Test",
			directories = replacement[:],
			temporary = true,
		},
		&prepared,
	)
	testing.expect(t, prepared_ok)
	_, published, _ := project_core.prepared_snapshot_publish(&project_registry, &prepared)
	testing.expect(t, published)
	_, opened, revoked_failure := document_synchronizer_open(&synchronizer, synchronization_test_open_request())
	testing.expect(t, !opened)
	testing.expect_value(t, revoked_failure.code, Failure_Code.Revoked)
	inspection, _ := document_synchronizer_inspect(&synchronizer)
	testing.expect(t, inspection.revoked)
}

/* Verifies Project, document, and queue owners release all tracked allocations. */
@(test)
synchronizer_releases_owned_storage :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	project_registry: project_core.Registry
	_, project_handle, membership, project_ok := synchronization_test_project(
		&project_registry, "/work/fixture", .Trusted, 211, allocator,
	)
	testing.expect(t, project_ok)
	if !project_ok {
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	synchronizer: Document_Synchronizer
	initialized, _ := document_synchronizer_init(
		&synchronizer, &project_registry,
		synchronization_test_request(synchronization_test_session(223), project_handle, membership, .Incremental),
		allocator,
	)
	testing.expect(t, initialized)
	if initialized {
		_, opened, _ := document_synchronizer_open(&synchronizer, synchronization_test_open_request())
		testing.expect(t, opened)
		document_synchronizer_close(&synchronizer)
	}
	project_core.registry_close(&project_registry)
	testing.expect_value(t, tracking.current_memory_allocated, 0)
	mem.tracking_allocator_destroy(&tracking)
}
