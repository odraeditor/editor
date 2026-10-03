// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package ui owns bounded logical UI publication independently of semantic
// models and physical frontend render surfaces.
package ui

/* KIBIBYTE is the binary byte unit used by UI resource policy. */
KIBIBYTE :: u64(1_024)
/* MEBIBYTE is 1,024 kibibytes. */
MEBIBYTE :: u64(1_024) * KIBIBYTE

/* MAX_LIVE_SURFACES bounds visible logical containment records. */
MAX_LIVE_SURFACES :: 128
/* MAX_LIVE_VIEWS bounds visual views in one published root. */
MAX_LIVE_VIEWS :: 128
/* MAX_SPLIT_DEPTH bounds root-to-surface composition nesting. */
MAX_SPLIT_DEPTH :: 32
/* MAX_COMPOSITION_NODES bounds one complete binary composition. */
MAX_COMPOSITION_NODES :: MAX_LIVE_SURFACES * 2 - 1
/* MAX_STATUS_REGIONS admits one attached region per surface and one root edge. */
MAX_STATUS_REGIONS :: MAX_LIVE_SURFACES + 1
/* MAX_LIVE_POPUPS admits one temporary floating surface in the initial root. */
MAX_LIVE_POPUPS :: 1
/* MAX_POPUP_PLACEMENTS bounds one deterministic placement preference order. */
MAX_POPUP_PLACEMENTS :: 4
/* MAX_POPUP_CONTENT_BYTES bounds one popup's admitted projected content. */
MAX_POPUP_CONTENT_BYTES :: 64 * KIBIBYTE
/* MAX_POPUP_ACTIONS bounds checked consumer actions exposed by one popup. */
MAX_POPUP_ACTIONS :: 16
/* MAX_LIST_ITEMS bounds copied items in one list projection. */
MAX_LIST_ITEMS :: 4_096
/* MAX_TREE_NODES bounds copied nodes in one tree projection. */
MAX_TREE_NODES :: 4_096
/* MAX_TREE_ICON_BYTES bounds one copied theme-independent text icon. */
MAX_TREE_ICON_BYTES :: 16
/* MAX_LIST_ITEM_STYLE_SPANS bounds semantic style changes within one list row. */
MAX_LIST_ITEM_STYLE_SPANS :: 16
/* MAX_STATUS_STYLE_SPANS bounds semantic style changes within one status row. */
MAX_STATUS_STYLE_SPANS :: 64
/* MAX_STATUS_SEGMENTS bounds semantic segment metadata in one status row. */
MAX_STATUS_SEGMENTS :: 32
/* MAX_STATUS_INSPECTION_BYTES bounds copied inspection text for one segment. */
MAX_STATUS_INSPECTION_BYTES :: 4 * KIBIBYTE
/* MAX_TEXT_GUTTER_ROWS bounds one operating text-view Gutter projection. */
MAX_TEXT_GUTTER_ROWS :: 80
/* MAX_INPUT_BYTES bounds one copied transient input value. */
MAX_INPUT_BYTES :: 4 * KIBIBYTE
/* MAX_FIXED_CHOICES bounds named alternatives in one input projection. */
MAX_FIXED_CHOICES :: 64
/* MAX_PROJECTION_BYTES bounds retained copied projection data. */
MAX_PROJECTION_BYTES :: 32 * MEBIBYTE
/* MAX_STYLES bounds the complete semantic role vocabulary in one generation. */
MAX_STYLES :: 66
/* MAX_DECORATIONS bounds anchored visual annotations in one generation. */
MAX_DECORATIONS :: 65_536
/* MAX_COMPACT_REGION_BYTES bounds copied status and diagnostic content. */
MAX_COMPACT_REGION_BYTES :: 64 * KIBIBYTE
/* MAX_EVENT_SUBSCRIPTIONS bounds active logical UI event interests. */
MAX_EVENT_SUBSCRIPTIONS :: 256
/* MAX_QUEUED_EVENTS bounds deferred logical UI input and lifecycle events. */
MAX_QUEUED_EVENTS :: 256
/* MAX_CALLBACK_DEPTH bounds nested package-owned UI calls. */
MAX_CALLBACK_DEPTH :: 64
/* MAX_DEFERRED_WORK bounds callback-requested work awaiting revalidation. */
MAX_DEFERRED_WORK :: 256
/* MAX_SNAPSHOT_BYTES bounds one copied frontend-independent UI snapshot. */
MAX_SNAPSHOT_BYTES :: 8 * MEBIBYTE
/* MAX_TEMPORARY_BYTES bounds one prepare, validation, or snapshot operation. */
MAX_TEMPORARY_BYTES :: 64 * MEBIBYTE
/* MAX_DIAGNOSTIC_BYTES bounds one precise UI failure explanation. */
MAX_DIAGNOSTIC_BYTES :: 4 * KIBIBYTE
/* MAX_GEOMETRY_WORK bounds one complete composition materialization. */
MAX_GEOMETRY_WORK :: u64(1_048_576)
/* MAX_HIT_TEST_DEPTH bounds one popup-and-surface stacking search. */
MAX_HIT_TEST_DEPTH :: u64(MAX_LIVE_POPUPS + MAX_LIVE_SURFACES)
/* MAX_HIT_TEST_WORK bounds one complete semantic pointer hit search. */
MAX_HIT_TEST_WORK :: u64(MAX_LIVE_POPUPS) +
	u64(MAX_LIVE_SURFACES) * u64(MAX_STATUS_REGIONS + 1) +
	u64(MAX_LIVE_VIEWS)

/* Registry_ID identifies one logical UI registry; zero is invalid. */
Registry_ID :: distinct u32
/* Owner_ID identifies one lifecycle owner outside the UI registry. */
Owner_ID :: distinct u64
/* Model_ID identifies semantic state without granting mutation authority. */
Model_ID :: distinct u64
/* Model_Generation identifies one exact semantic state observation. */
Model_Generation :: distinct u64
/* List_Item_ID identifies one semantic item within one exact list projection. */
List_Item_ID :: distinct u64
/* List_Action_ID identifies one source-owned semantic action without a callback. */
List_Action_ID :: distinct u64
/* Tree_Node_ID identifies one semantic node within one exact tree projection. */
Tree_Node_ID :: distinct u64
/* Input_Choice_ID identifies one semantic fixed choice within one input projection. */
Input_Choice_ID :: distinct u64
/* Root_Generation identifies one atomically published logical UI root. */
Root_Generation :: distinct u64
/* Object_ID identifies one logical UI object for the registry lifetime. */
Object_ID :: distinct u64
/* Renderer_Profile_ID identifies one immutable physical frontend capability set. */
Renderer_Profile_ID :: distinct u64
/* Popup_ID identifies one semantic popup across root replacements. */
Popup_ID :: distinct u64
/* Popup_Generation identifies one exact popup proposal. */
Popup_Generation :: distinct u64

/* Object_Handle is a checked non-pointer identity for one published UI slot. */
Object_Handle :: struct {
	registry_id:    Registry_ID,
	object_id:      Object_ID,
	root_generation: Root_Generation,
	slot:           u32,
	slot_generation: u32,
}

/* Root_Handle identifies one exact atomically published UI root. */
Root_Handle :: struct {
	registry_id: Registry_ID,
	generation:  Root_Generation,
}

/* Visual_Kind is the initial current-consumer-driven visual primitive set. */
Visual_Kind :: enum u8 {
	Invalid,
	Text_View,
	Terminal_View,
	List_View,
	Tree_View,
	Input,
}

/* Composition_Kind is the initial logical UI composition primitive set. */
Composition_Kind :: enum u8 {
	Invalid,
	Surface,
	Split,
	Panel,
}

