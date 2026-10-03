// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "core:fmt"
import "core:mem"
import "core:os"
import "core:slice"
import "core:time"

KIBIBYTE :: u64(1024)
MEBIBYTE :: u64(1024) * KIBIBYTE
GIBIBYTE :: u64(1024) * MEBIBYTE

DEFAULT_ENTRIES :: 60
DEFAULT_ENTRY_BYTES :: 12 * MEBIBYTE
DEFAULT_TOTAL_BYTES :: 256 * MEBIBYTE
DEFAULT_INSPECTION_ENTRIES :: 256
DEFAULT_COALESCED_OPERATIONS :: 10_000
DEFAULT_ROTATION_WORK :: 4_096
DEFAULT_TEMPORARY_BYTES :: 64 * MEBIBYTE
DEFAULT_CANCELLATION_BYTES :: 256 * KIBIBYTE

MIN_ENTRIES :: 16
MAX_ENTRIES :: 4_096
MIN_ENTRY_BYTES :: 4 * KIBIBYTE
MAX_ENTRY_BYTES :: 12 * MEBIBYTE
MIN_TOTAL_BYTES :: 1 * MEBIBYTE
MAX_TOTAL_BYTES :: 256 * MEBIBYTE
MIN_COALESCED_OPERATIONS :: 16
MAX_COALESCED_OPERATIONS :: 10_000
MIN_INSPECTION_ENTRIES :: 1
MAX_INSPECTION_ENTRIES :: 256
MIN_ROTATION_WORK :: 16
MAX_ROTATION_WORK :: 4_096
MIN_TEMPORARY_BYTES :: 1 * MEBIBYTE
MAX_TEMPORARY_BYTES :: 256 * MEBIBYTE
MIN_CANCELLATION_BYTES :: 64 * KIBIBYTE
MAX_CANCELLATION_BYTES :: 4 * MEBIBYTE

ORDINARY_SAMPLES :: 1_024
DEMANDING_SAMPLES :: 9
ORDINARY_GATE_NS :: i64(2_000_000)
DEMANDING_GATE_NS :: i64(25_000_000)

Direction :: enum u8 {
	Forward,
	Backward,
}

Candidate_Entry :: struct {
	id:               u64,
	text:             []byte,
	coalesced_ops:    u64,
	source_buffer_id: u64,
	source_start:     u64,
	source_end:       u64,
	direction:        Direction,
}

Candidate_Policy :: struct {
	entry_count:           int,
	entry_bytes:           u64,
	total_bytes:           u64,
	coalesced_operations:  u64,
	inspection_entries:    int,
	rotation_work:         int,
	temporary_bytes:       u64,
	cancellation_bytes:    u64,
}

Candidate_Ring :: struct {
	entries:        []Candidate_Entry,
	count:          int,
	retained_bytes: u64,
	generation:     u64,
	next_id:        u64,
	allocator:      mem.Allocator,
	policy:         Candidate_Policy,
}

Latency :: struct {
	p50_ns: i64,
	p99_ns: i64,
}

main :: proc() {
	passed := print_policy_evidence()
	passed = run_ordinary() && passed
	passed = run_demanding() && passed
	passed = run_stress() && passed
	if !passed {
		os.exit(1)
	}
}

