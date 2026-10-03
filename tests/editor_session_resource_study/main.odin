// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import session_reference "../session_reference"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strings"
import "core:time"

KIBIBYTE :: u64(1_024)
MEBIBYTE :: u64(1_024) * KIBIBYTE
GIBIBYTE :: u64(1_024) * MEBIBYTE

MIN_LIVE_BUFFERS :: 16
MAX_LIVE_BUFFERS :: 1_024
SELECTED_LIVE_BUFFERS :: 128
MIN_LIVE_DOCUMENTS :: 16
MAX_LIVE_DOCUMENTS :: 1_024
SELECTED_LIVE_DOCUMENTS :: 128
MIN_AGGREGATE_TEXT_BYTES :: 256 * MEBIBYTE
MAX_AGGREGATE_TEXT_BYTES :: 16 * GIBIBYTE
SELECTED_AGGREGATE_TEXT_BYTES :: 4 * GIBIBYTE
MIN_NAME_BYTES :: 64
MAX_NAME_BYTES :: 4_096
SELECTED_NAME_BYTES :: 256
MIN_LABEL_BYTES :: 64 * KIBIBYTE
MAX_LABEL_BYTES :: 16 * MEBIBYTE
SELECTED_LABEL_BYTES :: 4 * MEBIBYTE
MIN_DESCRIPTOR_BATCH :: 16
MAX_DESCRIPTOR_BATCH :: 4_096
SELECTED_DESCRIPTOR_BATCH :: 256
MIN_MARKS :: 16
MAX_MARKS :: 1_024
SELECTED_MARKS :: 128
MIN_CAPABILITIES :: 32
MAX_CAPABILITIES :: 8_192
SELECTED_CAPABILITIES :: 2_048
MIN_OPERATIONS :: 1
MAX_OPERATIONS :: 64
SELECTED_OPERATIONS :: 16
MIN_DETACH_PARTICIPANTS :: 16
MAX_DETACH_PARTICIPANTS :: 1_024
SELECTED_DETACH_PARTICIPANTS :: 128
MIN_CLEANUP_ENTRIES :: 1
MAX_CLEANUP_ENTRIES :: 256
SELECTED_CLEANUP_ENTRIES :: 64

LOOKUP_SAMPLES :: 4_096
ACTIVATION_SAMPLES :: 4_096
PROJECTION_SAMPLES :: 128
ACTIVATION_GATE_NS :: i64(1_000_000)
LOOKUP_GATE_NS :: i64(2_000_000)
PROJECTION_GATE_NS :: i64(4_000_000)
DETACH_GATE_NS :: i64(8_000_000)

Latency :: struct {
	p50_ns: i64,
	p99_ns: i64,
}

Candidate_Entry :: struct {
	handle:        session_reference.Handle,
	identity_text: string,
	text_bytes:    u64,
	history_bytes: u64,
	previous_mru:  int,
	next_mru:      int,
	associated:    bool,
	modified:      bool,
	live:          bool,
}

Candidate_Descriptor :: struct {
	handle:       session_reference.Handle,
	label_bytes:  u32,
	associated:   bool,
	modified:     bool,
	active:       bool,
	text_bytes:   u64,
	history_bytes: u64,
}

Candidate_Session :: struct {
	entries:          []Candidate_Entry,
	descriptors:      []Candidate_Descriptor,
	label_index:      map[string]int,
	path_index:       map[string]int,
	mru_head:         int,
	mru_tail:         int,
	live_count:       int,
	document_count:   int,
	aggregate_text:   u64,
	aggregate_history: u64,
	retained_labels:  u64,
	allocator:        mem.Allocator,
}

Profile :: struct {
	name:           string,
	buffers:        int,
	documents:      int,
	aggregate_text: u64,
	marks:          int,
}

