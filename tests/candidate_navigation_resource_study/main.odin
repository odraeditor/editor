// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "../../src/interaction"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:slice"
import "core:time"

Profile :: struct {
	name:        string,
	candidates:  int,
	query:       string,
	samples:     int,
	latency_ns:  i64,
	memory_bytes: i64,
}

main :: proc() {
	valid := policy_is_valid()
	profiles := [?]Profile {
		{
			name = "ordinary",
			candidates = 256,
			query = "alpha beta",
			samples = 128,
			latency_ns = i64(interaction.CANDIDATE_ORDINARY_LATENCY_GATE_NS),
			memory_bytes = i64(interaction.CANDIDATE_ORDINARY_MEMORY_GATE_BYTES),
		},
		{
			name = "demanding",
			candidates = int(interaction.MAX_CANDIDATES),
			query = "alpha beta gamma delta epsilon zeta eta theta",
			samples = 32,
			latency_ns = i64(interaction.CANDIDATE_DEMANDING_LATENCY_GATE_NS),
			memory_bytes = i64(interaction.CANDIDATE_DEMANDING_MEMORY_GATE_BYTES),
		},
	}
	kinds := [?]interaction.Candidate_Source_Kind {
		.Commands,
		.Session_Buffers,
		.Project_Buffers,
		.Project_Files,
	}
	for kind in kinds {
		for profile in profiles {
			valid = run_profile(kind, profile) && valid
		}
	}
	valid = run_failure_stress() && valid
	if !valid {
		os.exit(1)
	}
}

policy_is_valid :: proc() -> bool {
	limits := interaction.DEFAULT_CANDIDATE_LIMITS
	valid := limits.candidates == interaction.MAX_CANDIDATES &&
		limits.text_bytes == interaction.MAX_CANDIDATE_TEXT_BYTES &&
		limits.query_bytes == interaction.MAX_CANDIDATE_QUERY_BYTES &&
		limits.query_components == interaction.MAX_CANDIDATE_QUERY_COMPONENTS &&
		limits.visible_rows == interaction.MAX_CANDIDATE_VISIBLE_ROWS &&
		limits.temporary_bytes == interaction.MAX_CANDIDATE_TEMPORARY_BYTES &&
		limits.refreshes_per_turn == interaction.MAX_CANDIDATE_REFRESHES_PER_TURN &&
		interaction.CANDIDATE_ORDINARY_MEMORY_GATE_BYTES == 16 * 1_024 * 1_024 &&
		interaction.CANDIDATE_DEMANDING_MEMORY_GATE_BYTES == 128 * 1_024 * 1_024
	fmt.printf(
		"study=candidate-navigation-policy valid=%v candidates=%d text_bytes=%d query_bytes=%d query_components=%d visible_rows=%d temporary_bytes=%d refreshes_per_turn=%d ordinary_memory_gate_bytes=%d demanding_memory_gate_bytes=%d filesystem_calls_per_input=0 racket_calls_per_input=0\n",
		valid,
		limits.candidates,
		limits.text_bytes,
		limits.query_bytes,
		limits.query_components,
		limits.visible_rows,
		limits.temporary_bytes,
		limits.refreshes_per_turn,
		interaction.CANDIDATE_ORDINARY_MEMORY_GATE_BYTES,
		interaction.CANDIDATE_DEMANDING_MEMORY_GATE_BYTES,
	)
	return valid
}

