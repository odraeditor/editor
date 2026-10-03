// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package interaction

import "base:runtime"

/* MAX_CANDIDATES bounds one complete admitted candidate source generation. */
MAX_CANDIDATES :: u32(4_096)
/* MAX_CANDIDATE_TEXT_BYTES bounds copied labels, searchable fields, and annotations. */
MAX_CANDIDATE_TEXT_BYTES :: u64(32 * 1_024 * 1_024)
/* MAX_CANDIDATE_LABEL_BYTES bounds one canonical copied candidate label. */
MAX_CANDIDATE_LABEL_BYTES :: u32(4 * 1_024)
/* MAX_CANDIDATE_FIELDS bounds source-declared searchable fields per candidate. */
MAX_CANDIDATE_FIELDS :: u8(4)
/* MAX_CANDIDATE_ANNOTATIONS bounds copied presentation annotations per candidate. */
MAX_CANDIDATE_ANNOTATIONS :: u8(4)
/* MAX_CANDIDATE_QUERY_BYTES bounds one editable valid UTF-8 query. */
MAX_CANDIDATE_QUERY_BYTES :: u32(4 * 1_024)
/* MAX_CANDIDATE_QUERY_COMPONENTS bounds whitespace-separated query components. */
MAX_CANDIDATE_QUERY_COMPONENTS :: u8(8)
/* MAX_CANDIDATE_PATTERN_BYTES bounds one admitted pattern-aware component. */
MAX_CANDIDATE_PATTERN_BYTES :: u32(4 * 1_024)
/* MAX_CANDIDATE_VISIBLE_ROWS bounds one normalized candidate view generation. */
MAX_CANDIDATE_VISIBLE_ROWS :: u32(4_096)
/* MAX_CANDIDATE_TEMPORARY_BYTES bounds one matching and ranking turn. */
MAX_CANDIDATE_TEMPORARY_BYTES :: u64(16 * 1_024 * 1_024)
/* MAX_CANDIDATE_REFRESHES_PER_TURN admits one complete source replacement per input turn. */
MAX_CANDIDATE_REFRESHES_PER_TURN :: u8(1)
/* CANDIDATE_ORDINARY_LATENCY_GATE_NS is the selected 256-candidate input-turn gate. */
CANDIDATE_ORDINARY_LATENCY_GATE_NS :: u64(5_000_000)
/* CANDIDATE_DEMANDING_LATENCY_GATE_NS is the selected 4,096-candidate input-turn gate. */
CANDIDATE_DEMANDING_LATENCY_GATE_NS :: u64(100_000_000)
/* CANDIDATE_ORDINARY_MEMORY_GATE_BYTES bounds the measured 256-candidate peak footprint. */
CANDIDATE_ORDINARY_MEMORY_GATE_BYTES :: u64(16 * 1_024 * 1_024)
/* CANDIDATE_DEMANDING_MEMORY_GATE_BYTES bounds the measured 4,096-candidate peak footprint. */
CANDIDATE_DEMANDING_MEMORY_GATE_BYTES :: u64(128 * 1_024 * 1_024)

/* Candidate_Source_Kind identifies one closed factory candidate source. */
Candidate_Source_Kind :: enum u8 {
	Invalid,
	Commands,
	Session_Buffers,
	Project_Buffers,
	Project_Files,
	Dir_Files,
	Themes,
	Interaction_Profiles,
	Test,
	Language_Diagnostics,
	Filesystem_Entries,
	Projects,
	Workspaces,
	Named_Locations,
	Named_Slots,
	Results,
	Status_Segments,
	Package_Catalogs,
	Packages,
	Package_Catalog_Diagnostics,
	Personal_Command_Results,
}

/* Candidate_Identity is one source-owned stable opaque identity within a scope. */
Candidate_Identity :: struct {
	kind:      u16,
	primary:   u64,
	secondary: u64,
}

/* Candidate_Annotation_Kind classifies copied presentation text without changing labels. */
Candidate_Annotation_Kind :: enum u8 {
	Invalid,
	Binding,
	Provider,
	Availability,
	Description,
	Document_Path,
	Modified_State,
	Project_Member,
	Generic,
	Severity,
	Location,
	Filesystem_Permissions,
	Filesystem_Size,
	Filesystem_Modified,
}

