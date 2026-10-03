// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package jan_editing owns Jan Stage 2 structured-editing behavior over copied analysis.
package jan_editing

import "../editor"
import "../language"
import "../view"

/* JAN_STRUCTURED_EDITING_SPECIFICATION_COMMIT identifies the accepted Stage 2 contract. */
JAN_STRUCTURED_EDITING_SPECIFICATION_COMMIT :: "dcad6239360d5e7862138d090bbaf91fa8e1a915"
/* MAX_HIDDEN_RANGES bounds one view-local Jan visibility result. */
MAX_HIDDEN_RANGES :: u32(16_384)
/* MAX_SPARSE_MATCHES bounds matches retained by one sparse projection. */
MAX_SPARSE_MATCHES :: u32(16_384)
/* MAX_SPARSE_PREDICATE_BYTES bounds copied textual sparse predicates. */
MAX_SPARSE_PREDICATE_BYTES :: u64(4 * 1_024)
/* MAX_SEMANTIC_TARGETS bounds targets admitted by one structured command. */
MAX_SEMANTIC_TARGETS :: u32(4_096)
/* MAX_TABLE_CELLS bounds cells admitted by one table operation. */
MAX_TABLE_CELLS :: u32(65_536)
/* MAX_COMPLETION_CANDIDATES bounds one copied completion result. */
MAX_COMPLETION_CANDIDATES :: u16(512)
/* MAX_COMPLETION_BYTES bounds copied candidate text in one result. */
MAX_COMPLETION_BYTES :: u64(256 * 1_024)
/* MAX_TEMPLATES bounds one confirmed template catalog. */
MAX_TEMPLATES :: u16(256)
/* MAX_COMPLETION_SOURCES bounds one confirmed completion-source catalog. */
MAX_COMPLETION_SOURCES :: u16(256)
/* MAX_CONFIGURATION_BYTES bounds copied Stage 2 configuration data. */
MAX_CONFIGURATION_BYTES :: u64(1_024 * 1_024)
/* MAX_ACTIVE_PREVIEWS_PER_VIEW bounds concurrent adapter requests for one view. */
MAX_ACTIVE_PREVIEWS_PER_VIEW :: u8(8)
/* MAX_PREVIEW_RESULT_BYTES bounds one retained preview result. */
MAX_PREVIEW_RESULT_BYTES :: u64(8 * 1_024 * 1_024)
/* MAX_PREVIEW_CACHE_BYTES bounds the process-wide Stage 2 preview cache. */
MAX_PREVIEW_CACHE_BYTES :: u64(64 * 1_024 * 1_024)
/* CANCELLATION_CHECK_ENTRIES bounds work between cooperative cancellation checks. */
CANCELLATION_CHECK_ENTRIES :: u32(4_096)

/* Operation_ID identifies one Stage 2 request lifetime; zero is invalid. */
Operation_ID :: distinct u64
/* Configuration_Generation identifies one confirmed Stage 2 configuration. */
Configuration_Generation :: distinct u64
/* Provider_Generation identifies one confirmed optional Stage 2 provider set. */
Provider_Generation :: distinct u64

/* Operation identifies the Stage 2 action associated with a result or failure. */
Operation :: enum u8 {
	None,
	Navigate,
	Apply_Outline_Visibility,
	Plan_Heading_Edit,
	Copy_Subtree,
	Derive_Sparse_View,
	Refresh_Sparse_View,
	Navigate_Sparse_View,
	Plan_List_Edit,
	Plan_Structure_Edit,
	Validate_Structural_Region,
	Plan_Structural_Region,
	Plan_Table_Edit,
	Copy_Table_Rectangle,
	Prepare_Table_Presentation,
	Plan_Table_Cell_Edit,
	Inspect_Table_Formula,
	Prepare_Rich_Presentation,
	Resolve_Footnote,
	Plan_Footnote_Edit,
	Prepare_Visibility,
	Publish_Visibility,
	Inspect_Visibility,
	Resolve_Target,
	Plan_Rewrite,
	Complete,
	Expand_Template,
	Request_Preview,
	Publish_Preview,
	Inspect_Preview,
	Evict_Preview,
	Configure,
	Resolve_Context,
	Apply_Drawer_Visibility,
}

