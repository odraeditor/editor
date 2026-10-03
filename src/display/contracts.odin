// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package display

import "../editor"
import editor_view "../view"
import "base:runtime"

/* KIBIBYTE is the binary byte unit used by display resource contracts. */
KIBIBYTE :: u64(1_024)
/* MEBIBYTE is 1,024 kibibytes. */
MEBIBYTE :: u64(1_024) * KIBIBYTE

/* MAX_VIEWPORT_WIDTH_CELLS is the initial frontend-width safety ceiling. */
MAX_VIEWPORT_WIDTH_CELLS :: u32(4_096)
/* MAX_VIEWPORT_HEIGHT_ROWS is the initial frontend-height safety ceiling. */
MAX_VIEWPORT_HEIGHT_ROWS :: u32(4_096)
/* MAX_DISPLAYED_CELLS is the initial projected cell-product safety ceiling. */
MAX_DISPLAYED_CELLS :: u64(1_048_576)
/* MAX_SOURCE_BYTES is the maximum canonical text examined by one projection. */
MAX_SOURCE_BYTES :: 16 * MEBIBYTE
/* MAX_DERIVED_BYTES is the maximum retained derived display storage per view. */
MAX_DERIVED_BYTES :: 64 * MEBIBYTE
/* MAX_RUNS bounds compact UTF-8 runs retained by one display snapshot. */
MAX_RUNS :: u32(1_048_576)
/* MAX_BOUNDARIES bounds grapheme/source/display mappings in one snapshot. */
MAX_BOUNDARIES :: u32(1_052_672)
/* MAX_CHECKPOINTS bounds retained long-line checkpoints per view. */
MAX_CHECKPOINTS :: u32(65_536)
/* MAX_SEARCH_MATCHES bounds projected current and secondary search occurrences. */
MAX_SEARCH_MATCHES :: u32(65_536)
/* OPERATING_VIEWPORT_WIDTH_CELLS is the evidence-backed initial width limit. */
OPERATING_VIEWPORT_WIDTH_CELLS :: u32(240)
/* OPERATING_VIEWPORT_HEIGHT_ROWS is the evidence-backed initial height limit. */
OPERATING_VIEWPORT_HEIGHT_ROWS :: u32(80)
/* OPERATING_DISPLAYED_CELLS is the evidence-backed initial viewport product. */
OPERATING_DISPLAYED_CELLS :: u64(19_200)
/* OPERATING_SOURCE_BYTES is the initial bounded projection work allowance. */
OPERATING_SOURCE_BYTES :: 64 * KIBIBYTE
/* OPERATING_DERIVED_BYTES is the initial retained display-snapshot allowance. */
OPERATING_DERIVED_BYTES :: 2 * MEBIBYTE
/* OPERATING_RUNS is the initial compact-run allowance per display snapshot. */
OPERATING_RUNS :: u32(4_096)
/* OPERATING_BOUNDARIES is the initial source/display mapping allowance. */
OPERATING_BOUNDARIES :: u32(65_536)
/* OPERATING_CHECKPOINTS is the initial long-line checkpoint allowance. */
OPERATING_CHECKPOINTS :: u32(4_096)
/* OPERATING_SEARCH_MATCHES is the measured initial projected occurrence capacity. */
OPERATING_SEARCH_MATCHES :: u32(256)
/* OPERATING_POINTER_MAPPING_WORK bounds one display-to-text pointer query. */
OPERATING_POINTER_MAPPING_WORK :: u64(65_536)
/* TERMINAL_UNICODE17_PROFILE_ID identifies the initial terminal display policy. */
TERMINAL_UNICODE17_PROFILE_ID :: Display_Profile_ID(1)

/* Display_Profile_ID identifies one immutable display and Unicode policy combination. */
Display_Profile_ID :: distinct u64
/* Snapshot_ID identifies one immutable display snapshot; zero is invalid. */
Snapshot_ID :: distinct u64
/* Display_Column addresses a zero-based logical cell column. */
Display_Column :: distinct u32
/* Display_Row_Index addresses a zero-based viewport row. */
Display_Row_Index :: distinct u32
/* Logical_Line_Index identifies a zero-based canonical logical line. */
Logical_Line_Index :: distinct u64

