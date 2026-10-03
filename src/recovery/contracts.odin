// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package recovery owns unsaved-work recovery contracts and resource policy.
package recovery

/* KIBIBYTE is the binary byte unit used by recovery policy. */
KIBIBYTE :: u64(1_024)
/* MEBIBYTE is 1,024 kibibytes. */
MEBIBYTE :: u64(1_024) * KIBIBYTE
/* GIBIBYTE is 1,024 mebibytes. */
GIBIBYTE :: u64(1_024) * MEBIBYTE

/* RECOVERY_FORMAT_VERSION identifies the first durable recovery schema. */
RECOVERY_FORMAT_VERSION :: u32(1)
/* PRIVATE_DIRECTORY_MODE is the required Unix recovery-directory mode. */
PRIVATE_DIRECTORY_MODE :: u32(0o700)
/* PRIVATE_FILE_MODE is the required Unix recovery-file mode. */
PRIVATE_FILE_MODE :: u32(0o600)

/* MIN_DEBOUNCE_MILLISECONDS is the shortest admitted quiet checkpoint delay. */
MIN_DEBOUNCE_MILLISECONDS :: u64(50)
/* MAX_DEBOUNCE_MILLISECONDS is the longest admitted quiet checkpoint delay. */
MAX_DEBOUNCE_MILLISECONDS :: u64(5_000)
/* DEFAULT_DEBOUNCE_MILLISECONDS is the factory quiet checkpoint delay. */
DEFAULT_DEBOUNCE_MILLISECONDS :: u64(300)
/* MIN_MAXIMUM_INTERVAL_MILLISECONDS is the shortest periodic durability bound. */
MIN_MAXIMUM_INTERVAL_MILLISECONDS :: u64(1_000)
/* MAX_MAXIMUM_INTERVAL_MILLISECONDS is the longest periodic durability bound. */
MAX_MAXIMUM_INTERVAL_MILLISECONDS :: u64(60_000)
/* DEFAULT_MAXIMUM_INTERVAL_MILLISECONDS is the factory periodic durability bound. */
DEFAULT_MAXIMUM_INTERVAL_MILLISECONDS :: u64(5_000)

/* MIN_RETENTION_SECONDS is the shortest admitted checkpoint retention age. */
MIN_RETENTION_SECONDS :: u64(3_600)
/* MAX_RETENTION_SECONDS is the longest admitted checkpoint retention age. */
MAX_RETENTION_SECONDS :: u64(30 * 24 * 3_600)
/* DEFAULT_RETENTION_SECONDS is the factory checkpoint retention age. */
DEFAULT_RETENTION_SECONDS :: u64(7 * 24 * 3_600)
/* MIN_RECORDS_PER_BUFFER is the smallest retained checkpoint history. */
MIN_RECORDS_PER_BUFFER :: u64(1)
/* MAX_RECORDS_PER_BUFFER is the largest retained checkpoint history. */
MAX_RECORDS_PER_BUFFER :: u64(64)
/* DEFAULT_RECORDS_PER_BUFFER is the factory retained checkpoint history. */
DEFAULT_RECORDS_PER_BUFFER :: u64(8)
/* MIN_TOTAL_RECORDS is the smallest complete-store record budget. */
MIN_TOTAL_RECORDS :: u64(16)
/* MAX_TOTAL_RECORDS is the largest complete-store record budget. */
MAX_TOTAL_RECORDS :: u64(16_384)
/* DEFAULT_TOTAL_RECORDS is the factory complete-store record budget. */
DEFAULT_TOTAL_RECORDS :: u64(512)

