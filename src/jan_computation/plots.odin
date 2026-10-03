// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_computation

import "core:fmt"
import "core:math"
import "core:unicode/utf8"

/* MAX_TEXT_PLOT_WIDTH bounds one terminal plot row. */
MAX_TEXT_PLOT_WIDTH :: u16(256)
/* MAX_PLOT_LABEL_BYTES bounds one copied plot label. */
MAX_PLOT_LABEL_BYTES :: 128
/* MAX_PLOT_OUTPUT_KEY_BYTES bounds one copied output resource key. */
MAX_PLOT_OUTPUT_KEY_BYTES :: 4 * 1_024

/* Plot_Point is one copied label and numeric value. */
Plot_Point :: struct {
	label: string,
	value: f64,
}

/* Plot_Snapshot is one exact copied table-range projection. */
Plot_Snapshot :: struct {
	operation_id: Operation_ID,
	scope:        Scope,
	table_id:     u64,
	digest:       [32]u8,
	title:        string,
	x_label:      string,
	y_label:      string,
	points:       []Plot_Point,
}

/* Plot_Terminal identifies one admitted Gnuplot output family. */
Plot_Terminal :: enum u8 {
	Invalid,
	Png,
	Svg,
	Pdf,
}

/* Plot_Output is one copied provider-owned output resource. */
Plot_Output :: struct {
	provider: u64,
	key:      [MAX_PLOT_OUTPUT_KEY_BYTES]u8,
	length:   u16,
}

/* Gnuplot_Request is a bounded process handoff over copied data, not an execution grant. */
Gnuplot_Request :: struct {
	operation_id:      Operation_ID,
	scope:             Scope,
	adapter_generation: Adapter_Generation,
	table_id:          u64,
	snapshot_digest:   [32]u8,
	terminal:          Plot_Terminal,
	output:            Plot_Output,
	width:             u16,
	height:            u16,
	point_count:       u32,
	input_bytes:       u64,
	limits:            Limits,
}

/* plot_snapshot_is_valid checks exact provenance and copied labels and points. */
plot_snapshot_is_valid :: proc(snapshot: Plot_Snapshot) -> bool {
	if snapshot.operation_id == Operation_ID(0) || !scope_is_valid(snapshot.scope) ||
	   snapshot.table_id == 0 || !digest_is_present(snapshot.digest) ||
	   len(snapshot.points) == 0 || len(snapshot.points) > int(MAX_TABLE_CELLS) ||
	   !plot_text_is_valid(snapshot.title) || !plot_text_is_valid(snapshot.x_label) ||
	   !plot_text_is_valid(snapshot.y_label) {
		return false
	}
	for point in snapshot.points {
		if !plot_text_is_valid(point.label) || math.is_nan(point.value) || math.is_inf(point.value) {
			return false
		}
	}
	return true
}

/* render_text_plot renders copied nonnegative data into one bounded text buffer. */
render_text_plot :: proc(snapshot: Plot_Snapshot, width: u16, output: []u8) -> (string, bool, Failure) {
	if !plot_snapshot_is_valid(snapshot) || width == 0 || width > MAX_TEXT_PLOT_WIDTH ||
	   len(output) == 0 {
		return "", false, plot_failure(.Invalid_Request, .Result)
	}
	maximum := f64(0)
	for point in snapshot.points {
		magnitude := abs(point.value)
		if magnitude > maximum do maximum = magnitude
	}
	if maximum == 0 do maximum = 1
	cursor := 0
	header := fmt.bprintf(output[cursor:], "%s\n", snapshot.title)
	if len(header) == 0 || cursor + len(header) >= len(output) do return "", false, plot_failure(.Limited, .Result)
	cursor += len(header)
	for point in snapshot.points {
		bar_width := int(abs(point.value) / maximum * f64(width))
		if point.value != 0 && bar_width == 0 do bar_width = 1
		prefix := fmt.bprintf(output[cursor:], "%s %s", point.label, "-" if point.value < 0 else "+")
		if len(prefix) == 0 || cursor + len(prefix) + bar_width + 1 >= len(output) {
			return "", false, plot_failure(.Limited, .Result)
		}
		cursor += len(prefix)
		for _ in 0 ..< bar_width {
			output[cursor] = '#'
			cursor += 1
		}
		output[cursor] = '\n'
		cursor += 1
	}
	return string(output[:cursor]), true, {}
}

/* plot_output_copy creates one pointer-free provider-owned output identity. */
plot_output_copy :: proc(provider: u64, key: string) -> (Plot_Output, bool) {
	if provider == 0 || len(key) == 0 || len(key) > MAX_PLOT_OUTPUT_KEY_BYTES || !utf8.valid_string(key) {
		return {}, false
	}
	output: Plot_Output
	output.provider = provider
	output.length = u16(copy(output.key[:], key))
	return output, true
}

/* gnuplot_request_prepare validates one copied-data process handoff without executing it. */
gnuplot_request_prepare :: proc(
	snapshot: Plot_Snapshot,
	adapter_generation: Adapter_Generation,
	terminal: Plot_Terminal,
	output: Plot_Output,
	width, height: u16,
	input_bytes: u64,
	limits := DEFAULT_LIMITS,
) -> (Gnuplot_Request, bool, Failure) {
	if !plot_snapshot_is_valid(snapshot) || adapter_generation == Adapter_Generation(0) ||
	   terminal == .Invalid || !plot_output_is_valid(output) || width == 0 || height == 0 ||
	   input_bytes == 0 || input_bytes > limits.output_bytes || !limits_are_valid(limits) {
		return {}, false, plot_failure(.Invalid_Request, .Adapter)
	}
	return {
		operation_id = snapshot.operation_id,
		scope = snapshot.scope,
		adapter_generation = adapter_generation,
		table_id = snapshot.table_id,
		snapshot_digest = snapshot.digest,
		terminal = terminal,
		output = output,
		width = width,
		height = height,
		point_count = u32(len(snapshot.points)),
		input_bytes = input_bytes,
		limits = limits,
	}, true, {}
}

/* plot_output_is_valid checks one copied output resource identity. */
plot_output_is_valid :: proc(output: Plot_Output) -> bool {
	key := output.key
	return output.provider != 0 && output.length > 0 &&
	       int(output.length) <= len(key) && utf8.valid_string(string(key[:output.length]))
}

@(private)
plot_text_is_valid :: proc(value: string) -> bool {
	return len(value) > 0 && len(value) <= MAX_PLOT_LABEL_BYTES && utf8.valid_string(value)
}

@(private)
plot_failure :: proc(code: Failure_Code, field: Failure_Field) -> Failure {
	return {kind = .Plot, code = code, field = field}
}
