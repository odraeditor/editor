// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package bridge

import "../project"

/* CANDIDATE_HISTORY_SCHEMA_VERSION identifies the first durable usage record family. */
CANDIDATE_HISTORY_SCHEMA_VERSION :: u64(1)
/* MAX_CANDIDATE_HISTORY_ENTRIES bounds one copied load or publication request. */
MAX_CANDIDATE_HISTORY_ENTRIES :: u64(project.MAX_CANDIDATE_HISTORY_ENTRIES)
/* MAX_CANDIDATE_HISTORY_KEY_BYTES bounds aggregate copied candidate identities. */
MAX_CANDIDATE_HISTORY_KEY_BYTES :: u64(project.MAX_CANDIDATE_HISTORY_MODULE_BYTES)
/* MAX_CANDIDATE_HISTORY_DIAGNOSTIC_BYTES bounds one copied load diagnostic. */
MAX_CANDIDATE_HISTORY_DIAGNOSTIC_BYTES :: u64(4096)

/* CANDIDATE_HISTORY_LOAD_HEADER_BYTES precedes copied entries, keys, and diagnostic text. */
CANDIDATE_HISTORY_LOAD_HEADER_BYTES :: u64(64)
/* CANDIDATE_HISTORY_ENTRY_RECORD_BYTES is one pointer-free usage entry width. */
CANDIDATE_HISTORY_ENTRY_RECORD_BYTES :: u64(32)
/* CANDIDATE_HISTORY_PUBLISH_HEADER_BYTES precedes copied entries and keys. */
CANDIDATE_HISTORY_PUBLISH_HEADER_BYTES :: u64(48)
/* CANDIDATE_HISTORY_PUBLICATION_BYTES is one complete persistence outcome. */
CANDIDATE_HISTORY_PUBLICATION_BYTES :: u64(48)

/* Candidate_History_Observation identifies the bounded loader outcome. */
Candidate_History_Observation :: enum u64 {
	Absent = 1,
	Confirmed = 2,
	Rejected = 3,
	Unavailable = 4,
}

/* Candidate_History_Publication identifies the durable visibility outcome. */
Candidate_History_Publication :: enum u64 {
	Published_Durable = 1,
	Published_Recovered = 2,
	Published_Durability_Uncertain = 3,
}

/* Candidate_History_Load_Header_Record describes one complete copied observation. */
Candidate_History_Load_Header_Record :: struct {
	schema_version:   u64,
	observation:      Candidate_History_Observation,
	generation:       u64,
	next_sequence:    u64,
	entry_count:      u64,
	key_bytes:        u64,
	diagnostic_offset: u64,
	diagnostic_bytes: u64,
}

/* Candidate_History_Entry_Record identifies one copied category, key, and sequence. */
Candidate_History_Entry_Record :: struct {
	category:   u64,
	key_offset: u64,
	key_bytes:  u64,
	sequence:   u64,
}

/* Candidate_History_Publish_Header_Record describes one exact native snapshot. */
Candidate_History_Publish_Header_Record :: struct {
	schema_version:      u64,
	generation:          u64,
	next_sequence:       u64,
	entry_count:         u64,
	key_bytes:           u64,
	expected_generation: u64,
}

/* Candidate_History_Publication_Record confirms one visible persisted generation. */
Candidate_History_Publication_Record :: struct {
	schema_version:   u64,
	publication:      Candidate_History_Publication,
	generation:       u64,
	file_synced:      u64,
	directory_synced: u64,
	reserved:         u64,
}

/* candidate_history_load_record_bytes validates one copied observation width. */
candidate_history_load_record_bytes :: proc(
	entries, key_bytes, diagnostic_bytes: u64,
) -> (bytes: u64, ok: bool) {
	if entries > MAX_CANDIDATE_HISTORY_ENTRIES ||
	   key_bytes > MAX_CANDIDATE_HISTORY_KEY_BYTES ||
	   diagnostic_bytes > MAX_CANDIDATE_HISTORY_DIAGNOSTIC_BYTES {
		return 0, false
	}
	return CANDIDATE_HISTORY_LOAD_HEADER_BYTES +
	       entries * CANDIDATE_HISTORY_ENTRY_RECORD_BYTES +
	       key_bytes + diagnostic_bytes, true
}

/* candidate_history_publish_record_bytes validates one copied publication request width. */
candidate_history_publish_record_bytes :: proc(
	entries, key_bytes: u64,
) -> (bytes: u64, ok: bool) {
	if entries > MAX_CANDIDATE_HISTORY_ENTRIES ||
	   key_bytes > MAX_CANDIDATE_HISTORY_KEY_BYTES {
		return 0, false
	}
	return CANDIDATE_HISTORY_PUBLISH_HEADER_BYTES +
	       entries * CANDIDATE_HISTORY_ENTRY_RECORD_BYTES + key_bytes, true
}

/* candidate_history_record_layout_is_valid verifies every C and Racket ABI width. */
candidate_history_record_layout_is_valid :: proc() -> bool {
	return u64(size_of(Candidate_History_Load_Header_Record)) ==
	           CANDIDATE_HISTORY_LOAD_HEADER_BYTES &&
	       u64(size_of(Candidate_History_Entry_Record)) ==
	           CANDIDATE_HISTORY_ENTRY_RECORD_BYTES &&
	       u64(size_of(Candidate_History_Publish_Header_Record)) ==
	           CANDIDATE_HISTORY_PUBLISH_HEADER_BYTES &&
	       u64(size_of(Candidate_History_Publication_Record)) ==
	           CANDIDATE_HISTORY_PUBLICATION_BYTES
}
