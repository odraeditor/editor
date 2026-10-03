// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package darek_module

import "../darek"
import "../filesystem"
import "../product_module"

/* PRESENTATION_PROVIDER_SCHEMA_VERSION identifies copied Darek presentation updates. */
PRESENTATION_PROVIDER_SCHEMA_VERSION :: u32(1)
/* PRESENTATION_ANNOTATION_IGNORED marks one resource as ignored by its VCS provider. */
PRESENTATION_ANNOTATION_IGNORED :: u16(1 << 0)

/* Presentation_Update_Kind selects one complete annotation generation or watcher hint. */
Presentation_Update_Kind :: enum u32 {
	Invalid,
	Annotations,
	Annotations_Unavailable,
	Watch_Activity,
	Watch_Loss,
	Watch_Overflow,
	Watch_Restart,
}

/* Presentation_Update_Header prefixes one bounded copied provider publication. */
Presentation_Update_Header :: struct #align(8) {
	schema_version:      u32,
	kind:                Presentation_Update_Kind,
	provider_generation: u64,
	record_count:        u32,
	_reserved:           u32,
}

/* Presentation_Annotation copies presentation-only state for one resource. */
Presentation_Annotation :: struct #align(8) {
	resource:        product_module.Filesystem_Resource,
	version_control: u8,
	diagnostic:      u8,
	flags:           u16,
	_reserved:       u32,
}

@(private)
module_configure_presentation :: proc(
	state: ^Module_Instance,
	input: []u8,
) -> product_module.Status {
	if state == nil || !state.active || len(input) < size_of(Presentation_Update_Header) {
		return .Unavailable if state != nil && !state.active else .Invalid_Argument
	}
	header := (^Presentation_Update_Header)(raw_data(input))
	if header.schema_version != PRESENTATION_PROVIDER_SCHEMA_VERSION ||
	   header.kind == .Invalid || header.provider_generation == 0 || header._reserved != 0 {
		return .Invalid_Argument
	}
	record_bytes := u64(header.record_count) * u64(size_of(Presentation_Annotation))
	if record_bytes != u64(len(input) - size_of(Presentation_Update_Header)) {
		return .Invalid_Argument
	}
	generation := darek.Provider_Generation(header.provider_generation)
	changed := false
	switch header.kind {
	case .Annotations, .Annotations_Unavailable:
		if header.kind == .Annotations_Unavailable && header.record_count != 0 {
			return .Invalid_Argument
		}
		annotations, allocation_error := make(
			[]darek.Node_Annotation, int(header.record_count), state.temporary_allocator,
		)
		if allocation_error != nil do return .Failed
		defer delete(annotations, state.temporary_allocator)
		for index in 0 ..< int(header.record_count) {
			offset := size_of(Presentation_Update_Header) + index * size_of(Presentation_Annotation)
			record := (^Presentation_Annotation)(raw_data(input[offset:]))
			if record.version_control > u8(darek.Version_Control_State.Conflicted) ||
			   record.diagnostic > u8(darek.Diagnostic_State.Error) ||
			   record.flags & ~PRESENTATION_ANNOTATION_IGNORED != 0 || record._reserved != 0 {
				return .Invalid_Argument
			}
			resource := filesystem.Resource_ID {
				provider = record.resource.provider,
				device = record.resource.device,
				inode = record.resource.inode,
			}
			if !filesystem.resource_id_valid(resource) do return .Invalid_Argument
			annotations[index] = {
				resource = resource,
				provider_generation = generation,
				version_control = darek.Version_Control_State(record.version_control),
				diagnostic = darek.Diagnostic_State(record.diagnostic),
				ignored = record.flags & PRESENTATION_ANNOTATION_IGNORED != 0,
			}
		}
		ok := false
		failure: darek.Failure_Context
		changed, ok, failure = darek.instance_publish_annotations(
			&state.instance, generation, annotations,
		)
		_ = failure
		if !ok do return .Stale
	case .Watch_Restart:
		if header.record_count != 0 do return .Invalid_Argument
		ok := false
		changed, ok, _ = darek.instance_set_watch_enabled(&state.instance, true, generation)
		if !ok do return .Stale
	case .Watch_Activity, .Watch_Loss, .Watch_Overflow:
		if header.record_count != 0 do return .Invalid_Argument
		hint := darek.Watch_Hint.Activity
		if header.kind == .Watch_Loss do hint = .Loss
		if header.kind == .Watch_Overflow do hint = .Overflow
		ok := false
		changed, ok, _ = darek.instance_observe_watch_hint(&state.instance, generation, hint)
		if !ok do return .Stale
	case .Invalid:
		return .Invalid_Argument
	}
	if changed do return module_publish(state)
	return .Ok
}