/* Navigation_Kind identifies one frontend-independent logical cursor movement. */
Navigation_Kind :: enum u8 {
	Previous_Grapheme,
	Next_Grapheme,
	Previous_Line,
	Next_Line,
	Line_Start,
	Line_End,
	Previous_Word,
	Next_Word,
	Next_Word_Start,
	Line_First_Non_Whitespace,
	Buffer_Start,
	Buffer_End,
}

/* Line_Character_Target_Kind selects exact or adjacent line-local character movement. */
Line_Character_Target_Kind :: enum u8 {
	Invalid,
	Find_Next,
	Find_Previous,
	Till_Next,
	Till_Previous,
}

/* Display_Position addresses one grapheme boundary relative to a snapshot viewport. */
Display_Position :: struct {
	viewport_row: Display_Row_Index,
	column:       Display_Column,
}

/* Text_Hit_Affinity declares how one represented cell resolved to a text boundary. */
Text_Hit_Affinity :: enum u8 {
	Invalid,
	Exact,
	Leading,
	Trailing,
}

/* Text_Hit is one immutable pointer-free mapping from displayed text to canonical text. */
Text_Hit :: struct {
	snapshot_id:          Snapshot_ID,
	buffer_id:            editor.Buffer_ID,
	buffer_revision:      editor.Revision,
	view_id:              u64,
	view_generation:      u32,
	view_state_generation: u64,
	display:              Display_Position,
	position:             editor.Position,
	logical_line:         Logical_Line_Index,
	span_start:           Display_Column,
	span_end:             Display_Column,
	affinity:             Text_Hit_Affinity,
}

/* text_hit_is_valid checks identity, canonical-position, span, and affinity invariants. */
text_hit_is_valid :: proc(hit: Text_Hit) -> bool {
	return hit.snapshot_id != Snapshot_ID(0) && hit.buffer_id != editor.Buffer_ID(0) &&
	       hit.view_id != 0 && hit.view_generation != 0 && hit.view_state_generation != 0 &&
	       hit.position.buffer_id == hit.buffer_id &&
	       hit.position.revision == hit.buffer_revision &&
	       hit.span_start <= hit.span_end && hit.display.column >= hit.span_start &&
	       hit.display.column <= hit.span_end &&
	       hit.affinity >= .Exact && hit.affinity <= .Trailing
}

/* Display_Profile combines versioned Unicode behavior with fixed terminal policy. */
Display_Profile :: struct {
	id:                    Display_Profile_ID,
	unicode:               Unicode_Profile,
	ambiguous_width_cells: u8,
	replacement_rune:      rune,
}

/* terminal_unicode17_profile returns the initial deterministic terminal profile. */
terminal_unicode17_profile :: proc() -> Display_Profile {
	return Display_Profile {
		id = TERMINAL_UNICODE17_PROFILE_ID,
		unicode = unicode17_profile(),
		ambiguous_width_cells = 1,
		replacement_rune = '\uFFFD',
	}
}

/* display_profile_is_valid checks identity, Unicode operations, and fixed policies. */
display_profile_is_valid :: proc(profile: Display_Profile) -> bool {
	return profile.id != Display_Profile_ID(0) && profile_is_valid(profile.unicode) &&
	       profile.ambiguous_width_cells == 1 && profile.replacement_rune == '\uFFFD'
}

/* Viewport_Constraints contains immutable frontend-supplied projection geometry. */
Viewport_Constraints :: struct {
	width_cells: u32,
	height_rows: u32,
}

/* Resource_Limits collects hard source, storage, mapping, and work ceilings. */
Resource_Limits :: struct {
	viewport_width_cells:  u32,
	viewport_height_rows:  u32,
	displayed_cells:       u64,
	source_bytes:          u64,
	derived_bytes:         u64,
	runs:                  u32,
	boundaries:            u32,
	checkpoints:           u32,
	search_matches:        u32,
}

/* SAFETY_RESOURCE_LIMITS is the initial investigation-ceiling set. */
SAFETY_RESOURCE_LIMITS :: Resource_Limits {
	viewport_width_cells = MAX_VIEWPORT_WIDTH_CELLS,
	viewport_height_rows = MAX_VIEWPORT_HEIGHT_ROWS,
	displayed_cells = MAX_DISPLAYED_CELLS,
	source_bytes = MAX_SOURCE_BYTES,
	derived_bytes = MAX_DERIVED_BYTES,
	runs = MAX_RUNS,
	boundaries = MAX_BOUNDARIES,
	checkpoints = MAX_CHECKPOINTS,
	search_matches = MAX_SEARCH_MATCHES,
}