/* List_Edit_Kind identifies one source-preserving plain-list operation. */
List_Edit_Kind :: enum u8 {
	Invalid,
	Insert_Before,
	Insert_After,
	Delete_Item,
	Promote_Item,
	Demote_Item,
	Move_Up,
	Move_Down,
	Duplicate_Item,
	Sort_Items,
	Select_Bullet,
	Set_Counter,
	Repair_Indentation,
	Convert_Region,
}

/* List_Bullet_Kind is the admitted factory list marker vocabulary. */
List_Bullet_Kind :: enum u8 {
	Invalid,
	Unordered_Dash,
	Unordered_Plus,
	Unordered_Star,
	Ordered_Dot,
	Ordered_Paren,
	Descriptive,
}

/* List_Edit_Request binds one list operation to exact source and policy. */
List_Edit_Request :: struct {
	operation_id:      Operation_ID,
	scope:             Scope,
	kind:              List_Edit_Kind,
	target_id:         language.Jan_Node_ID,
	rewrite_generation: language.Jan_Rewrite_Generation,
	bullet:            List_Bullet_Kind,
	text:              string,
	counter:           u32,
	indent_width:      u8,
}

/* Structure_Edit_Kind identifies one complete drawer or block operation. */
Structure_Edit_Kind :: enum u8 {
	Invalid,
	Insert_Before,
	Insert_After,
	Expand_Template,
	Delete,
	Move_Up,
	Move_Down,
	Rename,
}

/* Structure_Template_Kind identifies one factory structural template. */
Structure_Template_Kind :: enum u8 {
	Invalid,
	Drawer,
	Source_Block,
	Example_Block,
	Quote_Block,
	Center_Block,
	Comment_Block,
	Export_Block,
	Special_Block,
	Dynamic_Block,
}

/* Structure_Edit_Request binds a complete structural mutation to exact source. */
Structure_Edit_Request :: struct {
	operation_id:       Operation_ID,
	scope:              Scope,
	kind:               Structure_Edit_Kind,
	target_id:          language.Jan_Node_ID,
	rewrite_generation: language.Jan_Rewrite_Generation,
	template:           Structure_Template_Kind,
	name:               string,
	arguments:          string,
	body:               string,
}

/* Structure_Inspection exposes complete, body, selection, and fold ranges. */
Structure_Inspection :: struct {
	target:          Target,
	selection:       language.Jan_Source_Range,
	body:            language.Jan_Source_Range,
	fold_range:      view.Hidden_Range,
	foldable:        bool,
}

/* Structural_Region_Descriptor reports one copied, sorted complete target set. */
Structural_Region_Descriptor :: struct {
	operation_id:   Operation_ID,
	scope:          Scope,
	target_count:   u32,
	retained_bytes: u64,
}

/* Structural_Region owns a validated target set until explicit close. */
Structural_Region :: struct {
	state: rawptr,
}

/* Table_Edit_Kind identifies one non-executing table structure operation. */
Table_Edit_Kind :: enum u8 {
	Invalid,
	Create,
	Convert_Delimited,
	Insert_Row_Before,
	Insert_Row_After,
	Delete_Row,
	Move_Row_Up,
	Move_Row_Down,
	Duplicate_Row,
	Insert_Column_Before,
	Insert_Column_After,
	Delete_Column,
	Move_Column_Left,
	Move_Column_Right,
	Duplicate_Column,
	Insert_Separator_After,
	Delete_Separator,
	Cut_Rectangle,
	Paste_Rectangle,
}

/* Table_Rectangle identifies half-open data-row and column coordinates. */
Table_Rectangle :: struct {
	row_start:    u32,
	row_end:      u32,
	column_start: u32,
	column_end:   u32,
}

/* Table_Edit_Request binds one table mutation to exact source and coordinates. */
Table_Edit_Request :: struct {
	operation_id:       Operation_ID,
	scope:              Scope,
	kind:               Table_Edit_Kind,
	target_id:          language.Jan_Node_ID,
	rewrite_generation: language.Jan_Rewrite_Generation,
	rows:               u32,
	columns:            u32,
	delimiter:          u8,
	rectangle:          Table_Rectangle,
	text:               string,
	cancel_requested:   ^bool,
}

