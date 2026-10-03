// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

import "core:fmt"

/* MAX_CANDIDATE_PROMPT_LABEL_BYTES bounds source, scope, and count presentation. */
MAX_CANDIDATE_PROMPT_LABEL_BYTES :: 128

/* candidate_prompt_label formats source, scope, and selected/total counts. */
candidate_prompt_label :: proc(view: Candidate_View, output: []u8) -> (string, bool) {
	if !candidate_projection_view_is_valid(view) || len(output) < MAX_CANDIDATE_PROMPT_LABEL_BYTES {
		return "", false
	}
	selected := u32(0)
	if view.has_selection do selected = view.selected_row + 1
	switch view.source_kind {
	case .Commands:
		label := fmt.bprintf(
			output,
			"Commands [active editor context] %d/%d M-x ",
			selected,
			len(view.rows),
		)
		return label, len(label) > 0
	case .Session_Buffers:
		label := fmt.bprintf(
			output,
			"Buffers [session] %d/%d Switch to buffer: ",
			selected,
			len(view.rows),
		)
		return label, len(label) > 0
	case .Project_Buffers:
		label := fmt.bprintf(
			output,
			"Buffers [active Project] %d/%d Project switch buffer: ",
			selected,
			len(view.rows),
		)
		return label, len(label) > 0
	case .Project_Files:
		label := fmt.bprintf(
			output,
			"Files [active Project] %d/%d Project find file: ",
			selected,
			len(view.rows),
		)
		return label, len(label) > 0
	case .Dir_Files:
		label := fmt.bprintf(
			output,
			"Files [active Dir] %d/%d Find file: ",
			selected,
			len(view.rows),
		)
		return label, len(label) > 0
	case .Themes:
		label := fmt.bprintf(
			output,
			"Themes [session] %d/%d Select theme: ",
			selected,
			len(view.rows),
		)
		return label, len(label) > 0
	case .Interaction_Profiles:
		label := fmt.bprintf(
			output,
			"Profiles [session] %d/%d Select interaction profile: ",
			selected,
			len(view.rows),
		)
		return label, len(label) > 0
	case .Projects:
		label := fmt.bprintf(
			output,
			"Projects [global] %d/%d Open Project: ",
			selected,
			len(view.rows),
		)
		return label, len(label) > 0
	case .Workspaces:
		label := fmt.bprintf(
			output,
			"Workspaces [global] %d/%d Open Workspace: ",
			selected,
			len(view.rows),
		)
		return label, len(label) > 0
	case .Named_Locations:
		label := fmt.bprintf(
			output,
			"Locations [global] %d/%d Visit location: ",
			selected,
			len(view.rows),
		)
		return label, len(label) > 0
	case .Named_Slots:
		label := fmt.bprintf(
			output,
			"Slots [global] %d/%d Select stored value: ",
			selected,
			len(view.rows),
		)
		return label, len(label) > 0
	case .Language_Diagnostics:
		label := fmt.bprintf(output, "Diagnostics [current scope] %d/%d Diagnostic: ",
			selected, len(view.rows))
		return label, len(label) > 0
	case .Results:
		label := fmt.bprintf(output, "Results [current set] %d/%d Result: ",
			selected, len(view.rows))
		return label, len(label) > 0
	case .Status_Segments:
		label := fmt.bprintf(output, "Status Bar [active pane] %d/%d Segment: ",
			selected, len(view.rows))
		return label, len(label) > 0
	case .Package_Catalogs:
		label := fmt.bprintf(output, "Package catalogs [configured] %d/%d Select: ",
			selected, len(view.rows))
		return label, len(label) > 0
	case .Packages:
		label := fmt.bprintf(output, "Packages %d/%d Search: ", selected, len(view.rows))
		return label, len(label) > 0
	case .Package_Catalog_Diagnostics:
		label := fmt.bprintf(output, "Package catalog doctor %d/%d: ",
			selected, len(view.rows))
		return label, len(label) > 0
	case .Personal_Command_Results:
		label := fmt.bprintf(output, "Candidates %d/%d Select: ", selected, len(view.rows))
		return label, len(label) > 0
	case .Filesystem_Entries:
		label := fmt.bprintf(output, "Paths [local filesystem] %d/%d Open path: ",
			selected, len(view.rows))
		return label, len(label) > 0
	case .Invalid, .Test:
		return "", false
	}
	return "", false
}