/* MIN_RECORD_PAYLOAD_BYTES is the smallest admitted checkpoint payload ceiling. */
MIN_RECORD_PAYLOAD_BYTES :: u64(64) * KIBIBYTE
/* MAX_RECORD_PAYLOAD_BYTES is the largest admitted checkpoint payload ceiling. */
MAX_RECORD_PAYLOAD_BYTES :: u64(1) * GIBIBYTE
/* DEFAULT_RECORD_PAYLOAD_BYTES is the factory checkpoint payload ceiling. */
DEFAULT_RECORD_PAYLOAD_BYTES :: u64(128) * MEBIBYTE
/* MIN_BUFFER_STORAGE_BYTES is the smallest per-buffer recovery budget. */
MIN_BUFFER_STORAGE_BYTES :: u64(1) * MEBIBYTE
/* MAX_BUFFER_STORAGE_BYTES is the largest per-buffer recovery budget. */
MAX_BUFFER_STORAGE_BYTES :: u64(4) * GIBIBYTE
/* DEFAULT_BUFFER_STORAGE_BYTES is the factory per-buffer recovery budget. */
DEFAULT_BUFFER_STORAGE_BYTES :: u64(512) * MEBIBYTE
/* MIN_STORE_STORAGE_BYTES is the smallest complete recovery-store budget. */
MIN_STORE_STORAGE_BYTES :: u64(64) * MEBIBYTE
/* MAX_STORE_STORAGE_BYTES is the largest complete recovery-store budget. */
MAX_STORE_STORAGE_BYTES :: u64(32) * GIBIBYTE
/* DEFAULT_STORE_STORAGE_BYTES is the factory complete recovery-store budget. */
DEFAULT_STORE_STORAGE_BYTES :: u64(2) * GIBIBYTE
/* MIN_CLEANUP_RECORDS is the smallest cleanup work budget per turn. */
MIN_CLEANUP_RECORDS :: u64(8)
/* MAX_CLEANUP_RECORDS is the largest cleanup work budget per turn. */
MAX_CLEANUP_RECORDS :: u64(4_096)
/* DEFAULT_CLEANUP_RECORDS is the factory cleanup work budget per turn. */
DEFAULT_CLEANUP_RECORDS :: u64(128)

/* Policy_Generation identifies one complete confirmed recovery policy. */
Policy_Generation :: distinct u64
/* Record_ID identifies one immutable checkpoint record. */
Record_ID :: distinct u64
/* Buffer_ID is a session-independent recovery identity for one buffer. */
Buffer_ID :: distinct u64
/* Digest is one copied SHA-256 identity or content fingerprint. */
Digest :: [32]u8

/* Strategy selects when a dirty buffer becomes eligible for checkpointing. */
Strategy :: enum u8 {
	Invalid,
	Transaction_Debounced,
	Interval,
	Hybrid,
}

/* Startup_Policy selects the safe startup presentation for admitted candidates. */
Startup_Policy :: enum u8 {
	Invalid,
	Ask,
	Inspect,
	Restore_Matching,
}

/* Source_Autosave_Policy remains independent from auxiliary recovery storage. */
Source_Autosave_Policy :: enum u8 {
	Invalid,
	Disabled,
	After_Checkpoint,
}

/* Platform identifies the path and permission policy used by one recovery root. */
Platform :: enum u8 {
	Invalid,
	Linux,
	Darwin,
	Windows,
}

/* Encoding identifies the confirmed checkpoint text encoding. */
Encoding :: enum u8 {
	Invalid,
	UTF_8,
}

/* Line_Ending identifies the confirmed checkpoint line-ending policy. */
Line_Ending :: enum u8 {
	Invalid,
	LF,
	CRLF,
}

/* Candidate_State classifies one startup recovery observation. */
Candidate_State :: enum u8 {
	Invalid,
	Restorable,
	Conflict,
	Pathless,
	Missing_Source,
	Inaccessible,
	Quarantined,
}

/* Candidate_Action lists the explicit operations available for one candidate. */
Candidate_Action :: enum u8 {
	Invalid,
	Restore,
	Inspect,
	Compare,
	Discard,
}

/* Conflict_Reason explains why a source cannot be restored automatically. */
Conflict_Reason :: enum u8 {
	None,
	Source_Changed,
	Source_Identity_Changed,
	Saved_Revision_Ahead,
}

/* Quarantine_Reason classifies rejected recovery state without exposing payload content. */
Quarantine_Reason :: enum u8 {
	None,
	Malformed,
	Truncated,
	Excessive,
	Incompatible,
	Permission_Invalid,
	Digest_Mismatch,
}

