// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package terminal_session

import "core:testing"
import "../terminal_emulator"

@(private)
projected_cell_text :: proc(cell: ^Render_Cell) -> string {
	if cell == nil || int(cell.text_length) > len(cell.text) do return ""
	return string(cell.text[:cell.text_length])
}

@(private)
find_projected_text :: proc(cells: []Render_Cell, text: string) -> ^Render_Cell {
	for &cell in cells {
		if projected_cell_text(&cell) == text do return &cell
	}
	return nil
}

/* Verifies copied full and dirty revisions preserve cells, styles, cursor, and palette. */
@(test)
projection_copies_stable_full_and_dirty_revisions :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry)
	testing.expect(t, initialized)
	if !initialized do return
	defer if registry.state != nil {
		_, _ = registry_close(&registry)
	}
	request := test_open_request(
		"projection",
		arguments = []string{"-c", "sleep 30"},
	)
	request.process.limits.columns = 120
	request.process.limits.rows = 40
	record, opened, open_failure := registry_open(&registry, request)
	testing.expectf(t, opened, "projection terminal failed with %v", open_failure.code)
	if !opened do return

	initial := transmute([]u8)(string(
		"plain \x1b[31mred\x1b[0m é 界" +
		"\x1b]4;1;#112233\x07\x1b[3;5H",
	))
	testing.expect_value(
		t,
		terminal_emulator.write(record.emulator, initial),
		terminal_emulator.Result.OK,
	)
	revision, projected, failure := registry_project_render(&registry, record.ref)
	testing.expectf(t, projected, "full projection failed with %v", failure.code)
	if !projected do return
	testing.expect_value(t, revision.revision, u64(1))
	testing.expect_value(t, revision.projection.damage, terminal_emulator.Damage.Full)
	testing.expect_value(t, revision.row_count, u64(24))
	testing.expect_value(t, revision.cell_count, u64(80 * 24))
	testing.expect_value(t, revision.projection.cursor_column, u16(4))
	testing.expect_value(t, revision.projection.cursor_row, u16(2))
	testing.expect(t, revision.projection.cursor_in_viewport)
	testing.expect_value(t, revision.projection.palette[1], terminal_emulator.Color{0x11, 0x22, 0x33})

	rows := make([]Render_Row, int(revision.row_count))
	cells := make([]Render_Cell, int(revision.cell_count))
	defer delete(rows)
	defer delete(cells)
	row_count, rows_copied, rows_failure := registry_copy_render_rows(
		&registry, record.ref, rows,
	)
	cell_count, cells_copied, cells_failure := registry_copy_render_cells(
		&registry, record.ref, cells,
	)
	testing.expectf(t, rows_copied, "row copy failed with %v", rows_failure.code)
	testing.expectf(t, cells_copied, "cell copy failed with %v", cells_failure.code)
	testing.expect_value(t, row_count, len(rows))
	testing.expect_value(t, cell_count, len(cells))
	red := find_projected_text(cells, "r")
	testing.expect(t, red != nil)
	if red != nil {
		testing.expect_value(t, red.style.foreground.kind, terminal_emulator.Style_Color_Kind.Palette)
		testing.expect_value(t, red.style.foreground.palette, u8(1))
	}
	combined := find_projected_text(cells, "é")
	testing.expect(t, combined != nil)
	wide := find_projected_text(cells, "界")
	testing.expect(t, wide != nil)
	if wide != nil do testing.expect_value(t, wide.width, terminal_emulator.Cell_Width.Wide)

	stable: Render_Revision
	stable, projected, failure = registry_project_render(&registry, record.ref)
	testing.expectf(t, projected, "stable projection failed with %v", failure.code)
	testing.expect_value(t, stable.revision, revision.revision)
	testing.expect_value(t, stable.projection.damage, terminal_emulator.Damage.Clean)

	change := transmute([]u8)(string("\x1b[2;1Hchanged"))
	_ = terminal_emulator.write(record.emulator, change)
	dirty: Render_Revision
	dirty, projected, failure = registry_project_render(&registry, record.ref)
	testing.expectf(t, projected, "dirty projection failed with %v", failure.code)
	testing.expect_value(t, dirty.revision, revision.revision + 1)
	testing.expect_value(t, dirty.projection.damage, terminal_emulator.Damage.Partial)
	testing.expect(t, dirty.projection.damaged_rows > 0 && dirty.projection.damaged_rows < 24)
	testing.expect_value(t, dirty.projection.first_damaged_row, u16(1))
	_, cells_copied, cells_failure = registry_copy_render_cells(&registry, record.ref, cells)
	testing.expectf(t, cells_copied, "incremental cell copy failed with %v", cells_failure.code)
	testing.expect(t, find_projected_text(cells, "p") != nil)
	testing.expect(t, find_projected_text(cells, "c") != nil)
	cluster: [81]u8
	cluster[0] = 'a'
	for index in 0 ..< 40 {
		cluster[1 + index * 2] = 0xcc
		cluster[2 + index * 2] = 0x81
	}
	_ = terminal_emulator.write(record.emulator, transmute([]u8)(string("\x1b[4;1H")))
	_ = terminal_emulator.write(record.emulator, cluster[:])
	clipped: Render_Revision
	clipped, projected, failure = registry_project_render(&registry, record.ref)
	testing.expectf(t, projected, "clipped projection failed with %v", failure.code)
	testing.expect(t, clipped.projection.clipped_cells > 0)
	testing.expect(t, clipped.projection.clipped_text_bytes > terminal_emulator.CELL_TEXT_BYTES)

	_ = terminal_emulator.write(record.emulator, transmute([]u8)(string("\x1b[?1049hALT")))
	alternate: Render_Revision
	alternate, projected, failure = registry_project_render(&registry, record.ref)
	testing.expectf(t, projected, "alternate projection failed with %v", failure.code)
	testing.expect_value(t, alternate.projection.damage, terminal_emulator.Damage.Full)
	_ = terminal_emulator.write(record.emulator, transmute([]u8)(string("\x1b[?1049l")))
	restored: Render_Revision
	restored, projected, failure = registry_project_render(&registry, record.ref)
	testing.expectf(t, projected, "restored projection failed with %v", failure.code)
	testing.expect_value(t, restored.projection.damage, terminal_emulator.Damage.Full)

	resized, resize_failure := registry_resize(&registry, record.ref, 100, 30, 9, 18)
	testing.expectf(t, resized, "terminal resize failed with %v", resize_failure.code)
	if resized {
		resized_revision, resized_projected, resized_failure := registry_project_render(
			&registry, record.ref,
		)
		testing.expectf(t, resized_projected, "resized projection failed with %v", resized_failure.code)
		testing.expect_value(t, resized_revision.projection.columns, u16(100))
		testing.expect_value(t, resized_revision.projection.rows, u16(30))
		testing.expect_value(t, resized_revision.projection.damage, terminal_emulator.Damage.Full)
	}
}