/* candidate_row_text_size returns the exact shared-list text size for one semantic row. */
candidate_row_text_size :: proc(
	source: Candidate_Source_Kind,
	row: Candidate_Row,
) -> (size: int, ok: bool) {
	if len(row.label) == 0 {
		return 0, false
	}
	switch source {
	case .Commands:
		binding, provider, availability, description, valid :=
			candidate_command_annotations(row)
		_ = provider
		_ = availability
		if !valid do return 0, false
		size = len(row.label) + len("    ") + len(description)
		if len(binding) > 0 do size += len("[") + len(binding) + len("]")
		return size, true
	case .Session_Buffers, .Project_Buffers:
		path, modified, backing, valid := candidate_buffer_annotations(row)
		if !valid do return 0, false
		return len(row.label) + len("  [") + len(path) + len("]  [") +
			len(modified) + len("]  ") + len(backing), true
	case .Project_Files, .Dir_Files, .Projects, .Workspaces, .Named_Locations:
		member, valid := candidate_project_file_annotation(row)
		if !valid do return 0, false
		size = len(row.label)
		if len(member) > 0 do size += len("  [") + len(member) + len("]")
		return size, true
	case .Named_Slots:
		preview, has_preview, valid := candidate_named_slot_preview(row)
		if !valid do return 0, false
		size = len(row.label)
		if has_preview do size += len("    ") + len(preview)
		return size, true
	case .Themes:
		identity, provider, selection, valid := candidate_theme_annotations(row)
		if !valid do return 0, false
		return len(row.label) + len("  [") + len(identity) + len("]  [") +
			len(provider) + len("]  ") + len(selection), true
	case .Interaction_Profiles:
		state := candidate_generic_annotation(row)
		size = len(row.label)
		if len(state) > 0 do size += len("  [") + len(state) + len("]")
		return size, true
	case .Language_Diagnostics:
		severity, location, valid := candidate_diagnostic_annotations(row)
		if !valid do return 0, false
		return len(row.label) + len("  [") + len(severity) + len("]  ") + len(location), true
	case .Results:
		path, location := candidate_result_annotations(row)
		size = len(row.label)
		if len(path) > 0 do size += len(path) + len("  ")
		if len(location) > 0 do size += len(location) + len("   ")
		return size, true
	case .Status_Segments, .Package_Catalogs, .Packages, .Package_Catalog_Diagnostics:
		detail := candidate_generic_annotation(row)
		size = len(row.label)
		if len(detail) > 0 do size += len("   ") + len(detail)
		return size, true
	case .Filesystem_Entries, .Personal_Command_Results:
		return len(row.label), true
	case .Invalid, .Test:
		return 0, false
	}
	return 0, false
}

/* candidate_row_text_write formats one validated semantic row into exact caller storage. */
candidate_row_text_write :: proc(
	source: Candidate_Source_Kind,
	row: Candidate_Row,
	output: []u8,
) -> (text: string, ok: bool) {
	size, valid := candidate_row_text_size(source, row)
	if !valid || len(output) < size {
		return "", false
	}
	offset := 0
	switch source {
	case .Commands:
		binding, provider, availability, description, _ := candidate_command_annotations(row)
		_ = provider
		_ = availability
		offset = candidate_text_append(output, offset, row.label)
		offset = candidate_text_append(output, offset, "  ")
		if len(binding) > 0 {
			offset = candidate_text_append(output, offset, "[")
			offset = candidate_text_append(output, offset, binding)
			offset = candidate_text_append(output, offset, "]")
		}
		offset = candidate_text_append(output, offset, "  ")
		offset = candidate_text_append(output, offset, description)
	case .Session_Buffers, .Project_Buffers:
		path, modified, backing, _ := candidate_buffer_annotations(row)
		offset = candidate_text_append(output, offset, row.label)
		offset = candidate_text_append(output, offset, "  [")
		offset = candidate_text_append(output, offset, path)
		offset = candidate_text_append(output, offset, "]  [")
		offset = candidate_text_append(output, offset, modified)
		offset = candidate_text_append(output, offset, "]  ")
		offset = candidate_text_append(output, offset, backing)
	case .Project_Files, .Dir_Files, .Projects, .Workspaces, .Named_Locations:
		member, _ := candidate_project_file_annotation(row)
		offset = candidate_text_append(output, offset, row.label)
		if len(member) > 0 {
			offset = candidate_text_append(output, offset, "  [")
			offset = candidate_text_append(output, offset, member)
			offset = candidate_text_append(output, offset, "]")
		}
	case .Named_Slots:
		preview, has_preview, _ := candidate_named_slot_preview(row)
		offset = candidate_text_append(output, offset, row.label)
		if has_preview {
			offset = candidate_text_append(output, offset, "    ")
			offset = candidate_text_append(output, offset, preview)
		}
	case .Themes:
		identity, provider, selection, _ := candidate_theme_annotations(row)
		offset = candidate_text_append(output, offset, row.label)
		offset = candidate_text_append(output, offset, "  [")
		offset = candidate_text_append(output, offset, identity)
		offset = candidate_text_append(output, offset, "]  [")
		offset = candidate_text_append(output, offset, provider)
		offset = candidate_text_append(output, offset, "]  ")
		offset = candidate_text_append(output, offset, selection)
	case .Interaction_Profiles:
		state := candidate_generic_annotation(row)
		offset = candidate_text_append(output, offset, row.label)
		if len(state) > 0 {
			offset = candidate_text_append(output, offset, "  [")
			offset = candidate_text_append(output, offset, state)
			offset = candidate_text_append(output, offset, "]")
		}
	case .Language_Diagnostics:
		severity, location, _ := candidate_diagnostic_annotations(row)
		offset = candidate_text_append(output, offset, row.label)
		offset = candidate_text_append(output, offset, "  [")
		offset = candidate_text_append(output, offset, severity)
		offset = candidate_text_append(output, offset, "]  ")
		offset = candidate_text_append(output, offset, location)
	case .Results:
		path, location := candidate_result_annotations(row)
		if len(path) > 0 {
			offset = candidate_text_append(output, offset, path)
			offset = candidate_text_append(output, offset, "  ")
		}
		if len(location) > 0 {
			offset = candidate_text_append(output, offset, location)
			offset = candidate_text_append(output, offset, "   ")
		}
		offset = candidate_text_append(output, offset, row.label)
	case .Filesystem_Entries, .Personal_Command_Results:
		offset = candidate_text_append(output, offset, row.label)
	case .Status_Segments, .Package_Catalogs, .Packages, .Package_Catalog_Diagnostics:
		detail := candidate_generic_annotation(row)
		offset = candidate_text_append(output, offset, row.label)
		if len(detail) > 0 {
			offset = candidate_text_append(output, offset, "   ")
			offset = candidate_text_append(output, offset, detail)
		}
	case .Invalid, .Test:
		return "", false
	}
	assert(offset == size)
	return string(output[:offset]), true
}

