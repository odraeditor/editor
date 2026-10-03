// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package feedback

import "core:fmt"

/* Headless_Observer bounds progress observation independently from UI routing. */
Headless_Observer :: struct {
	progress_stride:    u32,
	seen_updates:       u64,
	emitted_updates:    u64,
	suppressed_updates: u64,
	last_record:        Record_ID,
	last_generation:    Record_Generation,
}

/* Headless_Observation borrows one formatted caller-owned result. */
Headless_Observation :: struct {
	record_id:  Record_ID,
	generation: Record_Generation,
	severity:   Severity,
	attention:  Attention,
	terminal:   bool,
	content:    string,
}

/* headless_observer_init creates one bounded progress coalescer. */
headless_observer_init :: proc(observer: ^Headless_Observer, progress_stride := DEFAULT_HEADLESS_PROGRESS_STRIDE) -> bool {
	if observer == nil || progress_stride == 0 do return false
	observer^ = {progress_stride = progress_stride}
	return true
}

/* headless_observe formats eligible feedback without claiming operation authority. */
headless_observe :: proc(
	observer: ^Headless_Observer,
	record: Record,
	storage: []u8,
	include_sensitive := false,
) -> (Headless_Observation, bool, Failure) {
	if observer == nil || observer.progress_stride == 0 || len(storage) == 0 || len(storage) > MAX_HEADLESS_BYTES {
		return {}, false, Failure{operation = .Observe, code = .Inspection_Limit, limit = MAX_HEADLESS_BYTES, actual = u64(len(storage))}
	}
	observer.seen_updates += 1
	terminal := record_is_terminal(record)
	important := record.attention == .Required || record.severity == .Error || terminal
	emit := important || record.kind == .Notification || record.id != observer.last_record ||
		u64(record.generation) % u64(observer.progress_stride) == 0
	observer.last_record = record.id
	observer.last_generation = record.generation
	if !emit {
		observer.suppressed_updates += 1
		return {}, false, {}
	}
	title := record.title
	message := record.message
	if record.sensitivity == .Sensitive && !include_sensitive {
		title = "<redacted>"
		message = "<redacted>"
	}
	content := fmt.bprintf(storage, "%v: %s", record.severity, title)
	if len(message) > 0 do content = fmt.bprintf(storage, "%v: %s - %s", record.severity, title, message)
	observer.emitted_updates += 1
	return Headless_Observation {
		record_id = record.id,
		generation = record.generation,
		severity = record.severity,
		attention = record.attention,
		terminal = terminal,
		content = content,
	}, true, {}
}