/* Table_Rectangle_Descriptor reports one copied rectangular text selection. */
Table_Rectangle_Descriptor :: struct {
	operation_id:   Operation_ID,
	scope:          Scope,
	table:          Target,
	selection:      Table_Rectangle,
	cell_count:     u32,
	retained_bytes: u64,
}

/* Table_Rectangle_Copy owns copied tabular text until explicit close. */
Table_Rectangle_Copy :: struct {
	state: rawptr,
}

/* Table_Alignment identifies one display-only cell alignment policy. */
Table_Alignment :: enum u8 {
	Invalid,
	Left,
	Center,
	Right,
}

/* Table_Column_Policy controls display width without changing stored cells. */
Table_Column_Policy :: struct {
	width:       u16,
	alignment:   Table_Alignment,
	truncate:    bool,
	group_after: bool,
}

/* Table_Presentation_Request binds display policy to one exact table. */
Table_Presentation_Request :: struct {
	operation_id:     Operation_ID,
	scope:            Scope,
	table_id:         language.Jan_Node_ID,
	columns:          []Table_Column_Policy,
	cancel_requested: ^bool,
}

/* Table_Presentation_Descriptor reports copied display output accounting. */
Table_Presentation_Descriptor :: struct {
	operation_id:    Operation_ID,
	scope:           Scope,
	table:           Target,
	rows:            u32,
	columns:         u32,
	cells:           u32,
	truncated_cells: u32,
	retained_bytes:  u64,
}

/* Table_Presentation owns copied display text until explicit close. */
Table_Presentation :: struct {
	state: rawptr,
}

/* Focused_Table_Cell identifies one exact stored cell editing surface. */
Focused_Table_Cell :: struct {
	target:    Target,
	selection: language.Jan_Source_Range,
	row:       u32,
	column:    u32,
}

/* Table_Formula_Status exposes formula presence without evaluation authority. */
Table_Formula_Status :: struct {
	table:   Target,
	present: bool,
	range:   language.Jan_Source_Range,
}

/* Table_Cell_Edit_Request binds one focused value replacement to exact source. */
Table_Cell_Edit_Request :: struct {
	operation_id:       Operation_ID,
	scope:              Scope,
	cell_id:            language.Jan_Node_ID,
	rewrite_generation: language.Jan_Rewrite_Generation,
	text:               string,
}

/* Rich_Presentation_Generation identifies one immutable derived source projection. */
Rich_Presentation_Generation :: distinct u64

/* Rich_Surface identifies rich-capable and terminal source-fallback projection. */
Rich_Surface :: enum u8 {
	Invalid,
	Rich,
	Terminal_Source,
}

/* Rich_Item_Kind distinguishes semantic source roles from derived display additions. */
Rich_Item_Kind :: enum u8 {
	Invalid,
	Source_Role,
	Composed_Markup,
	Prettified_Entity,
	Visual_Indent,
	Heading_Number,
}

/* Rich_Presentation_Request binds display policy to one exact visible source range. */
Rich_Presentation_Request :: struct {
	operation_id:       Operation_ID,
	generation:         Rich_Presentation_Generation,
	scope:              Scope,
	visible_start:      editor.Byte_Offset,
	visible_end:        editor.Byte_Offset,
	surface:            Rich_Surface,
	compose_markup:     bool,
	prettify_entities:  bool,
	visual_indent_width: u8,
	number_headings:    bool,
	cancel_requested:   ^bool,
}

/* Rich_Presentation_Item maps one exact source range to a role or copied display text. */
Rich_Presentation_Item :: struct {
	kind:          Rich_Item_Kind,
	node_kind:     language.Jan_Node_Kind,
	range:         language.Jan_Source_Range,
	role:          language.Syntax_Role,
	display_offset: u32,
	display_bytes:  u32,
}

/* Rich_Presentation_Descriptor reports immutable projection identity and accounting. */
Rich_Presentation_Descriptor :: struct {
	operation_id:    Operation_ID,
	generation:      Rich_Presentation_Generation,
	scope:           Scope,
	visible_start:   editor.Byte_Offset,
	visible_end:     editor.Byte_Offset,
	surface:         Rich_Surface,
	item_count:      u32,
	source_fallback: bool,
	retained_bytes:  u64,
}

/* Rich_Presentation owns copied items, display text, and terminal fallback until close. */
Rich_Presentation :: struct {
	state: rawptr,
}

