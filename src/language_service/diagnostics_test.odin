// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_service

import project_core "../project"
import "base:runtime"
import "core:mem"
import "core:testing"

@(private)
diagnostic_test_open :: proc(
	synchronizer: ^Document_Synchronizer,
	registry: ^project_core.Registry,
	session: Session_Handle,
	allocator: mem.Allocator,
) -> (Document_Binding_Handle, bool) {
	_, project_handle, membership, project_ready := synchronization_test_project(
		registry,
		"/work/diagnostics",
		.Trusted,
		8_101,
		allocator,
	)
	if !project_ready do return {}, false
	languages := [1]string{"fixture"}
	synchronizer_ready, _ := document_synchronizer_init(
		synchronizer,
		registry,
		Synchronizer_Request{
			session = session,
			project = project_handle,
			membership = membership,
			root_policy = .Project_Membership,
			languages = languages[:],
			capabilities = {.Initialize, .Shutdown, .Full_Synchronization, .Push_Diagnostics},
			position_encoding = .UTF_16,
			synchronization_mode = .Full,
			limits = DEFAULT_LIMITS,
		},
		allocator,
	)
	if !synchronizer_ready do return {}, false
	binding, opened, _ := document_synchronizer_open(
		synchronizer,
		Document_Open_Request{
			document_identity = 8_111,
			buffer_identity = 8_113,
			canonical_revision = 1,
			path = "/work/diagnostics/source.fixture",
			uri = "file:///work/diagnostics/source.fixture",
			language = "fixture",
			text = "a😀b\n",
		},
	)
	if !opened do return {}, false
	message, queued := document_synchronizer_peek(synchronizer)
	if !queued do return {}, false
	acked := document_synchronizer_ack(synchronizer, message.record.generation)
	return binding, acked
}

/* Verifies version provenance, UTF-16 ranges, partial rejection, invalidation, and cleanup. */
@(test)
publish_only_for_the_exact_current_revision :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	session := synchronization_test_session(8_001)
	registry: project_core.Registry
	synchronizer: Document_Synchronizer
	binding, ready := diagnostic_test_open(&synchronizer, &registry, session, allocator)
	testing.expect(t, ready)
	if !ready {
		mem.tracking_allocator_destroy(&tracking)
		return
	}
	store: Diagnostic_Store
	store_ready, store_failure := diagnostic_store_init(&store, session, DEFAULT_LIMITS, allocator)
	testing.expectf(t, store_ready, "diagnostic store failed: %v", store_failure.code)
	if store_ready {
		items := [?]Diagnostic_Item_Proposal{
			{
				start = {line = 0, character = 1},
				end = {line = 0, character = 3},
				has_severity = true,
				severity = .Error,
				message = "emoji",
				source = "fixture",
				code = "E1",
				field_count = 6,
			},
			{
				start = {line = 0, character = 4},
				end = {line = 0, character = 4},
				message = "point",
				field_count = 3,
			},
			{
				start = {line = 0, character = 2},
				end = {line = 0, character = 3},
				has_severity = true,
				severity = .Warning,
				message = "inside surrogate",
				field_count = 4,
			},
		}
		descriptor, published, failure := diagnostic_store_publish(
			&store,
			&synchronizer,
			Diagnostic_Batch_Proposal{
				binding = binding,
				uri = "file:///work/diagnostics/source.fixture",
				has_version = true,
				document_version = 1,
				items = items[:],
			},
		)
		testing.expectf(t, published, "diagnostic publish failed: %v", failure.code)
		testing.expect_value(t, descriptor.provenance, Diagnostic_Provenance.Server_Versioned)
		testing.expect_value(t, descriptor.diagnostics, u32(2))
		testing.expect_value(t, descriptor.rejected_items, u32(1))
		testing.expect_value(t, descriptor.errors, u32(1))
		testing.expect_value(t, descriptor.information, u32(1))
		copy_batch, copied, _ := diagnostic_store_copy(&store, binding)
		testing.expect(t, copied)
		if copied {
			testing.expect_value(t, copy_batch.records[0].range, Diagnostic_Range{start = 1, end = 5})
			testing.expect(t, copy_batch.records[1].point)
			testing.expect_value(t, diagnostic_record_text(&copy_batch, copy_batch.records[0].message), "emoji")
			diagnostic_batch_copy_close(&copy_batch)
		}
		late := Diagnostic_Batch_Proposal{
			binding = binding,
			uri = "file:///work/diagnostics/source.fixture",
			has_version = true,
			document_version = 0,
			items = items[:1],
		}
		_, late_published, late_failure := diagnostic_store_publish(&store, &synchronizer, late)
		testing.expect(t, !late_published)
		testing.expect_value(t, late_failure.code, Failure_Code.Stale_Generation)
		preserved, preserved_ok, _ := diagnostic_store_copy(&store, binding)
		testing.expect(t, preserved_ok)
		if preserved_ok {
			testing.expect_value(t, preserved.descriptor.generation, descriptor.generation)
			diagnostic_batch_copy_close(&preserved)
		}
		invalidated, _ := diagnostic_store_invalidate(&store, binding)
		testing.expect(t, invalidated)
		_, remains, _ := diagnostic_store_copy(&store, binding)
		testing.expect(t, !remains)
		change_ok, _ := document_synchronizer_change(
			&synchronizer,
			Document_Change_Request{
				binding = binding,
				base_revision = 1,
				target_revision = 2,
				start = 0,
				end = 0,
				replacement = "x",
				target_text = "xa😀b\n",
			},
		)
		testing.expect(t, change_ok)
		receipt := Diagnostic_Batch_Proposal{
			binding = binding,
			uri = "file:///work/diagnostics/source.fixture",
			receipt_revision = 2,
			items = items[:1],
		}
		_, pending_published, pending_failure := diagnostic_store_publish(&store, &synchronizer, receipt)
		testing.expect(t, !pending_published)
		testing.expect_value(t, pending_failure.code, Failure_Code.Stale_Generation)
		change_message, change_queued := document_synchronizer_peek(&synchronizer)
		testing.expect(t, change_queued)
		if change_queued do testing.expect(t, document_synchronizer_ack(&synchronizer, change_message.record.generation))
		receipt.items = nil
		receipt_descriptor, receipt_published, _ := diagnostic_store_publish(&store, &synchronizer, receipt)
		testing.expect(t, receipt_published)
		testing.expect_value(t, receipt_descriptor.provenance, Diagnostic_Provenance.Receipt_Bound)
		testing.expect_value(t, receipt_descriptor.canonical_revision, u64(2))
		diagnostic_store_close(&store)
	}
	document_synchronizer_close(&synchronizer)
	project_core.registry_close(&registry)
	testing.expect_value(t, tracking.current_memory_allocated, 0)
	mem.tracking_allocator_destroy(&tracking)
}