/* OPERATING_RESOURCE_LIMITS is the evidence-backed initial projection limit set. */
OPERATING_RESOURCE_LIMITS :: Resource_Limits {
	viewport_width_cells = OPERATING_VIEWPORT_WIDTH_CELLS,
	viewport_height_rows = OPERATING_VIEWPORT_HEIGHT_ROWS,
	displayed_cells = OPERATING_DISPLAYED_CELLS,
	source_bytes = OPERATING_SOURCE_BYTES,
	derived_bytes = OPERATING_DERIVED_BYTES,
	runs = OPERATING_RUNS,
	boundaries = OPERATING_BOUNDARIES,
	checkpoints = OPERATING_CHECKPOINTS,
	search_matches = OPERATING_SEARCH_MATCHES,
}

/* DEFAULT_RESOURCE_LIMITS is the evidence-backed initial operating set. */
DEFAULT_RESOURCE_LIMITS :: OPERATING_RESOURCE_LIMITS

/* Allocator_Set separates retained snapshot storage from temporary layout work. */
Allocator_Set :: struct {
	persistent: runtime.Allocator,
	temporary:  runtime.Allocator,
}

/* Text_Run locates compact snapshot-owned UTF-8 and its display-column extent. */
Text_Run :: struct {
	text_offset:    u32,
	text_bytes:     u32,
	start_column:   Display_Column,
	cell_count:     u32,
}

/* Boundary_Map maps one grapheme boundary across canonical, row-text, and display units. */
Boundary_Map :: struct {
	source_byte_offset: editor.Byte_Offset,
	row_text_offset:    u32,
	display_column:     Display_Column,
}

/* Display_Row describes one logical line projected into one clipped viewport row. */
Display_Row :: struct {
	viewport_row:       Display_Row_Index,
	logical_line:       Logical_Line_Index,
	source_start:       editor.Byte_Offset,
	source_end:         editor.Byte_Offset,
	first_run:          u32,
	run_count:          u32,
	first_boundary:     u32,
	boundary_count:     u32,
	visible_start:      Display_Column,
	visible_cells:      u32,
	clipped_left:       bool,
	clipped_right:      bool,
	used_replacement:   bool,
	has_content:        bool,
	region_active:      bool,
	region_start:       editor.Byte_Offset,
	region_end:         editor.Byte_Offset,
}

/* Cursor_Target maps the logical primary cursor into one visible display position. */
Cursor_Target :: struct {
	visible:      bool,
	viewport_row: Display_Row_Index,
	column:       Display_Column,
}

/* Region_Map records ordered logical endpoints and their visible display positions. */
Region_Map :: struct {
	active:               bool,
	rectangular:          bool,
	start:                editor.Byte_Offset,
	end:                  editor.Byte_Offset,
	start_visible:        bool,
	end_visible:          bool,
	start_viewport_row:   Display_Row_Index,
	end_viewport_row:     Display_Row_Index,
	start_column:         Display_Column,
	end_column:           Display_Column,
}

/* Search_Match_Map projects one revisioned occurrence into visible endpoint geometry. */
Search_Match_Map :: struct {
	start:              editor.Byte_Offset,
	end:                editor.Byte_Offset,
	current:            bool,
	intersects_visible: bool,
	start_visible:      bool,
	end_visible:        bool,
	start_row:          Display_Row_Index,
	end_row:            Display_Row_Index,
	start_column:       Display_Column,
	end_column:         Display_Column,
	clipped_start:      bool,
	clipped_end:        bool,
}

/* Line_Checkpoint accelerates bounded replay within one long logical line. */
Line_Checkpoint :: struct {
	logical_line:       Logical_Line_Index,
	source_byte_offset: editor.Byte_Offset,
	grapheme_index:     u64,
	display_column:     Display_Column,
}