/* Candidate_Annotation_Definition borrows one annotation during source admission. */
Candidate_Annotation_Definition :: struct {
	kind: Candidate_Annotation_Kind,
	text: string,
}

/* Candidate_Annotation is immutable borrowed text in one session or view generation. */
Candidate_Annotation :: struct {
	kind: Candidate_Annotation_Kind,
	text: string,
}

/* Candidate_Action_Kind selects an ordinary owner operation without carrying a procedure. */
Candidate_Action_Kind :: enum u8 {
	Invalid,
	Invoke_Command,
	Activate_Buffer,
	Create_Buffer,
	Open_Document,
	Select_Theme,
	Select_Interaction_Profile,
	Navigate_Diagnostic,
	Select_Path_Entry,
	Open_Project,
	Open_Workspace,
	Visit_Location,
	Select_Named_Slot,
	Visit_Result,
	Inspect_Status_Segment,
	Select_Package_Catalog,
	Open_Command_Candidate,
	Open_Command_Prompt,
}

/* Candidate_Action stores copied source-owned inputs for later checked invocation. */
Candidate_Action :: struct {
	kind:             Candidate_Action_Kind,
	owner_generation: u64,
	primary:          u64,
	secondary:        u64,
	graph_identity:   [6]u64,
}

/* Candidate_Availability distinguishes ordinary, unavailable, and synthetic candidates. */
Candidate_Availability :: enum u8 {
	Invalid,
	Available,
	Unavailable,
	Synthetic,
}

/* Candidate_Durable_Category classifies optional cross-process usage identities. */
Candidate_Durable_Category :: enum u8 {
	None,
	Command,
	Document,
	Project_File,
	Project,
	Workspace,
	Package_Catalog,
}

/* Candidate_Descriptor_Definition borrows one candidate during complete source admission. */
Candidate_Descriptor_Definition :: struct {
	identity:          Candidate_Identity,
	label:             string,
	searchable_fields: []string,
	annotations:       []Candidate_Annotation_Definition,
	action:            Candidate_Action,
	availability:      Candidate_Availability,
	durable_category:  Candidate_Durable_Category,
	durable_key:       string,
	recency:           u64,
	label_highlight_start: u32,
	label_highlight_end:   u32,
	label_highlight_present: bool,
}

/* Candidate_Source_Definition borrows one complete immutable source generation. */
Candidate_Source_Definition :: struct {
	kind:              Candidate_Source_Kind,
	scope_identity:    u64,
	scope_generation:  u64,
	source_generation: u64,
	descriptors:       []Candidate_Descriptor_Definition,
}

/* Candidate_Limits selects admitted source, query, projection, and temporary bounds. */
Candidate_Limits :: struct {
	candidates:         u32,
	text_bytes:         u64,
	label_bytes:        u32,
	fields_per_candidate: u8,
	annotations_per_candidate: u8,
	query_bytes:        u32,
	query_components:   u8,
	pattern_bytes:      u32,
	visible_rows:       u32,
	temporary_bytes:    u64,
	refreshes_per_turn: u8,
}

/* DEFAULT_CANDIDATE_LIMITS is the measured factory candidate-session policy. */
DEFAULT_CANDIDATE_LIMITS :: Candidate_Limits {
	candidates = MAX_CANDIDATES,
	text_bytes = MAX_CANDIDATE_TEXT_BYTES,
	label_bytes = MAX_CANDIDATE_LABEL_BYTES,
	fields_per_candidate = MAX_CANDIDATE_FIELDS,
	annotations_per_candidate = MAX_CANDIDATE_ANNOTATIONS,
	query_bytes = MAX_CANDIDATE_QUERY_BYTES,
	query_components = MAX_CANDIDATE_QUERY_COMPONENTS,
	pattern_bytes = MAX_CANDIDATE_PATTERN_BYTES,
	visible_rows = MAX_CANDIDATE_VISIBLE_ROWS,
	temporary_bytes = MAX_CANDIDATE_TEMPORARY_BYTES,
	refreshes_per_turn = MAX_CANDIDATE_REFRESHES_PER_TURN,
}