@(private = "file")
candidate_generic_annotation :: proc(row: Candidate_Row) -> string {
	for annotation in row.annotations {
		if annotation.kind == .Generic do return annotation.text
	}
	return ""
}

@(private)
candidate_result_annotations :: proc(row: Candidate_Row) -> (path, location: string) {
	for annotation in row.annotations {
		#partial switch annotation.kind {
		case .Document_Path:
			path = annotation.text
		case .Location:
			location = annotation.text
		}
	}
	return
}

/* candidate_result_presentation returns the optional path and required source location columns. */
candidate_result_presentation :: proc(row: Candidate_Row) -> (
	path, location: string,
	ok: bool,
) {
	path, location = candidate_result_annotations(row)
	return path, location, len(location) > 0
}

@(private)
candidate_optional_location_annotation :: proc(row: Candidate_Row) -> string {
	for annotation in row.annotations do if annotation.kind == .Location do return annotation.text
	return ""
}

@(private)
candidate_theme_annotations :: proc(
	row: Candidate_Row,
) -> (identity, provider, selection: string, ok: bool) {
	identity_seen, provider_seen, selection_seen: bool
	for annotation in row.annotations {
		switch annotation.kind {
		case .Generic:
			if identity_seen do return "", "", "", false
			identity_seen = true
			identity = annotation.text
		case .Provider:
			if provider_seen do return "", "", "", false
			provider_seen = true
			provider = annotation.text
		case .Availability:
			if selection_seen do return "", "", "", false
			selection_seen = true
			selection = annotation.text
		case .Invalid, .Binding, .Description, .Document_Path, .Modified_State,
		     .Project_Member, .Severity, .Location, .Filesystem_Permissions,
		     .Filesystem_Size, .Filesystem_Modified:
			return "", "", "", false
		}
	}
	return identity, provider, selection, identity_seen && provider_seen && selection_seen
}

@(private)
candidate_named_slot_preview :: proc(row: Candidate_Row) -> (preview: string, present, valid: bool) {
	if len(row.annotations) == 0 do return "", false, true
	if len(row.annotations) != 1 || row.annotations[0].kind != .Description ||
	   len(row.annotations[0].text) == 0 {
		return "", false, false
	}
	return row.annotations[0].text, true, true
}

/* candidate_named_slot_presentation exposes one optional scoped value preview. */
candidate_named_slot_presentation :: proc(
	row: Candidate_Row,
) -> (preview: string, present, ok: bool) {
	return candidate_named_slot_preview(row)
}

@(private)
candidate_project_file_annotation :: proc(row: Candidate_Row) -> (member: string, ok: bool) {
	if len(row.annotations) == 0 {
		return "", true
	}
	if len(row.annotations) != 1 || row.annotations[0].kind != .Project_Member ||
	   len(row.annotations[0].text) == 0 {
		return "", false
	}
	return row.annotations[0].text, true
}