/* Failure_Code identifies one recovery contract rejection. */
Failure_Code :: enum u8 {
	None,
	Invalid_Policy,
	Invalid_Root,
	Invalid_Record,
	Invalid_Candidate,
}

/* Policy_Field identifies the rejected resource-policy field. */
Policy_Field :: enum u8 {
	None,
	Debounce_Interval,
	Maximum_Interval,
	Retention_Age,
	Records_Per_Buffer,
	Total_Records,
	Record_Payload_Bytes,
	Buffer_Storage_Bytes,
	Store_Storage_Bytes,
	Cleanup_Records,
}

/* Failure_Context reports a bounded contract failure without private content. */
Failure_Context :: struct {
	code:    Failure_Code,
	field:   Policy_Field,
	minimum: u64,
	maximum: u64,
	actual:  u64,
}

/* Retention_Policy bounds checkpoint age and record counts. */
Retention_Policy :: struct {
	maximum_age_seconds: u64,
	records_per_buffer:  u64,
	total_records:       u64,
}

/* Storage_Policy bounds individual payload, buffer, store, and cleanup work. */
Storage_Policy :: struct {
	record_payload_bytes: u64,
	buffer_storage_bytes: u64,
	store_storage_bytes:  u64,
	cleanup_records:      u64,
}

/* Policy is one complete copied unsaved-work recovery configuration. */
Policy :: struct {
	enabled:                       bool,
	strategy:                      Strategy,
	debounce_milliseconds:         u64,
	maximum_interval_milliseconds: u64,
	retention:                     Retention_Policy,
	storage:                       Storage_Policy,
	startup:                       Startup_Policy,
	source_autosave:               Source_Autosave_Policy,
	generation:                    Policy_Generation,
}

/* DEFAULT_POLICY is the calibrated factory recovery policy. */
DEFAULT_POLICY :: Policy {
	enabled = true,
	strategy = .Hybrid,
	debounce_milliseconds = DEFAULT_DEBOUNCE_MILLISECONDS,
	maximum_interval_milliseconds = DEFAULT_MAXIMUM_INTERVAL_MILLISECONDS,
	retention = {
		maximum_age_seconds = DEFAULT_RETENTION_SECONDS,
		records_per_buffer = DEFAULT_RECORDS_PER_BUFFER,
		total_records = DEFAULT_TOTAL_RECORDS,
	},
	storage = {
		record_payload_bytes = DEFAULT_RECORD_PAYLOAD_BYTES,
		buffer_storage_bytes = DEFAULT_BUFFER_STORAGE_BYTES,
		store_storage_bytes = DEFAULT_STORE_STORAGE_BYTES,
		cleanup_records = DEFAULT_CLEANUP_RECORDS,
	},
	startup = .Ask,
	source_autosave = .Disabled,
	generation = Policy_Generation(1),
}

/* Root identifies the derived private recovery namespace under one platform state root. */
Root :: struct {
	platform:               Platform,
	state_root:             string,
	recovery_root:          string,
	private_directory_mode: u32,
	private_file_mode:      u32,
}

/* Record identifies one immutable recoverable buffer revision and its payload. */
Record :: struct {
	record_id:          Record_ID,
	buffer_id:          Buffer_ID,
	source_present:     bool,
	source_identity:    string,
	source_fingerprint: Digest,
	saved_revision:     u64,
	recovered_revision: u64,
	encoding:           Encoding,
	line_ending:        Line_Ending,
	payload_digest:     Digest,
	payload_bytes:      u64,
	created_at_seconds: u64,
	policy_generation:  Policy_Generation,
	format_version:     u32,
}

/* Candidate is one checked startup action surface derived from a recovery record. */
Candidate :: struct {
	record_id:         Record_ID,
	buffer_id:         Buffer_ID,
	state:             Candidate_State,
	conflict:          Conflict_Reason,
	quarantine:        Quarantine_Reason,
	actions:           [4]Candidate_Action,
	action_count:      u8,
	recovered_revision: u64,
}

