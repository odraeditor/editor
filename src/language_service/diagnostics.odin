// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_service

import "base:runtime"
import json "core:encoding/json"
import "core:strings"
import "core:unicode/utf8"

/* Diagnostic_Provenance identifies how one publication was bound to a revision. */
Diagnostic_Provenance :: enum u8 {
	Invalid,
	Server_Versioned,
	Receipt_Bound,
}

/* Diagnostic_Severity is one language-independent semantic severity. */
Diagnostic_Severity :: enum u8 {
	Invalid,
	Error,
	Warning,
	Information,
	Hint,
}

/* Diagnostic_Range is one canonical half-open UTF-8 byte range. */
Diagnostic_Range :: struct {
	start: u64,
	end:   u64,
}

/* Diagnostic_Item_Proposal is one untrusted LSP diagnostic item. */
Diagnostic_Item_Proposal :: struct {
	start:             LSP_Position,
	end:               LSP_Position,
	has_severity:      bool,
	severity:          Diagnostic_Severity,
	message:           string,
	source:            string,
	code:              string,
	field_count:       u16,
	related_locations: u16,
}

/* Diagnostic_Batch_Proposal is one complete push-diagnostic notification. */
Diagnostic_Batch_Proposal :: struct {
	binding:         Document_Binding_Handle,
	uri:             string,
	has_version:     bool,
	document_version: i64,
	receipt_revision: u64,
	items:           []Diagnostic_Item_Proposal,
}

/* Diagnostic_Record is one copied normalized diagnostic. */
Diagnostic_Record :: struct {
	binding:            Document_Binding_Handle,
	generation:         Diagnostic_Generation,
	id:                 Diagnostic_ID,
	canonical_revision: u64,
	document_version:   i64,
	provenance:         Diagnostic_Provenance,
	range:              Diagnostic_Range,
	point:              bool,
	severity:           Diagnostic_Severity,
	message:            Storage_Range,
	source:             Storage_Range,
	code:               Storage_Range,
}

/* Diagnostic_Batch_Descriptor is one pointer-free complete generation summary. */
Diagnostic_Batch_Descriptor :: struct {
	binding:            Document_Binding_Handle,
	generation:         Diagnostic_Generation,
	canonical_revision: u64,
	document_version:   i64,
	provenance:         Diagnostic_Provenance,
	diagnostics:        u32,
	rejected_items:     u32,
	errors:             u32,
	warnings:           u32,
	information:        u32,
	hints:              u32,
	retained_bytes:     u64,
}

/* Diagnostic_Batch_Copy owns copied records and their shared text storage. */
Diagnostic_Batch_Copy :: struct {
	descriptor: Diagnostic_Batch_Descriptor,
	records:    []Diagnostic_Record,
	storage:    []u8,
	allocator:  runtime.Allocator,
}

/* Diagnostic_Inspection is one pointer-free store snapshot. */
Diagnostic_Inspection :: struct {
	session:        Session_Handle,
	generations:    u32,
	diagnostics:    u32,
	diagnostic_bytes: u64,
	retained_bytes:   u64,
	server_versioned: u32,
	receipt_bound:    u32,
	errors:           u32,
	warnings:         u32,
	information:      u32,
	hints:            u32,
	latest_failure: Failure_Context,
}

/* Diagnostic_Store owns at most one complete generation per document binding. */
Diagnostic_Store :: struct {
	state: rawptr,
}

@(private)
Diagnostic_Generation_Owner :: struct {
	descriptor: Diagnostic_Batch_Descriptor,
	records:    [dynamic]Diagnostic_Record,
	storage:    [dynamic]u8,
	live:       bool,
}

@(private)
Diagnostic_Store_State :: struct {
	session:         Session_Handle,
	generations:     [dynamic]Diagnostic_Generation_Owner,
	next_generation: Diagnostic_Generation,
	usage:           Resource_Usage,
	server_versioned: u32,
	receipt_bound:    u32,
	limits:          Service_Limits,
	latest_failure:  Failure_Context,
	allocator:       runtime.Allocator,
}