/* Footnote_Edit_Kind identifies one same-document source operation. */
Footnote_Edit_Kind :: enum u8 {
	Invalid,
	Create_Definition,
	Normalize_Inline,
	Renumber_Local,
	Move_Definition_Up,
	Move_Definition_Down,
}

/* Footnote_Edit_Request binds one local footnote mutation to exact source. */
Footnote_Edit_Request :: struct {
	operation_id:       Operation_ID,
	scope:              Scope,
	kind:               Footnote_Edit_Kind,
	target_id:          language.Jan_Node_ID,
	rewrite_generation: language.Jan_Rewrite_Generation,
	name:               string,
	text:               string,
}

/* Footnote_Resolution reports one same-document visit destination. */
Footnote_Resolution :: struct {
	source:      Target,
	destination: Target,
	position:    editor.Position,
	named:       bool,
	inline:      bool,
}

/* Preview_Request_ID identifies one asynchronous adapter request; zero is invalid. */
Preview_Request_ID :: distinct u64
/* Preview_Cache_Generation identifies one process-wide derived cache lifetime. */
Preview_Cache_Generation :: distinct u64
/* Preview_Adapter_ID identifies one factory adapter capability. */
Preview_Adapter_ID :: distinct u64

/* Preview_Kind distinguishes the two admitted Stage 2 preview families. */
Preview_Kind :: enum u8 {
	Invalid,
	Latex,
	Image,
}

/* Preview_Status exposes pending, copied, and source-fallback states. */
Preview_Status :: enum u8 {
	Invalid,
	Pending,
	Ready,
	Source_Fallback,
}

/* Preview_Adapter_Handle binds one adapter identity to an exact generation. */
Preview_Adapter_Handle :: struct {
	id:         Preview_Adapter_ID,
	generation: Provider_Generation,
	kind:       Preview_Kind,
	available:  bool,
}

/* Preview_Adapter_Capability reports factory-adapter authority requirements. */
Preview_Adapter_Capability :: struct {
	handle:                      Preview_Adapter_Handle,
	class:                       language.Jan_Availability_Class,
	requires_resource_admission: bool,
}

/* Preview_Request binds one adapter request to exact source and authority state. */
Preview_Request :: struct {
	request_id:         Preview_Request_ID,
	operation_id:       Operation_ID,
	scope:              Scope,
	target_id:          language.Jan_Node_ID,
	range:              language.Jan_Source_Range,
	kind:               Preview_Kind,
	adapter:            Preview_Adapter_Handle,
	resource_generation: u64,
	resource_admitted:  bool,
	surface_supported:  bool,
	cancel_requested:   ^bool,
}

/* Preview_Descriptor reports one immutable request or copied result state. */
Preview_Descriptor :: struct {
	request_id:         Preview_Request_ID,
	operation_id:       Operation_ID,
	scope:              Scope,
	target:             Target,
	kind:               Preview_Kind,
	status:             Preview_Status,
	adapter:            Preview_Adapter_Handle,
	resource_generation: u64,
	result_bytes:       u64,
	source_visible:     bool,
	sequence:           u64,
}

/* Preview_Cache_Descriptor reports bounded process-wide ownership. */
Preview_Cache_Descriptor :: struct {
	generation:     Preview_Cache_Generation,
	entries:        u32,
	active:         u32,
	ready:          u32,
	retained_bytes: u64,
}

/* Preview_Cache owns pending identities and copied results until eviction or close. */
Preview_Cache :: struct {
	state: rawptr,
}

/* Heading_Edit_Kind identifies one exact-revision heading or subtree rewrite. */
Heading_Edit_Kind :: enum u8 {
	Invalid,
	Insert_Before,
	Insert_After,
	Insert_Below,
	Split,
	Promote_Text,
	Promote_Heading,
	Demote_Heading,
	Move_Up,
	Move_Down,
	Clone_Subtree,
	Kill_Subtree,
	Sort_Children,
	Heading_To_List_Item,
	List_Item_To_Heading,
}

/* Heading_Edit_Request binds one structural rewrite to an exact scope and target. */
Heading_Edit_Request :: struct {
	operation_id:      Operation_ID,
	scope:             Scope,
	kind:              Heading_Edit_Kind,
	target_id:         language.Jan_Node_ID,
	rewrite_generation: language.Jan_Rewrite_Generation,
	split_offset:      editor.Byte_Offset,
	level:             u16,
	text:              string,
}