print_policy_evidence :: proc() -> bool {
	policy := default_policy()
	valid := policy.entry_count >= MIN_ENTRIES && policy.entry_count <= MAX_ENTRIES &&
		policy.entry_bytes >= MIN_ENTRY_BYTES && policy.entry_bytes <= MAX_ENTRY_BYTES &&
		policy.total_bytes >= MIN_TOTAL_BYTES && policy.total_bytes <= MAX_TOTAL_BYTES &&
		policy.entry_bytes <= policy.total_bytes &&
		policy.coalesced_operations >= MIN_COALESCED_OPERATIONS &&
		policy.coalesced_operations <= MAX_COALESCED_OPERATIONS &&
		policy.inspection_entries >= MIN_INSPECTION_ENTRIES &&
		policy.inspection_entries <= MAX_INSPECTION_ENTRIES &&
		policy.rotation_work >= MIN_ROTATION_WORK &&
		policy.rotation_work <= MAX_ROTATION_WORK &&
		policy.temporary_bytes >= MIN_TEMPORARY_BYTES &&
		policy.temporary_bytes <= MAX_TEMPORARY_BYTES &&
		3 * policy.entry_bytes <= policy.temporary_bytes &&
		policy.cancellation_bytes >= MIN_CANCELLATION_BYTES &&
		policy.cancellation_bytes <= MAX_CANCELLATION_BYTES
	fmt.printf(
		"study=kill-ring profile=policy valid=%v default_entries=%d entry_range=%d..%d default_entry_bytes=%d entry_bytes_range=%d..%d default_total_bytes=%d total_bytes_range=%d..%d default_coalesced_operations=%d coalesced_range=%d..%d default_inspection_entries=%d inspection_range=%d..%d default_rotation_work=%d rotation_range=%d..%d default_temporary_bytes=%d temporary_range=%d..%d default_cancellation_bytes=%d cancellation_range=%d..%d\n",
		valid,
		policy.entry_count,
		MIN_ENTRIES,
		MAX_ENTRIES,
		policy.entry_bytes,
		MIN_ENTRY_BYTES,
		MAX_ENTRY_BYTES,
		policy.total_bytes,
		MIN_TOTAL_BYTES,
		MAX_TOTAL_BYTES,
		policy.coalesced_operations,
		MIN_COALESCED_OPERATIONS,
		MAX_COALESCED_OPERATIONS,
		policy.inspection_entries,
		MIN_INSPECTION_ENTRIES,
		MAX_INSPECTION_ENTRIES,
		policy.rotation_work,
		MIN_ROTATION_WORK,
		MAX_ROTATION_WORK,
		policy.temporary_bytes,
		MIN_TEMPORARY_BYTES,
		MAX_TEMPORARY_BYTES,
		policy.cancellation_bytes,
		MIN_CANCELLATION_BYTES,
		MAX_CANCELLATION_BYTES,
	)
	return valid
}