/* diagnostic_store_init creates one bounded session-owned diagnostic registry. */
diagnostic_store_init :: proc(
	store: ^Diagnostic_Store,
	session: Session_Handle,
	limits: Service_Limits,
	allocator := context.allocator,
) -> (bool, Failure_Context) {
	if store == nil || store.state != nil || session.id == 0 || session.generation == 0 ||
	   !service_limits_valid(limits) {
		return false, Failure_Context{code = .Invalid_Input, session = session}
	}
	state, state_error := new(Diagnostic_Store_State, allocator)
	if state_error != nil do return false, Failure_Context{code = .Allocation, session = session}
	state^ = Diagnostic_Store_State{session = session, next_generation = 1, limits = limits, allocator = allocator}
	state.generations, state_error = make(
		[dynamic]Diagnostic_Generation_Owner,
		0,
		int(limits.documents_per_session),
		allocator,
	)
	if state_error != nil {
		free(state, allocator)
		return false, Failure_Context{code = .Allocation, session = session}
	}
	state.usage.retained_bytes = diagnostic_store_base_bytes(state)
	if state.usage.retained_bytes > limits.retained_bytes {
		actual := state.usage.retained_bytes
		delete(state.generations)
		free(state, allocator)
		return false, Failure_Context{
			code = .Resource_Limit,
			resource = .Retained_Bytes,
			session = session,
			limit = limits.retained_bytes,
			actual = actual,
		}
	}
	store.state = state
	return true, {}
}

