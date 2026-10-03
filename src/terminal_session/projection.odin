// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package terminal_session

import "../interactive_session"
import "../terminal_emulator"

/* registry_resize coordinates PTY and emulator geometry with rollback. */
registry_resize :: proc(
	registry: ^Registry,
	ref: Session_Ref,
	columns, rows: u16,
	cell_width_pixels, cell_height_pixels: u32,
) -> (bool, Failure_Record) {
	state := registry_state(registry)
	if state == nil do return false, registry_access_failure(registry, .Resize)
	session, resolved := registry_resolve(state, ref)
	if !resolved do return false, failure_record(.Resize, .Stale_Reference)
	if !terminal_geometry_valid(columns, rows) {
		return false, failure_record(
			.Resize, .Projection_Limit, limit = MAX_PROJECTED_CELLS,
			actual = u64(columns) * u64(rows),
		)
	}
	resized, process_issue := interactive_session.registry_resize(
		&state.interactive,
		session.record.process.ref,
		columns,
		rows,
	)
	if !resized do return false, process_failure(.Resize, process_issue)
	if result := terminal_emulator.resize(
		session.record.emulator,
		columns,
		rows,
		cell_width_pixels,
		cell_height_pixels,
	); result != .OK {
		rolled_back, rollback_issue := interactive_session.registry_resize(
			&state.interactive,
			session.record.process.ref,
			session.columns,
			session.rows,
		)
		if !rolled_back {
			failure := process_failure(.Resize, rollback_issue)
			session.record.lifecycle = .Failed
			session.record.failure = failure
			return false, failure
		}
		return false, emulator_failure(.Resize, result)
	}
	session.columns = columns
	session.rows = rows
	session.cell_width_pixels = cell_width_pixels
	session.cell_height_pixels = cell_height_pixels
	return true, {}
}

/* registry_project_render copies one complete or incremental visible revision. */
registry_project_render :: proc(
	registry: ^Registry,
	ref: Session_Ref,
) -> (revision: Render_Revision, ok: bool, failure: Failure_Record) {
	state := registry_state(registry)
	if state == nil {
		return {}, false, registry_access_failure(registry, .Project)
	}
	session, resolved := registry_resolve(state, ref)
	if !resolved {
		return {}, false, failure_record(.Project, .Stale_Reference)
	}
	render_state, render_result := terminal_emulator.render(session.record.emulator)
	if render_result != .OK {
		failure = emulator_failure(.Project, render_result)
		return {}, false, projection_fail(session, failure)
	}
	cell_count := u64(render_state.columns) * u64(render_state.rows)
	projection_bytes := u64(render_state.rows) * u64(size_of(Render_Row)) +
		cell_count * u64(size_of(Render_Cell))
	if cell_count > MAX_PROJECTED_CELLS {
		failure = failure_record(
			.Project,
			.Projection_Limit,
			limit = MAX_PROJECTED_CELLS,
			actual = cell_count,
		)
		return {}, false, projection_fail(session, failure)
	}
	if projection_bytes > session.limits.state_bytes {
		failure = failure_record(
			.Project,
			.Projection_Limit,
			limit = session.limits.state_bytes,
			actual = projection_bytes,
		)
		return {}, false, projection_fail(session, failure)
	}
	if resize_error := resize(&session.projected_rows, int(render_state.rows)); resize_error != nil {
		failure = failure_record(.Project, .Allocation)
		return {}, false, projection_fail(session, failure)
	}
	if resize_error := resize(&session.projected_cells, int(cell_count)); resize_error != nil {
		failure = failure_record(.Project, .Allocation)
		return {}, false, projection_fail(session, failure)
	}
	projection_bytes = u64(cap(session.projected_rows)) * u64(size_of(Render_Row)) +
		u64(cap(session.projected_cells)) * u64(size_of(Render_Cell))
	if projection_bytes > session.limits.state_bytes {
		failure = failure_record(
			.Project,
			.Projection_Limit,
			limit = session.limits.state_bytes,
			actual = projection_bytes,
		)
		return {}, false, projection_fail(session, failure)
	}
	for &row in session.projected_rows do row.dirty = false
	projection, project_result := terminal_emulator.project(
		session.record.emulator,
		session.projected_rows[:],
		session.projected_cells[:],
	)
	if project_result != .OK {
		failure = emulator_failure(.Project, project_result)
		return {}, false, projection_fail(session, failure)
	}
	image_projection, image_result := terminal_emulator.project_images(
		session.record.emulator, session.images[:],
	)
	if image_result != .OK {
		failure = emulator_failure(.Project, image_result)
		return {}, false, projection_fail(session, failure)
	}
	if image_projection.truncated {
		for &image in session.images[:image_projection.count] do image.rejected = true
		session.record.effects.diagnostics = effect_add(session.record.effects.diagnostics, 1)
	}
	image_changed := image_projection.generation != session.image_projection.generation ||
		image_projection.count != session.image_projection.count ||
		image_projection.truncated != session.image_projection.truncated
	if projection.damage != .Clean || image_changed {
		session.record.render_revision += 1
		if session.record.render_revision == 0 do session.record.render_revision = 1
		terminal_event_publish(
			state, session, .Terminal_Revision, "terminal",
			{session.record.render_revision, 0, 0, 0},
		)
	}
	session.projection = projection
	session.image_projection = image_projection
	projection_bytes += u64(MAX_IMAGE_PLACEMENTS) * u64(size_of(Image_Placement))
	if projection_bytes > session.limits.state_bytes {
		failure = failure_record(
			.Project, .Projection_Limit,
			limit = session.limits.state_bytes, actual = projection_bytes,
		)
		return {}, false, projection_fail(session, failure)
	}
	session.record.projection_bytes = projection_bytes
	revision = Render_Revision {
		ref = ref,
		revision = session.record.render_revision,
		projection = projection,
		row_count = u64(len(session.projected_rows)),
		cell_count = u64(len(session.projected_cells)),
		projection_bytes = projection_bytes,
		image_generation = image_projection.generation,
		image_count = image_projection.count,
		image_bytes = image_projection.decoded_bytes,
		images_truncated = image_projection.truncated,
	}
	return revision, true, {}
}