/* Verifies protocol notifications stay in the generic decoder and publish copied diagnostics. */
@(test)
notification_decodes_without_provider_logic :: proc(t: ^testing.T) {
	session := synchronization_test_session(8_151)
	registry: project_core.Registry
	synchronizer: Document_Synchronizer
	binding, ready := diagnostic_test_open(&synchronizer, &registry, session, context.allocator)
	testing.expect(t, ready)
	if !ready do return
	defer {
		document_synchronizer_close(&synchronizer)
		project_core.registry_close(&registry)
	}
	store: Diagnostic_Store
	initialized, _ := diagnostic_store_init(&store, session, DEFAULT_LIMITS)
	testing.expect(t, initialized)
	if !initialized do return
	defer diagnostic_store_close(&store)
	body := transmute([]u8)(string(`{"jsonrpc":"2.0","method":"textDocument/publishDiagnostics","params":{"uri":"file:///work/diagnostics/source.fixture","version":1,"diagnostics":[{"range":{"start":{"line":0,"character":1},"end":{"line":0,"character":3}},"severity":2,"message":"warning","source":"fixture","code":"W1"},{"range":{"start":{"line":0,"character":2},"end":{"line":0,"character":3}},"severity":1,"message":"invalid surrogate"}]}}`))
	message, decoded, decode_failure := message_decode(body)
	testing.expectf(t, decoded, "diagnostic message failed: %v", decode_failure.code)
	if !decoded do return
	defer message_close(&message)
	uri, uri_ok := diagnostic_message_uri(&message, DEFAULT_LIMITS.uri_bytes)
	testing.expect(t, uri_ok)
	if uri_ok {
		testing.expect_value(t, uri, "file:///work/diagnostics/source.fixture")
		delete(uri)
	}
	descriptor, published, publish_failure := diagnostic_store_publish_message(
		&store,
		&synchronizer,
		binding,
		1,
		&message,
	)
	testing.expectf(t, published, "diagnostic notification failed: %v", publish_failure.code)
	if published {
		testing.expect_value(t, descriptor.diagnostics, u32(1))
		testing.expect_value(t, descriptor.rejected_items, u32(1))
		testing.expect_value(t, descriptor.warnings, u32(1))
	}
}