/* diagnostic_store_publish atomically replaces one complete current generation. */
diagnostic_store_publish :: proc(
	store: ^Diagnostic_Store,
	synchronizer: ^Document_Synchronizer,
	proposal: Diagnostic_Batch_Proposal,
) -> (Diagnostic_Batch_Descriptor, bool, Failure_Context) {
	state := diagnostic_store_state(store)
	if state == nil do return {}, false, Failure_Context{code = .Closed}
	scope, scoped := document_synchronizer_inspect(synchronizer)
	if !scoped || scope.session != state.session || scope.revoked {
		return diagnostic_store_reject(state, .Stale_Generation, proposal.binding)
	}
	binding, bound, binding_failure := document_synchronizer_binding(synchronizer, proposal.binding)
	if !bound || binding.state != .Open {
		if binding_failure.code == .None do binding_failure = diagnostic_failure(state, .Invalid_Document, proposal.binding)
		state.latest_failure = binding_failure
		return {}, false, binding_failure
	}
	uri, uri_ok, uri_failure := document_synchronizer_uri(synchronizer, proposal.binding)
	text, text_ok, text_failure := document_synchronizer_text(synchronizer, proposal.binding)
	if !uri_ok || !text_ok || proposal.uri != uri {
		failure := uri_failure
		if failure.code == .None do failure = text_failure
		if failure.code == .None do failure = diagnostic_failure(state, .Invalid_Document, proposal.binding)
		state.latest_failure = failure
		return {}, false, failure
	}
	if len(proposal.items) > int(state.limits.diagnostics_per_document) {
		return diagnostic_store_resource_reject(
			state, .Diagnostic, u64(state.limits.diagnostics_per_document), u64(len(proposal.items)), proposal.binding,
		)
	}
	provenance := Diagnostic_Provenance.Server_Versioned
	if proposal.has_version {
		if proposal.document_version != binding.document_version {
			return diagnostic_store_reject(state, .Stale_Generation, proposal.binding)
		}
	} else {
		provenance = .Receipt_Bound
		if proposal.receipt_revision != binding.canonical_revision || scope.queue_depth != 0 {
			return diagnostic_store_reject(state, .Stale_Generation, proposal.binding)
		}
	}
	if state.next_generation == Diagnostic_Generation(0) ||
	   state.next_generation == Diagnostic_Generation(max(u64)) {
		return diagnostic_store_reject(state, .Arithmetic_Overflow, proposal.binding)
	}
	work_per_item := u64(len(text)) * 2
	work_bytes := u64(0)
	if len(proposal.items) > 0 {
		item_count := u64(len(proposal.items))
		work_bytes = max(u64) if work_per_item > max(u64) / item_count else work_per_item * item_count
	}
	if work_per_item / 2 != u64(len(text)) || work_bytes > state.limits.work_bytes_per_turn {
		return diagnostic_store_resource_reject(
			state, .Work_Bytes, state.limits.work_bytes_per_turn,
			work_bytes, proposal.binding,
		)
	}
	candidate := Diagnostic_Generation_Owner{live = true}
	candidate.records, _ = make([dynamic]Diagnostic_Record, 0, len(proposal.items), state.allocator)
	if candidate.records == nil && len(proposal.items) > 0 {
		return diagnostic_store_reject(state, .Allocation, proposal.binding)
	}
	candidate.storage, _ = make([dynamic]u8, 0, 0, state.allocator)
	defer if candidate.live do diagnostic_generation_close(&candidate)
	generation := state.next_generation
	rejected := u32(0)
	for item in proposal.items {
		storage_start := len(candidate.storage)
		record, accepted := diagnostic_item_normalize(
			state, proposal.binding, generation, binding, provenance, text, item, &candidate.storage,
		)
		if !accepted {
			resize(&candidate.storage, storage_start)
			rejected += 1
			continue
		}
		record.id = Diagnostic_ID(len(candidate.records) + 1)
		if _, append_error := append(&candidate.records, record); append_error != nil {
			return diagnostic_store_reject(state, .Allocation, proposal.binding)
		}
	}
	old_index := diagnostic_store_find(state, proposal.binding)
	old_count, old_bytes := u64(0), u64(0)
	if old_index >= 0 {
		old_count = u64(state.generations[old_index].descriptor.diagnostics)
		old_bytes = state.generations[old_index].descriptor.retained_bytes
	}
	new_count := u64(len(candidate.records))
	new_bytes := u64(cap(candidate.storage)) + u64(cap(candidate.records)) * u64(size_of(Diagnostic_Record))
	projected_count := u64(state.usage.diagnostics) - old_count + new_count
	projected_bytes := state.usage.diagnostic_bytes - old_bytes + new_bytes
	projected_retained := diagnostic_store_base_bytes(state) + projected_bytes
	if projected_count > u64(state.limits.diagnostics_per_project) {
		return diagnostic_store_resource_reject(state, .Diagnostic, u64(state.limits.diagnostics_per_project), projected_count, proposal.binding)
	}
	if projected_bytes > state.limits.diagnostic_bytes {
		return diagnostic_store_resource_reject(state, .Diagnostic_Bytes, state.limits.diagnostic_bytes, projected_bytes, proposal.binding)
	}
	if projected_retained > state.limits.retained_bytes {
		return diagnostic_store_resource_reject(state, .Retained_Bytes, state.limits.retained_bytes, projected_retained, proposal.binding)
	}
	candidate.descriptor = Diagnostic_Batch_Descriptor{
		binding = proposal.binding,
		generation = generation,
		canonical_revision = binding.canonical_revision,
		document_version = binding.document_version,
		provenance = provenance,
		diagnostics = u32(new_count),
		rejected_items = rejected,
		retained_bytes = new_bytes,
	}
	for record in candidate.records {
		switch record.severity {
		case .Error: candidate.descriptor.errors += 1
		case .Warning: candidate.descriptor.warnings += 1
		case .Information: candidate.descriptor.information += 1
		case .Hint: candidate.descriptor.hints += 1
		case .Invalid:
		}
	}
	if old_index >= 0 {
		old_provenance := state.generations[old_index].descriptor.provenance
		diagnostic_generation_close(&state.generations[old_index])
		state.generations[old_index] = candidate
		if old_provenance == .Server_Versioned do state.server_versioned -= 1
		if old_provenance == .Receipt_Bound do state.receipt_bound -= 1
	} else {
		if _, append_error := append(&state.generations, candidate); append_error != nil {
			return diagnostic_store_reject(state, .Allocation, proposal.binding)
		}
	}
	candidate.live = false
	state.next_generation += 1
	state.usage.diagnostics = u32(projected_count)
	state.usage.diagnostic_bytes = projected_bytes
	state.usage.retained_bytes = projected_retained
	if provenance == .Server_Versioned do state.server_versioned += 1
	if provenance == .Receipt_Bound do state.receipt_bound += 1
	state.latest_failure = {}
	return state.generations[old_index if old_index >= 0 else len(state.generations) - 1].descriptor, true, {}
}

