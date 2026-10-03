// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import "base:runtime"
import "core:bytes"
import "core:encoding/base64"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:slice"
import "core:time"

OSC52_BODY_LIMIT_BYTES :: 256 * 1024
OSC52_BODY_PREFIX :: "52;c;"
OSC52_FRAME_PREFIX :: "\x1b]52;c;"
OSC52_TERMINATOR :: byte(0x07)
MAX_TEXT_BYTES :: 196_602
CANCELLATION_CHECKPOINT_BYTES :: 64 * 1024
MAX_SAMPLES :: 256

Profile :: struct {
	name:         string,
	text_bytes:   int,
	warmups:      int,
	samples:      int,
}

main :: proc() {
	print_environment()
	profiles := [?]Profile{
		Profile{name = "ordinary", text_bytes = 4 * 1024, warmups = 32, samples = 256},
		Profile{name = "demanding", text_bytes = 64 * 1024, warmups = 16, samples = 128},
		Profile{name = "transport-ceiling", text_bytes = MAX_TEXT_BYTES, warmups = 8, samples = 64},
	}
	passed := true
	for profile in profiles {
		passed = run_profile(profile) && passed
	}
	passed = verify_oversized_rejection() && passed
	if !passed {
		os.exit(1)
	}
}

print_environment :: proc() {
	remote := env_present("SSH_CONNECTION") || env_present("SSH_TTY")
	herdr := env_present("HERDR_PANE_ID") && env_present("HERDR_SOCKET_PATH")
	tmux := env_present("TMUX")
	zellij := env_present("ZELLIJ")
	graphical := env_present("WAYLAND_DISPLAY") || env_present("DISPLAY")
	fmt.printf(
		"probe=clipboard-environment remote=%t herdr=%t tmux=%t zellij=%t graphical_session=%t selected=osc52-bel read_capable=false write_capable=%t presentation_host=outer-terminal-client\n",
		remote,
		herdr,
		tmux,
		zellij,
		graphical,
		herdr,
	)
	fmt.printf(
		"probe=clipboard-policy body_limit_bytes=%d max_text_bytes=%d cancellation_checkpoint_bytes=%d timeout_scope=bounded-terminal-write cleanup=owned-frame\n",
		OSC52_BODY_LIMIT_BYTES,
		MAX_TEXT_BYTES,
		CANCELLATION_CHECKPOINT_BYTES,
	)
}

env_present :: proc(name: string) -> bool {
	buffer: [1024]u8
	value, _ := os.lookup_env(buffer[:], name)
	return len(value) > 0
}

run_profile :: proc(profile: Profile) -> bool {
	if profile.samples <= 0 || profile.samples > MAX_SAMPLES || profile.text_bytes <= 0 {
		return false
	}

	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	allocator := mem.tracking_allocator(&tracking)

	text, text_error := make([]byte, profile.text_bytes, allocator)
	if text_error != nil {
		fmt.eprintf("probe=clipboard-framing profile=%s allocation_failure=true\n", profile.name)
		return false
	}
	for index in 0 ..< len(text) {
		text[index] = byte('a' + index % 26)
	}

	latencies: [MAX_SAMPLES]i64
	frame_bytes := 0
	valid := true
	for sample_index in 0 ..< profile.warmups + profile.samples {
		started := time.tick_now()
		frame, framed := build_frame(text, allocator)
		elapsed_ns := time.duration_nanoseconds(time.tick_since(started))
		if !framed {
			valid = false
			break
		}
		frame_bytes = len(frame)
		valid = validate_frame(frame, text, allocator)
		delete(frame, allocator)
		if !valid {
			break
		}
		if sample_index >= profile.warmups {
			latencies[sample_index - profile.warmups] = elapsed_ns
		}
	}

	delete(text, allocator)
	cleanup := tracking.current_memory_allocated == 0
	sorted := latencies[:profile.samples]
	slice.sort(sorted)
	checkpoints := (profile.text_bytes + CANCELLATION_CHECKPOINT_BYTES - 1) /
		CANCELLATION_CHECKPOINT_BYTES
	fmt.printf(
		"probe=clipboard-framing profile=%s text_bytes=%d frame_bytes=%d warmups=%d samples=%d p50_ns=%d p99_ns=%d max_ns=%d cancellation_checkpoints=%d peak_bytes=%d valid=%t cleanup=%t\n",
		profile.name,
		profile.text_bytes,
		frame_bytes,
		profile.warmups,
		profile.samples,
		percentile_nearest_rank(sorted, 50),
		percentile_nearest_rank(sorted, 99),
		sorted[len(sorted) - 1],
		checkpoints,
		tracking.peak_memory_allocated,
		valid,
		cleanup,
	)
	return valid && cleanup
}

verify_oversized_rejection :: proc() -> bool {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	allocator := mem.tracking_allocator(&tracking)

	text, text_error := make([]byte, MAX_TEXT_BYTES + 1, allocator)
	if text_error != nil {
		return false
	}
	frame, framed := build_frame(text, allocator)
	if framed {
		delete(frame, allocator)
	}
	delete(text, allocator)
	cleanup := tracking.current_memory_allocated == 0
	fmt.printf(
		"probe=clipboard-framing profile=oversized text_bytes=%d rejected=%t peak_bytes=%d cleanup=%t\n",
		MAX_TEXT_BYTES + 1,
		!framed,
		tracking.peak_memory_allocated,
		cleanup,
	)
	return !framed && cleanup
}

build_frame :: proc(text: []byte, allocator: runtime.Allocator) -> (frame: []byte, ok: bool) {
	encoded_bytes := base64.encoded_len(text)
	body_bytes := len(OSC52_BODY_PREFIX) + encoded_bytes
	if body_bytes > OSC52_BODY_LIMIT_BYTES {
		return nil, false
	}
	candidate, allocation_error := make(
		[]byte,
		len(OSC52_FRAME_PREFIX) + encoded_bytes + 1,
		allocator,
	)
	if allocation_error != nil {
		return nil, false
	}
	frame = candidate
	copy(frame, OSC52_FRAME_PREFIX)
	encoded_start := len(OSC52_FRAME_PREFIX)
	encoded_end := encoded_start + encoded_bytes
	_, encoding_error := base64.encode_into_buf(frame[encoded_start:encoded_end], text)
	if encoding_error != nil {
		delete(frame, allocator)
		return nil, false
	}
	frame[encoded_end] = OSC52_TERMINATOR
	return frame, true
}

validate_frame :: proc(frame, expected: []byte, allocator: runtime.Allocator) -> bool {
	if len(frame) <= len(OSC52_FRAME_PREFIX) || frame[len(frame) - 1] != OSC52_TERMINATOR {
		return false
	}
	if string(frame[:len(OSC52_FRAME_PREFIX)]) != OSC52_FRAME_PREFIX {
		return false
	}
	encoded := string(frame[len(OSC52_FRAME_PREFIX):len(frame) - 1])
	decoded, decoding_error := base64.decode(encoded, allocator = allocator)
	if decoding_error != nil {
		return false
	}
	defer delete(decoded, allocator)
	return bytes.equal(decoded, expected)
}

percentile_nearest_rank :: proc(values: []i64, percentile: int) -> i64 {
	assert(len(values) > 0)
	assert(percentile > 0 && percentile <= 100)
	rank := (percentile * len(values) + 99) / 100
	return values[rank - 1]
}