/* Split_Orientation names the spatial relationship between two children. */
Split_Orientation :: enum u8 {
	Invalid,
	Above_Below,
	Left_Right,
}

/* Panel_Edge identifies the edge occupied by one persistent auxiliary panel. */
Panel_Edge :: enum u8 {
	Invalid,
	Left,
	Right,
	Top,
	Bottom,
}

/* Popup_Anchor_Kind identifies the checked evidence used for later placement. */
Popup_Anchor_Kind :: enum u8 {
	Invalid,
	Cursor,
	Logical_Text,
	Gutter_Marker,
	Surface,
	Backend_Coordinates,
}

/* Popup_Placement names one owner-ordered anchor-relative preference. */
Popup_Placement :: enum u8 {
	Invalid,
	Above,
	Below,
	Before,
	After,
}

/* Popup_Behavior distinguishes read-only information from admitted interaction. */
Popup_Behavior :: enum u8 {
	Invalid,
	Informational,
	Interactive,
}

/* Popup_Input_Policy preserves the active root's one focus truth. */
Popup_Input_Policy :: enum u8 {
	Invalid,
	Preserve_Source_Focus,
	Transient_Capture,
	Transfer_Focus,
}

/* Popup_Clipping_Policy declares how bounded content handles insufficient extent. */
Popup_Clipping_Policy :: enum u8 {
	Invalid,
	Reject,
	Clip,
	Scroll,
	Wrap,
}

/* Popup_Fallback_Policy selects the shared non-floating degradation path. */
Popup_Fallback_Policy :: enum u8 {
	Invalid,
	Reject,
	Compact_Feedback,
}

/* Popup_Geometry_State records placement or the selected non-floating outcome. */
Popup_Geometry_State :: enum u8 {
	Invalid,
	Placed,
	Fallback,
	Rejected,
}

/* Popup_Dismissal_Cause names owner-admitted lifecycle invalidation evidence. */
Popup_Dismissal_Cause :: enum u16 {
	Explicit_Cancel,
	Action_Completion,
	Owner_Cancellation,
	Owner_Teardown,
	Anchor_Invalidation,
	Source_Closure,
	Generation_Replacement,
	Focus_Loss,
	Cursor_Movement,
	Viewport_Movement,
	Pointer_Departure,
}

/* Popup_Dismissal_Policy is the bounded set of causes admitted by one owner. */
Popup_Dismissal_Policy :: bit_set[Popup_Dismissal_Cause; u16]

/* Selection_Owner preserves whether list selection belongs to model or view. */
Selection_Owner :: enum u8 {
	None,
	Model,
	View,
}

/* List_Mark copies the delivered mark semantics used by current list consumers. */
List_Mark :: enum u8 {
	None,
	Save,
	Kill,
}

/* Status_Placement distinguishes surface-attached from root-edge regions. */
Status_Placement :: enum u8 {
	Invalid,
	Attached,
	Root_Edge,
}

/* Style_Role is the complete initial semantic role vocabulary. */
Style_Role :: enum u8 {
	Invalid,
	Text_Normal,
	Text_Region,
	Text_Search_Current,
	List_Normal,
	List_Current,
	List_Mark_Save,
	List_Mark_Kill,
	Status_Normal,
	Status_Active,
	Diagnostic_Normal,
	Diagnostic_Rejected,
	Syntax_Attribute,
	Syntax_Boolean,
	Syntax_Comment,
	Syntax_Constant,
	Syntax_Constructor,
	Syntax_Function,
	Syntax_Function_Builtin,
	Syntax_Keyword,
	Syntax_Label,
	Syntax_Number,
	Syntax_Operator,
	Syntax_Punctuation,
	Syntax_String,
	Syntax_Type,
	Syntax_Variable,
	Syntax_Variable_Parameter,
	Diagnostic_Error,
	Diagnostic_Warning,
	Diagnostic_Information,
	Diagnostic_Hint,
	List_Emphasis,
	Filesystem_Directory,
	Filesystem_Permission_Read,
	Filesystem_Permission_Write,
	Filesystem_Permission_Execute,
	Filesystem_Metadata,
	Status_Safety,
	Status_Identity,
	Status_Position,
	Status_Alert,
	Status_Workspace,
	Status_Project,
	Status_Editing_Context,
	Tree_Project,
	Tree_Directory,
	Tree_Directory_Special,
	Tree_File,
	Tree_File_Source,
	Tree_File_Documentation,
	Tree_File_Configuration,
	Tree_File_Version_Control,
	Tree_Hierarchy,
	Tree_Inactive,
	Tree_Loading,
	Tree_Failure,
	Tree_Destructive,
	Gutter_Background,
	Gutter_Line_Number,
	Gutter_Line_Number_Current,
	Gutter_Separator,
	Popup_Background,
	Popup_Content,
	Popup_Border,
	Popup_Diagnostic,
	Popup_Unavailable,
}

/* Tree_Icon_Role identifies one frontend-lowered tree resource icon. */
Tree_Icon_Role :: enum u8 {
	Invalid,
	Project,
	Directory_Open,
	Directory_Closed,
	Directory_Special_Open,
	Directory_Special_Closed,
	File,
	File_Source,
	File_Documentation,
	File_Configuration,
	File_Version_Control,
	Failure,
}

/* List_Icon_Role identifies one frontend-lowered semantic list-item icon. */
List_Icon_Role :: enum u8 {
	Invalid,
	Textual,
	Callable,
	Construct,
	Value,
	Type,
	Module,
	Field,
	Keyword,
}

/* Change_Review_Kind identifies provider-neutral staged operation presentation. */
Change_Review_Kind :: enum u8 {
	Invalid,
	Rename,
	Move,
	Delete,
	Conflict,
}

/* Style_Attribute names terminal-independent effects admitted initially. */
Style_Attribute :: enum u8 {
	Bold,
	Dim,
	Underline,
	Reverse,
	Italic,
	Blink,
	Strikethrough,
	Overline,
}

/* Style_Attributes is the bounded set of semantic visual effects. */
Style_Attributes :: bit_set[Style_Attribute; u8]

/* SRGB_Color is one frontend-independent eight-bit sRGB color. */
SRGB_Color :: struct {
	red:   u8,
	green: u8,
	blue:  u8,
}

/* Optional_SRGB_Color canonically represents inheritance or one explicit color. */
Optional_SRGB_Color :: struct {
	present: bool,
	color:   SRGB_Color,
}

/* Renderer_Color_Capability selects one deterministic physical color profile. */
Renderer_Color_Capability :: enum u8 {
	Monochrome,
	Basic_16,
	Indexed_256,
	True_Color,
}

/* Decoration_Kind identifies initial anchored presentation without model ownership. */
Decoration_Kind :: enum u8 {
	Invalid,
	Text_Range,
	List_Mark,
	Diagnostic,
}

/* Cursor_Kind identifies visual cursor requirements of text and input views. */
Cursor_Kind :: enum u8 {
	Invalid,
	Hidden,
	Text,
	Input,
}

/* Text_Presentation_Ownership preserves the delivered editor-view lifetime owner. */
Text_Presentation_Ownership :: enum u8 {
	Invalid,
	Retained_Primary,
	Additional,
}

/* Text_Search_Status copies the visible incremental-search state of one text view. */
Text_Search_Status :: enum u8 {
	Inactive,
	Active,
	Failing,
	Pending,
	Wrapped,
}

/* Text_View_Source identifies one exact delivered editor-view generation. */
Text_View_Source :: struct {
	registry_id:      u32,
	view_id:          u64,
	view_generation:  u32,
	state_generation: u64,
	selection_generation: u64,
}

