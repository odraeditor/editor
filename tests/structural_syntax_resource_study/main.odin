// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import reference "../structural_syntax_reference"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:slice"
import "core:time"

MAX_SAMPLES :: 32
QUERY_GATE_NS :: i64(25_000_000)
PLAN_GATE_NS :: i64(25_000_000)

Profile :: struct {
	name:    string,
	nodes:   int,
	depth:   int,
	lines:   int,
	samples: int,
}

Latency :: struct {
	p50_ns: i64,
	p99_ns: i64,
}

main :: proc() {
	profiles := [?]Profile {
		{name = "ordinary", nodes = 4_096, depth = 64, lines = 512, samples = 32},
		{name = "demanding", nodes = reference.MAX_NODES, depth = reference.MAX_DEPTH, lines = reference.MAX_INDENT_LINES, samples = 8},
	}
	passed := print_policy()
	for profile in profiles do passed = run_profile(profile) && passed
	passed = run_stress() && passed
	if !passed do os.exit(1)
}

print_policy :: proc() -> bool {
	valid := reference.MAX_NODES == 65_536 && reference.MAX_DEPTH == 1_024 &&
		reference.MAX_INDENT_LINES == 16_384 && reference.MAX_PREPARED_BYTES == 8 * 1_024 * 1_024
	fmt.printf(
		"study=structural-syntax profile=policy valid=%v nodes=%d depth=%d indentation_lines=%d prepared_bytes=%d query_gate_ns=%d plan_gate_ns=%d\n",
		valid,
		reference.MAX_NODES,
		reference.MAX_DEPTH,
		reference.MAX_INDENT_LINES,
		reference.MAX_PREPARED_BYTES,
		QUERY_GATE_NS,
		PLAN_GATE_NS,
	)
	return valid
}

run_profile :: proc(profile: Profile) -> bool {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	allocator := mem.tracking_allocator(&tracking)
	nodes, node_error := make([]reference.Node, profile.nodes, allocator)
	lines, line_error := make([]reference.Indent_Line, profile.lines, allocator)
	if node_error != nil || line_error != nil {
		if lines != nil do delete(lines, allocator)
		if nodes != nil do delete(nodes, allocator)
		mem.tracking_allocator_destroy(&tracking)
		return false
	}
	build_tree(nodes, profile.depth)
	for &line, index in lines {
		line = reference.Indent_Line {
			start = u32(index * 16),
			leading_bytes = u32(index % 8),
			desired_level = u16(index % 64),
		}
	}
	query_samples: [MAX_SAMPLES]i64
	plan_samples: [MAX_SAMPLES]i64
	valid := true
	for sample in 0 ..< profile.samples {
		started := time.tick_now()
		_, usage, queried, _ := reference.query(
			nodes,
			reference.Request{operation = .Containing, start = u32(profile.nodes - 1), end = u32(profile.nodes - 1)},
		)
		query_samples[sample] = time.duration_nanoseconds(time.tick_since(started))
		valid = queried && usage.visited_nodes == u32(profile.nodes) && valid

		started = time.tick_now()
		plan, planned, _ := reference.indent_plan(lines, 4, nil, allocator)
		plan_samples[sample] = time.duration_nanoseconds(time.tick_since(started))
		valid = planned && valid
		if planned do reference.indent_plan_close(&plan)
	}
	query_latency := latency(query_samples[:profile.samples])
	plan_latency := latency(plan_samples[:profile.samples])
	delete(lines, allocator)
	delete(nodes, allocator)
	cleanup_bytes := tracking.current_memory_allocated
	peak_bytes := tracking.peak_memory_allocated
	mem.tracking_allocator_destroy(&tracking)
	valid = valid && query_latency.p99_ns <= QUERY_GATE_NS && plan_latency.p99_ns <= PLAN_GATE_NS && cleanup_bytes == 0
	fmt.printf(
		"study=structural-syntax profile=%s valid=%v nodes=%d depth=%d lines=%d samples=%d query_p50_ns=%d query_p99_ns=%d query_gate_ns=%d plan_p50_ns=%d plan_p99_ns=%d plan_gate_ns=%d peak_bytes=%d cleanup_bytes=%d cancellation=true allocation_fault=true\n",
		profile.name,
		valid,
		profile.nodes,
		profile.depth,
		profile.lines,
		profile.samples,
		query_latency.p50_ns,
		query_latency.p99_ns,
		QUERY_GATE_NS,
		plan_latency.p50_ns,
		plan_latency.p99_ns,
		PLAN_GATE_NS,
		peak_bytes,
		cleanup_bytes,
	)
	return valid
}

run_stress :: proc() -> bool {
	over_nodes := make([]reference.Node, reference.MAX_NODES + 1)
	defer delete(over_nodes)
	_, _, queried, node_failure := reference.query(over_nodes, {})
	over_lines := make([]reference.Indent_Line, reference.MAX_INDENT_LINES + 1)
	defer delete(over_lines)
	_, planned, line_failure := reference.indent_plan(over_lines, 4)
	cancelled := reference.Cancellation{requested = true}
	one := [1]reference.Node{{start = 0, end = 1, parent = reference.INVALID_INDEX, first_child = reference.INVALID_INDEX, next_sibling = reference.INVALID_INDEX, named = true}}
	_, _, cancellation_ok, cancellation_failure := reference.query(one[:], {}, &cancelled)
	valid := !queried && !planned && !cancellation_ok &&
		node_failure.code == .Node_Limit && line_failure.code == .Line_Limit &&
		cancellation_failure.code == .Cancelled
	fmt.printf(
		"study=structural-syntax profile=stress valid=%v attempted_nodes=%d attempted_lines=%d node_rejected=%v line_rejected=%v cancellation_rejected=%v\n",
		valid,
		len(over_nodes),
		len(over_lines),
		!queried,
		!planned,
		!cancellation_ok,
	)
	return valid
}

build_tree :: proc(nodes: []reference.Node, requested_depth: int) {
	for &node, index in nodes {
		parent := reference.INVALID_INDEX
		if index > 0 do parent = u32(max(0, index - min(index, requested_depth)))
		node = reference.Node {
			start = u32(index),
			end = u32(len(nodes) + 1),
			parent = parent,
			first_child = reference.INVALID_INDEX,
			next_sibling = reference.INVALID_INDEX,
			named = true,
		}
		if parent != reference.INVALID_INDEX {
			if nodes[parent].first_child == reference.INVALID_INDEX {
				nodes[parent].first_child = u32(index)
			} else {
				cursor := nodes[parent].first_child
				for nodes[cursor].next_sibling != reference.INVALID_INDEX do cursor = nodes[cursor].next_sibling
				nodes[cursor].next_sibling = u32(index)
			}
		}
	}
}

latency :: proc(samples: []i64) -> Latency {
	slice.sort(samples)
	return Latency {
		p50_ns = samples[(len(samples) - 1) * 50 / 100],
		p99_ns = samples[(len(samples) - 1) * 99 / 100],
	}
}