/* Subtree_Copy_Descriptor identifies copied source owned outside the parser analysis. */
Subtree_Copy_Descriptor :: struct {
	operation_id:  Operation_ID,
	scope:         language.Jan_Analysis_Scope,
	target:        Target,
	retained_bytes: u64,
}

/* Subtree_Copy owns copied subtree bytes until explicit close. */
Subtree_Copy :: struct {
	state: rawptr,
}

/* Sparse_Generation identifies one exact derived sparse result. */
Sparse_Generation :: distinct u64

/* Sparse_Predicate_Kind distinguishes structural, textual, and indexed inputs. */
Sparse_Predicate_Kind :: enum u8 {
	Invalid,
	Heading_Level,
	Node_Kind,
	Text_Contains,
	Indexed_Fact,
}

/* Sparse_Predicate is copied before a sparse result becomes observable. */
Sparse_Predicate :: struct {
	kind:          Sparse_Predicate_Kind,
	heading_level: u16,
	node_kind:     language.Jan_Node_Kind,
	index_kind:    language.Jan_Index_Kind,
	text:          string,
}

/* Sparse_View_Request binds one projection to exact analysis and view generations. */
Sparse_View_Request :: struct {
	operation_id:    Operation_ID,
	generation:      Sparse_Generation,
	scope:           Scope,
	predicate:       Sparse_Predicate,
	cancel_requested: ^bool,
}

/* Sparse_Match is one copied heading target with direct or ancestor context. */
Sparse_Match :: struct {
	target:           Target,
	position:         editor.Position,
	direct_match:     bool,
	ancestor_context: bool,
}

/* Sparse_View_Descriptor reports one bounded exact derived projection. */
Sparse_View_Descriptor :: struct {
	operation_id:   Operation_ID,
	generation:     Sparse_Generation,
	scope:          Scope,
	match_count:    u32,
	direct_matches: u32,
	retained_bytes: u64,
}

/* Sparse_View owns copied predicate and match state until refresh or close. */
Sparse_View :: struct {
	state: rawptr,
}

/* Target_Kind distinguishes copied structural targets without retaining parser nodes. */
Target_Kind :: enum u8 {
	Invalid,
	Document,
	Heading,
	Subtree,
	Structural_Element,
	List_Item,
	Drawer,
	Block,
	Table,
	Table_Row,
	Table_Cell,
	Footnote,
	Region,
}

/* Capability is the fixed Stage 2 availability inventory. */
Capability :: enum u8 {
	Invalid,
	Visibility,
	Structural_Editing,
	List_Editing,
	Table_Editing,
	Contextual_Editing,
}

/* Visibility_Kind distinguishes subtree-local and complete-document state. */
Visibility_Kind :: enum u8 {
	Invalid,
	Local,
	Global,
	Drawer,
}

/* Visibility_State is the closed Stage 2 visibility transition vocabulary. */
Visibility_State :: enum u8 {
	Invalid,
	Heading_Only,
	Direct_Children,
	Complete_Subtree,
	Overview,
	Contents,
	Show_All,
	Drawer_Visible,
	Drawer_Folded,
}

/* Failure_Code classifies expected Stage 2 rejection without changing source or view state. */
Failure_Code :: enum u8 {
	None,
	Invalid_Scope,
	Invalid_Target,
	Invalid_Visibility,
	Stale,
	Limited,
	Cancelled,
	Allocation_Failed,
	Malformed,
	View_Failed,
	Unavailable,
	Hidden_Target,
}

/* Navigation_Kind identifies one deterministic structural destination rule. */
Navigation_Kind :: enum u8 {
	Invalid,
	Next_Visible_Heading,
	Previous_Visible_Heading,
	Next_Same_Level_Heading,
	Previous_Same_Level_Heading,
	Parent_Heading,
	First_Child_Heading,
	Subtree_Start,
	Subtree_End,
	Next_Structural_Element,
	Previous_Structural_Element,
	Next_List_Item,
	Previous_List_Item,
	Next_Table_Row,
	Previous_Table_Row,
	Next_Table_Cell,
	Previous_Table_Cell,
	Next_Drawer,
	Previous_Drawer,
	Next_Block,
	Previous_Block,
	Next_Footnote,
	Previous_Footnote,
}