/* Text_Search_Descriptor copies the current visible search range without query ownership. */
Text_Search_Descriptor :: struct {
	present:                bool,
	interaction_generation: u64,
	source_revision:        u64,
	status:                 Text_Search_Status,
	match_count:            u32,
	has_current:            bool,
	current_start:          u64,
	current_end:            u64,
}

/* Text_Gutter_Row_Definition borrows one composed visible Gutter row. */
Text_Gutter_Row_Definition :: struct {
	viewport_row:        u32,
	logical_line:        u64,
	left_text:           string,
	right_text:          string,
	left_cells:          u16,
	right_cells:         u16,
	left_separator_bytes: u8,
	right_separator_bytes: u8,
	left_style_role:     Style_Role,
	right_style_role:    Style_Role,
	current:             bool,
}

/* Text_Gutter_Row_Descriptor owns checked offsets into compact UI content. */
Text_Gutter_Row_Descriptor :: struct {
	viewport_row:        u32,
	logical_line:        u64,
	left_offset:         u32,
	left_bytes:          u16,
	left_cells:          u16,
	right_offset:        u32,
	right_bytes:         u16,
	right_cells:         u16,
	left_separator_bytes: u8,
	right_separator_bytes: u8,
	left_style_role:     Style_Role,
	right_style_role:    Style_Role,
	current:             bool,
}

/* Text_Gutter_State copies one exact Gutter generation into a TextView. */
Text_Gutter_State :: struct {
	present:       bool,
	generation:    u64,
	left_cells:    u16,
	right_cells:   u16,
	text_cells:    u32,
	rows:          [MAX_TEXT_GUTTER_ROWS]Text_Gutter_Row_Descriptor,
	row_count:     u8,
}

/* Text_Cursor_Shape names frontend-independent editable-text cursor intent. */
Text_Cursor_Shape :: enum u8 {
	Default,
	Block,
	Bar,
	Underline,
}

/* Text_View_State copies one exact revisioned editor-view presentation generation. */
Text_View_State :: struct {
	present:                    bool,
	source:                     Text_View_Source,
	buffer_id:                  u64,
	revision:                   u64,
	source_text_bytes:          u64,
	stored_point:               u64,
	effective_point:            u64,
	mark_present:               bool,
	mark:                       u64,
	region_active:              bool,
	region_rectangular:         bool,
	viewport_origin:            u64,
	horizontal_display_column:  u32,
	desired_display_column:     u32,
	tab_width:                  u16,
	display_profile_id:         u64,
	presentation_ownership:     Text_Presentation_Ownership,
	cursor_shape:               Text_Cursor_Shape,
	search:                     Text_Search_Descriptor,
	gutter:                     Text_Gutter_State,
}

/* Layout_Geometry_State copies the delivered pane materialization state. */
Layout_Geometry_State :: enum u8 {
	Invalid,
	Operating,
	Semantic,
	Insufficient,
}

/* Pane_Dedication copies the delivered pane reuse policy. */
Pane_Dedication :: enum u8 {
	None,
	Soft,
	Hard,
}

/* Cell_Rect copies one delivered integer terminal rectangle. */
Cell_Rect :: struct {
	row:    i32,
	column: i32,
	height: i32,
	width:  i32,
}

/* Hit_Kind identifies one semantic coordinate target in an immutable UI root. */
Hit_Kind :: enum u8 {
	Invalid,
	Popup,
	Surface,
	Content,
	Gutter,
	Status,
	Separator,
	Background,
}

/* Hit_Request names one normalized root-relative cell against an exact UI root. */
Hit_Request :: struct {
	root:   Root_Handle,
	row:    i32,
	column: i32,
}

/* Semantic_Item_Kind identifies one model-owned row resolved by hit testing. */
Semantic_Item_Kind :: enum u8 {
	Invalid,
	List,
	Tree,
}

/* Semantic_Item_Hit copies exact model and projection evidence without mutation authority. */
Semantic_Item_Hit :: struct {
	kind:                    Semantic_Item_Kind,
	projection:              Object_Handle,
	model:                   Model_Reference,
	item_id:                 u64,
	action:                  List_Action_Reference,
	presentation_generation: u64,
	projection_index:        u32,
}

/* Hit_Result copies semantic identities and geometry without retaining renderer state. */
Hit_Result :: struct {
	root:         Root_Handle,
	kind:         Hit_Kind,
	row:          i32,
	column:       i32,
	local_row:    i32,
	local_column: i32,
	geometry:     Cell_Rect,
	popup:        Object_Handle,
	surface:      Object_Handle,
	view:         Object_Handle,
	status:       Object_Handle,
	pane:         Pane_Surface_State,
	item:         Semantic_Item_Hit,
	focusable:    bool,
}

/* Popup_Anchor_Reference retains semantic evidence, never derived cell authority. */
Popup_Anchor_Reference :: struct {
	kind:              Popup_Anchor_Kind,
	source_surface:    Object_Handle,
	owner_id:          Owner_ID,
	source_id:         u64,
	source_generation: u64,
	start:             u64,
	end:               u64,
	presentation_generation: u64,
	viewport_row:      u32,
	viewport_column:   u32,
	height_rows:       u16,
	width_columns:     u16,
}

/* Popup_Anchor_Resolution is one checked root-relative placement target. */
Popup_Anchor_Resolution :: struct {
	root:              Root_Handle,
	popup:             Object_Handle,
	kind:              Popup_Anchor_Kind,
	source_surface:    Object_Handle,
	source_view:       Object_Handle,
	owner_id:          Owner_ID,
	source_id:         u64,
	source_generation: u64,
	geometry:          Cell_Rect,
}

/* Popup_Dimension_Bounds declares coherent minimum, preferred, and maximum size. */
Popup_Dimension_Bounds :: struct {
	minimum_rows:      u16,
	minimum_columns:   u16,
	preferred_rows:    u16,
	preferred_columns: u16,
	maximum_rows:      u16,
	maximum_columns:   u16,
}

/* Popup_Geometry is one deterministic root-relative overlap result. */
Popup_Geometry :: struct {
	state:              Popup_Geometry_State,
	placement:          Popup_Placement,
	anchor:             Cell_Rect,
	outer:              Cell_Rect,
	content:            Cell_Rect,
	clipped:            bool,
	attempts:           u8,
	z_order:            u8,
	obscures_underlay:  bool,
}

/* Popup_Descriptor copies one complete checked temporary-surface proposal. */
Popup_Descriptor :: struct {
	handle:             Object_Handle,
	id:                 Popup_ID,
	generation:         Popup_Generation,
	owner_id:           Owner_ID,
	owner_generation:   u64,
	anchor:             Popup_Anchor_Reference,
	content_surface:    Object_Handle,
	content_generation: u64,
	placements:         [MAX_POPUP_PLACEMENTS]Popup_Placement,
	placement_count:    u8,
	bounds:             Popup_Dimension_Bounds,
	margin_rows:        u8,
	margin_columns:     u8,
	padding_rows:       u8,
	padding_columns:    u8,
	border:             bool,
	clipping:           Popup_Clipping_Policy,
	behavior:           Popup_Behavior,
	input_policy:       Popup_Input_Policy,
	dismissal:          Popup_Dismissal_Policy,
	fallback:           Popup_Fallback_Policy,
	required_profile:   Renderer_Profile_ID,
	presentation_profile: Presentation_Profile_Record,
	content_bytes:      u32,
	action_count:       u16,
	geometry:           Popup_Geometry,
}