main :: proc() {
	passed := print_policy_evidence()
	passed = run_reference_probe() && passed
	profiles := [?]Profile {
		{name = "ordinary", buffers = 16, documents = 8, aggregate_text = 64 * MEBIBYTE, marks = 16},
		{name = "demanding", buffers = 256, documents = 128, aggregate_text = 2 * GIBIBYTE, marks = 256},
		{name = "stress", buffers = 1_024, documents = 512, aggregate_text = 16 * GIBIBYTE, marks = 1_024},
	}
	for profile in profiles {
		passed = run_profile(profile) && passed
	}
	passed = run_rejection_probe() && passed
	if !passed {
		os.exit(1)
	}
}

print_policy_evidence :: proc() -> bool {
	valid := SELECTED_LIVE_BUFFERS >= MIN_LIVE_BUFFERS &&
		SELECTED_LIVE_BUFFERS <= MAX_LIVE_BUFFERS &&
		SELECTED_LIVE_DOCUMENTS >= MIN_LIVE_DOCUMENTS &&
		SELECTED_LIVE_DOCUMENTS <= MAX_LIVE_DOCUMENTS &&
		SELECTED_LIVE_DOCUMENTS <= SELECTED_LIVE_BUFFERS &&
		SELECTED_AGGREGATE_TEXT_BYTES >= MIN_AGGREGATE_TEXT_BYTES &&
		SELECTED_AGGREGATE_TEXT_BYTES <= MAX_AGGREGATE_TEXT_BYTES &&
		SELECTED_NAME_BYTES >= MIN_NAME_BYTES && SELECTED_NAME_BYTES <= MAX_NAME_BYTES &&
		SELECTED_LABEL_BYTES >= MIN_LABEL_BYTES && SELECTED_LABEL_BYTES <= MAX_LABEL_BYTES &&
		SELECTED_DESCRIPTOR_BATCH >= MIN_DESCRIPTOR_BATCH &&
		SELECTED_DESCRIPTOR_BATCH <= MAX_DESCRIPTOR_BATCH &&
		SELECTED_MARKS >= MIN_MARKS && SELECTED_MARKS <= MAX_MARKS &&
		SELECTED_MARKS <= SELECTED_LIVE_BUFFERS &&
		SELECTED_CAPABILITIES >= MIN_CAPABILITIES && SELECTED_CAPABILITIES <= MAX_CAPABILITIES &&
		SELECTED_OPERATIONS >= MIN_OPERATIONS && SELECTED_OPERATIONS <= MAX_OPERATIONS &&
		SELECTED_DETACH_PARTICIPANTS >= MIN_DETACH_PARTICIPANTS &&
		SELECTED_DETACH_PARTICIPANTS <= MAX_DETACH_PARTICIPANTS &&
		SELECTED_DETACH_PARTICIPANTS <= SELECTED_LIVE_BUFFERS &&
		SELECTED_CLEANUP_ENTRIES >= MIN_CLEANUP_ENTRIES &&
		SELECTED_CLEANUP_ENTRIES <= MAX_CLEANUP_ENTRIES
	fmt.printf(
		"study=editor-session profile=policy valid=%v selected_live_buffers=%d live_buffer_range=%d..%d selected_live_documents=%d live_document_range=%d..%d selected_aggregate_text_bytes=%d aggregate_text_range=%d..%d selected_name_bytes=%d name_range=%d..%d selected_label_bytes=%d label_range=%d..%d selected_descriptor_batch=%d descriptor_range=%d..%d selected_marks=%d mark_range=%d..%d selected_capabilities=%d capability_range=%d..%d selected_operations=%d operation_range=%d..%d selected_detach_participants=%d detach_range=%d..%d selected_cleanup_entries=%d cleanup_range=%d..%d selected_lookup=hash-index selected_activation=intrusive-mru\n",
		valid,
		SELECTED_LIVE_BUFFERS,
		MIN_LIVE_BUFFERS,
		MAX_LIVE_BUFFERS,
		SELECTED_LIVE_DOCUMENTS,
		MIN_LIVE_DOCUMENTS,
		MAX_LIVE_DOCUMENTS,
		SELECTED_AGGREGATE_TEXT_BYTES,
		MIN_AGGREGATE_TEXT_BYTES,
		MAX_AGGREGATE_TEXT_BYTES,
		SELECTED_NAME_BYTES,
		MIN_NAME_BYTES,
		MAX_NAME_BYTES,
		SELECTED_LABEL_BYTES,
		MIN_LABEL_BYTES,
		MAX_LABEL_BYTES,
		SELECTED_DESCRIPTOR_BATCH,
		MIN_DESCRIPTOR_BATCH,
		MAX_DESCRIPTOR_BATCH,
		SELECTED_MARKS,
		MIN_MARKS,
		MAX_MARKS,
		SELECTED_CAPABILITIES,
		MIN_CAPABILITIES,
		MAX_CAPABILITIES,
		SELECTED_OPERATIONS,
		MIN_OPERATIONS,
		MAX_OPERATIONS,
		SELECTED_DETACH_PARTICIPANTS,
		MIN_DETACH_PARTICIPANTS,
		MAX_DETACH_PARTICIPANTS,
		SELECTED_CLEANUP_ENTRIES,
		MIN_CLEANUP_ENTRIES,
		MAX_CLEANUP_ENTRIES,
	)
	return valid
}