run_ordinary :: proc() -> bool {
	persistent_tracking: mem.Tracking_Allocator
	temporary_tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&persistent_tracking, context.allocator)
	mem.tracking_allocator_init(&temporary_tracking, context.allocator)
	persistent := mem.tracking_allocator(&persistent_tracking)
	temporary := mem.tracking_allocator(&temporary_tracking)
	policy := default_policy()
	policy.total_bytes = 1 * MEBIBYTE
	ring, initialized := ring_init(policy, persistent)
	if !initialized {
		return false
	}

	source := make([]byte, int(MEBIBYTE / u64(DEFAULT_ENTRIES)) + DEFAULT_ENTRIES)
	defer delete(source)
	touch(source)
	for index in 0 ..< DEFAULT_ENTRIES {
		entry_bytes := int(MEBIBYTE / u64(DEFAULT_ENTRIES))
		if index == DEFAULT_ENTRIES - 1 {
			entry_bytes = int(MEBIBYTE) - entry_bytes * (DEFAULT_ENTRIES - 1)
		}
		if !ring_admit(&ring, source[:entry_bytes]) {
			ring_close(&ring)
			return false
		}
	}
	shape_exact := ring.count == DEFAULT_ENTRIES && ring.retained_bytes == MEBIBYTE
	metadata_bytes := u64(len(ring.entries)) * u64(size_of(Candidate_Entry))
	accounting_exact := persistent_tracking.current_memory_allocated ==
		i64(metadata_bytes + ring.retained_bytes)

	copy_latency, copy_checksum := measure_copy(
		ring.entries[0].text[:min(len(ring.entries[0].text), 4 * int(KIBIBYTE))],
		ORDINARY_SAMPLES,
		temporary,
	)
	yank_latency, yank_checksum := measure_reservation(
		ring.entries[0].text[:min(len(ring.entries[0].text), 4 * int(KIBIBYTE))],
		ORDINARY_SAMPLES,
		2,
		temporary,
	)
	rotation_latency, rotation_checksum := measure_rotation(
		&ring,
		4 * int(KIBIBYTE),
		ORDINARY_SAMPLES,
		temporary,
	)

	unit_storage := [1]byte{'x'}
	unit := unit_storage[:]
	coalescence_started := time.tick_now()
	coalesced := true
	for _ in 0 ..< 8 {
		coalesced = ring_coalesce(&ring, unit, .Forward) && coalesced
	}
	for _ in 0 ..< 8 {
		coalesced = ring_coalesce(&ring, unit, .Backward) && coalesced
	}
	coalescence_ns := time.duration_nanoseconds(time.tick_since(coalescence_started))
	directional := coalesced && ring.entries[0].text[0] == 'x' &&
		ring.entries[0].text[len(ring.entries[0].text) - 1] == 'x' &&
		ring.entries[0].coalesced_ops == 17

	eviction_started := time.tick_now()
	evicted := ring_admit(&ring, source[:int(MEBIBYTE / u64(DEFAULT_ENTRIES))])
	eviction_ns := time.duration_nanoseconds(time.tick_since(eviction_started))
	eviction_exact := evicted && ring.count == DEFAULT_ENTRIES - 1 &&
		ring.retained_bytes <= policy.total_bytes

	cancellation_ns, cancellation_exact := measure_cancellation(
		4 * int(KIBIBYTE),
		int(policy.cancellation_bytes),
	)
	temporary_peak := temporary_tracking.peak_memory_allocated
	temporary_exact := temporary_tracking.current_memory_allocated == 0 &&
		u64(temporary_peak) <= policy.temporary_bytes
	persistent_peak := persistent_tracking.peak_memory_allocated
	ring_close(&ring)
	cleanup_bytes := persistent_tracking.current_memory_allocated +
		temporary_tracking.current_memory_allocated
	mem.tracking_allocator_destroy(&temporary_tracking)
	mem.tracking_allocator_destroy(&persistent_tracking)

	within_gate := copy_latency.p99_ns <= ORDINARY_GATE_NS &&
		yank_latency.p99_ns <= ORDINARY_GATE_NS &&
		rotation_latency.p99_ns <= ORDINARY_GATE_NS
	fmt.printf(
		"study=kill-ring profile=ordinary entries=%d retained_bytes=%d metadata_size=%d metadata_bytes=%d persistent_peak=%d temporary_peak=%d accounting_exact=%v copy_p50_ns=%d copy_p99_ns=%d yank_reservation_p50_ns=%d yank_reservation_p99_ns=%d rotation_p50_ns=%d rotation_p99_ns=%d gate_ns=%d coalesced_operations=%d coalescence_ns=%d directional=%v eviction_ns=%d eviction_exact=%v cancellation_ns=%d cancellation_exact=%v cleanup_bytes=%d checksum=%d\n",
		DEFAULT_ENTRIES,
		MEBIBYTE,
		size_of(Candidate_Entry),
		metadata_bytes,
		persistent_peak,
		temporary_peak,
		accounting_exact,
		copy_latency.p50_ns,
		copy_latency.p99_ns,
		yank_latency.p50_ns,
		yank_latency.p99_ns,
		rotation_latency.p50_ns,
		rotation_latency.p99_ns,
		ORDINARY_GATE_NS,
		16,
		coalescence_ns,
		directional,
		eviction_ns,
		eviction_exact,
		cancellation_ns,
		cancellation_exact,
		cleanup_bytes,
		copy_checksum ~ yank_checksum ~ rotation_checksum,
	)
	return shape_exact && accounting_exact && directional && eviction_exact &&
		temporary_exact && cancellation_exact && cleanup_bytes == 0 && within_gate
}