/* Pane_Surface_State binds one logical surface to one exact delivered pane leaf. */
Pane_Surface_State :: struct {
	present:          bool,
	layout_owner_id:  u64,
	layout_id:        u64,
	layout_generation: u64,
	node_id:          u64,
	node_generation:  u32,
	pane_id:          u64,
	pane_slot:        u16,
	pane_generation:  u32,
	buffer_id:        u64,
	entry_id:         u64,
	entry_generation: u32,
	dedication:       Pane_Dedication,
	history_count:    u16,
	history_generation: u64,
	outer:            Cell_Rect,
	content:          Cell_Rect,
	status:           Cell_Rect,
	separator:        Cell_Rect,
	active:           bool,
	mru_rank:         u16,
}

/* Layout_Node_State copies one exact delivered pane or partition node identity. */
Layout_Node_State :: struct {
	present:           bool,
	layout_owner_id:   u64,
	layout_id:         u64,
	layout_generation: u64,
	node_id:           u64,
	node_generation:   u32,
	parent_id:         u64,
	depth:             u16,
	geometry_state:    Layout_Geometry_State,
	geometry_rows:     i32,
	geometry_columns:  i32,
	reserved_rows:     i32,
	reserved_columns:  i32,
	outer:             Cell_Rect,
	separator:         Cell_Rect,
}

/* Model_Reference observes semantic state without transferring its ownership. */
Model_Reference :: struct {
	owner_id:  Owner_ID,
	model_id:  Model_ID,
	generation: Model_Generation,
}

/* List_Action_Reference identifies one exact source-owned semantic action. */
List_Action_Reference :: struct {
	owner_id:  Owner_ID,
	action_id: List_Action_ID,
	generation: u64,
}

/* List_View_Position is the bounded presentation state owned by one list view. */
List_View_Position :: struct {
	presentation_generation: u64,
	selection_owner:         Selection_Owner,
	current_item:            i32,
	first_visible_item:      u32,
	viewport_items:          u32,
}

/* List_View_State binds one list view to copied items and presentation state. */
List_View_State :: struct {
	present:     bool,
	mark_lane:   bool,
	item_offset: u32,
	item_count:  u32,
	position:    List_View_Position,
}

/* List_Projection_Request declares one exact model and list presentation generation. */
List_Projection_Request :: struct {
	model:     Model_Reference,
	position:  List_View_Position,
	read_only: bool,
	mark_lane: bool,
}

/* List_Item_Style_Span applies one semantic role to a checked UTF-8 byte range. */
List_Item_Style_Span :: struct {
	start_byte: u32,
	end_byte:   u32,
	style_role: Style_Role,
}

/* List_Item_Definition borrows one item while preparing a checked list projection. */
List_Item_Definition :: struct {
	id:             List_Item_ID,
	text:           string,
	icon_role:      List_Icon_Role,
	icon_style_role: Style_Role,
	action:         List_Action_Reference,
	mark:           List_Mark,
	passive:        bool,
	emphasis_bytes: u32,
	emphasis_style: Style_Role,
	style_spans:      [MAX_LIST_ITEM_STYLE_SPANS]List_Item_Style_Span,
	style_span_count: u8,
}

/* List_Item_Descriptor owns one copied item record in a published generation. */
List_Item_Descriptor :: struct {
	projection:    Object_Handle,
	id:            List_Item_ID,
	text_offset:   u64,
	text_bytes:    u32,
	icon_role:     List_Icon_Role,
	icon_style_role: Style_Role,
	action:        List_Action_Reference,
	mark:          List_Mark,
	passive:       bool,
	emphasis_bytes: u32,
	emphasis_style: Style_Role,
	style_spans:      [MAX_LIST_ITEM_STYLE_SPANS]List_Item_Style_Span,
	style_span_count: u8,
}

/* Tree_View_State binds one tree view to a flat visible preorder projection. */
Tree_View_State :: struct {
	present:     bool,
	node_offset: u32,
	node_count:  u32,
	position:    List_View_Position,
}

/* Tree_Projection_Request declares one exact tree presentation generation. */
Tree_Projection_Request :: struct {
	model:     Model_Reference,
	position:  List_View_Position,
	read_only: bool,
}

/* Tree_Node_Definition borrows one visible semantic node during projection. */
Tree_Node_Definition :: struct {
	id:               Tree_Node_ID,
	parent:           Tree_Node_ID,
	text:             string,
	icon:             string,
	icon_role:        Tree_Icon_Role,
	icon_style_role:  Style_Role,
	depth:            u16,
	indent_depth:     u16,
	expandable:       bool,
	expanded:         bool,
	action:           List_Action_Reference,
	style_spans:      [MAX_LIST_ITEM_STYLE_SPANS]List_Item_Style_Span,
	style_span_count: u8,
}

/* Tree_Node_Descriptor owns one copied visible node in a published generation. */
Tree_Node_Descriptor :: struct {
	projection:       Object_Handle,
	id:               Tree_Node_ID,
	parent:           Tree_Node_ID,
	text_offset:      u64,
	text_bytes:       u32,
	icon_offset:      u64,
	icon_bytes:       u8,
	icon_role:        Tree_Icon_Role,
	icon_style_role:  Style_Role,
	depth:            u16,
	indent_depth:     u16,
	expandable:       bool,
	expanded:         bool,
	action:           List_Action_Reference,
	style_spans:      [MAX_LIST_ITEM_STYLE_SPANS]List_Item_Style_Span,
	style_span_count: u8,
}

/* Input_Validation_State presents one checked backing interaction validation result. */
Input_Validation_State :: enum u8 {
	Invalid,
	Valid,
	Rejected,
}

/* Input_View_State copies visual state for one exact backing interaction generation. */
Input_View_State :: struct {
	present:                 bool,
	presentation_generation: u64,
	backing_generation:      u64,
	value_offset:            u64,
	value_bytes:             u32,
	cursor_offset:           u32,
	first_visible_byte:      u32,
	viewport_bytes:          u32,
	validation:              Input_Validation_State,
	choice_offset:           u16,
	choice_count:            u16,
}

/* Input_Projection_Request declares one exact backing and visual input generation. */
Input_Projection_Request :: struct {
	model:                   Model_Reference,
	presentation_generation: u64,
	backing_generation:      u64,
	cursor_offset:           u32,
	first_visible_byte:      u32,
	viewport_bytes:          u32,
	validation:              Input_Validation_State,
	read_only:               bool,
}

/* Input_Choice_Definition borrows one named semantic alternative during projection. */
Input_Choice_Definition :: struct {
	id:     Input_Choice_ID,
	name:   string,
	action: List_Action_Reference,
}

/* Input_Choice_Descriptor owns one copied named semantic alternative. */
Input_Choice_Descriptor :: struct {
	projection: Object_Handle,
	id:         Input_Choice_ID,
	name_offset: u64,
	name_bytes: u32,
	action:     List_Action_Reference,
}

/* Projection_Descriptor identifies copied model-to-view data and its exact size. */
Projection_Descriptor :: struct {
	handle:       Object_Handle,
	model:        Model_Reference,
	byte_count:   u64,
	item_count:   u32,
	read_only:    bool,
}

/* TERMINAL_CELL_TEXT_BYTES bounds one copied visible grapheme cluster. */
TERMINAL_CELL_TEXT_BYTES :: 64

/* Terminal_Damage identifies the redraw scope already computed by the emulator. */
Terminal_Damage :: enum u8 {
	Clean,
	Partial,
	Full,
}

/* Terminal_Cursor_Style preserves the child terminal cursor presentation. */
Terminal_Cursor_Style :: enum u8 {
	Bar,
	Block,
	Underline,
	Hollow_Block,
}

/* Terminal_Color_Kind distinguishes theme inheritance, palette, and true color. */
Terminal_Color_Kind :: enum u8 {
	Default,
	Palette,
	RGB,
}