/* Verifies an excessive batch rejects atomically and preserves the prior generation. */
@(test)
batch_limits_keep_confirmed_generation :: proc(t: ^testing.T) {
	session := synchronization_test_session(8_201)
	registry: project_core.Registry
	synchronizer: Document_Synchronizer
	binding, ready := diagnostic_test_open(&synchronizer, &registry, session, context.allocator)
	testing.expect(t, ready)
	if !ready do return
	defer {
		document_synchronizer_close(&synchronizer)
		project_core.registry_close(&registry)
	}
	limits := DEFAULT_LIMITS
	limits.diagnostics_per_document = 1
	store: Diagnostic_Store
	initialized, _ := diagnostic_store_init(&store, session, limits)
	testing.expect(t, initialized)
	if !initialized do return
	defer diagnostic_store_close(&store)
	item := Diagnostic_Item_Proposal{
		start = {}, end = {line = 0, character = 1}, message = "one", field_count = 3,
	}
	proposal := Diagnostic_Batch_Proposal{
		binding = binding,
		uri = "file:///work/diagnostics/source.fixture",
		has_version = true,
		document_version = 1,
		items = []Diagnostic_Item_Proposal{item},
	}
	first, published, _ := diagnostic_store_publish(&store, &synchronizer, proposal)
	testing.expect(t, published)
	excessive := [2]Diagnostic_Item_Proposal{item, item}
	proposal.items = excessive[:]
	_, replaced, failure := diagnostic_store_publish(&store, &synchronizer, proposal)
	testing.expect(t, !replaced)
	testing.expect_value(t, failure.resource, Resource_Kind.Diagnostic)
	preserved, copied, _ := diagnostic_store_copy(&store, binding)
	testing.expect(t, copied)
	if copied {
		testing.expect_value(t, preserved.descriptor.generation, first.generation)
		diagnostic_batch_copy_close(&preserved)
	}
}

/* Verifies malformed batches and every diagnostic allocation fault preserve ownership. */
@(test)
publish_faults_leave_no_partial_generation :: proc(t: ^testing.T) {
	session := synchronization_test_session(8_301)
	registry: project_core.Registry
	synchronizer: Document_Synchronizer
	binding, ready := diagnostic_test_open(&synchronizer, &registry, session, context.allocator)
	if !ready do return
	defer {
		document_synchronizer_close(&synchronizer)
		project_core.registry_close(&registry)
	}
	item := Diagnostic_Item_Proposal {start = {}, end = {line = 0, character = 1},
		message = "failure", field_count = 3}
	for fail_after in 0..<u64(8) {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		failing := Diagnostic_Failing_Allocator {backing = mem.tracking_allocator(&tracking),
			fail_after = fail_after}
		store: Diagnostic_Store
		initialized, initialize_failure := diagnostic_store_init(
			&store, session, DEFAULT_LIMITS, diagnostic_failing_allocator(&failing))
		if initialized {
			_, published, publication_failure := diagnostic_store_publish(
				&store, &synchronizer, {binding = binding,
					uri = "file:///work/diagnostics/source.fixture", has_version = true,
					document_version = 1, items = []Diagnostic_Item_Proposal{item}})
			if !published do testing.expect_value(t, publication_failure.code, Failure_Code.Allocation)
			diagnostic_store_close(&store)
		} else {
			testing.expect_value(t, initialize_failure.code, Failure_Code.Allocation)
		}
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		mem.tracking_allocator_destroy(&tracking)
	}

	store: Diagnostic_Store
	initialized, _ := diagnostic_store_init(&store, session, DEFAULT_LIMITS)
	if initialized {
		_, published, failure := diagnostic_store_publish(&store, &synchronizer,
			{binding = binding, uri = "file:///outside.fixture", has_version = true,
				document_version = 1, items = []Diagnostic_Item_Proposal{item}})
		testing.expect(t, !published)
		testing.expect_value(t, failure.code, Failure_Code.Invalid_Document)
		inspection, inspected := diagnostic_store_inspect(&store)
		testing.expect(t, inspected)
		if inspected do testing.expect_value(t, inspection.generations, u32(0))
		diagnostic_store_close(&store)
	}
}

@(private)
Diagnostic_Failing_Allocator :: struct {
	backing:                runtime.Allocator,
	fail_after:             u64,
	successful_allocations: u64,
}

@(private)
diagnostic_failing_allocator :: proc(data: ^Diagnostic_Failing_Allocator) -> runtime.Allocator {
	return {procedure = diagnostic_failing_allocator_proc, data = data}
}

@(private)
diagnostic_failing_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> ([]byte, runtime.Allocator_Error) {
	allocator := (^Diagnostic_Failing_Allocator)(allocator_data)
	if mode == .Alloc || mode == .Resize || mode == .Resize_Non_Zeroed {
		if allocator.successful_allocations >= allocator.fail_after {
			return nil, runtime.Allocator_Error.Out_Of_Memory
		}
		allocator.successful_allocations += 1
	}
	return allocator.backing.procedure(allocator.backing.data, mode, size, alignment,
		old_memory, old_size, location)
}
