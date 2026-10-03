// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language

/* JAN_CAPABILITY_COUNT is the complete published Jan capability inventory. */
JAN_CAPABILITY_COUNT :: 19
/* JAN_FUTURE_CAPABILITY_COUNT is the compatibility width of the post-planning inventory. */
JAN_FUTURE_CAPABILITY_COUNT :: 8

/* jan_capability_availability returns the final linked Jan capability inventory. */
jan_capability_availability :: proc() -> [JAN_CAPABILITY_COUNT]Jan_Availability_Record {
	return {
		jan_factory_native_record("jan-visibility"),
		jan_factory_native_record("jan-structural-editing"),
		jan_factory_native_record("jan-list-editing"),
		jan_factory_native_record("jan-table-editing"),
		jan_factory_native_record("jan-contextual-editing"),
		jan_planning_record("jan-task-planning"),
		jan_planning_record("jan-tag-resolution"),
		jan_planning_record("jan-property-operations"),
		jan_planning_record("jan-time-and-agenda"),
		jan_planning_record("jan-refile-and-archive"),
		jan_planning_record("jan-capture-and-feeds"),
		jan_final_record("jan-computable-tables", .Factory_Native, .Computable_Documents, true),
		jan_final_record("jan-source-execution", .Factory_Adapter, .Computable_Documents, false),
		jan_final_record("jan-link-following", .Configured_Provider, .Export_Publishing_And_Integration, false),
		jan_final_record("jan-export", .Factory_Native, .Export_Publishing_And_Integration, true),
		jan_final_record("jan-publishing", .Configured_Provider, .Export_Publishing_And_Integration, false),
		jan_final_record("jan-citations", .Factory_Adapter, .Export_Publishing_And_Integration, false),
		jan_final_record("jan-external-resources", .Configured_Provider, .Export_Publishing_And_Integration, false),
		jan_final_record("jan-extension-contributions", .Configured_Provider, .Export_Publishing_And_Integration, false),
	}
}

/* jan_future_stage_availability retains the Stage 2 API while returning final later-domain state. */
jan_future_stage_availability :: proc() -> [JAN_FUTURE_CAPABILITY_COUNT]Jan_Availability_Record {
	all := jan_capability_availability()
	result: [JAN_FUTURE_CAPABILITY_COUNT]Jan_Availability_Record
	copy(result[:], all[11:])
	return result
}

@(private)
jan_planning_record :: proc(name: string) -> Jan_Availability_Record {
	capability: Jan_Capability_Name
	capability.length = u16(copy(
		capability.bytes[:],
		name[:min(len(name), MAX_JAN_CAPABILITY_NAME_BYTES)],
	))
	detail_text := "Available through the factory Planning and Agenda owner; optional providers remain isolated."
	detail: Jan_Availability_Detail
	detail.length = u16(copy(
		detail.bytes[:],
		detail_text[:min(len(detail_text), MAX_JAN_AVAILABILITY_DETAIL_BYTES)],
	))
	return {
		capability = capability,
		class = .Factory_Native,
		owner = .Planning_And_Agenda,
		available = true,
		detail = detail,
	}
}

@(private)
jan_factory_native_record :: proc(name: string) -> Jan_Availability_Record {
	capability: Jan_Capability_Name
	capability.length = u16(copy(
		capability.bytes[:],
		name[:min(len(name), MAX_JAN_CAPABILITY_NAME_BYTES)],
	))
	detail_text := "Available through the factory-native Jan structured editing owner."
	detail: Jan_Availability_Detail
	detail.length = u16(copy(
		detail.bytes[:],
		detail_text[:min(len(detail_text), MAX_JAN_AVAILABILITY_DETAIL_BYTES)],
	))
	return {
		capability = capability,
		class = .Factory_Native,
		owner = .Structured_Editing,
		available = true,
		detail = detail,
	}
}

@(private)
jan_final_record :: proc(
	name: string,
	class: Jan_Availability_Class,
	owner: Jan_Stage,
	available: bool,
) -> Jan_Availability_Record {
	capability: Jan_Capability_Name
	capability.length = u16(copy(
		capability.bytes[:],
		name[:min(len(name), MAX_JAN_CAPABILITY_NAME_BYTES)],
	))
	detail_text := "Available through the linked factory owner."
	if !available {
		detail_text = "Linked and source-preserving; the optional adapter or configured provider is unavailable."
	}
	detail: Jan_Availability_Detail
	detail.length = u16(copy(
		detail.bytes[:],
		detail_text[:min(len(detail_text), MAX_JAN_AVAILABILITY_DETAIL_BYTES)],
	))
	return {
		capability = capability,
		class = class,
		owner = owner,
		available = available,
		detail = detail,
	}
}