@(private)
candidate_buffer_annotations :: proc(
	row: Candidate_Row,
) -> (path, modified, backing: string, ok: bool) {
	path_seen, modified_seen, backing_seen: bool
	for annotation in row.annotations {
		switch annotation.kind {
		case .Document_Path:
			if path_seen do return "", "", "", false
			path_seen = true
			path = annotation.text
		case .Modified_State:
			if modified_seen do return "", "", "", false
			modified_seen = true
			modified = annotation.text
		case .Generic:
			if backing_seen do return "", "", "", false
			backing_seen = true
			backing = annotation.text
		case .Invalid, .Binding, .Provider, .Availability, .Description, .Project_Member,
		     .Severity, .Location, .Filesystem_Permissions, .Filesystem_Size,
		     .Filesystem_Modified:
			return "", "", "", false
		}
	}
	return path, modified, backing, path_seen && modified_seen && backing_seen
}

@(private)
candidate_command_annotations :: proc(
	row: Candidate_Row,
) -> (binding, provider, availability, description: string, ok: bool) {
	binding_seen, provider_seen, availability_seen, description_seen: bool
	for annotation in row.annotations {
		switch annotation.kind {
		case .Binding:
			if binding_seen do return "", "", "", "", false
			binding_seen = true
			binding = annotation.text
		case .Provider:
			if provider_seen do return "", "", "", "", false
			provider_seen = true
			provider = annotation.text
		case .Availability:
			if availability_seen do return "", "", "", "", false
			availability_seen = true
			availability = annotation.text
		case .Description:
			if description_seen do return "", "", "", "", false
			description_seen = true
			description = annotation.text
		case .Invalid, .Document_Path, .Modified_State, .Project_Member, .Generic,
		     .Severity, .Location, .Filesystem_Permissions, .Filesystem_Size,
		     .Filesystem_Modified:
			return "", "", "", "", false
		}
	}
	return binding, provider, availability, description,
		binding_seen && provider_seen && availability_seen && description_seen
}

/* candidate_command_presentation returns selectable columns without internal metadata. */
candidate_command_presentation :: proc(row: Candidate_Row) -> (
	binding, description: string,
	ok: bool,
) {
	binding, _, _, description, ok = candidate_command_annotations(row)
	return
}

@(private)
candidate_diagnostic_annotations :: proc(row: Candidate_Row) -> (severity, location: string, ok: bool) {
	severity_seen, location_seen: bool
	for annotation in row.annotations {
		switch annotation.kind {
		case .Severity:
			if severity_seen do return "", "", false
			severity_seen = true
			severity = annotation.text
		case .Location:
			if location_seen do return "", "", false
			location_seen = true
			location = annotation.text
		case .Invalid, .Binding, .Provider, .Availability, .Description, .Document_Path,
		     .Modified_State, .Project_Member, .Generic, .Filesystem_Permissions,
		     .Filesystem_Size, .Filesystem_Modified:
			return "", "", false
		}
	}
	return severity, location, severity_seen && location_seen
}

@(private)
candidate_text_append :: proc(output: []u8, offset: int, text: string) -> int {
	copy(output[offset:], transmute([]u8)text)
	return offset + len(text)
}

@(private)
candidate_projection_view_is_valid :: proc(view: Candidate_View) -> bool {
	valid_source := view.source_kind == .Commands || view.source_kind == .Session_Buffers ||
		view.source_kind == .Project_Buffers || view.source_kind == .Project_Files ||
		view.source_kind == .Dir_Files ||
		view.source_kind == .Themes || view.source_kind == .Interaction_Profiles ||
		view.source_kind == .Projects ||
		view.source_kind == .Workspaces ||
		view.source_kind == .Named_Locations ||
		view.source_kind == .Named_Slots ||
		view.source_kind == .Language_Diagnostics ||
		view.source_kind == .Results ||
		view.source_kind == .Status_Segments ||
	view.source_kind == .Package_Catalogs ||
	view.source_kind == .Packages ||
	view.source_kind == .Package_Catalog_Diagnostics ||
	view.source_kind == .Personal_Command_Results
	valid_source = valid_source || view.source_kind == .Filesystem_Entries
	return valid_source && view.session_id != Candidate_Session_ID(0) &&
		view.session_generation != Candidate_Session_Generation(0) &&
		view.scope_identity != 0 && view.scope_generation != 0 &&
		view.source_generation != 0 && !view.cancelled &&
		(view.has_selection && view.selected_row < u32(len(view.rows)) ||
		 !view.has_selection && len(view.rows) == 0)
}