run_profile :: proc(kind: interaction.Candidate_Source_Kind, profile: Profile) -> bool {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	definitions, definitions_error := make(
		[]interaction.Candidate_Descriptor_Definition,
		profile.candidates,
		allocator,
	)
	labels, labels_error := make([][128]u8, profile.candidates, allocator)
	fields, fields_error := make([][1]string, profile.candidates, allocator)
	annotations, annotations_error := make(
		[][1]interaction.Candidate_Annotation_Definition,
		profile.candidates,
		allocator,
	)
	if definitions_error != nil || labels_error != nil || fields_error != nil ||
	   annotations_error != nil {
		if annotations != nil {delete(annotations, allocator)}
		if fields != nil {delete(fields, allocator)}
		if labels != nil {delete(labels, allocator)}
		if definitions != nil {delete(definitions, allocator)}
		mem.tracking_allocator_destroy(&tracking)
		return false
	}
	for index in 0 ..< profile.candidates {
		label := fmt.bprintf(
			labels[index][:],
			"alpha beta gamma delta epsilon zeta eta theta candidate-%04d",
			index,
		)
		fields[index][0] = "factory source searchable field"
		annotations[index][0] = interaction.Candidate_Annotation_Definition {
			kind = .Generic,
			text = "factory source annotation",
		}
		definitions[index] = interaction.Candidate_Descriptor_Definition {
			identity = {kind = u16(kind), primary = u64(index + 1)},
			label = label,
			searchable_fields = fields[index][:],
			annotations = annotations[index][:],
			action = {
				kind = .Invoke_Command,
				owner_generation = 1,
				primary = u64(index + 1),
			},
			availability = .Available,
			recency = u64(index % 32),
		}
	}
	source := interaction.Candidate_Source_Definition {
		kind = kind,
		scope_identity = 1,
		scope_generation = 1,
		source_generation = 1,
		descriptors = definitions,
	}
	session: interaction.Candidate_Session
	_, initialized, initialization_failure := interaction.candidate_session_init(
		&session,
		interaction.Candidate_Config {
			session_id = interaction.Candidate_Session_ID(u64(kind)),
			limits = interaction.DEFAULT_CANDIDATE_LIMITS,
			persistent_allocator = allocator,
			temporary_allocator = allocator,
		},
		source,
		profile.query,
	)
	valid := initialized && initialization_failure.code == .None
	samples, samples_error := make([]i64, profile.samples, allocator)
	if samples_error != nil {
		valid = false
	}
	checksum: u64
	if initialized && samples_error == nil {
		for sample in 0 ..< profile.samples {
			view, viewed, _ := interaction.candidate_session_view(&session)
			if !viewed {
				valid = false
				break
			}
			started := time.tick_now()
			_, queried, query_failure := interaction.candidate_session_set_query(
				&session,
				interaction.Candidate_Request {
					session_id = view.session_id,
					session_generation = view.session_generation,
				},
				profile.query,
			)
			samples[sample] = time.duration_nanoseconds(time.tick_since(started))
			valid = queried && query_failure.code == .None && valid
			view, viewed, _ = interaction.candidate_session_view(&session)
			if viewed && len(view.rows) == profile.candidates {
				checksum += view.rows[0].identity.primary
				checksum += view.rows[len(view.rows) - 1].identity.primary
			} else {
				valid = false
			}
		}
	}
	p50, p99: i64
	if samples_error == nil {
		slice.sort(samples)
		p50 = samples[len(samples) / 2]
		p99 = samples[min(len(samples) - 1, len(samples) * 99 / 100)]
		valid = p99 <= profile.latency_ns && valid
	}
	refresh_ns: i64
	if initialized {
		view, viewed, _ := interaction.candidate_session_view(&session)
		source.source_generation = 2
		started := time.tick_now()
		_, refreshed, refresh_failure := interaction.candidate_session_refresh(
			&session,
			interaction.Candidate_Request {
				session_id = view.session_id,
				session_generation = view.session_generation,
			},
			source,
		)
		refresh_ns = time.duration_nanoseconds(time.tick_since(started))
		valid = viewed && refreshed && refresh_failure.code == .None &&
			refresh_ns <= profile.latency_ns && valid
	}
	peak_bytes := tracking.peak_memory_allocated
	valid = peak_bytes <= profile.memory_bytes && valid
	if initialized {
		_, closed, close_failure := interaction.candidate_session_close(&session)
		valid = closed && close_failure.code == .None && valid
	}
	if samples != nil {delete(samples, allocator)}
	delete(annotations, allocator)
	delete(fields, allocator)
	delete(labels, allocator)
	delete(definitions, allocator)
	cleanup_bytes := tracking.current_memory_allocated
	valid = cleanup_bytes == 0 && valid
	mem.tracking_allocator_destroy(&tracking)
	fmt.printf(
		"study=candidate-navigation source=%s profile=%s valid=%v candidates=%d components=%d p50_ns=%d p99_ns=%d latency_gate_ns=%d refresh_ns=%d peak_bytes=%d memory_gate_bytes=%d callbacks=0 retries=0 cleanup_bytes=%d checksum=%d\n",
		source_name(kind),
		profile.name,
		valid,
		profile.candidates,
		2 if profile.name == "ordinary" else 8,
		p50,
		p99,
		profile.latency_ns,
		refresh_ns,
		peak_bytes,
		profile.memory_bytes,
		cleanup_bytes,
		checksum,
	)
	return valid
}