/* Snapshot_Key identifies every input that makes a display snapshot compatible. */
Snapshot_Key :: struct {
	snapshot_id:        Snapshot_ID,
	buffer_id:          editor.Buffer_ID,
	buffer_revision:    editor.Revision,
	view_id:            u64,
	view_generation:    u32,
	view_state_generation: u64,
	display_profile_id: Display_Profile_ID,
	unicode_version:    Unicode_Version,
	constraints:        Viewport_Constraints,
	tab_width:          u16,
}

/* Snapshot_View borrows immutable arrays and UTF-8 owned by one live snapshot. */
Snapshot_View :: struct {
	key:          Snapshot_Key,
	text:         string,
	rows:         []Display_Row,
	runs:         []Text_Run,
	boundaries:   []Boundary_Map,
	checkpoints:  []Line_Checkpoint,
	cursor:       Cursor_Target,
	region:       Region_Map,
	search_matches: []Search_Match_Map,
	accounting:   Resource_Accounting,
}

/* Snapshot is a non-copyable opaque owner consumed exactly once by snapshot_close. */
Snapshot :: struct {
	state: rawptr,
}

/* Projection_Cache owns bounded disposable checkpoints for one editor view. */
Projection_Cache :: struct {
	state: rawptr,
	closed: bool,
}

/* Projection_Cache_Stats reports cache identity, occupancy, and retained storage. */
Projection_Cache_Stats :: struct {
	view_id:          u64,
	view_generation:  u32,
	buffer_id:        editor.Buffer_ID,
	buffer_revision:  editor.Revision,
	logical_line:     Logical_Line_Index,
	checkpoint_count: u32,
	capacity:         u32,
	storage_bytes:    u64,
	valid:            bool,
}

/* Projection_Request contains immutable identities, policies, limits, and live allocators. */
Projection_Request :: struct {
	snapshot_id:   Snapshot_ID,
	search:        editor_view.Search_Snapshot,
	view:          editor_view.Snapshot,
	hidden_ranges: []editor_view.Hidden_Range,
	constraints:   Viewport_Constraints,
	profile:       Display_Profile,
	limits:        Resource_Limits,
	allocators:    Allocator_Set,
}

/* Resource_Accounting reports retained and peak temporary representation costs. */
Resource_Accounting :: struct {
	owner_bytes:            u64,
	source_bytes_examined: u64,
	text_bytes:            u64,
	row_bytes:             u64,
	run_bytes:             u64,
	boundary_bytes:        u64,
	checkpoint_bytes:      u64,
	search_match_bytes:    u64,
	retained_bytes:        u64,
	temporary_peak_bytes:  u64,
}

/* Representation_Estimate is a checked pre-allocation cost model for one snapshot. */
Representation_Estimate :: struct {
	row_count:       u32,
	run_count:       u32,
	boundary_count:  u32,
	checkpoint_count: u32,
	accounting:      Resource_Accounting,
}

/* Failure_Code classifies expected profile, geometry, capacity, and mapping failures. */
Failure_Code :: enum u16 {
	None,
	Invalid_Profile,
	Invalid_Constraints,
	Displayed_Cell_Limit,
	Source_Byte_Limit,
	Derived_Storage_Limit,
	Run_Limit,
	Boundary_Limit,
	Checkpoint_Limit,
	Search_Match_Limit,
	Persistent_Memory_Limit,
	Temporary_Memory_Limit,
	Stale_Snapshot,
	Incompatible_Snapshot,
	Mapping_Miss,
	Malformed_UTF8,
	Work_Limit,
	Invalid_Request,
	Closed_Snapshot,
	Editor_Failure,
	Invalid_Cache,
	Wrong_View,
	Cache_Limit,
}

/* Failure_Context reports incompatible identity, geometry, counts, and bounds. */
Failure_Context :: struct {
	code:               Failure_Code,
	buffer_id:          editor.Buffer_ID,
	buffer_revision:    editor.Revision,
	snapshot_id:        Snapshot_ID,
	display_profile_id: Display_Profile_ID,
	limit:              u64,
	actual:             u64,
	editor_failure:     editor.Failure_Context,
}

