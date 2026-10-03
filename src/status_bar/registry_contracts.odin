// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package status_bar

/* MAX_PROGRAMMABLE_PROVIDERS bounds admitted package owners in one editor session. */
MAX_PROGRAMMABLE_PROVIDERS :: 32
/* MAX_PROGRAMMABLE_SEGMENTS_PER_PROVIDER bounds one complete package generation. */
MAX_PROGRAMMABLE_SEGMENTS_PER_PROVIDER :: 16
/* FACTORY_SEGMENT_COUNT reserves the identities currently owned by the built-in factory. */
FACTORY_SEGMENT_COUNT :: 12
/* MAX_PROGRAMMABLE_SEGMENTS keeps factory and package segments within MAX_SEGMENTS. */
MAX_PROGRAMMABLE_SEGMENTS :: MAX_SEGMENTS - FACTORY_SEGMENT_COUNT
/* MAX_PROGRAMMABLE_IDENTITY_BYTES bounds one stable machine-readable segment identity. */
MAX_PROGRAMMABLE_IDENTITY_BYTES :: 256
/* MAX_PROGRAMMABLE_PROVIDER_NAME_BYTES bounds one copied provider display name. */
MAX_PROGRAMMABLE_PROVIDER_NAME_BYTES :: MAX_CONTEXT_LABEL_BYTES
/* MAX_PROGRAMMABLE_PACKAGE_NAME_BYTES bounds one copied package identity. */
MAX_PROGRAMMABLE_PACKAGE_NAME_BYTES :: MAX_CONTEXT_LABEL_BYTES
/* MAX_PROGRAMMABLE_RETAINED_BYTES bounds aggregate logical registry content. */
MAX_PROGRAMMABLE_RETAINED_BYTES :: 8 * 1_024 * 1_024

/* Registry_ID identifies one Status Bar registry; zero is invalid. */
Registry_ID :: distinct u64
/* Registry_Generation identifies one exact registry state; zero is invalid. */
Registry_Generation :: distinct u64
/* Provider_ID identifies one package provider for a registry lifetime. */
Provider_ID :: distinct u64
/* Provider_Generation identifies one exact provider generation. */
Provider_Generation :: distinct u64
/* Segment_Generation identifies one exact programmable segment generation. */
Segment_Generation :: distinct u64

/* Provider_Handle is one checked pointer-free package owner identity. */
Provider_Handle :: struct {
	registry_id:         Registry_ID,
	provider_id:         Provider_ID,
	provider_generation: Provider_Generation,
}

/* Programmable_Segment_Handle identifies one exact copied segment generation. */
Programmable_Segment_Handle :: struct {
	provider:           Provider_Handle,
	segment_id:         Segment_ID,
	segment_generation: Segment_Generation,
}

/* Programmable_Segment_Proposal borrows one complete package definition during mutation. */
Programmable_Segment_Proposal :: struct {
	identity:          string,
	kind:              Segment_Kind,
	group:             Group,
	order:             u16,
	priority:          u16,
	full_text:         string,
	compact_text:      string,
	omittable:         bool,
	truncatable:       bool,
	style_role:        Semantic_Role,
	inspection_text:   string,
	primary_command:   Command_Reference,
	secondary_command: Command_Reference,
}

/* Provider_Proposal borrows one atomic package generation during validation. */
Provider_Proposal :: struct {
	provider_name: string,
	package_name:  string,
	segments:      []Programmable_Segment_Proposal,
}

/* Provider_Descriptor copies stable provider identity and accounting. */
Provider_Descriptor :: struct {
	handle:             Provider_Handle,
	registration_order: u64,
	segment_count:      u16,
	retained_bytes:     u64,
	provider_name:      [MAX_PROGRAMMABLE_PROVIDER_NAME_BYTES]u8,
	provider_name_bytes: u16,
	package_name:       [MAX_PROGRAMMABLE_PACKAGE_NAME_BYTES]u8,
	package_name_bytes:  u16,
}

/* Programmable_Segment_Descriptor copies one stable segment identity and ordering record. */
Programmable_Segment_Descriptor :: struct {
	handle:         Programmable_Segment_Handle,
	order:          u16,
	retained_bytes: u64,
	identity:       [MAX_PROGRAMMABLE_IDENTITY_BYTES]u8,
	identity_bytes: u16,
}

/* Programmable_Segment_View borrows immutable copied text until the next registry mutation. */
Programmable_Segment_View :: struct {
	descriptor: Programmable_Segment_Descriptor,
	definition: Segment_Definition,
}

/* Registry_Limits records the complete programmable-segment resource policy. */
Registry_Limits :: struct {
	providers:             u16,
	segments_per_provider: u16,
	total_segments:        u16,
	identity_bytes:        u16,
	provider_name_bytes:   u16,
	package_name_bytes:    u16,
	segment_text_bytes:    u32,
	retained_bytes:        u64,
}