run_reference_probe :: proc() -> bool {
	model, ready := session_reference.model_init(32)
	if !ready {
		fmt.eprintf("study=editor-session profile=reference ready=false\n")
		return false
	}
	defer session_reference.model_deinit(&model)
	created := true
	for index in 0 ..< 16 {
		name := fmt.aprintf("reference-buffer-%04d", index)
		_, ok, _ := session_reference.model_create(&model, name, u64(index + 1) * MEBIBYTE)
		delete(name)
		created = created && ok
	}
	first, first_ok := session_reference.model_mru_handle(&model, 15)
	activated, _ := session_reference.model_activate(&model, first)
	_, closed, _ := session_reference.model_close(&model, first)
	valid := created && first_ok && activated && closed &&
		session_reference.model_live_count(&model) == 15 &&
		session_reference.model_validate(&model)
	fmt.printf(
		"study=editor-session profile=reference valid=%v entries=%d representation=contiguous-linear-mru\n",
		valid,
		session_reference.model_live_count(&model),
	)
	return valid
}

run_profile :: proc(profile: Profile) -> bool {
	if !profile_admitted(profile) {
		fmt.eprintf(
			"study=editor-session profile=%s phase=admission buffers=%d documents=%d aggregate_text=%d marks=%d\n",
			profile.name,
			profile.buffers,
			profile.documents,
			profile.aggregate_text,
			profile.marks,
		)
		return false
	}
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	session, ready := candidate_init(profile.buffers, allocator)
	if !ready {
		mem.tracking_allocator_destroy(&tracking)
		fmt.eprintf("study=editor-session profile=%s phase=init\n", profile.name)
		return false
	}
	per_buffer_text := profile.aggregate_text / u64(profile.buffers)
	built := true
	for slot in 0 ..< profile.buffers {
		associated := slot < profile.documents
		text_bytes := per_buffer_text
		if slot == profile.buffers - 1 {
			text_bytes += profile.aggregate_text % u64(profile.buffers)
		}
		_, published := candidate_publish_generated(&session, slot, associated, text_bytes)
		built = built && published
	}
	if !built || !candidate_validate(&session) {
		candidate_close(&session)
		cleanup_bytes := tracking.current_memory_allocated
		mem.tracking_allocator_destroy(&tracking)
		fmt.eprintf(
			"study=editor-session profile=%s phase=build cleanup_bytes=%d\n",
			profile.name,
			cleanup_bytes,
		)
		return false
	}
	metadata_live_bytes := tracking.current_memory_allocated
	metadata_peak_bytes := tracking.peak_memory_allocated
	usage_exact := candidate_usage_exact(&session, profile)
	map_lookup, linear_lookup, lookup_checksum := measure_lookup(&session)
	activation, activation_checksum := measure_activation(&session)
	projection, projected, projection_checksum := measure_projection(&session)
	detach_participants := min(profile.buffers, SELECTED_DETACH_PARTICIPANTS)
	detach_ns, reuse_valid, detach_checksum := measure_detach_and_reuse(
		&session,
		detach_participants,
	)
	valid := usage_exact && map_lookup.p99_ns <= LOOKUP_GATE_NS &&
		activation.p99_ns <= ACTIVATION_GATE_NS && projection.p99_ns <= PROJECTION_GATE_NS &&
		detach_ns <= DETACH_GATE_NS && reuse_valid && candidate_validate(&session)
	metadata_peak_bytes = max(metadata_peak_bytes, tracking.peak_memory_allocated)
	candidate_close(&session)
	cleanup_bytes := tracking.current_memory_allocated
	valid = valid && cleanup_bytes == 0
	mem.tracking_allocator_destroy(&tracking)
	fmt.printf(
		"study=editor-session profile=%s valid=%v buffers=%d documents=%d aggregate_text=%d marks=%d entry_size=%d descriptor_size=%d metadata_live_bytes=%d metadata_peak_bytes=%d usage_exact=%v map_lookup_p50_ns=%d map_lookup_p99_ns=%d linear_lookup_p50_ns=%d linear_lookup_p99_ns=%d lookup_gate_ns=%d activation_p50_ns=%d activation_p99_ns=%d activation_gate_ns=%d projected_descriptors=%d projection_p50_ns=%d projection_p99_ns=%d projection_gate_ns=%d detach_participants=%d detach_ns=%d detach_gate_ns=%d generation_reuse_valid=%v cleanup_bytes=%d checksum=%d\n",
		profile.name,
		valid,
		profile.buffers,
		profile.documents,
		profile.aggregate_text,
		profile.marks,
		size_of(Candidate_Entry),
		size_of(Candidate_Descriptor),
		metadata_live_bytes,
		metadata_peak_bytes,
		usage_exact,
		map_lookup.p50_ns,
		map_lookup.p99_ns,
		linear_lookup.p50_ns,
		linear_lookup.p99_ns,
		LOOKUP_GATE_NS,
		activation.p50_ns,
		activation.p99_ns,
		ACTIVATION_GATE_NS,
		projected,
		projection.p50_ns,
		projection.p99_ns,
		PROJECTION_GATE_NS,
		detach_participants,
		detach_ns,
		DETACH_GATE_NS,
		reuse_valid,
		cleanup_bytes,
		lookup_checksum ~ activation_checksum ~ projection_checksum ~ detach_checksum,
	)
	return valid
}