/* Candidate_Session_ID identifies one process-local candidate-session owner. */
Candidate_Session_ID :: distinct u64
/* Candidate_Session_Generation identifies one immutable published session projection. */
Candidate_Session_Generation :: distinct u64

/* Candidate_Match_Class orders exact, boundary, literal, pattern, and empty-query results. */
Candidate_Match_Class :: enum u8 {
	Invalid,
	Exact_Label,
	Prefix_Or_Boundary,
	Literal,
	Pattern,
	Empty,
}

/* Candidate_Accounting records retained copied resources for one complete session generation. */
Candidate_Accounting :: struct {
	candidates:       u32,
	label_bytes:      u64,
	searchable_bytes: u64,
	annotation_bytes: u64,
	durable_key_bytes: u64,
	query_bytes:      u32,
	query_components: u8,
	filtered_indices: u32,
}

/* Candidate_Row is one immutable borrowed normalized row in ranked order. */
Candidate_Row :: struct {
	identity:     Candidate_Identity,
	label:        string,
	annotations:  []Candidate_Annotation,
	action:       Candidate_Action,
	availability: Candidate_Availability,
	durable_category: Candidate_Durable_Category,
	durable_key:      string,
	match_class:  Candidate_Match_Class,
	recency:      u64,
	label_highlight_start: u32,
	label_highlight_end:   u32,
	label_highlight_present: bool,
}

/* Candidate_View borrows immutable state until the next operation on its session. */
Candidate_View :: struct {
	session_id:         Candidate_Session_ID,
	session_generation: Candidate_Session_Generation,
	source_kind:        Candidate_Source_Kind,
	scope_identity:     u64,
	scope_generation:   u64,
	source_generation:  u64,
	query:              string,
	rows:               []Candidate_Row,
	selected_row:       u32,
	has_selection:      bool,
	cancelled:          bool,
	accounting:         Candidate_Accounting,
}

/* Candidate_Transition classifies one checked session operation result. */
Candidate_Transition :: enum u8 {
	Invalid,
	No_Change,
	Changed,
	Refreshed,
	Cancelled,
	Closed,
}

/* Candidate_Result reports one published session generation and optional selection. */
Candidate_Result :: struct {
	transition:         Candidate_Transition,
	session_id:         Candidate_Session_ID,
	session_generation: Candidate_Session_Generation,
	identity:           Candidate_Identity,
	selected_row:       u32,
	has_selection:      bool,
}

/* Candidate_Request carries the exact session generation expected by a state change. */
Candidate_Request :: struct {
	session_id:         Candidate_Session_ID,
	session_generation: Candidate_Session_Generation,
}

/* Candidate_Failure_Code classifies admission, lifecycle, generation, and resource failures. */
Candidate_Failure_Code :: enum u8 {
	None,
	Invalid_Config,
	Invalid_Session,
	Closed_Session,
	Stale_Session,
	Invalid_Source,
	Stale_Source,
	Invalid_Identity,
	Duplicate_Identity,
	Malformed_UTF8,
	Candidate_Limit,
	Text_Limit,
	Label_Limit,
	Field_Limit,
	Annotation_Limit,
	Query_Limit,
	Component_Limit,
	Pattern_Limit,
	Visible_Row_Limit,
	Temporary_Memory_Limit,
	Persistent_Memory_Limit,
	Invalid_Movement,
	No_Selection,
	Cancelled,
}

/* Candidate_Failure identifies the rejected session, source generation, and applicable bound. */
Candidate_Failure :: struct {
	code:               Candidate_Failure_Code,
	session_id:         Candidate_Session_ID,
	session_generation: Candidate_Session_Generation,
	source_generation:  u64,
	identity:           Candidate_Identity,
	limit:              u64,
	actual:             u64,
}

/* Candidate_Config selects one process-local identity, bounds, and owned allocators. */
Candidate_Config :: struct {
	session_id:          Candidate_Session_ID,
	limits:              Candidate_Limits,
	persistent_allocator: runtime.Allocator,
	temporary_allocator:  runtime.Allocator,
}

/* Candidate_Session owns one complete source snapshot, query, projection, and recency state. */
Candidate_Session :: struct {
	state: rawptr,
}