/* DEFAULT_REGISTRY_LIMITS is the initial package contribution policy. */
DEFAULT_REGISTRY_LIMITS :: Registry_Limits {
	providers = MAX_PROGRAMMABLE_PROVIDERS,
	segments_per_provider = MAX_PROGRAMMABLE_SEGMENTS_PER_PROVIDER,
	total_segments = MAX_PROGRAMMABLE_SEGMENTS,
	identity_bytes = MAX_PROGRAMMABLE_IDENTITY_BYTES,
	provider_name_bytes = MAX_PROGRAMMABLE_PROVIDER_NAME_BYTES,
	package_name_bytes = MAX_PROGRAMMABLE_PACKAGE_NAME_BYTES,
	segment_text_bytes = MAX_SEGMENT_TEXT_BYTES,
	retained_bytes = MAX_PROGRAMMABLE_RETAINED_BYTES,
}

/* Registry_Usage reports exact logical occupancy and peak atomic preparation. */
Registry_Usage :: struct {
	providers:              u16,
	segments:               u16,
	retained_bytes:         u64,
	preparation_peak_bytes: u64,
}

/* Registry_Inspection copies exact lifecycle, occupancy, policy, and latest rejection. */
Registry_Inspection :: struct {
	registry_id:         Registry_ID,
	registry_generation: Registry_Generation,
	usage:               Registry_Usage,
	limits:              Registry_Limits,
	latest_failure:      Registry_Failure,
}

/* Registry_Operation identifies one programmable-segment lifecycle action. */
Registry_Operation :: enum u8 {
	None,
	Initialize,
	Inspect,
	Register,
	Replace,
	Remove,
	Teardown,
	Close,
}

/* Registry_Failure_Code classifies every expected registry rejection. */
Registry_Failure_Code :: enum u16 {
	None,
	Invalid_Registry,
	Closed_Registry,
	Wrong_Registry,
	Stale_Registry,
	Invalid_Provider,
	Stale_Provider,
	Duplicate_Provider,
	Provider_Limit,
	Invalid_Proposal,
	Invalid_Segment,
	Duplicate_Segment,
	Factory_Identity_Conflict,
	Segment_Limit,
	Text_Limit,
	Retained_Bytes_Limit,
	Generation_Limit,
	Allocation,
}

/* Registry_Failure reports one bounded rejection without retaining proposal data. */
Registry_Failure :: struct {
	operation: Registry_Operation,
	code:      Registry_Failure_Code,
	provider:  Provider_Handle,
	segment:   Programmable_Segment_Handle,
	limit:     u64,
	actual:    u64,
}

/* Registry is the non-copyable owner of one session package-segment registry. */
Registry :: struct {
	state:  rawptr,
	closed: bool,
}

/* registry_limits_are_valid checks every selected bound and aggregate relationship. */
registry_limits_are_valid :: proc(limits: Registry_Limits) -> bool {
	return limits.providers > 0 && limits.providers <= MAX_PROGRAMMABLE_PROVIDERS &&
		limits.segments_per_provider > 0 &&
		limits.segments_per_provider <= MAX_PROGRAMMABLE_SEGMENTS_PER_PROVIDER &&
		limits.total_segments > 0 && limits.total_segments <= MAX_PROGRAMMABLE_SEGMENTS &&
		limits.identity_bytes > 0 && limits.identity_bytes <= MAX_PROGRAMMABLE_IDENTITY_BYTES &&
		limits.provider_name_bytes > 0 &&
		limits.provider_name_bytes <= MAX_PROGRAMMABLE_PROVIDER_NAME_BYTES &&
		limits.package_name_bytes > 0 &&
		limits.package_name_bytes <= MAX_PROGRAMMABLE_PACKAGE_NAME_BYTES &&
		limits.segment_text_bytes > 0 && limits.segment_text_bytes <= MAX_SEGMENT_TEXT_BYTES &&
		limits.retained_bytes > 0 && limits.retained_bytes <= MAX_PROGRAMMABLE_RETAINED_BYTES
}

/* provider_descriptor_name borrows the copied provider display name. */
provider_descriptor_name :: proc(descriptor: ^Provider_Descriptor) -> string {
	if descriptor == nil || descriptor.provider_name_bytes > MAX_PROGRAMMABLE_PROVIDER_NAME_BYTES {
		return ""
	}
	return string(descriptor.provider_name[:descriptor.provider_name_bytes])
}

/* provider_descriptor_package borrows the copied package identity. */
provider_descriptor_package :: proc(descriptor: ^Provider_Descriptor) -> string {
	if descriptor == nil || descriptor.package_name_bytes > MAX_PROGRAMMABLE_PACKAGE_NAME_BYTES {
		return ""
	}
	return string(descriptor.package_name[:descriptor.package_name_bytes])
}

/* programmable_segment_identity borrows the copied stable segment identity. */
programmable_segment_identity :: proc(descriptor: ^Programmable_Segment_Descriptor) -> string {
	if descriptor == nil || descriptor.identity_bytes > MAX_PROGRAMMABLE_IDENTITY_BYTES {
		return ""
	}
	return string(descriptor.identity[:descriptor.identity_bytes])
}