/* diagnostic_store_publish_message decodes and publishes one bounded push notification. */
diagnostic_store_publish_message :: proc(
	store: ^Diagnostic_Store,
	synchronizer: ^Document_Synchronizer,
	binding: Document_Binding_Handle,
	receipt_revision: u64,
	message: ^Message,
) -> (Diagnostic_Batch_Descriptor, bool, Failure_Context) {
	state := diagnostic_store_state(store)
	if state == nil do return {}, false, Failure_Context{code = .Closed}
	if message == nil || message.closed || message.record.kind != .Notification ||
	   !message_method_is(message, "textDocument/publishDiagnostics") {
		return diagnostic_store_reject(state, .Protocol, binding)
	}
	value, parse_error := json.parse_bytes(message.body, .JSON, true, context.temp_allocator)
	if parse_error != .None {
		return diagnostic_store_reject(state, .Malformed_JSON, binding)
	}
	defer json.destroy_value(value, context.temp_allocator)
	object, object_ok := value.(json.Object)
	if !object_ok do return diagnostic_store_reject(state, .Protocol, binding)
	params_value, params_present := object["params"]
	if !params_present do return diagnostic_store_reject(state, .Protocol, binding)
	params, params_ok := params_value.(json.Object)
	if !params_ok do return diagnostic_store_reject(state, .Protocol, binding)
	uri_value, uri_present := params["uri"]
	diagnostics_value, diagnostics_present := params["diagnostics"]
	uri, uri_ok := uri_value.(json.String)
	diagnostics, diagnostics_ok := diagnostics_value.(json.Array)
	if !uri_present || !diagnostics_present || !uri_ok || !diagnostics_ok ||
	   len(uri) == 0 || u64(len(uri)) > state.limits.uri_bytes ||
	   len(diagnostics) > int(state.limits.diagnostics_per_document) {
		return diagnostic_store_reject(state, .Protocol, binding)
	}
	items, allocation_error := make([]Diagnostic_Item_Proposal, len(diagnostics), context.temp_allocator)
	if allocation_error != nil do return diagnostic_store_reject(state, .Allocation, binding)
	defer delete(items, context.temp_allocator)
	for item_value, index in diagnostics {
		items[index] = diagnostic_item_from_json(item_value, state.limits)
	}
	proposal := Diagnostic_Batch_Proposal {
		binding = binding,
		uri = string(uri),
		receipt_revision = receipt_revision,
		items = items,
	}
	if version_value, version_present := params["version"]; version_present {
		#partial switch version in version_value {
		case json.Integer:
			proposal.has_version = true
			proposal.document_version = i64(version)
		case json.Null:
		case:
			return diagnostic_store_reject(state, .Protocol, binding)
		}
	}
	return diagnostic_store_publish(store, synchronizer, proposal)
}