/* Resource_Usage accounts one bounded recovery store without exposing payload data. */
Resource_Usage :: struct {
	records:              u64,
	buffers:              u64,
	payload_bytes:        u64,
	metadata_bytes:       u64,
	quarantined_records:  u64,
	pending_cleanup:      u64,
}

/* policy_validate checks one complete policy without publishing it. */
policy_validate :: proc(policy: Policy) -> (bool, Failure_Context) {
	if policy.generation == Policy_Generation(0) ||
	   policy.strategy == .Invalid || policy.startup == .Invalid ||
	   policy.source_autosave == .Invalid {
		return false, Failure_Context{code = .Invalid_Policy}
	}
	if ok, failure := range_validate(
		policy.debounce_milliseconds,
		MIN_DEBOUNCE_MILLISECONDS,
		MAX_DEBOUNCE_MILLISECONDS,
		.Debounce_Interval,
	); !ok {
		return false, failure
	}
	if ok, failure := range_validate(
		policy.maximum_interval_milliseconds,
		MIN_MAXIMUM_INTERVAL_MILLISECONDS,
		MAX_MAXIMUM_INTERVAL_MILLISECONDS,
		.Maximum_Interval,
	); !ok {
		return false, failure
	}
	if policy.debounce_milliseconds > policy.maximum_interval_milliseconds {
		return false, policy_failure(
			.Debounce_Interval,
			MIN_DEBOUNCE_MILLISECONDS,
			policy.maximum_interval_milliseconds,
			policy.debounce_milliseconds,
		)
	}
	checks := [?]struct {value, minimum, maximum: u64, field: Policy_Field} {
		{policy.retention.maximum_age_seconds, MIN_RETENTION_SECONDS, MAX_RETENTION_SECONDS, .Retention_Age},
		{policy.retention.records_per_buffer, MIN_RECORDS_PER_BUFFER, MAX_RECORDS_PER_BUFFER, .Records_Per_Buffer},
		{policy.retention.total_records, MIN_TOTAL_RECORDS, MAX_TOTAL_RECORDS, .Total_Records},
		{policy.storage.record_payload_bytes, MIN_RECORD_PAYLOAD_BYTES, MAX_RECORD_PAYLOAD_BYTES, .Record_Payload_Bytes},
		{policy.storage.buffer_storage_bytes, MIN_BUFFER_STORAGE_BYTES, MAX_BUFFER_STORAGE_BYTES, .Buffer_Storage_Bytes},
		{policy.storage.store_storage_bytes, MIN_STORE_STORAGE_BYTES, MAX_STORE_STORAGE_BYTES, .Store_Storage_Bytes},
		{policy.storage.cleanup_records, MIN_CLEANUP_RECORDS, MAX_CLEANUP_RECORDS, .Cleanup_Records},
	}
	for check in checks {
		if ok, failure := range_validate(check.value, check.minimum, check.maximum, check.field); !ok {
			return false, failure
		}
	}
	if policy.retention.records_per_buffer > policy.retention.total_records {
		return false, policy_failure(
			.Records_Per_Buffer,
			MIN_RECORDS_PER_BUFFER,
			policy.retention.total_records,
			policy.retention.records_per_buffer,
		)
	}
	if policy.storage.record_payload_bytes > policy.storage.buffer_storage_bytes {
		return false, policy_failure(
			.Record_Payload_Bytes,
			MIN_RECORD_PAYLOAD_BYTES,
			policy.storage.buffer_storage_bytes,
			policy.storage.record_payload_bytes,
		)
	}
	if policy.storage.buffer_storage_bytes > policy.storage.store_storage_bytes {
		return false, policy_failure(
			.Buffer_Storage_Bytes,
			MIN_BUFFER_STORAGE_BYTES,
			policy.storage.store_storage_bytes,
			policy.storage.buffer_storage_bytes,
		)
	}
	return true, {}
}