/* Terminal_Color is one frontend-independent child terminal color request. */
Terminal_Color :: struct {
	kind:    Terminal_Color_Kind,
	palette: u8,
	rgb:     SRGB_Color,
}

/* Terminal_Cell_Style is copied presentation, never executable terminal output. */
Terminal_Cell_Style :: struct {
	foreground:      Terminal_Color,
	background:      Terminal_Color,
	underline_color: Terminal_Color,
	attributes:      Style_Attributes,
	invisible:       bool,
}

/* Terminal_Cell is one checked already-emulated visible cell. */
Terminal_Cell :: struct {
	column:      u16,
	row:         u16,
	text:        [TERMINAL_CELL_TEXT_BYTES]u8,
	text_length: u16,
	width:       u8,
	selected:    bool,
	hyperlink:   bool,
	style:       Terminal_Cell_Style,
}

/* Terminal_Row carries emulator damage and wrapping metadata. */
Terminal_Row :: struct {
	row:               u16,
	dirty:             bool,
	wrapped:           bool,
	wrap_continuation: bool,
}

/* Terminal_Cursor is one copied logical cursor, shown only on the focused surface. */
Terminal_Cursor :: struct {
	column:      u16,
	row:         u16,
	style:       Terminal_Cursor_Style,
	in_viewport: bool,
	visible:     bool,
	blinking:    bool,
	wide_tail:   bool,
}

/* Terminal_Lifecycle is presentation-only process state. */
Terminal_Lifecycle :: enum u8 {
	Running,
	Exited,
	Failed,
}

/* Terminal_View_State references copied rows and cells in one immutable UI root. */
Terminal_View_State :: struct {
	present:          bool,
	session_id:       u32,
	session_generation: u32,
	revision:         u64,
	columns:          u16,
	rows:             u16,
	damage:           Terminal_Damage,
	row_offset:       u32,
	row_count:        u32,
	cell_offset:      u32,
	cell_count:       u32,
	cursor:           Terminal_Cursor,
	foreground:       SRGB_Color,
	background:       SRGB_Color,
	cursor_color:     Optional_SRGB_Color,
	palette:          [256]SRGB_Color,
	lifecycle:        Terminal_Lifecycle,
	exit_code:        i32,
	activity_generation: u64,
	audible_attention: bool,
	visual_attention:  bool,
	title_offset:     u32,
	title_bytes:      u16,
}

/* Terminal_Projection_Request borrows one already-emulated visual generation. */
Terminal_Projection_Request :: struct {
	model:             Model_Reference,
	session_id:        u32,
	session_generation: u32,
	revision:          u64,
	columns:           u16,
	rows:              u16,
	damage:            Terminal_Damage,
	cursor:            Terminal_Cursor,
	foreground:        SRGB_Color,
	background:        SRGB_Color,
	cursor_color:      Optional_SRGB_Color,
	palette:           [256]SRGB_Color,
	lifecycle:         Terminal_Lifecycle,
	exit_code:         i32,
	activity_generation: u64,
	audible_attention: bool,
	visual_attention:  bool,
	title:             string,
}

/* Visual_View_Descriptor describes one initial view without semantic pointers. */
Visual_View_Descriptor :: struct {
	handle:             Object_Handle,
	kind:               Visual_Kind,
	projection:         Object_Handle,
	read_only:          bool,
	text:               Text_View_State,
	terminal:           Terminal_View_State,
	list:               List_View_State,
	tree:               Tree_View_State,
	input:              Input_View_State,
}

/* Surface_Descriptor is one logical renderable and focusable containment record. */
Surface_Descriptor :: struct {
	handle:          Object_Handle,
	owner_id:        Owner_ID,
	view:            Object_Handle,
	focusable:       bool,
	visible:         bool,
	input_context:   u64,
	keymap_context:  u64,
	required_profile: Renderer_Profile_ID,
	geometry:        Cell_Rect,
	pane:             Pane_Surface_State,
}

/* Composition_Descriptor is one surface leaf, binary split, or panel wrapper. */
Composition_Descriptor :: struct {
	handle:      Object_Handle,
	kind:        Composition_Kind,
	surface:     Object_Handle,
	first:       Object_Handle,
	second:      Object_Handle,
	orientation: Split_Orientation,
	first_weight: u64,
	second_weight: u64,
	panel_child:   Object_Handle,
	panel_edge:    Panel_Edge,
	panel_extent:  u32,
	depth:       u16,
	layout:      Layout_Node_State,
}

/* Status_Style_Span applies one semantic role to a checked UTF-8 byte range. */
Status_Style_Span :: struct {
	start_byte: u32,
	end_byte:   u32,
	style_role: Style_Role,
}

/* Status_Command_Reference identifies one checked catalog command without a callback. */
Status_Command_Reference :: struct {
	registry_generation: u64,
	slot:                u16,
	entry_generation:    u32,
}

/* Status_Segment_Definition borrows semantic metadata during status publication. */
Status_Segment_Definition :: struct {
	identity:          u64,
	kind:              u8,
	start_byte:        u32,
	end_byte:          u32,
	start_cell:        u32,
	end_cell:          u32,
	compact:           bool,
	truncated:         bool,
	inspection_text:   string,
	primary_command:   Status_Command_Reference,
	secondary_command: Status_Command_Reference,
}

/* Status_Segment_Descriptor owns checked ranges and copied inspection offsets. */
Status_Segment_Descriptor :: struct {
	identity:          u64,
	kind:              u8,
	start_byte:        u32,
	end_byte:          u32,
	start_cell:        u32,
	end_cell:          u32,
	compact:           bool,
	truncated:         bool,
	inspection_offset: u32,
	inspection_bytes:  u32,
	primary_command:   Status_Command_Reference,
	secondary_command: Status_Command_Reference,
}

/* Status_Region_Descriptor reserves bounded rows and copied compact content. */
Status_Region_Descriptor :: struct {
	handle:       Object_Handle,
	owner_id:     Owner_ID,
	placement:    Status_Placement,
	surface:      Object_Handle,
	rows:         u16,
	geometry:     Cell_Rect,
	content_offset: u32,
	content_bytes: u32,
	style_role:   Style_Role,
	style_spans:  [MAX_STATUS_STYLE_SPANS]Status_Style_Span,
	style_span_count: u8,
	presentation_generation: u64,
	segments:      [MAX_STATUS_SEGMENTS]Status_Segment_Descriptor,
	segment_count: u8,
	active:       bool,
}

/* Style_Definition maps one semantic role to frontend-independent presentation. */
Style_Definition :: struct {
	role:       Style_Role,
	foreground: Optional_SRGB_Color,
	background: Optional_SRGB_Color,
	attributes: Style_Attributes,
}

/* Style_Descriptor owns one definition in an exact UI root generation. */
Style_Descriptor :: struct {
	handle:     Object_Handle,
	role:       Style_Role,
	foreground: Optional_SRGB_Color,
	background: Optional_SRGB_Color,
	attributes: Style_Attributes,
}

/* Decoration_Descriptor associates semantic presentation with checked content. */
Decoration_Descriptor :: struct {
	handle:       Object_Handle,
	owner_id:     Owner_ID,
	kind:         Decoration_Kind,
	projection:   Object_Handle,
	source_revision: u64,
	start:        u64,
	end:          u64,
	style_role:   Style_Role,
	precedence:   u16,
}

/* Transient_Input_Capture identifies one popup command owner while source focus remains active. */
Transient_Input_Capture :: struct {
	active:           bool,
	popup:            Object_Handle,
	popup_id:         Popup_ID,
	popup_generation: Popup_Generation,
	owner_id:         Owner_ID,
	owner_generation: u64,
	source_surface:   Object_Handle,
}