run_rejection_probe :: proc() -> bool {
	attempted_buffers := MAX_LIVE_BUFFERS + 1
	attempted_documents := MAX_LIVE_DOCUMENTS + 1
	attempted_text := MAX_AGGREGATE_TEXT_BYTES + 1
	attempted_marks := MAX_MARKS + 1
	profile := Profile {
		name = "rejection",
		buffers = attempted_buffers,
		documents = attempted_documents,
		aggregate_text = attempted_text,
		marks = attempted_marks,
	}
	rejected := !profile_admitted(profile)
	fmt.printf(
		"study=editor-session profile=rejection valid=%v attempted_buffers=%d buffer_limit=%d attempted_documents=%d document_limit=%d attempted_text=%d text_limit=%d attempted_marks=%d mark_limit=%d reason=bounded-prepublication-rejection cleanup_bytes=0\n",
		rejected,
		attempted_buffers,
		MAX_LIVE_BUFFERS,
		attempted_documents,
		MAX_LIVE_DOCUMENTS,
		attempted_text,
		MAX_AGGREGATE_TEXT_BYTES,
		attempted_marks,
		MAX_MARKS,
	)
	return rejected
}

profile_admitted :: proc(profile: Profile) -> bool {
	return profile.buffers > 0 && profile.buffers <= MAX_LIVE_BUFFERS &&
		profile.documents >= 0 && profile.documents <= profile.buffers &&
		profile.documents <= MAX_LIVE_DOCUMENTS &&
		profile.aggregate_text <= MAX_AGGREGATE_TEXT_BYTES &&
		profile.marks >= 0 && profile.marks <= profile.buffers && profile.marks <= MAX_MARKS
}

