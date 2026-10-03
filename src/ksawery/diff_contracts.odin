// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

/* MIN_DIFF_UNITS is the smallest configurable semantic diff-unit capacity. */
MIN_DIFF_UNITS :: u32(16)
/* MAX_DIFF_UNITS is the immutable semantic diff-unit capacity ceiling. */
MAX_DIFF_UNITS :: u32(4_096)
/* DEFAULT_DIFF_UNITS is the measured initial semantic diff-unit capacity. */
DEFAULT_DIFF_UNITS :: u32(512)
/* MIN_DIFF_LINE_BYTES is the smallest configurable complete diff-line budget. */
MIN_DIFF_LINE_BYTES :: u64(1 * KIBIBYTE)
/* MAX_DIFF_LINE_BYTES is the immutable complete diff-line ceiling. */
MAX_DIFF_LINE_BYTES :: u64(64 * KIBIBYTE)
/* DEFAULT_DIFF_LINE_BYTES is the measured initial complete diff-line budget. */
DEFAULT_DIFF_LINE_BYTES :: MAX_DIFF_LINE_BYTES
/* MIN_DIFF_PATCH_BYTES is the smallest configurable owned patch-material budget. */
MIN_DIFF_PATCH_BYTES :: u64(64 * KIBIBYTE)
/* MAX_DIFF_PATCH_BYTES is the immutable owned patch-material ceiling. */
MAX_DIFF_PATCH_BYTES :: u64(4 * MEBIBYTE)
/* DEFAULT_DIFF_PATCH_BYTES reuses the measured expanded-detail byte budget. */
DEFAULT_DIFF_PATCH_BYTES :: DEFAULT_DIFF_BYTES
/* MIN_DIFF_TEMPORARY_BYTES is the smallest parser temporary-allocation budget. */
MIN_DIFF_TEMPORARY_BYTES :: u64(512 * KIBIBYTE)
/* MAX_DIFF_TEMPORARY_BYTES is the immutable parser temporary-allocation ceiling. */
MAX_DIFF_TEMPORARY_BYTES :: u64(16 * MEBIBYTE)
/* DEFAULT_DIFF_TEMPORARY_BYTES is the measured initial parser temporary budget. */
DEFAULT_DIFF_TEMPORARY_BYTES :: u64(4 * MEBIBYTE)

/* Diff_Unit_ID identifies one semantic hunk inside one exact diff source. */
Diff_Unit_ID :: distinct u32

/* Diff_Source_ID identifies the complete bounded diff input used by semantic units. */
Diff_Source_ID :: distinct u64

/* Diff_Layer identifies the Git state comparison owned by one diff. */
Diff_Layer :: enum u8 {
	Invalid,
	Working_Tree,
	Index,
}

/* Diff_Line_Kind classifies one unified-diff body line. */
Diff_Line_Kind :: enum u8 {
	Invalid,
	Context,
	Addition,
	Removal,
	No_Newline_Marker,
}

/* Diff_Text_Ref identifies bounded bytes owned by one semantic diff document. */
Diff_Text_Ref :: struct {
	offset: u32,
	length: u32,
}

/* Diff_Limits bounds semantic units and all parser-owned patch material. */
Diff_Limits :: struct {
	units:           u32,
	line_bytes:      u64,
	patch_bytes:     u64,
	temporary_bytes: u64,
}

/* DEFAULT_DIFF_LIMITS selects the measured initial semantic diff envelope. */
DEFAULT_DIFF_LIMITS :: Diff_Limits {
	units = DEFAULT_DIFF_UNITS,
	line_bytes = DEFAULT_DIFF_LINE_BYTES,
	patch_bytes = DEFAULT_DIFF_PATCH_BYTES,
	temporary_bytes = DEFAULT_DIFF_TEMPORARY_BYTES,
}

/* Diff_Unit_Target identifies one exact observation-bound semantic hunk. */
Diff_Unit_Target :: struct {
	path:   Path_Target,
	source: Diff_Source_ID,
	layer:  Diff_Layer,
	unit:   Diff_Unit_ID,
}

/* Diff_Unit_Descriptor copies one hunk identity, ranges, and owned-byte references. */
Diff_Unit_Descriptor :: struct {
	target:      Diff_Unit_Target,
	old_start:   u32,
	old_count:   u32,
	new_start:   u32,
	new_count:   u32,
	line_count:  u32,
	presentation: Diff_Text_Ref,
	patch:        Diff_Text_Ref,
}

/* Diff_Line_Descriptor copies one line identity inside a semantic diff unit. */
Diff_Line_Descriptor :: struct {
	unit:     Diff_Unit_Target,
	kind:     Diff_Line_Kind,
	ordinal:  u32,
	old_line: u32,
	new_line: u32,
	text:     Diff_Text_Ref,
}

/* Diff_Document_Descriptor reports one complete bounded semantic diff source. */
Diff_Document_Descriptor :: struct {
	path:               Path_Target,
	source:             Diff_Source_ID,
	layer:              Diff_Layer,
	unit_count:         u32,
	line_count:         u32,
	presentation_bytes: u64,
	patch_bytes:        u64,
}