/* Focus_Descriptor records ordinary focus plus exclusive temporary input ownership. */
Focus_Descriptor :: struct {
	target:        Object_Handle,
	captured:      bool,
	return_target: Object_Handle,
	transient:     Transient_Input_Capture,
}

/* Renderer_Capability identifies one initial physical frontend feature. */
Renderer_Capability :: enum u8 {
	Cell_Geometry,
	Clipping,
	Unicode_Profile,
	Text_Cursor,
	Input_Cursor,
	Semantic_Attributes,
	Atomic_Generation,
	Full_Redraw,
	Popup_Overlap,
}

/* Renderer_Capabilities is the admitted initial backend capability set. */
Renderer_Capabilities :: bit_set[Renderer_Capability; u16]

/* Renderer_Profile describes one physical frontend without exposing its surface. */
Renderer_Profile :: struct {
	id:              Renderer_Profile_ID,
	capabilities:    Renderer_Capabilities,
	unicode_profile: u64,
	max_rows:        u32,
	max_columns:     u32,
	max_cells:       u64,
	color:           Renderer_Color_Capability,
	attributes:      Style_Attributes,
}

/* Resource_Limits contains all selected initial UI bounds. */
Resource_Limits :: struct {
	live_surfaces:       u16,
	live_views:          u16,
	split_depth:         u16,
	composition_nodes:   u16,
	status_regions:      u16,
	live_popups:         u16,
	popup_content_bytes: u64,
	popup_actions:       u16,
	list_items:          u32,
	tree_nodes:          u32,
	input_bytes:         u32,
	fixed_choices:       u16,
	projection_bytes:    u64,
	styles:              u16,
	decorations:         u32,
	compact_region_bytes: u64,
	event_subscriptions: u16,
	queued_events:       u16,
	callback_depth:      u16,
	deferred_work:       u16,
	snapshot_bytes:      u64,
	temporary_bytes:     u64,
	diagnostic_bytes:    u64,
	geometry_work:       u64,
}

/* DEFAULT_RESOURCE_LIMITS is the evidence-selected initial policy. */
DEFAULT_RESOURCE_LIMITS :: Resource_Limits {
	live_surfaces = MAX_LIVE_SURFACES,
	live_views = MAX_LIVE_VIEWS,
	split_depth = MAX_SPLIT_DEPTH,
	composition_nodes = MAX_COMPOSITION_NODES,
	status_regions = MAX_STATUS_REGIONS,
	live_popups = MAX_LIVE_POPUPS,
	popup_content_bytes = MAX_POPUP_CONTENT_BYTES,
	popup_actions = MAX_POPUP_ACTIONS,
	list_items = MAX_LIST_ITEMS,
	tree_nodes = MAX_TREE_NODES,
	input_bytes = u32(MAX_INPUT_BYTES),
	fixed_choices = MAX_FIXED_CHOICES,
	projection_bytes = MAX_PROJECTION_BYTES,
	styles = MAX_STYLES,
	decorations = MAX_DECORATIONS,
	compact_region_bytes = MAX_COMPACT_REGION_BYTES,
	event_subscriptions = MAX_EVENT_SUBSCRIPTIONS,
	queued_events = MAX_QUEUED_EVENTS,
	callback_depth = MAX_CALLBACK_DEPTH,
	deferred_work = MAX_DEFERRED_WORK,
	snapshot_bytes = MAX_SNAPSHOT_BYTES,
	temporary_bytes = MAX_TEMPORARY_BYTES,
	diagnostic_bytes = MAX_DIAGNOSTIC_BYTES,
	geometry_work = MAX_GEOMETRY_WORK,
}

/* Resource_Accounting reports exact retained and peak operation costs. */
Resource_Accounting :: struct {
	registry_bytes:       u64,
	projection_bytes:     u64,
	style_bytes:          u64,
	decoration_bytes:     u64,
	list_items:           u32,
	tree_nodes:           u32,
	input_bytes:          u32,
	fixed_choices:        u16,
	snapshot_bytes:       u64,
	compact_region_bytes: u64,
	popup_bytes:          u64,
	popup_content_bytes:  u64,
	popup_actions:        u16,
	queued_events:        u16,
	deferred_work:        u16,
	callback_depth:       u16,
	temporary_peak_bytes: u64,
	geometry_work:        u64,
}

/* Operation identifies the logical UI action that produced a failure. */
Operation :: enum u8 {
	Invalid,
	Initialize,
	Prepare,
	Validate,
	Publish,
	Inspect,
	Focus,
	Capture_Focus,
	Release_Focus,
	Capture_Transient_Input,
	Release_Transient_Input,
	Replace_Root,
	Dismiss_Popup,
	Navigate,
	Resize,
	Snapshot,
	Hit_Test,
	Teardown,
}

/* Failure_Code classifies every expected logical UI rejection. */
Failure_Code :: enum u16 {
	None,
	Invalid_Registry,
	Invalid_Proposal,
	Closed_Registry,
	Wrong_Registry,
	Invalid_Owner,
	Wrong_Owner,
	Invalid_Root,
	Stale_Root,
	Invalid_Surface,
	Stale_Surface,
	Invalid_View,
	Stale_View,
	Invalid_Text_View,
	Stale_Text_View,
	Incompatible_Text_View,
	Invalid_Terminal_View,
	Malformed_Terminal_Cell,
	Invalid_List_View,
	Stale_List_View,
	Invalid_List_Item,
	Duplicate_List_Item,
	Invalid_List_Action,
	Invalid_List_Mark,
	Malformed_List_Text,
	Invalid_Tree_View,
	Invalid_Tree_Node,
	Duplicate_Tree_Node,
	Malformed_Tree_Text,
	Invalid_Layout,
	Stale_Layout,
	Incompatible_Layout,
	Invalid_Projection,
	Stale_Projection,
	Invalid_Composition,
	Invalid_Status_Region,
	Invalid_Hit,
	Invalid_Popup,
	Stale_Popup,
	Invalid_Popup_Anchor,
	Invalid_Popup_Content,
	Invalid_Style,
	Invalid_Decoration,
	Invalid_Focus,
	Focus_Captured,
	Invalid_Transient_Input,
	Transient_Input_Captured,
	No_Focus_Fallback,
	Surface_Limit,
	View_Limit,
	Composition_Limit,
	Split_Depth_Limit,
	Status_Region_Limit,
	Popup_Limit,
	Popup_Content_Limit,
	Popup_Action_Limit,
	List_Item_Limit,
	Tree_Node_Limit,
	Input_Limit,
	Fixed_Choice_Limit,
	Projection_Limit,
	Style_Limit,
	Decoration_Limit,
	Compact_Region_Limit,
	Event_Subscription_Limit,
	Queue_Limit,
	Callback_Depth_Limit,
	Deferred_Work_Limit,
	Snapshot_Limit,
	Temporary_Memory_Limit,
	Diagnostic_Limit,
	Geometry_Work_Limit,
	Renderer_Incompatible,
	Generation_Limit,
	Checked_Integer_Overflow,
	Allocation,
	Busy,
}

/* Failure reports one rejected operation without exposing native pointers. */
Failure :: struct {
	operation:    Operation,
	code:         Failure_Code,
	root:         Root_Handle,
	object:       Object_Handle,
	limit:        u64,
	actual:       u64,
	required_profile: Renderer_Profile_ID,
	source_view_id: u64,
	source_view_generation: u32,
}

/* Registry is a non-copyable owner of one bounded logical UI generation. */
Registry :: struct {
	state:  rawptr,
	closed: bool,
}