/* diagnostic_message_uri copies the target URI from one push notification. */
diagnostic_message_uri :: proc(
	message: ^Message,
	maximum_bytes: u64,
	allocator := context.allocator,
) -> (string, bool) {
	if message == nil || message.closed || message.record.kind != .Notification ||
	   !message_method_is(message, "textDocument/publishDiagnostics") ||
	   maximum_bytes == 0 || allocator.procedure == nil {
		return "", false
	}
	value, parse_error := json.parse_bytes(message.body, .JSON, true, context.temp_allocator)
	if parse_error != .None do return "", false
	defer json.destroy_value(value, context.temp_allocator)
	object, object_ok := value.(json.Object)
	if !object_ok do return "", false
	params_value, params_present := object["params"]
	if !params_present do return "", false
	params, params_ok := params_value.(json.Object)
	if !params_ok do return "", false
	uri_value, uri_present := params["uri"]
	uri, uri_ok := uri_value.(json.String)
	if !uri_present || !uri_ok || len(uri) == 0 || u64(len(uri)) > maximum_bytes do return "", false
	owned, allocation_error := strings.clone(string(uri), allocator)
	return owned, allocation_error == nil
}

/* diagnostic_store_invalidate removes current diagnostics before a canonical edit. */
diagnostic_store_invalidate :: proc(
	store: ^Diagnostic_Store,
	binding: Document_Binding_Handle,
) -> (bool, Failure_Context) {
	state := diagnostic_store_state(store)
	if state == nil do return false, Failure_Context{code = .Closed}
	index := diagnostic_store_find(state, binding)
	if index < 0 do return true, {}
	descriptor := state.generations[index].descriptor
	state.usage.diagnostics -= descriptor.diagnostics
	state.usage.diagnostic_bytes -= descriptor.retained_bytes
	state.usage.retained_bytes = diagnostic_store_base_bytes(state) + state.usage.diagnostic_bytes
	if descriptor.provenance == .Server_Versioned do state.server_versioned -= 1
	if descriptor.provenance == .Receipt_Bound do state.receipt_bound -= 1
	diagnostic_generation_close(&state.generations[index])
	ordered_remove(&state.generations, index)
	return true, {}
}

/* diagnostic_store_copy returns one caller-owned complete generation. */
diagnostic_store_copy :: proc(
	store: ^Diagnostic_Store,
	binding: Document_Binding_Handle,
) -> (Diagnostic_Batch_Copy, bool, Failure_Context) {
	state := diagnostic_store_state(store)
	if state == nil do return {}, false, Failure_Context{code = .Closed}
	index := diagnostic_store_find(state, binding)
	if index < 0 do return {}, false, diagnostic_failure(state, .Invalid_Document, binding)
	owner := &state.generations[index]
	result := Diagnostic_Batch_Copy{descriptor = owner.descriptor, allocator = state.allocator}
	result.records, _ = make([]Diagnostic_Record, len(owner.records), state.allocator)
	if result.records == nil && len(owner.records) > 0 do return {}, false, diagnostic_failure(state, .Allocation, binding)
	result.storage, _ = make([]u8, len(owner.storage), state.allocator)
	if result.storage == nil && len(owner.storage) > 0 {
		if result.records != nil do delete(result.records, state.allocator)
		return {}, false, diagnostic_failure(state, .Allocation, binding)
	}
	copy(result.records, owner.records[:])
	copy(result.storage, owner.storage[:])
	return result, true, {}
}

/* diagnostic_batch_copy_close releases one copied diagnostic generation. */
diagnostic_batch_copy_close :: proc(batch: ^Diagnostic_Batch_Copy) {
	if batch == nil do return
	if batch.records != nil do delete(batch.records, batch.allocator)
	if batch.storage != nil do delete(batch.storage, batch.allocator)
	batch^ = {}
}

/* diagnostic_record_text resolves one copied text range inside its batch. */
diagnostic_record_text :: proc(batch: ^Diagnostic_Batch_Copy, value: Storage_Range) -> string {
	if batch == nil || value.storage_generation != u64(batch.descriptor.generation) ||
	   !storage_range_valid(value, u64(len(batch.storage))) {
		return ""
	}
	return string(batch.storage[int(value.offset):int(value.offset + value.length)])
}