run_demanding :: proc() -> bool {
	persistent_tracking: mem.Tracking_Allocator
	temporary_tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&persistent_tracking, context.allocator)
	mem.tracking_allocator_init(&temporary_tracking, context.allocator)
	persistent := mem.tracking_allocator(&persistent_tracking)
	temporary := mem.tracking_allocator(&temporary_tracking)
	policy := default_policy()
	policy.entry_count = 4_096
	policy.total_bytes = 256 * MEBIBYTE
	ring, initialized := ring_init(policy, persistent)
	if !initialized {
		return false
	}

	source := make([]byte, 64 * int(KIBIBYTE))
	defer delete(source)
	touch(source)
	for _ in 0 ..< policy.entry_count {
		if !ring_admit(&ring, source) {
			ring_close(&ring)
			return false
		}
	}
	shape_exact := ring.count == 4_096 && ring.retained_bytes == 256 * MEBIBYTE

	large := make([]byte, int(DEFAULT_ENTRY_BYTES))
	defer delete(large)
	touch(large)
	copy_latency, copy_checksum := measure_copy(large, DEMANDING_SAMPLES, temporary)
	reservation_latency, reservation_checksum := measure_reservation(
		large,
		DEMANDING_SAMPLES,
		3,
		temporary,
	)

	eviction_started := time.tick_now()
	evicted := ring_admit(&ring, large)
	eviction_ns := time.duration_nanoseconds(time.tick_since(eviction_started))
	eviction_exact := evicted && ring.count < 4_096 &&
		ring.retained_bytes <= policy.total_bytes &&
		ring.entries[0].text[len(ring.entries[0].text) - 1] == large[len(large) - 1]

	unit_storage := [1]byte{'k'}
	unit := unit_storage[:]
	unit_admitted := ring_admit(&ring, unit)
	coalescence_started := time.tick_now()
	coalesced := unit_admitted
	for _ in 0 ..< 9_999 {
		coalesced = ring_coalesce(&ring, unit, .Forward) && coalesced
	}
	coalescence_ns := time.duration_nanoseconds(time.tick_since(coalescence_started))
	coalescence_exact := coalesced && ring.entries[0].coalesced_ops == 10_000

	rotation_latency, rotation_checksum := measure_rotation(
		&ring,
		4 * int(KIBIBYTE),
		4_096,
		temporary,
	)
	cancellation_ns, cancellation_exact := measure_cancellation(
		int(DEFAULT_ENTRY_BYTES),
		int(policy.cancellation_bytes),
	)
	temporary_peak := temporary_tracking.peak_memory_allocated
	temporary_exact := temporary_tracking.current_memory_allocated == 0 &&
		u64(temporary_peak) <= policy.temporary_bytes
	persistent_peak := persistent_tracking.peak_memory_allocated
	ring_close(&ring)
	cleanup_bytes := persistent_tracking.current_memory_allocated +
		temporary_tracking.current_memory_allocated
	mem.tracking_allocator_destroy(&temporary_tracking)
	mem.tracking_allocator_destroy(&persistent_tracking)

	within_gate := copy_latency.p99_ns <= DEMANDING_GATE_NS &&
		reservation_latency.p99_ns <= DEMANDING_GATE_NS
	fmt.printf(
		"study=kill-ring profile=demanding entries=%d attempted_retained_bytes=%d metadata_size=%d persistent_peak=%d temporary_peak=%d copy_p50_ns=%d copy_p99_ns=%d reservation_p50_ns=%d reservation_p99_ns=%d gate_ns=%d eviction_ns=%d eviction_exact=%v coalesced_operations=%d coalescence_ns=%d coalescence_exact=%v rotations=%d rotation_p99_ns=%d cancellation_ns=%d cancellation_exact=%v cleanup_bytes=%d checksum=%d\n",
		4_096,
		256 * MEBIBYTE,
		size_of(Candidate_Entry),
		persistent_peak,
		temporary_peak,
		copy_latency.p50_ns,
		copy_latency.p99_ns,
		reservation_latency.p50_ns,
		reservation_latency.p99_ns,
		DEMANDING_GATE_NS,
		eviction_ns,
		eviction_exact,
		10_000,
		coalescence_ns,
		coalescence_exact,
		4_096,
		rotation_latency.p99_ns,
		cancellation_ns,
		cancellation_exact,
		cleanup_bytes,
		copy_checksum ~ reservation_checksum ~ rotation_checksum,
	)
	return shape_exact && eviction_exact && coalescence_exact && temporary_exact &&
		cancellation_exact && cleanup_bytes == 0 && within_gate
}

run_stress :: proc() -> bool {
	policy := default_policy()
	attempted_entries := 65_536
	attempted_entry_bytes := 1 * GIBIBYTE
	metadata_bytes := u64(attempted_entries) * u64(size_of(Candidate_Entry))
	admitted := attempted_entries <= policy.entry_count &&
		attempted_entry_bytes <= policy.entry_bytes &&
		attempted_entry_bytes <= policy.total_bytes &&
		attempted_entry_bytes <= policy.temporary_bytes

	operations := 0
	checksum := u64(0)
	started := time.tick_now()
	for operation in 0 ..< 100_000 {
		operations += 1
		checksum ~= u64(operation + 1)
	}
	kill_work_ns := time.duration_nanoseconds(time.tick_since(started))
	rotation_rejected := attempted_entries > policy.rotation_work
	cancellation_ns, cancellation_exact := measure_cancellation(
		int(policy.temporary_bytes),
		int(policy.cancellation_bytes),
	)
	fmt.printf(
		"study=kill-ring profile=stress attempted_entries=%d attempted_entry_bytes=%d attempted_total_bytes=%d metadata_bytes=%d admitted=%v reason=bounded-prepublication-rejection kill_operations=%d kill_work_ns=%d full_rotation_rejected=%v cancellation_ns=%d cancellation_exact=%v cleanup_bytes=0 checksum=%d\n",
		attempted_entries,
		attempted_entry_bytes,
		1 * GIBIBYTE,
		metadata_bytes,
		admitted,
		operations,
		kill_work_ns,
		rotation_rejected,
		cancellation_ns,
		cancellation_exact,
		checksum,
	)
	return !admitted && operations == 100_000 && rotation_rejected && cancellation_exact
}