/* Proposal is a non-copyable private generation prepared before publication. */
Proposal :: struct {
	state: rawptr,
}

/* Registry_Stats reports current occupancy, generations, and exact accounting. */
Registry_Stats :: struct {
	root:                Root_Handle,
	surfaces:            u16,
	views:               u16,
	projections:         u16,
	composition_nodes:   u16,
	status_regions:      u16,
	popups:              u16,
	styles:              u16,
	decorations:         u32,
	list_items:          u32,
	tree_nodes:          u32,
	focus_captured:      bool,
	transient_input_captured: bool,
	focus_generation:    u64,
	accounting:          Resource_Accounting,
}

/* Snapshot is a non-copyable owner of one immutable copied UI generation. */
Snapshot :: struct {
	state: rawptr,
}

/* Snapshot_View borrows copied records until its owning snapshot is closed. */
Snapshot_View :: struct {
	root:           Root_Handle,
	root_node:      Object_Handle,
	focus:          Focus_Descriptor,
	renderer:       Renderer_Profile,
	projections:    []Projection_Descriptor,
	views:          []Visual_View_Descriptor,
	terminal_rows:  []Terminal_Row,
	terminal_cells: []Terminal_Cell,
	list_items:     []List_Item_Descriptor,
	list_content:   []u8,
	tree_nodes:     []Tree_Node_Descriptor,
	tree_content:   []u8,
	input_choices:  []Input_Choice_Descriptor,
	input_content:  []u8,
	surfaces:       []Surface_Descriptor,
	composition:    []Composition_Descriptor,
	status_regions: []Status_Region_Descriptor,
	popups:         []Popup_Descriptor,
	compact_content: []u8,
	styles:         []Style_Descriptor,
	decorations:    []Decoration_Descriptor,
	accounting:     Resource_Accounting,
}

/* popup_descriptor_shape_is_valid checks copied policy before registry resolution. */
popup_descriptor_shape_is_valid :: proc(descriptor: Popup_Descriptor) -> bool {
	if descriptor.id == Popup_ID(0) || descriptor.generation == Popup_Generation(0) ||
	   descriptor.owner_id == Owner_ID(0) || descriptor.owner_generation == 0 ||
	   !popup_anchor_shape_is_valid(descriptor.anchor) ||
	   descriptor.content_surface.object_id == Object_ID(0) ||
	   descriptor.content_generation == 0 || descriptor.placement_count == 0 ||
	   int(descriptor.placement_count) > MAX_POPUP_PLACEMENTS ||
	   !popup_bounds_are_valid(descriptor.bounds) || descriptor.clipping == .Invalid ||
	   descriptor.behavior == .Invalid || descriptor.input_policy == .Invalid ||
	   descriptor.dismissal == {} || descriptor.fallback == .Invalid ||
	   descriptor.required_profile == Renderer_Profile_ID(0) ||
	   !presentation_profile_record_is_valid(descriptor.presentation_profile) ||
	   !presentation_profile_matches_popup(descriptor.presentation_profile, descriptor) ||
	   descriptor.content_bytes == 0 ||
	   u64(descriptor.content_bytes) > MAX_POPUP_CONTENT_BYTES ||
	   descriptor.action_count > MAX_POPUP_ACTIONS {
		return false
	}
	if descriptor.behavior == .Informational &&
	   descriptor.input_policy != .Preserve_Source_Focus {
		return false
	}
	if descriptor.behavior == .Interactive &&
	   descriptor.input_policy != .Transient_Capture &&
	   descriptor.input_policy != .Transfer_Focus {
		return false
	}
	for index in 0 ..< int(descriptor.placement_count) {
		placement := descriptor.placements[index]
		if placement == .Invalid {
			return false
		}
		for previous_index in 0 ..< index {
			previous := descriptor.placements[previous_index]
			if placement == previous {
				return false
			}
		}
	}
	return true
}

@(private = "file")
popup_anchor_shape_is_valid :: proc(anchor: Popup_Anchor_Reference) -> bool {
	return anchor.kind != .Invalid && anchor.source_surface.object_id != Object_ID(0) &&
		anchor.owner_id != Owner_ID(0) && anchor.source_id != 0 &&
		anchor.source_generation != 0 && anchor.end >= anchor.start
}

@(private = "file")
popup_bounds_are_valid :: proc(bounds: Popup_Dimension_Bounds) -> bool {
	return bounds.minimum_rows > 0 && bounds.minimum_columns > 0 &&
		bounds.minimum_rows <= bounds.preferred_rows &&
		bounds.preferred_rows <= bounds.maximum_rows &&
		bounds.minimum_columns <= bounds.preferred_columns &&
		bounds.preferred_columns <= bounds.maximum_columns
}

/* resource_limits_are_valid checks the complete selected policy relationship. */
resource_limits_are_valid :: proc(limits: Resource_Limits) -> bool {
	return limits.live_surfaces > 0 && limits.live_surfaces <= MAX_LIVE_SURFACES &&
		limits.live_views > 0 && limits.live_views <= MAX_LIVE_VIEWS &&
		limits.split_depth > 0 && limits.split_depth <= MAX_SPLIT_DEPTH &&
		limits.composition_nodes >= limits.live_surfaces &&
		limits.composition_nodes <= MAX_COMPOSITION_NODES &&
		limits.status_regions > 0 && limits.status_regions <= MAX_STATUS_REGIONS &&
		limits.live_popups > 0 && limits.live_popups <= MAX_LIVE_POPUPS &&
		limits.popup_content_bytes > 0 &&
		limits.popup_content_bytes <= MAX_POPUP_CONTENT_BYTES &&
		limits.popup_actions > 0 && limits.popup_actions <= MAX_POPUP_ACTIONS &&
		limits.list_items > 0 && limits.list_items <= MAX_LIST_ITEMS &&
		limits.tree_nodes > 0 && limits.tree_nodes <= MAX_TREE_NODES &&
		limits.input_bytes > 0 && u64(limits.input_bytes) <= MAX_INPUT_BYTES &&
		limits.fixed_choices > 0 && limits.fixed_choices <= MAX_FIXED_CHOICES &&
		limits.projection_bytes > 0 && limits.projection_bytes <= MAX_PROJECTION_BYTES &&
		limits.styles > 0 && limits.styles <= MAX_STYLES &&
		limits.decorations > 0 && limits.decorations <= MAX_DECORATIONS &&
		limits.compact_region_bytes > 0 &&
		limits.compact_region_bytes <= MAX_COMPACT_REGION_BYTES &&
		limits.event_subscriptions > 0 &&
		limits.event_subscriptions <= MAX_EVENT_SUBSCRIPTIONS &&
		limits.queued_events > 0 && limits.queued_events <= MAX_QUEUED_EVENTS &&
		limits.callback_depth > 0 && limits.callback_depth <= MAX_CALLBACK_DEPTH &&
		limits.deferred_work > 0 && limits.deferred_work <= MAX_DEFERRED_WORK &&
		limits.snapshot_bytes > 0 && limits.snapshot_bytes <= MAX_SNAPSHOT_BYTES &&
		limits.temporary_bytes > 0 && limits.temporary_bytes <= MAX_TEMPORARY_BYTES &&
		limits.diagnostic_bytes > 0 && limits.diagnostic_bytes <= MAX_DIAGNOSTIC_BYTES &&
		limits.geometry_work > 0 && limits.geometry_work <= MAX_GEOMETRY_WORK
}