/* diagnostic_store_inspect returns one pointer-free aggregate snapshot. */
diagnostic_store_inspect :: proc(store: ^Diagnostic_Store) -> (Diagnostic_Inspection, bool) {
	state := diagnostic_store_state(store)
	if state == nil do return {}, false
	result := Diagnostic_Inspection{
		session = state.session,
		generations = u32(len(state.generations)),
		diagnostics = state.usage.diagnostics,
		diagnostic_bytes = state.usage.diagnostic_bytes,
		retained_bytes = state.usage.retained_bytes,
		server_versioned = state.server_versioned,
		receipt_bound = state.receipt_bound,
		latest_failure = state.latest_failure,
	}
	for generation in state.generations {
		result.errors += generation.descriptor.errors
		result.warnings += generation.descriptor.warnings
		result.information += generation.descriptor.information
		result.hints += generation.descriptor.hints
	}
	return result, true
}

/* diagnostic_store_close releases every complete generation and invalidates the owner. */
diagnostic_store_close :: proc(store: ^Diagnostic_Store) -> bool {
	state := diagnostic_store_state(store)
	if state == nil do return false
	for &generation in state.generations do diagnostic_generation_close(&generation)
	delete(state.generations)
	allocator := state.allocator
	free(state, allocator)
	store^ = {}
	return true
}

@(private = "file")
diagnostic_item_from_json :: proc(
	value: json.Value,
	limits: Service_Limits,
) -> Diagnostic_Item_Proposal {
	object, object_ok := value.(json.Object)
	if !object_ok || len(object) == 0 || len(object) > int(limits.diagnostic_fields) do return {}
	range_value, range_present := object["range"]
	message_value, message_present := object["message"]
	range_object, range_ok := range_value.(json.Object)
	message, message_ok := message_value.(json.String)
	if !range_present || !message_present || !range_ok || !message_ok do return {}
	start_value, start_present := range_object["start"]
	end_value, end_present := range_object["end"]
	start, start_ok := lsp_position_from_json(start_value)
	end, end_ok := lsp_position_from_json(end_value)
	if !start_present || !end_present || !start_ok || !end_ok do return {}
	result := Diagnostic_Item_Proposal {
		start = start,
		end = end,
		message = string(message),
		field_count = u16(len(object)),
	}
	if severity_value, present := object["severity"]; present {
		severity, ok := severity_value.(json.Integer)
		if !ok || severity < 1 || severity > 4 do return {}
		result.has_severity = true
		result.severity = Diagnostic_Severity(severity)
	}
	if source_value, present := object["source"]; present {
		source, ok := source_value.(json.String)
		if !ok do return {}
		result.source = string(source)
	}
	if code_value, present := object["code"]; present {
		if code, ok := code_value.(json.String); ok {
			result.code = string(code)
		} else if _, integer_ok := code_value.(json.Integer); !integer_ok {
			return {}
		}
	}
	if related_value, present := object["relatedInformation"]; present {
		related, ok := related_value.(json.Array)
		if !ok || len(related) > int(limits.related_locations) do return {}
		result.related_locations = u16(len(related))
	}
	return result
}