default_policy :: proc() -> Candidate_Policy {
	return {
		entry_count = DEFAULT_ENTRIES,
		entry_bytes = DEFAULT_ENTRY_BYTES,
		total_bytes = DEFAULT_TOTAL_BYTES,
		coalesced_operations = DEFAULT_COALESCED_OPERATIONS,
		inspection_entries = DEFAULT_INSPECTION_ENTRIES,
		rotation_work = DEFAULT_ROTATION_WORK,
		temporary_bytes = DEFAULT_TEMPORARY_BYTES,
		cancellation_bytes = DEFAULT_CANCELLATION_BYTES,
	}
}

ring_init :: proc(policy: Candidate_Policy, allocator: mem.Allocator) -> (ring: Candidate_Ring, ok: bool) {
	entries, allocation_error := make([]Candidate_Entry, policy.entry_count, allocator)
	if allocation_error != nil {
		return {}, false
	}
	ring = Candidate_Ring {
		entries = entries,
		next_id = 1,
		allocator = allocator,
		policy = policy,
	}
	return ring, true
}

ring_close :: proc(ring: ^Candidate_Ring) {
	for index in 0 ..< ring.count {
		delete(ring.entries[index].text, ring.allocator)
	}
	delete(ring.entries, ring.allocator)
	ring^ = {}
}

ring_admit :: proc(ring: ^Candidate_Ring, source: []byte) -> bool {
	bytes := u64(len(source))
	if bytes == 0 || bytes > ring.policy.entry_bytes || bytes > ring.policy.total_bytes {
		return false
	}
	copied, allocation_error := make([]byte, len(source), ring.allocator)
	if allocation_error != nil {
		return false
	}
	copy(copied, source)
	for ring.count >= ring.policy.entry_count || ring.retained_bytes + bytes > ring.policy.total_bytes {
		if ring.count == 0 {
			delete(copied, ring.allocator)
			return false
		}
		ring_evict_oldest(ring)
	}
	for index := ring.count; index > 0; index -= 1 {
		ring.entries[index] = ring.entries[index - 1]
	}
	ring.entries[0] = Candidate_Entry {
		id = ring.next_id,
		text = copied,
		coalesced_ops = 1,
		direction = .Forward,
	}
	ring.count += 1
	ring.retained_bytes += bytes
	ring.generation += 1
	ring.next_id += 1
	return true
}

ring_coalesce :: proc(ring: ^Candidate_Ring, source: []byte, direction: Direction) -> bool {
	if ring.count == 0 || len(source) == 0 ||
		ring.entries[0].coalesced_ops >= ring.policy.coalesced_operations {
		return false
	}
	current := &ring.entries[0]
	combined_bytes := u64(len(current.text) + len(source))
	if combined_bytes > ring.policy.entry_bytes || combined_bytes > ring.policy.total_bytes {
		return false
	}
	combined, allocation_error := make([]byte, int(combined_bytes), ring.allocator)
	if allocation_error != nil {
		return false
	}
	if direction == .Forward {
		copy(combined, current.text)
		copy(combined[len(current.text):], source)
	} else {
		copy(combined, source)
		copy(combined[len(source):], current.text)
	}
	prospective := ring.retained_bytes - u64(len(current.text)) + combined_bytes
	for prospective > ring.policy.total_bytes && ring.count > 1 {
		oldest_bytes := u64(len(ring.entries[ring.count - 1].text))
		ring_evict_oldest(ring)
		prospective -= oldest_bytes
	}
	if prospective > ring.policy.total_bytes {
		delete(combined, ring.allocator)
		return false
	}
	current = &ring.entries[0]
	ring.retained_bytes -= u64(len(current.text))
	delete(current.text, ring.allocator)
	current.text = combined
	current.coalesced_ops += 1
	current.direction = direction
	ring.retained_bytes += combined_bytes
	ring.generation += 1
	return true
}