/* root_validate checks one derived recovery namespace before persistence admission. */
root_validate :: proc(root: Root) -> (bool, Failure_Context) {
	if root.platform == .Invalid || len(root.state_root) == 0 || len(root.recovery_root) == 0 ||
	   root.state_root == root.recovery_root {
		return false, Failure_Context{code = .Invalid_Root}
	}
	if root.platform == .Windows {
		if root.private_directory_mode != 0 || root.private_file_mode != 0 {
			return false, Failure_Context{code = .Invalid_Root}
		}
	} else if root.private_directory_mode != PRIVATE_DIRECTORY_MODE ||
	          root.private_file_mode != PRIVATE_FILE_MODE {
		return false, Failure_Context{code = .Invalid_Root}
	}
	return true, {}
}

/* record_validate checks metadata and resource bounds before payload publication. */
record_validate :: proc(record: Record, policy: Policy) -> (bool, Failure_Context) {
	if valid_policy, failure := policy_validate(policy); !valid_policy {
		return false, failure
	}
	if record.record_id == Record_ID(0) || record.buffer_id == Buffer_ID(0) ||
	   record.recovered_revision <= record.saved_revision ||
	   record.encoding == .Invalid || record.line_ending == .Invalid ||
	   record.payload_bytes > policy.storage.record_payload_bytes ||
	   record.created_at_seconds == 0 || record.policy_generation != policy.generation ||
	   record.format_version != RECOVERY_FORMAT_VERSION || !digest_present(record.payload_digest) {
		return false, Failure_Context{code = .Invalid_Record}
	}
	if record.source_present {
		if len(record.source_identity) == 0 || !digest_present(record.source_fingerprint) {
			return false, Failure_Context{code = .Invalid_Record}
		}
	} else if len(record.source_identity) != 0 || digest_present(record.source_fingerprint) {
		return false, Failure_Context{code = .Invalid_Record}
	}
	return true, {}
}

/* candidate_validate checks state-specific reasons and explicit action availability. */
candidate_validate :: proc(candidate: Candidate) -> (bool, Failure_Context) {
	if candidate.record_id == Record_ID(0) || candidate.buffer_id == Buffer_ID(0) ||
	   candidate.state == .Invalid || candidate.recovered_revision == 0 ||
	   candidate.action_count == 0 || int(candidate.action_count) > len(candidate.actions) {
		return false, Failure_Context{code = .Invalid_Candidate}
	}
	if candidate.state == .Conflict {
		if candidate.conflict == .None || candidate.quarantine != .None {
			return false, Failure_Context{code = .Invalid_Candidate}
		}
	} else if candidate.state == .Quarantined {
		if candidate.quarantine == .None || candidate.conflict != .None {
			return false, Failure_Context{code = .Invalid_Candidate}
		}
	} else if candidate.conflict != .None || candidate.quarantine != .None {
		return false, Failure_Context{code = .Invalid_Candidate}
	}
	seen: [5]bool
	for index in 0 ..< int(candidate.action_count) {
		action := candidate.actions[index]
		if action == .Invalid || seen[int(action)] {
			return false, Failure_Context{code = .Invalid_Candidate}
		}
		seen[int(action)] = true
	}
	if !seen[int(Candidate_Action.Inspect)] || !seen[int(Candidate_Action.Discard)] {
		return false, Failure_Context{code = .Invalid_Candidate}
	}
	if candidate.state == .Conflict && !seen[int(Candidate_Action.Compare)] {
		return false, Failure_Context{code = .Invalid_Candidate}
	}
	if candidate.state == .Quarantined && seen[int(Candidate_Action.Restore)] {
		return false, Failure_Context{code = .Invalid_Candidate}
	}
	return true, {}
}

@(private)
range_validate :: proc(
	value, minimum, maximum: u64,
	field: Policy_Field,
) -> (bool, Failure_Context) {
	if value < minimum || value > maximum {
		return false, policy_failure(field, minimum, maximum, value)
	}
	return true, {}
}

@(private)
policy_failure :: proc(field: Policy_Field, minimum, maximum, actual: u64) -> Failure_Context {
	return Failure_Context {
		code = .Invalid_Policy,
		field = field,
		minimum = minimum,
		maximum = maximum,
		actual = actual,
	}
}

@(private)
digest_present :: proc(digest: Digest) -> bool {
	for value in digest {
		if value != 0 {
			return true
		}
	}
	return false
}