candidate_init :: proc(capacity: int, allocator: mem.Allocator) -> (session: Candidate_Session, ok: bool) {
	entries, entries_error := make([]Candidate_Entry, capacity, allocator)
	if entries_error != nil {
		return {}, false
	}
	descriptors, descriptors_error := make([]Candidate_Descriptor, capacity, allocator)
	if descriptors_error != nil {
		delete(entries, allocator)
		return {}, false
	}
	label_index, label_error := make(map[string]int, capacity * 2, allocator)
	if label_error != nil {
		delete(descriptors, allocator)
		delete(entries, allocator)
		return {}, false
	}
	path_index, path_error := make(map[string]int, capacity * 2, allocator)
	if path_error != nil {
		delete(label_index)
		delete(descriptors, allocator)
		delete(entries, allocator)
		return {}, false
	}
	for &entry in entries {
		entry.previous_mru = -1
		entry.next_mru = -1
	}
	return Candidate_Session {
		entries = entries,
		descriptors = descriptors,
		label_index = label_index,
		path_index = path_index,
		mru_head = -1,
		mru_tail = -1,
		allocator = allocator,
	}, true
}

candidate_close :: proc(session: ^Candidate_Session) {
	if session == nil {
		return
	}
	if session.label_index != nil {
		delete(session.label_index)
	}
	if session.path_index != nil {
		delete(session.path_index)
	}
	for &entry in session.entries {
		if entry.live && len(entry.identity_text) > 0 {
			delete(entry.identity_text, session.allocator)
		}
	}
	if session.descriptors != nil {
		delete(session.descriptors, session.allocator)
	}
	if session.entries != nil {
		delete(session.entries, session.allocator)
	}
	session^ = {}
}

candidate_publish_generated :: proc(
	session: ^Candidate_Session,
	ordinal: int,
	associated: bool,
	text_bytes: u64,
) -> (handle: session_reference.Handle, ok: bool) {
	buffer: [128]byte
	label := fmt.bprintf(
		buffer[:],
		"/workspace/project-%04d/file-%04d.odin" if associated else "buffer-%04d",
		ordinal,
		ordinal,
	)
	return candidate_publish(session, label, associated, text_bytes)
}

candidate_publish :: proc(
	session: ^Candidate_Session,
	label: string,
	associated: bool,
	text_bytes: u64,
) -> (handle: session_reference.Handle, ok: bool) {
	if session == nil || len(label) == 0 || session.live_count >= len(session.entries) ||
	   session.label_index[label] != 0 || (associated && session.path_index[label] != 0) {
		return {}, false
	}
	slot := -1
	for index in 0 ..< len(session.entries) {
		if !session.entries[index].live {
			slot = index
			break
		}
	}
	if slot < 0 {
		return {}, false
	}
	entry := &session.entries[slot]
	if entry.handle.generation == max(u64) {
		return {}, false
	}
	owned, allocation_error := strings.clone(label, session.allocator)
	if allocation_error != nil {
		return {}, false
	}
	handle = session_reference.Handle {
		id = u64(slot + 1),
		generation = entry.handle.generation + 1,
	}
	history_bytes := text_bytes / 4 + 4 * KIBIBYTE
	entry^ = Candidate_Entry {
		handle = handle,
		identity_text = owned,
		text_bytes = text_bytes,
		history_bytes = history_bytes,
		previous_mru = -1,
		next_mru = -1,
		associated = associated,
		live = true,
	}
	session.label_index[owned] = slot + 1
	if associated {
		session.path_index[owned] = slot + 1
		session.document_count += 1
	}
	session.live_count += 1
	session.aggregate_text += text_bytes
	session.aggregate_history += history_bytes
	session.retained_labels += u64(len(owned))
	candidate_link_front(session, slot)
	return handle, true
}