/* Diff_Usage reports exact retained semantic diff resources. */
Diff_Usage :: struct {
	units:              u32,
	lines:              u32,
	presentation_bytes: u64,
	patch_bytes:        u64,
	allocation_bytes:   u64,
}

/* diff_limits_are_valid checks the complete semantic diff resource envelope. */
diff_limits_are_valid :: proc(limits: Diff_Limits) -> bool {
	return limits.units >= MIN_DIFF_UNITS && limits.units <= MAX_DIFF_UNITS &&
	       limits.line_bytes >= MIN_DIFF_LINE_BYTES && limits.line_bytes <= MAX_DIFF_LINE_BYTES &&
	       limits.patch_bytes >= MIN_DIFF_PATCH_BYTES && limits.patch_bytes <= MAX_DIFF_PATCH_BYTES &&
	       limits.temporary_bytes >= MIN_DIFF_TEMPORARY_BYTES &&
	       limits.temporary_bytes <= MAX_DIFF_TEMPORARY_BYTES &&
	       limits.line_bytes <= limits.patch_bytes && limits.patch_bytes <= limits.temporary_bytes
}

/* diff_layer_for_detail_kind maps one supported path detail to its Git layer. */
diff_layer_for_detail_kind :: proc(kind: Path_Detail_Kind) -> (Diff_Layer, bool) {
	switch kind {
	case .Unstaged: return .Working_Tree, true
	case .Staged:   return .Index, true
	case .Invalid, .Unmerged, .Untracked: return .Invalid, false
	}
	return .Invalid, false
}

/* diff_text_ref_is_valid checks one nonempty range against owned storage. */
diff_text_ref_is_valid :: proc(reference: Diff_Text_Ref, storage_bytes: u64) -> bool {
	if reference.length == 0 do return false
	end := u64(reference.offset) + u64(reference.length)
	return end >= u64(reference.offset) && end <= storage_bytes
}

/* diff_unit_target_is_valid checks one complete semantic hunk identity. */
diff_unit_target_is_valid :: proc(target: Diff_Unit_Target) -> bool {
	return path_target_is_valid(target.path) && target.source != Diff_Source_ID(0) &&
	       target.layer != .Invalid && target.unit != Diff_Unit_ID(0)
}

/* diff_unit_descriptor_is_valid checks one hunk against its owned storage bounds. */
diff_unit_descriptor_is_valid :: proc(
	descriptor: Diff_Unit_Descriptor,
	presentation_bytes: u64,
	patch_bytes: u64,
) -> bool {
	return diff_unit_target_is_valid(descriptor.target) && descriptor.line_count > 0 &&
	       diff_range_is_valid(descriptor.old_start, descriptor.old_count) &&
	       diff_range_is_valid(descriptor.new_start, descriptor.new_count) &&
	       diff_text_ref_is_valid(descriptor.presentation, presentation_bytes) &&
	       diff_text_ref_is_valid(descriptor.patch, patch_bytes)
}

/* diff_line_descriptor_is_valid checks line coordinates and copied text ownership. */
diff_line_descriptor_is_valid :: proc(
	descriptor: Diff_Line_Descriptor,
	presentation_bytes: u64,
) -> bool {
	if !diff_unit_target_is_valid(descriptor.unit) || descriptor.kind == .Invalid ||
	   !diff_text_ref_is_valid(descriptor.text, presentation_bytes) {
		return false
	}
	switch descriptor.kind {
	case .Context:
		return descriptor.old_line > 0 && descriptor.new_line > 0
	case .Addition:
		return descriptor.old_line == 0 && descriptor.new_line > 0
	case .Removal:
		return descriptor.old_line > 0 && descriptor.new_line == 0
	case .No_Newline_Marker:
		return descriptor.old_line == 0 && descriptor.new_line == 0
	case .Invalid:
		return false
	}
	return false
}

/* diff_document_descriptor_is_valid checks one complete bounded semantic diff shape. */
diff_document_descriptor_is_valid :: proc(
	descriptor: Diff_Document_Descriptor,
	limits := DEFAULT_DIFF_LIMITS,
) -> bool {
	return path_target_is_valid(descriptor.path) && descriptor.source != Diff_Source_ID(0) &&
	       descriptor.layer != .Invalid && descriptor.unit_count > 0 &&
	       descriptor.unit_count <= limits.units && descriptor.line_count > 0 &&
	       descriptor.presentation_bytes > 0 &&
	       descriptor.presentation_bytes <= limits.patch_bytes &&
	       descriptor.patch_bytes > 0 && descriptor.patch_bytes <= limits.patch_bytes &&
	       diff_limits_are_valid(limits)
}

@(private)
diff_range_is_valid :: proc(start, count: u32) -> bool {
	if count == 0 do return start == 0 || start > 0
	return start > 0 && start + count >= start
}