/* constraints_are_valid checks nonzero geometry and the displayed-cell product. */
constraints_are_valid :: proc(
	constraints: Viewport_Constraints,
	limits := DEFAULT_RESOURCE_LIMITS,
) -> (ok: bool, failure: Failure_Context) {
	if !resource_limits_are_valid(limits) || constraints.width_cells == 0 ||
	   constraints.height_rows == 0 || constraints.width_cells > limits.viewport_width_cells ||
	   constraints.height_rows > limits.viewport_height_rows {
		return false, Failure_Context {
			code = .Invalid_Constraints,
			limit = u64(limits.viewport_width_cells) * u64(limits.viewport_height_rows),
			actual = u64(constraints.width_cells) * u64(constraints.height_rows),
		}
	}
	cell_count := u64(constraints.width_cells) * u64(constraints.height_rows)
	if cell_count > limits.displayed_cells {
		return false, Failure_Context {
			code = .Displayed_Cell_Limit,
			limit = limits.displayed_cells,
			actual = cell_count,
		}
	}
	return true, {}
}

/* representation_estimate checks hybrid-row counts and retained byte costs before allocation. */
representation_estimate :: proc(
	constraints: Viewport_Constraints,
	source_bytes_examined, text_bytes: u64,
	run_count, boundary_count, checkpoint_count: u32,
	limits := DEFAULT_RESOURCE_LIMITS,
) -> (estimate: Representation_Estimate, ok: bool, failure: Failure_Context) {
	constraints_ok, constraints_failure := constraints_are_valid(constraints, limits)
	if !constraints_ok {
		return {}, false, constraints_failure
	}
	if source_bytes_examined > limits.source_bytes {
		return {}, false, Failure_Context {
			code = .Source_Byte_Limit,
			limit = limits.source_bytes,
			actual = source_bytes_examined,
		}
	}
	if run_count > limits.runs {
		return {}, false, Failure_Context{code = .Run_Limit, limit = u64(limits.runs), actual = u64(run_count)}
	}
	if boundary_count > limits.boundaries {
		return {}, false, Failure_Context {
			code = .Boundary_Limit,
			limit = u64(limits.boundaries),
			actual = u64(boundary_count),
		}
	}
	if checkpoint_count > limits.checkpoints {
		return {}, false, Failure_Context {
			code = .Checkpoint_Limit,
			limit = u64(limits.checkpoints),
			actual = u64(checkpoint_count),
		}
	}

	row_bytes := u64(constraints.height_rows) * u64(size_of(Display_Row))
	run_bytes := u64(run_count) * u64(size_of(Text_Run))
	boundary_bytes := u64(boundary_count) * u64(size_of(Boundary_Map))
	checkpoint_bytes := u64(checkpoint_count) * u64(size_of(Line_Checkpoint))
	retained_bytes, retained_ok := checked_sum_u64(
		text_bytes,
		row_bytes,
		run_bytes,
		boundary_bytes,
		checkpoint_bytes,
	)
	if !retained_ok || retained_bytes > limits.derived_bytes {
		actual := retained_bytes
		if !retained_ok {
			actual = max(u64)
		}
		return {}, false, Failure_Context {
			code = .Derived_Storage_Limit,
			limit = limits.derived_bytes,
			actual = actual,
		}
	}
	return Representation_Estimate {
		row_count = constraints.height_rows,
		run_count = run_count,
		boundary_count = boundary_count,
		checkpoint_count = checkpoint_count,
		accounting = Resource_Accounting {
			source_bytes_examined = source_bytes_examined,
			text_bytes = text_bytes,
			row_bytes = row_bytes,
			run_bytes = run_bytes,
			boundary_bytes = boundary_bytes,
			checkpoint_bytes = checkpoint_bytes,
			retained_bytes = retained_bytes,
		},
	}, true, {}
}

@(private)
resource_limits_are_valid :: proc(limits: Resource_Limits) -> bool {
	return limits.viewport_width_cells > 0 && limits.viewport_height_rows > 0 &&
	       limits.displayed_cells > 0 && limits.source_bytes > 0 &&
	       limits.derived_bytes > 0 && limits.runs > 0 && limits.boundaries > 0 &&
	       limits.checkpoints > 0 && limits.search_matches > 0 &&
	       limits.search_matches <= MAX_SEARCH_MATCHES
}

@(private)
checked_sum_u64 :: proc(values: ..u64) -> (total: u64, ok: bool) {
	for value in values {
		if total > max(u64) - value {
			return max(u64), false
		}
		total += value
	}
	return total, true
}