candidate_valid :: proc(session: ^Candidate_Session, handle: session_reference.Handle) -> bool {
	if session == nil || handle.id == 0 || handle.generation == 0 ||
	   handle.id > u64(len(session.entries)) {
		return false
	}
	entry := &session.entries[int(handle.id - 1)]
	return entry.live && entry.handle == handle
}

candidate_activate :: proc(session: ^Candidate_Session, handle: session_reference.Handle) -> bool {
	if !candidate_valid(session, handle) {
		return false
	}
	slot := int(handle.id - 1)
	if session.mru_head == slot {
		return true
	}
	candidate_unlink(session, slot)
	candidate_link_front(session, slot)
	return true
}

candidate_detach :: proc(session: ^Candidate_Session, handle: session_reference.Handle) -> bool {
	if !candidate_valid(session, handle) {
		return false
	}
	slot := int(handle.id - 1)
	entry := &session.entries[slot]
	candidate_unlink(session, slot)
	delete_key(&session.label_index, entry.identity_text)
	if entry.associated {
		delete_key(&session.path_index, entry.identity_text)
		session.document_count -= 1
	}
	session.live_count -= 1
	session.aggregate_text -= entry.text_bytes
	session.aggregate_history -= entry.history_bytes
	session.retained_labels -= u64(len(entry.identity_text))
	delete(entry.identity_text, session.allocator)
	generation := entry.handle.generation
	entry^ = Candidate_Entry {
		handle = session_reference.Handle{generation = generation},
		previous_mru = -1,
		next_mru = -1,
	}
	return true
}

candidate_link_front :: proc(session: ^Candidate_Session, slot: int) {
	entry := &session.entries[slot]
	entry.previous_mru = -1
	entry.next_mru = session.mru_head
	if session.mru_head >= 0 {
		session.entries[session.mru_head].previous_mru = slot
	} else {
		session.mru_tail = slot
	}
	session.mru_head = slot
}

candidate_unlink :: proc(session: ^Candidate_Session, slot: int) {
	entry := &session.entries[slot]
	if entry.previous_mru >= 0 {
		session.entries[entry.previous_mru].next_mru = entry.next_mru
	} else {
		session.mru_head = entry.next_mru
	}
	if entry.next_mru >= 0 {
		session.entries[entry.next_mru].previous_mru = entry.previous_mru
	} else {
		session.mru_tail = entry.previous_mru
	}
	entry.previous_mru = -1
	entry.next_mru = -1
}

candidate_validate :: proc(session: ^Candidate_Session) -> bool {
	if session == nil || session.live_count < 0 || session.live_count > len(session.entries) ||
	   session.document_count < 0 || session.document_count > session.live_count {
		return false
	}
	live_count := 0
	document_count := 0
	aggregate_text := u64(0)
	aggregate_history := u64(0)
	retained_labels := u64(0)
	for entry, slot in session.entries {
		if !entry.live {
			continue
		}
		live_count += 1
		document_count += 1 if entry.associated else 0
		aggregate_text += entry.text_bytes
		aggregate_history += entry.history_bytes
		retained_labels += u64(len(entry.identity_text))
		if entry.handle.id != u64(slot + 1) || entry.handle.generation == 0 ||
		   session.label_index[entry.identity_text] != slot + 1 ||
		   (entry.associated && session.path_index[entry.identity_text] != slot + 1) {
			return false
		}
	}
	if live_count != session.live_count || document_count != session.document_count ||
	   aggregate_text != session.aggregate_text || aggregate_history != session.aggregate_history ||
	   retained_labels != session.retained_labels {
		return false
	}
	linked := 0
	previous := -1
	slot := session.mru_head
	for slot >= 0 {
		if slot >= len(session.entries) || !session.entries[slot].live ||
		   session.entries[slot].previous_mru != previous || linked >= session.live_count {
			return false
		}
		previous = slot
		slot = session.entries[slot].next_mru
		linked += 1
	}
	return linked == session.live_count && previous == session.mru_tail &&
		((linked == 0 && session.mru_head == -1 && session.mru_tail == -1) || linked > 0)
}