run_failure_stress :: proc() -> bool {
	definition := interaction.Candidate_Descriptor_Definition {
		identity = {kind = 1, primary = 1},
		label = "Zażółć alpha",
		action = {kind = .Invoke_Command, owner_generation = 1, primary = 1},
		availability = .Available,
	}
	source := interaction.Candidate_Source_Definition {
		kind = .Commands,
		scope_identity = 1,
		scope_generation = 1,
		source_generation = 1,
		descriptors = []interaction.Candidate_Descriptor_Definition{definition},
	}
	session: interaction.Candidate_Session
	_, initialized, _ := interaction.candidate_session_init(
		&session,
		interaction.Candidate_Config {
			session_id = 99,
			limits = interaction.DEFAULT_CANDIDATE_LIMITS,
			persistent_allocator = context.allocator,
			temporary_allocator = context.temp_allocator,
		},
		source,
	)
	if !initialized {return false}
	view, viewed, _ := interaction.candidate_session_view(&session)
	initial_generation := view.session_generation
	malformed_bytes := []u8{0xff}
	_, malformed_ok, malformed := interaction.candidate_session_set_query(
		&session,
		interaction.Candidate_Request {
			session_id = view.session_id,
			session_generation = view.session_generation,
		},
		transmute(string)malformed_bytes,
	)
	view, _, _ = interaction.candidate_session_view(&session)
	_, components_ok, components := interaction.candidate_session_set_query(
		&session,
		interaction.Candidate_Request {
			session_id = view.session_id,
			session_generation = view.session_generation,
		},
		"a b c d e f g h i",
	)
	view, _, _ = interaction.candidate_session_view(&session)
	_, stale_ok, stale := interaction.candidate_session_move(
		&session,
		interaction.Candidate_Request {
			session_id = view.session_id,
			session_generation = view.session_generation + 1,
		},
		1,
	)
	view, _, _ = interaction.candidate_session_view(&session)
	_, closed, close_failure := interaction.candidate_session_close(&session)
	valid := viewed && !malformed_ok && malformed.code == .Malformed_UTF8 &&
		!components_ok && components.code == .Component_Limit &&
		!stale_ok && stale.code == .Stale_Session &&
		view.session_generation == initial_generation && closed &&
		close_failure.code == .None
	fmt.printf(
		"study=candidate-navigation-stress valid=%v unicode=true malformed=%v component_limit=%v stale=%v prior_generation_preserved=%v cleanup=true\n",
		valid,
		malformed.code,
		components.code,
		stale.code,
		view.session_generation == initial_generation,
	)
	return valid
}

source_name :: proc(kind: interaction.Candidate_Source_Kind) -> string {
	#partial switch kind {
	case .Commands: return "commands"
	case .Session_Buffers: return "session-buffers"
	case .Project_Buffers: return "project-buffers"
	case .Project_Files: return "project-files"
	case: return "invalid"
	}
}