/* renderer_profile_is_valid checks the complete initial frontend contract. */
renderer_profile_is_valid :: proc(profile: Renderer_Profile) -> bool {
	required := Renderer_Capabilities {
		.Cell_Geometry,
		.Clipping,
		.Unicode_Profile,
		.Text_Cursor,
		.Input_Cursor,
		.Semantic_Attributes,
		.Atomic_Generation,
		.Full_Redraw,
	}
	return profile.id != Renderer_Profile_ID(0) && profile.capabilities & required == required &&
		profile.unicode_profile != 0 && profile.max_rows > 0 &&
		profile.max_columns > 0 && profile.max_cells > 0 &&
		profile.color <= .True_Color &&
		u64(profile.max_rows) * u64(profile.max_columns) <= profile.max_cells
}

/* optional_srgb_color_is_valid requires a unique inherited representation. */
optional_srgb_color_is_valid :: proc(color: Optional_SRGB_Color) -> bool {
	return color.present || color.color == SRGB_Color{}
}

/* style_role_is_valid admits current shared and syntax semantic roles. */
style_role_is_valid :: proc(role: Style_Role) -> bool {
	return role >= .Text_Normal && role <= .Popup_Unavailable
}

/* style_definition_is_valid checks one complete frontend-independent mapping. */
style_definition_is_valid :: proc(definition: Style_Definition) -> bool {
	return style_role_is_valid(definition.role) &&
		optional_srgb_color_is_valid(definition.foreground) &&
		optional_srgb_color_is_valid(definition.background)
}

/* visual_contract_is_valid checks view-kind and selection ownership invariants. */
visual_contract_is_valid :: proc(view: Visual_View_Descriptor) -> bool {
	switch view.kind {
	case .Text_View:
		return view.terminal == Terminal_View_State{} &&
			view.list == List_View_State{} && view.tree == Tree_View_State{} &&
			view.input == Input_View_State{} &&
			(!view.text.present || text_view_state_is_valid(view.text))
	case .Terminal_View:
		return view.text == Text_View_State{} && view.list == List_View_State{} &&
			view.tree == Tree_View_State{} && view.input == Input_View_State{} &&
			terminal_view_state_is_valid(view.terminal)
	case .List_View:
		return view.text == Text_View_State{} && view.terminal == Terminal_View_State{} &&
			view.tree == Tree_View_State{} &&
			view.input == Input_View_State{} &&
			list_view_state_is_valid(view.list)
	case .Tree_View:
		return view.text == Text_View_State{} && view.terminal == Terminal_View_State{} &&
			view.list == List_View_State{} &&
			view.input == Input_View_State{} && tree_view_state_is_valid(view.tree)
	case .Input:
		return view.text == Text_View_State{} && view.terminal == Terminal_View_State{} &&
			view.list == List_View_State{} &&
			view.tree == Tree_View_State{} &&
			input_view_state_is_valid(view.input)
	case .Invalid:
		return false
	}
	return false
}

/* terminal_view_state_is_valid checks copied session, geometry, and slice bounds. */
terminal_view_state_is_valid :: proc(state: Terminal_View_State) -> bool {
	return state.present && state.session_id != 0 && state.session_generation != 0 &&
		state.revision != 0 && state.columns > 0 && state.rows > 0 &&
		state.damage <= .Full && state.cursor.style <= .Hollow_Block &&
		state.row_count == u32(state.rows) && state.cell_count <= u32(state.columns) * u32(state.rows) &&
		state.cursor.column < state.columns && state.cursor.row < state.rows &&
		(state.lifecycle == .Running || state.lifecycle == .Exited || state.lifecycle == .Failed)
}

/* tree_view_state_is_valid checks selection, generation, and viewport bounds. */
tree_view_state_is_valid :: proc(state: Tree_View_State) -> bool {
	list := List_View_State {
		present = state.present,
		item_offset = state.node_offset,
		item_count = state.node_count,
		position = state.position,
	}
	return list_view_state_is_valid(list)
}

/* input_view_state_is_valid checks backing, cursor, viewport, and choice bounds. */
input_view_state_is_valid :: proc(state: Input_View_State) -> bool {
	if !state.present || state.presentation_generation == 0 || state.backing_generation == 0 ||
	   state.viewport_bytes == 0 || u64(state.value_bytes) > MAX_INPUT_BYTES ||
	   state.choice_count > MAX_FIXED_CHOICES ||
	   (state.validation != .Valid && state.validation != .Rejected) ||
	   state.cursor_offset > state.value_bytes ||
	   state.first_visible_byte > state.cursor_offset {
		return false
	}
	visible_end := u64(state.first_visible_byte) + u64(state.viewport_bytes)
	return u64(state.cursor_offset) < visible_end
}

/* list_view_state_is_valid checks ownership, generation, selection, and viewport bounds. */
list_view_state_is_valid :: proc(state: List_View_State) -> bool {
	position := state.position
	if !state.present || position.presentation_generation == 0 ||
	   (position.selection_owner != .Model && position.selection_owner != .View) ||
	   position.viewport_items == 0 || position.viewport_items > MAX_LIST_ITEMS {
		return false
	}
	if state.item_count == 0 {
		return position.current_item == -1 && position.first_visible_item == 0
	}
	if position.current_item < 0 || u32(position.current_item) >= state.item_count ||
	   position.first_visible_item > u32(position.current_item) ||
	   position.first_visible_item >= state.item_count {
		return false
	}
	visible := min(position.viewport_items, state.item_count - position.first_visible_item)
	return u32(position.current_item) < position.first_visible_item + visible
}

/* text_view_state_is_valid checks one copied delivered editor-view generation. */
text_view_state_is_valid :: proc(state: Text_View_State) -> bool {
	if !state.present || state.source.registry_id == 0 || state.source.view_id == 0 ||
	   state.source.view_generation == 0 || state.source.state_generation == 0 ||
	   state.source.selection_generation == 0 || state.buffer_id == 0 ||
	   state.tab_width == 0 || state.tab_width > 64 || state.display_profile_id == 0 ||
	   state.presentation_ownership == .Invalid ||
	   state.cursor_shape > .Underline ||
	   state.stored_point > state.source_text_bytes ||
	   state.effective_point > state.source_text_bytes ||
	   state.viewport_origin > state.source_text_bytes ||
	   state.mark > state.source_text_bytes || state.region_active && !state.mark_present {
		return false
	}
	if !text_gutter_state_shape_is_valid(state.gutter) {
		return false
	}
	if !state.search.present {
		return state.search == Text_Search_Descriptor{}
	}
	return state.search.interaction_generation > 0 &&
		state.search.source_revision == state.revision &&
		state.search.status != .Inactive &&
		(!state.search.has_current ||
			(state.search.match_count > 0 &&
			 state.search.current_start <= state.search.current_end &&
			 state.search.current_end <= state.source_text_bytes))
}

/* text_gutter_state_shape_is_valid checks bounded geometry and row ordering. */
text_gutter_state_shape_is_valid :: proc(state: Text_Gutter_State) -> bool {
	if !state.present {
		return state == Text_Gutter_State{}
	}
	if state.generation == 0 || state.row_count == 0 ||
	   state.row_count > MAX_TEXT_GUTTER_ROWS || state.text_cells < 8 ||
	   u64(state.left_cells) + u64(state.right_cells) + u64(state.text_cells) > u64(max(u32)) {
		return false
	}
	for index in 0 ..< int(state.row_count) {
		row := state.rows[index]
		if row.viewport_row != u32(index) || row.left_cells != state.left_cells ||
		   row.right_cells != state.right_cells ||
		   state.left_cells > 0 && row.left_style_role == .Invalid ||
		   state.right_cells > 0 && row.right_style_role == .Invalid ||
		   u16(row.left_separator_bytes) > row.left_bytes ||
		   u16(row.right_separator_bytes) > row.right_bytes {
			return false
		}
	}
	return true
}