candidate_usage_exact :: proc(session: ^Candidate_Session, profile: Profile) -> bool {
	return session.live_count == profile.buffers &&
		session.document_count == profile.documents &&
		session.aggregate_text == profile.aggregate_text &&
		session.retained_labels <= SELECTED_LABEL_BYTES &&
		profile.marks <= MAX_MARKS
}

measure_lookup :: proc(session: ^Candidate_Session) -> (
	map_latency: Latency,
	linear_latency: Latency,
	checksum: u64,
) {
	map_samples: [LOOKUP_SAMPLES]i64
	linear_samples: [LOOKUP_SAMPLES]i64
	for sample in 0 ..< LOOKUP_SAMPLES {
		target := (sample * 2_653 + 17) % session.live_count
		label := session.entries[target].identity_text
		started := time.tick_now()
		indexed := session.label_index[label]
		map_samples[sample] = time.duration_nanoseconds(time.tick_since(started))
		checksum ~= u64(indexed)

		started = time.tick_now()
		linear := 0
		for entry, slot in session.entries {
			if entry.live && entry.identity_text == label {
				linear = slot + 1
				break
			}
		}
		linear_samples[sample] = time.duration_nanoseconds(time.tick_since(started))
		checksum ~= u64(linear)
	}
	return summarize(map_samples[:]), summarize(linear_samples[:]), checksum
}

measure_activation :: proc(session: ^Candidate_Session) -> (latency: Latency, checksum: u64) {
	samples: [ACTIVATION_SAMPLES]i64
	for sample in 0 ..< ACTIVATION_SAMPLES {
		target := (sample * 1_009 + 7) % session.live_count
		handle := session.entries[target].handle
		started := time.tick_now()
		activated := candidate_activate(session, handle)
		samples[sample] = time.duration_nanoseconds(time.tick_since(started))
		if activated {
			checksum ~= handle.id ~ handle.generation
		}
	}
	return summarize(samples[:]), checksum
}

measure_projection :: proc(session: ^Candidate_Session) -> (
	latency: Latency,
	projected: int,
	checksum: u64,
) {
	samples: [PROJECTION_SAMPLES]i64
	projected = min(session.live_count, len(session.descriptors))
	for sample in 0 ..< PROJECTION_SAMPLES {
		started := time.tick_now()
		slot := session.mru_head
		count := 0
		for slot >= 0 && count < projected {
			entry := &session.entries[slot]
			session.descriptors[count] = Candidate_Descriptor {
				handle = entry.handle,
				label_bytes = u32(len(entry.identity_text)),
				associated = entry.associated,
				modified = entry.modified,
				active = count == 0,
				text_bytes = entry.text_bytes,
				history_bytes = entry.history_bytes,
			}
			checksum ~= entry.handle.id ~ u64(len(entry.identity_text))
			slot = entry.next_mru
			count += 1
		}
		samples[sample] = time.duration_nanoseconds(time.tick_since(started))
	}
	return summarize(samples[:]), projected, checksum
}

measure_detach_and_reuse :: proc(
	session: ^Candidate_Session,
	participants: int,
) -> (elapsed_ns: i64, reuse_valid: bool, checksum: u64) {
	stale := session.entries[0].handle
	started := time.tick_now()
	for slot in 0 ..< participants {
		handle := session.entries[slot].handle
		if candidate_detach(session, handle) {
			checksum ~= handle.id ~ handle.generation
		}
	}
	elapsed_ns = time.duration_nanoseconds(time.tick_since(started))
	new_handle, published := candidate_publish(session, "reused-buffer", false, 0)
	reuse_valid = published && !candidate_valid(session, stale) &&
		new_handle.id == stale.id && new_handle.generation == stale.generation + 1
	checksum ~= new_handle.id ~ new_handle.generation
	return
}

summarize :: proc(latencies: []i64) -> Latency {
	slice.sort(latencies)
	p50_index := (len(latencies) * 50 + 99) / 100 - 1
	p99_index := (len(latencies) * 99 + 99) / 100 - 1
	return {p50_ns = latencies[p50_index], p99_ns = latencies[p99_index]}
}