/* Navigation_Status distinguishes a destination from a checked no-op. */
Navigation_Status :: enum u8 {
	Invalid,
	Resolved,
	No_Target,
}

/* Navigation_Request binds one structural lookup to exact copied state. */
Navigation_Request :: struct {
	scope:         Scope,
	kind:          Navigation_Kind,
	point:         editor.Position,
	hidden_ranges: []view.Hidden_Range,
}

/* Navigation_Result is one copied canonical destination or inspectable no-op. */
Navigation_Result :: struct {
	status:     Navigation_Status,
	kind:       Navigation_Kind,
	target:     Target,
	position:   editor.Position,
	candidates: u32,
}

/* Scope binds one operation to exact analysis, view, and configuration generations. */
Scope :: struct {
	analysis:                 language.Jan_Analysis_Scope,
	view_handle:              view.View_Handle,
	view_state_generation:    u64,
	visibility_generation:    view.Visibility_Generation,
	configuration_generation: Configuration_Generation,
	provider_generation:      Provider_Generation,
}

/* Target is one copied exact-revision semantic location. */
Target :: struct {
	kind:    Target_Kind,
	node_id: language.Jan_Node_ID,
	range:   language.Jan_Source_Range,
}

/* Limits is the complete accepted Stage 2 native resource policy. */
Limits :: struct {
	hidden_ranges:            u32,
	sparse_matches:           u32,
	semantic_targets:         u32,
	table_cells:              u32,
	rewrite_splices:          u32,
	completion_candidates:    u16,
	completion_bytes:         u64,
	templates:                 u16,
	completion_sources:       u16,
	configuration_bytes:      u64,
	active_previews_per_view: u8,
	preview_result_bytes:     u64,
	preview_cache_bytes:      u64,
	cancellation_entries:     u32,
}

/* DEFAULT_LIMITS is the accepted Stage 2 resource policy. */
DEFAULT_LIMITS :: Limits {
	hidden_ranges = MAX_HIDDEN_RANGES,
	sparse_matches = MAX_SPARSE_MATCHES,
	semantic_targets = MAX_SEMANTIC_TARGETS,
	table_cells = MAX_TABLE_CELLS,
	rewrite_splices = language.MAX_JAN_REWRITE_SPLICES,
	completion_candidates = MAX_COMPLETION_CANDIDATES,
	completion_bytes = MAX_COMPLETION_BYTES,
	templates = MAX_TEMPLATES,
	completion_sources = MAX_COMPLETION_SOURCES,
	configuration_bytes = MAX_CONFIGURATION_BYTES,
	active_previews_per_view = MAX_ACTIVE_PREVIEWS_PER_VIEW,
	preview_result_bytes = MAX_PREVIEW_RESULT_BYTES,
	preview_cache_bytes = MAX_PREVIEW_CACHE_BYTES,
	cancellation_entries = CANCELLATION_CHECK_ENTRIES,
}

/* Availability_Record reports final base-artifact availability for one Stage 2 family. */
Availability_Record :: struct {
	capability: Capability,
	class:      language.Jan_Availability_Class,
	available:  bool,
}

/* Failure records one bounded expected Stage 2 rejection and its underlying owner. */
Failure :: struct {
	operation:    Operation,
	code:         Failure_Code,
	scope:        Scope,
	limit:        u64,
	actual:       u64,
	view_failure: view.Failure_Context,
}

/* Visibility_Transition_Request describes one deterministic replacement candidate. */
Visibility_Transition_Request :: struct {
	operation_id: Operation_ID,
	scope:        Scope,
	kind:         Visibility_Kind,
	current:      Visibility_State,
	selected:     Visibility_State,
	ranges:       []view.Hidden_Range,
}

/* Outline_Visibility_Request selects one derived local, global, or startup state. */
Outline_Visibility_Request :: struct {
	operation_id:   Operation_ID,
	scope:          Scope,
	kind:           Visibility_Kind,
	current:        Visibility_State,
	selected:       Visibility_State,
	heading_id:     language.Jan_Node_ID,
	retained_ranges: []view.Hidden_Range,
}

/* Drawer_Visibility_Request toggles one exact complete drawer body in one view. */
Drawer_Visibility_Request :: struct {
	operation_id: Operation_ID,
	scope:        Scope,
	target_id:    language.Jan_Node_ID,
}