/* Verifies projection storage and caller copies reject explicit bounds. */
@(test)
projection_reports_storage_and_copy_limits :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry)
	testing.expect(t, initialized)
	if !initialized do return
	defer if registry.state != nil {
		_, _ = registry_close(&registry)
	}
	record, opened, _ := registry_open(
		&registry,
		test_open_request("copy-limit", arguments = []string{"-c", "sleep 30"}),
	)
	testing.expect(t, opened)
	if !opened do return
	revision, projected, failure := registry_project_render(&registry, record.ref)
	testing.expectf(t, projected, "bounded projection failed with %v", failure.code)
	if projected {
		short: [1]Render_Cell
		_, copied, copy_failure := registry_copy_render_cells(&registry, record.ref, short[:])
		testing.expect(t, !copied)
		testing.expect_value(t, copy_failure.code, Failure_Code.Projection_Limit)
		testing.expect_value(t, copy_failure.actual, revision.cell_count)
	}

	limited := test_open_request("state-limit", arguments = []string{"-c", "sleep 30"})
	limited.limits.scrollback_bytes = 1
	limited.limits.state_bytes = 1
	limited_record, limited_opened, limited_failure := registry_open(&registry, limited)
	testing.expectf(t, limited_opened, "limited terminal failed with %v", limited_failure.code)
	if limited_opened {
		_, projected, failure = registry_project_render(&registry, limited_record.ref)
		testing.expect(t, !projected)
		testing.expect_value(t, failure.code, Failure_Code.Projection_Limit)
	}
}