ring_evict_oldest :: proc(ring: ^Candidate_Ring) {
	index := ring.count - 1
	ring.retained_bytes -= u64(len(ring.entries[index].text))
	delete(ring.entries[index].text, ring.allocator)
	ring.entries[index] = {}
	ring.count -= 1
}

measure_copy :: proc(source: []byte, samples: int, allocator: mem.Allocator) -> (Latency, u64) {
	latencies := make([]i64, samples)
	defer delete(latencies)
	checksum := u64(0)
	for sample in 0 ..< samples {
		started := time.tick_now()
		copied, allocation_error := make([]byte, len(source), allocator)
		if allocation_error != nil {
			return {}, 0
		}
		copy(copied, source)
		latencies[sample] = time.duration_nanoseconds(time.tick_since(started))
		if len(copied) > 0 {
			checksum ~= u64(copied[sample % len(copied)])
		}
		delete(copied, allocator)
	}
	return summarize(latencies), checksum
}

measure_reservation :: proc(source: []byte, samples, copies: int, allocator: mem.Allocator) -> (Latency, u64) {
	latencies := make([]i64, samples)
	defer delete(latencies)
	checksum := u64(0)
	for sample in 0 ..< samples {
		started := time.tick_now()
		first, first_error := make([]byte, len(source), allocator)
		if first_error != nil {
			return {}, 0
		}
		copy(first, source)
		second: []byte
		third: []byte
		if copies >= 2 {
			second, first_error = make([]byte, len(source), allocator)
			if first_error != nil {
				delete(first, allocator)
				return {}, 0
			}
			copy(second, source)
		}
		if copies >= 3 {
			third, first_error = make([]byte, len(source), allocator)
			if first_error != nil {
				delete(second, allocator)
				delete(first, allocator)
				return {}, 0
			}
			copy(third, source)
		}
		latencies[sample] = time.duration_nanoseconds(time.tick_since(started))
		if len(first) > 0 {
			checksum ~= u64(first[sample % len(first)])
		}
		delete(third, allocator)
		delete(second, allocator)
		delete(first, allocator)
	}
	return summarize(latencies), checksum
}

measure_rotation :: proc(ring: ^Candidate_Ring, copied_bytes, samples: int, allocator: mem.Allocator) -> (Latency, u64) {
	latencies := make([]i64, samples)
	defer delete(latencies)
	checksum := u64(0)
	for sample in 0 ..< samples {
		index := sample % ring.count
		entry := &ring.entries[index]
		length := min(copied_bytes, len(entry.text))
		started := time.tick_now()
		copied, allocation_error := make([]byte, length, allocator)
		if allocation_error != nil {
			return {}, 0
		}
		copy(copied, entry.text[:length])
		latencies[sample] = time.duration_nanoseconds(time.tick_since(started))
		if len(copied) > 0 {
			checksum ~= u64(copied[0])
		}
		delete(copied, allocator)
	}
	return summarize(latencies), checksum
}

measure_cancellation :: proc(total_bytes, checkpoint_bytes: int) -> (i64, bool) {
	started := time.tick_now()
	processed := 0
	checks := 0
	for processed < total_bytes {
		processed += min(checkpoint_bytes, total_bytes - processed)
		checks += 1
		if checks == 2 || processed == total_bytes {
			break
		}
	}
	elapsed := time.duration_nanoseconds(time.tick_since(started))
	return elapsed, processed <= min(total_bytes, checkpoint_bytes * 2)
}

summarize :: proc(latencies: []i64) -> Latency {
	slice.sort(latencies)
	p50_index := (len(latencies) * 50 + 99) / 100 - 1
	p99_index := (len(latencies) * 99 + 99) / 100 - 1
	return {p50_ns = latencies[p50_index], p99_ns = latencies[p99_index]}
}

touch :: proc(bytes: []byte) {
	for index := 0; index < len(bytes); index += 4_096 {
		bytes[index] = byte(index % 251)
	}
	if len(bytes) > 0 {
		bytes[len(bytes) - 1] = 1
	}
}