/* registry_copy_image_placements copies bounded image metadata without pixel pointers. */
registry_copy_image_placements :: proc(
	registry: ^Registry,
	ref: Session_Ref,
	output: []Image_Placement,
) -> (copied: int, ok: bool, failure: Failure_Record) {
	state := registry_state(registry)
	if state == nil do return 0, false, registry_access_failure(registry, .Project)
	session, resolved := registry_resolve(state, ref)
	if !resolved do return 0, false, failure_record(.Project, .Stale_Reference)
	count := int(session.image_projection.count)
	if len(output) < count {
		return 0, false, failure_record(
			.Project, .Projection_Limit, limit = u64(len(output)), actual = u64(count),
		)
	}
	return copy(output, session.images[:count]), true, {}
}

/* registry_copy_render_rows copies the retained row projection to caller storage. */
registry_copy_render_rows :: proc(
	registry: ^Registry,
	ref: Session_Ref,
	output: []Render_Row,
) -> (copied: int, ok: bool, failure: Failure_Record) {
	state := registry_state(registry)
	if state == nil do return 0, false, registry_access_failure(registry, .Project)
	session, resolved := registry_resolve(state, ref)
	if !resolved do return 0, false, failure_record(.Project, .Stale_Reference)
	if len(output) < len(session.projected_rows) {
		return 0, false, failure_record(
			.Project, .Projection_Limit,
			limit = u64(len(output)), actual = u64(len(session.projected_rows)),
		)
	}
	return copy(output, session.projected_rows[:]), true, {}
}

/* registry_copy_render_cells copies the retained cell projection to caller storage. */
registry_copy_render_cells :: proc(
	registry: ^Registry,
	ref: Session_Ref,
	output: []Render_Cell,
) -> (copied: int, ok: bool, failure: Failure_Record) {
	state := registry_state(registry)
	if state == nil do return 0, false, registry_access_failure(registry, .Project)
	session, resolved := registry_resolve(state, ref)
	if !resolved do return 0, false, failure_record(.Project, .Stale_Reference)
	if len(output) < len(session.projected_cells) {
		return 0, false, failure_record(
			.Project, .Projection_Limit,
			limit = u64(len(output)), actual = u64(len(session.projected_cells)),
		)
	}
	return copy(output, session.projected_cells[:]), true, {}
}

@(private)
projection_fail :: proc(session: ^Session_State, failure: Failure_Record) -> Failure_Record {
	session.record.lifecycle = .Failed
	session.record.failure = failure
	return failure
}