/* Visibility_Transition_Descriptor is copied immutable transition inspection. */
Visibility_Transition_Descriptor :: struct {
	operation_id: Operation_ID,
	scope:        Scope,
	kind:         Visibility_Kind,
	previous:     Visibility_State,
	next:         Visibility_State,
	range_count:  u32,
	retained_bytes: u64,
}

/* Visibility_Transition owns copied ranges until publication or explicit close. */
Visibility_Transition :: struct {
	state: rawptr,
}

/* Visibility_Result reports one published deterministic transition. */
Visibility_Result :: struct {
	descriptor: Visibility_Transition_Descriptor,
	view:       view.Visibility_Update,
}

/* limits_are_valid checks every selected value against the accepted Stage 2 ceiling. */
limits_are_valid :: proc(limits: Limits) -> bool {
	return limits.hidden_ranges > 0 && limits.hidden_ranges <= MAX_HIDDEN_RANGES &&
	       limits.hidden_ranges <= view.MAX_HIDDEN_RANGES &&
	       limits.sparse_matches > 0 && limits.sparse_matches <= MAX_SPARSE_MATCHES &&
	       limits.semantic_targets > 0 && limits.semantic_targets <= MAX_SEMANTIC_TARGETS &&
	       limits.table_cells > 0 && limits.table_cells <= MAX_TABLE_CELLS &&
	       limits.rewrite_splices > 0 &&
	       limits.rewrite_splices <= language.MAX_JAN_REWRITE_SPLICES &&
	       limits.completion_candidates > 0 &&
	       limits.completion_candidates <= MAX_COMPLETION_CANDIDATES &&
	       limits.completion_bytes > 0 && limits.completion_bytes <= MAX_COMPLETION_BYTES &&
	       limits.templates > 0 && limits.templates <= MAX_TEMPLATES &&
	       limits.completion_sources > 0 &&
	       limits.completion_sources <= MAX_COMPLETION_SOURCES &&
	       limits.configuration_bytes > 0 &&
	       limits.configuration_bytes <= MAX_CONFIGURATION_BYTES &&
	       limits.active_previews_per_view > 0 &&
	       limits.active_previews_per_view <= MAX_ACTIVE_PREVIEWS_PER_VIEW &&
	       limits.preview_result_bytes > 0 &&
	       limits.preview_result_bytes <= MAX_PREVIEW_RESULT_BYTES &&
	       limits.preview_cache_bytes >= limits.preview_result_bytes &&
	       limits.preview_cache_bytes <= MAX_PREVIEW_CACHE_BYTES &&
	       limits.cancellation_entries > 0 &&
	       limits.cancellation_entries <= CANCELLATION_CHECK_ENTRIES
}

/* scope_is_valid checks stable analysis, view, configuration, and provider identities. */
scope_is_valid :: proc(scope: Scope) -> bool {
	return language.jan_analysis_scope_is_valid(scope.analysis) &&
	       scope.view_handle.registry_id != view.Registry_ID(0) &&
	       scope.view_handle.view_id != view.View_ID(0) &&
	       scope.view_handle.generation != 0 &&
	       scope.view_state_generation != 0 &&
	       scope.configuration_generation != Configuration_Generation(0) &&
	       scope.provider_generation != Provider_Generation(0)
}

/* target_is_valid checks one copied target against its exact operation scope. */
target_is_valid :: proc(target: Target, scope: Scope, source_bytes: u64) -> bool {
	return scope_is_valid(scope) && target.kind > .Invalid && target.kind <= .Region &&
	       target.range.scope == scope.analysis &&
	       language.jan_source_range_is_valid(target.range, source_bytes) &&
	       (target.kind == .Document || target.kind == .Region ||
	        target.node_id != language.Jan_Node_ID(0))
}

/* structured_editing_availability returns the five operational Stage 2 families. */
structured_editing_availability :: proc() -> [5]Availability_Record {
	return {
		{capability = .Visibility, class = .Factory_Native, available = true},
		{capability = .Structural_Editing, class = .Factory_Native, available = true},
		{capability = .List_Editing, class = .Factory_Native, available = true},
		{capability = .Table_Editing, class = .Factory_Native, available = true},
		{capability = .Contextual_Editing, class = .Factory_Native, available = true},
	}
}