@(private = "file")
diagnostic_item_normalize :: proc(
	state: ^Diagnostic_Store_State,
	binding_handle: Document_Binding_Handle,
	generation: Diagnostic_Generation,
	binding: Document_Binding_Descriptor,
	provenance: Diagnostic_Provenance,
	text: string,
	item: Diagnostic_Item_Proposal,
	storage: ^[dynamic]u8,
) -> (Diagnostic_Record, bool) {
	if item.field_count == 0 || item.field_count > state.limits.diagnostic_fields ||
	   item.related_locations > state.limits.related_locations || len(item.message) == 0 ||
	   u64(len(item.message)) > state.limits.diagnostic_message_bytes ||
	   u64(len(item.source)) > state.limits.diagnostic_message_bytes ||
	   u64(len(item.code)) > state.limits.diagnostic_message_bytes ||
	   !utf8.valid_string(item.message) || !utf8.valid_string(item.source) || !utf8.valid_string(item.code) {
		return {}, false
	}
	severity := Diagnostic_Severity.Information
	if item.has_severity {
		if item.severity < .Error || item.severity > .Hint do return {}, false
		severity = item.severity
	}
	start, start_ok, _ := position_to_byte_offset(text, item.start, binding.position_encoding)
	end, end_ok, _ := position_to_byte_offset(text, item.end, binding.position_encoding)
	if !start_ok || !end_ok || start > end do return {}, false
	message := diagnostic_append_text(storage, item.message, generation)
	if item.message != "" && message.length == 0 do return {}, false
	source := diagnostic_append_text(storage, item.source, generation)
	if item.source != "" && source.length == 0 do return {}, false
	code := diagnostic_append_text(storage, item.code, generation)
	if item.code != "" && code.length == 0 do return {}, false
	return Diagnostic_Record{
		binding = binding_handle,
		generation = generation,
		canonical_revision = binding.canonical_revision,
		document_version = binding.document_version,
		provenance = provenance,
		range = {start = start, end = end},
		point = start == end,
		severity = severity,
		message = message,
		source = source,
		code = code,
	}, true
}

@(private = "file")
diagnostic_append_text :: proc(
	storage: ^[dynamic]u8,
	value: string,
	generation: Diagnostic_Generation,
) -> Storage_Range {
	result := Storage_Range{storage_generation = u64(generation), offset = u64(len(storage^)), length = u64(len(value))}
	if len(value) == 0 do return result
	if _, append_error := append(storage, ..transmute([]u8)value); append_error != nil do return {}
	return result
}

@(private = "file")
diagnostic_store_find :: proc(state: ^Diagnostic_Store_State, binding: Document_Binding_Handle) -> int {
	for generation, index in state.generations {
		if generation.live && generation.descriptor.binding == binding do return index
	}
	return -1
}

@(private = "file")
diagnostic_generation_close :: proc(owner: ^Diagnostic_Generation_Owner) {
	if owner == nil || !owner.live do return
	if owner.records != nil do delete(owner.records)
	if owner.storage != nil do delete(owner.storage)
	owner^ = {}
}

@(private = "file")
diagnostic_store_state :: proc(store: ^Diagnostic_Store) -> ^Diagnostic_Store_State {
	if store == nil || store.state == nil do return nil
	return (^Diagnostic_Store_State)(store.state)
}

@(private = "file")
diagnostic_store_base_bytes :: proc(state: ^Diagnostic_Store_State) -> u64 {
	if state == nil do return 0
	return u64(size_of(Diagnostic_Store_State)) +
		u64(cap(state.generations)) * u64(size_of(Diagnostic_Generation_Owner))
}

@(private = "file")
diagnostic_failure :: proc(
	state: ^Diagnostic_Store_State,
	code: Failure_Code,
	binding := Document_Binding_Handle{},
) -> Failure_Context {
	failure := Failure_Context{code = code, binding = binding}
	if state != nil do failure.session = state.session
	return failure
}

@(private = "file")
diagnostic_store_reject :: proc(
	state: ^Diagnostic_Store_State,
	code: Failure_Code,
	binding: Document_Binding_Handle,
) -> (Diagnostic_Batch_Descriptor, bool, Failure_Context) {
	failure := diagnostic_failure(state, code, binding)
	state.latest_failure = failure
	return {}, false, failure
}

@(private = "file")
diagnostic_store_resource_reject :: proc(
	state: ^Diagnostic_Store_State,
	resource: Resource_Kind,
	limit, actual: u64,
	binding: Document_Binding_Handle,
) -> (Diagnostic_Batch_Descriptor, bool, Failure_Context) {
	failure := diagnostic_failure(state, .Resource_Limit, binding)
	failure.resource = resource
	failure.limit = limit
	failure.actual = actual
	state.latest_failure = failure
	return {}, false, failure
}
