// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package layout owns one bounded frontend-independent pane tree.
package layout

import "../editor"
import "../editor_session"
import "../view"
import "base:runtime"

/* KIBIBYTE is the binary unit used by layout policy. */
KIBIBYTE :: u64(1_024)
/* MEBIBYTE is the binary unit used by layout policy. */
MEBIBYTE :: u64(1_024) * KIBIBYTE

/* MAX_LIVE_PANES bounds leaves in one layout. */
MAX_LIVE_PANES :: 128
/* MAX_PARTITIONS bounds binary internal nodes in one layout. */
MAX_PARTITIONS :: MAX_LIVE_PANES - 1
/* MAX_NODES bounds all live tree nodes in one layout. */
MAX_NODES :: MAX_LIVE_PANES * 2 - 1
/* MAX_PARTITION_DEPTH bounds root-to-leaf partition nesting. */
MAX_PARTITION_DEPTH :: 32
/* MAX_SNAPSHOT_NODES bounds copied snapshot descriptors. */
MAX_SNAPSHOT_NODES :: MAX_NODES
/* MAX_SNAPSHOT_BYTES bounds one copied snapshot value. */
MAX_SNAPSHOT_BYTES :: 1 * MEBIBYTE
/* MAX_PREPARED_TRANSACTION_BYTES bounds private structural state. */
MAX_PREPARED_TRANSACTION_BYTES :: 4 * MEBIBYTE
/* MAX_GEOMETRY_WORK bounds one complete geometry operation. */
MAX_GEOMETRY_WORK :: u64(1_048_576)
/* MAX_PANE_HISTORY_ENTRIES bounds retained buffer contexts in one pane. */
MAX_PANE_HISTORY_ENTRIES :: 64
/* MAX_PANE_HISTORY_BYTES bounds retained buffer context storage in one pane. */
MAX_PANE_HISTORY_BYTES :: 64 * KIBIBYTE
/* MAX_TOTAL_PANE_HISTORY_BYTES bounds retained buffer context storage in one layout. */
MAX_TOTAL_PANE_HISTORY_BYTES :: 8 * MEBIBYTE
/* MAX_TOP_LEVEL_BUFFERS bounds the independent container buffer recency list. */
MAX_TOP_LEVEL_BUFFERS :: 1_024
/* MAX_DISPLAY_POLICY_ACTIONS bounds one copied ordered display proposal. */
MAX_DISPLAY_POLICY_ACTIONS :: 32
/* MAX_LAYOUT_HOOKS bounds retained programmable layout observers. */
MAX_LAYOUT_HOOKS :: 64
/* MAX_DEFERRED_REQUESTS bounds callback-requested mutations awaiting revalidation. */
MAX_DEFERRED_REQUESTS :: 256
/* DEFAULT_DISPLAY_SPLIT_HEIGHT_THRESHOLD selects automatic below-split willingness. */
DEFAULT_DISPLAY_SPLIT_HEIGHT_THRESHOLD :: i32(12)
/* DEFAULT_DISPLAY_SPLIT_WIDTH_THRESHOLD selects automatic right-split willingness. */
DEFAULT_DISPLAY_SPLIT_WIDTH_THRESHOLD :: i32(40)
/* SEMANTIC_CONTENT_ROWS is the minimum renderable pane content height. */
SEMANTIC_CONTENT_ROWS :: i32(1)
/* PANE_STATUS_ROWS is the exact status height owned by each pane. */
PANE_STATUS_ROWS :: i32(2)
/* SEMANTIC_COLUMNS is the minimum renderable pane content width. */
SEMANTIC_COLUMNS :: i32(1)
/* DEFAULT_OPERATING_CONTENT_ROWS selects deliberate-action content height. */
DEFAULT_OPERATING_CONTENT_ROWS :: i32(2)
/* DEFAULT_OPERATING_COLUMNS selects deliberate-action pane width. */
DEFAULT_OPERATING_COLUMNS :: i32(8)

/* Owner_ID identifies the native owner of one layout. */
Owner_ID :: distinct u64
/* Layout_ID identifies one layout within its owner. */
Layout_ID :: distinct u64
/* Layout_Generation identifies one exact published layout state. */
Layout_Generation :: distinct u64
/* Node_ID identifies one node for the layout lifetime. */
Node_ID :: distinct u64
/* Pane_ID identifies one pane for the layout lifetime. */
Pane_ID :: distinct u64
/* Display_Request_ID identifies one copied display intent issued by a layout. */
Display_Request_ID :: distinct u64
/* Display_Policy_Generation identifies one exact configured display policy. */
Display_Policy_Generation :: distinct u64
/* Hook_ID identifies one observer for the lifetime of its layout. */
Hook_ID :: distinct u64
/* Deferred_Sequence orders callback-requested mutations. */
Deferred_Sequence :: distinct u64

/* Layout_Handle is a checked non-pointer reference to one published layout. */
Layout_Handle :: struct {
	owner_id:   Owner_ID,
	layout_id:  Layout_ID,
	generation: Layout_Generation,
}

/* Pane_Handle is a checked non-pointer reference to one exact pane slot. */
Pane_Handle :: struct {
	layout:          Layout_Handle,
	pane_id:         Pane_ID,
	slot:            u16,
	slot_generation: u32,
}

/* Arrangement names the ordered spatial relationship between two children. */
Arrangement :: enum u8 {
	Invalid,
	Above_Below,
	Left_Right,
}

/* Node_Kind distinguishes binary partitions from pane leaves. */
Node_Kind :: enum u8 {
	Invalid,
	Partition,
	Pane,
}

/* Geometry_State classifies the currently published materialization. */
Geometry_State :: enum u8 {
	Invalid,
	Unmaterialized,
	Operating,
	Semantic,
	Insufficient,
}

/* Materialization_Mode selects deliberate or external-shrink admission. */
Materialization_Mode :: enum u8 {
	Invalid,
	Operating,
	External_Shrink,
}

/* Pane_Dedication controls automatic reuse and ordinary explicit replacement. */
Pane_Dedication :: enum u8 {
	None,
	Soft,
	Hard,
}

/* Operation identifies the layout action that produced a failure. */
Operation :: enum u8 {
	Invalid,
	Initialize,
	Inspect,
	Materialize,
	Split,
	Resize,
	Balance_Dimensions,
	Balance_Areas,
	Focus,
	Close,
	Keep_Only,
	Replace_Buffer,
	Kill_Buffer,
	Record_History,
	Purge_History,
	Inspect_Dedication,
	Set_Dedication,
	Inspect_Display_Policy,
	Configure_Display_Policy,
	Request_Display,
	Propose_Display,
	Display_Buffer,
	Register_Hook,
	Release_Hook,
	Defer_Mutation,
	Notify_Hooks,
	Teardown,
}

/* Failure_Code classifies expected layout failures. */
Failure_Code :: enum u16 {
	None,
	Invalid_Registry,
	Closed_Registry,
	Invalid_Owner,
	Wrong_Owner,
	Invalid_Layout,
	Stale_Layout,
	Invalid_Pane,
	Stale_Pane,
	Invalid_Topology,
	Invalid_Parent,
	Invalid_Weight,
	Pane_Limit,
	Depth_Limit,
	Snapshot_Limit,
	Prepared_Memory_Limit,
	Geometry_Work_Limit,
	Invalid_Geometry,
	No_Compatible_Divider,
	Operating_Minimum,
	Semantic_Insufficient,
	Final_Pane,
	Generation_Limit,
	Checked_Integer_Overflow,
	Persistent_Memory_Limit,
	Invalid_Buffer_State,
	Buffer_Displayed,
	History_Limit,
	Busy,
	No_Fallback,
	Invalid_Display_Request,
	Stale_Display_Request,
	Invalid_Display_Policy,
	Stale_Display_Policy,
	Display_Action_Limit,
	Invalid_Display_Action,
	No_Other_Pane,
	Invalid_Dedication,
	Dedication_Conflict,
	Hook_Limit,
	Invalid_Hook,
	Stale_Hook,
	Deferred_Limit,
	Invalid_Deferred_Request,
	Callback_Failure,
	View_Failure,
	Session_Failure,
}

/* Policy contains all selected layout resource and geometry bounds. */
Policy :: struct {
	live_panes:             u16,
	partition_depth:        u16,
	operating_content_rows: i32,
	operating_columns:      i32,
	snapshot_nodes:         u16,
	snapshot_bytes:         u64,
	prepared_bytes:         u64,
	geometry_work:          u64,
	pane_history_entries:   u16,
	pane_history_bytes:     u64,
	total_history_bytes:    u64,
	top_level_buffers:      u16,
	layout_hooks:           u16,
	deferred_requests:      u16,
}

/* DEFAULT_POLICY is the selected bounded layout policy. */
DEFAULT_POLICY :: Policy {
	live_panes = MAX_LIVE_PANES,
	partition_depth = MAX_PARTITION_DEPTH,
	operating_content_rows = DEFAULT_OPERATING_CONTENT_ROWS,
	operating_columns = DEFAULT_OPERATING_COLUMNS,
	snapshot_nodes = MAX_SNAPSHOT_NODES,
	snapshot_bytes = MAX_SNAPSHOT_BYTES,
	prepared_bytes = MAX_PREPARED_TRANSACTION_BYTES,
	geometry_work = MAX_GEOMETRY_WORK,
	pane_history_entries = MAX_PANE_HISTORY_ENTRIES,
	pane_history_bytes = MAX_PANE_HISTORY_BYTES,
	total_history_bytes = MAX_TOTAL_PANE_HISTORY_BYTES,
	top_level_buffers = MAX_TOP_LEVEL_BUFFERS,
	layout_hooks = MAX_LAYOUT_HOOKS,
	deferred_requests = MAX_DEFERRED_REQUESTS,
}

/* Hook_Handle is one checked observer identity without retained callback state. */
Hook_Handle :: struct {
	owner_id:        Owner_ID,
	layout_id:       Layout_ID,
	hook_id:         Hook_ID,
	slot:            u16,
	slot_generation: u32,
}

/* Deferred_Operation names one callback-requested public layout mutation. */
Deferred_Operation :: enum u8 {
	Invalid,
	Split_Below,
	Split_Right,
	Focus,
	Close,
	Keep_Only,
	Resize,
	Balance_Dimensions,
	Balance_Areas,
	Set_Dedication,
}

/* Deferred_Request is one copied optimistic mutation request. */
Deferred_Request :: struct {
	sequence:    Deferred_Sequence,
	operation:   Deferred_Operation,
	expected:    Layout_Handle,
	pane:        Pane_Handle,
	arrangement: Arrangement,
	delta:       i32,
	dedication:  Pane_Dedication,
}

/* Hook_Callback_Context admits bounded deferred requests during one notification. */
Hook_Callback_Context :: struct {
	registry: ^Registry,
	hook:     Hook_Handle,
}

/* Hook_Procedure observes one immutable published snapshot. */
Hook_Procedure :: proc "c" (
	user_data: rawptr,
	hook: Hook_Handle,
	snapshot: ^Snapshot,
	ctx: ^Hook_Callback_Context,
) -> bool

/* Hook_Stats reports exact observer, queue, and callback accounting. */
Hook_Stats :: struct {
	hooks:               u16,
	deferred:            u16,
	notifying:           bool,
	processing_deferred: bool,
	notification_rounds: u64,
	callback_calls:      u64,
	callback_failures:   u64,
	deferred_enqueued:   u64,
	deferred_processed:  u64,
	deferred_failures:   u64,
}

/* Display_Action_Kind names one ordered destination-selection strategy. */
Display_Action_Kind :: enum u8 {
	Invalid,
	Reuse_Same_Buffer,
	Split_Below,
	Split_Right,
	Reuse_Least_Recent,
	Reuse_Most_Recent,
}

/* Display_Action is one copied, pointer-free policy action. */
Display_Action :: struct {
	kind: Display_Action_Kind,
}

/* Display_Eligibility declares the mandatory constraints for other-pane intent. */
Display_Eligibility :: struct {
	exclude_active:         bool,
	exclude_dedicated:      bool,
	require_live_buffer:    bool,
	require_current_layout: bool,
	automatic_reuse_only:   bool,
}

/* Display_Policy is one bounded ordered strategy and its split heuristics. */
Display_Policy :: struct {
	action_count:           u16,
	actions:                [MAX_DISPLAY_POLICY_ACTIONS]Display_Action,
	split_height_threshold: i32,
	split_width_threshold:  i32,
}

/* DEFAULT_DISPLAY_POLICY is the factory other-pane strategy. */
DEFAULT_DISPLAY_POLICY :: Display_Policy {
	action_count = 4,
	actions = {
		0 = {kind = .Reuse_Same_Buffer},
		1 = {kind = .Split_Below},
		2 = {kind = .Split_Right},
		3 = {kind = .Reuse_Least_Recent},
	},
	split_height_threshold = DEFAULT_DISPLAY_SPLIT_HEIGHT_THRESHOLD,
	split_width_threshold = DEFAULT_DISPLAY_SPLIT_WIDTH_THRESHOLD,
}

/* Display_Policy_Snapshot copies one complete configured generation. */
Display_Policy_Snapshot :: struct {
	layout:     Layout_Handle,
	generation: Display_Policy_Generation,
	policy:     Display_Policy,
}

/* Display_Policy_Replacement_Request requests one generation-checked replacement. */
Display_Policy_Replacement_Request :: struct {
	layout:              Layout_Handle,
	expected_generation: Display_Policy_Generation,
	policy:              Display_Policy,
}

/* Display_Request copies exact other-pane intent without borrowing layout state. */
Display_Request :: struct {
	request_id: Display_Request_ID,
	layout:     Layout_Handle,
	entry:      editor_session.Entry_Handle,
	buffer_id:  editor.Buffer_ID,
	active_pane: Pane_Handle,
	other_pane: bool,
}

/* Display_Policy_Proposal is one copied action sequence for one exact request. */
Display_Policy_Proposal :: struct {
	request:           Display_Request,
	policy_generation: Display_Policy_Generation,
	eligibility:       Display_Eligibility,
	action_count:      u16,
	actions:           [MAX_DISPLAY_POLICY_ACTIONS]Display_Action,
	split_height_threshold: i32,
	split_width_threshold:  i32,
}

/* Display_Result reports one destination publication without changing focus. */
Display_Result :: struct {
	layout:  Layout_Handle,
	pane:    Pane_Handle,
	entry:   editor_session.Entry_Handle,
	view:    view.View_Handle,
	action:  Display_Action_Kind,
	created: bool,
	changed: bool,
}

/* Pane_Buffer_State is one copied pane-local redisplay state for a live entry. */
Pane_Buffer_State :: struct {
	entry:                     editor_session.Entry_Handle,
	buffer_id:                 editor.Buffer_ID,
	stored_point:              editor.Position,
	viewport_start:            editor.Position,
	horizontal_display_column: u32,
	desired_display_column:    u32,
}

/* Pane_History_Entry is one unique recency record in a pane-local history. */
Pane_History_Entry :: struct {
	state:              Pane_Buffer_State,
	insertion_sequence: u64,
}

/* Pane_History_Snapshot copies one pane-local ordered history generation. */
Pane_History_Snapshot :: struct {
	layout:     Layout_Handle,
	pane:       Pane_Handle,
	generation: u64,
	count:      u16,
	entries:    [MAX_PANE_HISTORY_ENTRIES]Pane_History_Entry,
}

/* Pane_Dedication_Snapshot copies one pane's persistent dedication state. */
Pane_Dedication_Snapshot :: struct {
	layout:     Layout_Handle,
	pane:       Pane_Handle,
	dedication: Pane_Dedication,
}

/* Pane_Dedication_Result reports one checked dedication mutation. */
Pane_Dedication_Result :: struct {
	layout:     Layout_Handle,
	pane:       Pane_Handle,
	previous:   Pane_Dedication,
	current:    Pane_Dedication,
	changed:    bool,
}

/* Buffer_List_Entry is one top-level duplicate-free recency record. */
Buffer_List_Entry :: struct {
	entry:              editor_session.Entry_Handle,
	buffer_id:          editor.Buffer_ID,
	insertion_sequence: u64,
}

/* Buffer_List_Snapshot copies the independent top-level buffer recency list. */
Buffer_List_Snapshot :: struct {
	layout:     Layout_Handle,
	generation: u64,
	count:      u16,
	entries:    [MAX_TOP_LEVEL_BUFFERS]Buffer_List_Entry,
}

/* Geometry_Request describes total and top-level reserved terminal cells. */
Geometry_Request :: struct {
	rows:                    i32,
	columns:                 i32,
	global_reserved_rows:    i32,
	global_reserved_columns: i32,
}

/* Rect is one integer cell rectangle. */
Rect :: struct {
	row:    i32,
	column: i32,
	height: i32,
	width:  i32,
}

/* Pane_Geometry copies outer, content, status, and separator rectangles. */
Pane_Geometry :: struct {
	outer:     Rect,
	content:   Rect,
	status:    Rect,
	separator: Rect,
}

/* Node_Descriptor is one pointer-free copied node record. */
Node_Descriptor :: struct {
	kind:            Node_Kind,
	node_id:         Node_ID,
	slot_generation: u32,
	parent_id:       Node_ID,
	depth:           u16,
	arrangement:     Arrangement,
	first_child_id:  Node_ID,
	second_child_id: Node_ID,
	first_weight:    u64,
	second_weight:   u64,
	pane:            Pane_Handle,
	view:            view.View_Handle,
	buffer_id:       editor.Buffer_ID,
	entry:           editor_session.Entry_Handle,
	dedication:      Pane_Dedication,
	history_count:   u16,
	history_generation: u64,
	geometry:        Pane_Geometry,
	active:          bool,
	mru_rank:        u16,
}

/* Snapshot is one immutable copied layout generation in spatial preorder. */
Snapshot :: struct {
	handle:                  Layout_Handle,
	geometry_state:          Geometry_State,
	geometry_request:        Geometry_Request,
	root_id:                 Node_ID,
	active_pane:             Pane_Handle,
	node_count:              u16,
	pane_count:              u16,
	partition_count:         u16,
	geometry_work:           u64,
	nodes:                   [MAX_SNAPSHOT_NODES]Node_Descriptor,
}

/* Registry_Stats reports exact occupancy, storage, and geometry work. */
Registry_Stats :: struct {
	handle:          Layout_Handle,
	node_count:      u16,
	pane_count:      u16,
	partition_count: u16,
	storage_bytes:   u64,
	geometry_work:   u64,
	history_entries: u32,
	history_bytes:   u64,
	buffer_list_entries: u16,
	display_policy_generation: Display_Policy_Generation,
	display_policy_actions: u16,
	soft_dedicated_panes: u16,
	hard_dedicated_panes: u16,
	hooks: u16,
	deferred_requests: u16,
	notification_rounds: u64,
	callback_failures: u64,
	deferred_failures: u64,
}

/* Split_Result returns the new layout generation and both resulting panes. */
Split_Result :: struct {
	layout:   Layout_Handle,
	original: Pane_Handle,
	created:  Pane_Handle,
}

/* Resize_Result reports one exact divider movement and its persisted child spans. */
Resize_Result :: struct {
	layout:        Layout_Handle,
	pane:          Pane_Handle,
	partition_id:  Node_ID,
	arrangement:   Arrangement,
	delta:         i32,
	first_span:    i32,
	second_span:   i32,
}

/* Balance_Result reports one topology-preserving balance publication. */
Balance_Result :: struct {
	layout:       Layout_Handle,
	active_pane:  Pane_Handle,
	changed:      bool,
}

/* Replace_Result reports one checked pane buffer and presentation replacement. */
Replace_Result :: struct {
	layout:         Layout_Handle,
	pane:           Pane_Handle,
	previous_entry: editor_session.Entry_Handle,
	entry:          editor_session.Entry_Handle,
	view:           view.View_Handle,
	changed:        bool,
}

/* Kill_Outcome distinguishes dirty admission from one completed coordinated kill. */
Kill_Outcome :: enum u8 {
	Invalid,
	Discard_Required,
	Killed,
}

/* Kill_Result reports coordinated pane replacement and session graph release. */
Kill_Result :: struct {
	outcome:      Kill_Outcome,
	layout:       Layout_Handle,
	active_pane:  Pane_Handle,
	active_entry: editor_session.Entry_Handle,
	closure:      editor_session.Closure_Result,
	replacements: u16,
}

/* Focus_Result returns the new layout generation and active pane. */
Focus_Result :: struct {
	layout: Layout_Handle,
	active: Pane_Handle,
}

/* Failure_Context identifies the rejected operation, identity, and bound. */
Failure_Context :: struct {
	code:         Failure_Code,
	operation:    Operation,
	layout:       Layout_Handle,
	pane:         Pane_Handle,
	maximum:      u64,
	actual:       u64,
	view_failure: view.Failure_Context,
	session_failure: editor_session.Failure_Context,
	display_request_id: Display_Request_ID,
	display_policy_generation: Display_Policy_Generation,
	display_action_index: u16,
	dedication: Pane_Dedication,
	hook:       Hook_Handle,
	deferred_sequence: Deferred_Sequence,
}

/* Registry is the opaque lifecycle handle for one pane layout. */
Registry :: struct {
	state:  rawptr,
	closed: bool,
}

@(private)
Registry_State :: enum u8 {
	Invalid,
	Ready,
	Closed,
}

@(private)
Node_Ref :: struct {
	slot:       u16,
	generation: u32,
}

@(private)
Node_Slot :: struct {
	live:          bool,
	kind:          Node_Kind,
	node_id:       Node_ID,
	generation:    u32,
	parent:        Node_Ref,
	depth:         u16,
	arrangement:   Arrangement,
	first:         Node_Ref,
	second:        Node_Ref,
	first_weight:  u64,
	second_weight: u64,
	pane_id:       Pane_ID,
	view:          view.View_Handle,
	buffer_id:     editor.Buffer_ID,
	entry:         editor_session.Entry_Handle,
	dedication:    Pane_Dedication,
	history:       [MAX_PANE_HISTORY_ENTRIES]Pane_History_Entry,
	history_count: u16,
	history_generation: u64,
	geometry:      Pane_Geometry,
}

@(private)
Registry_Data :: struct {
	state:            Registry_State,
	owner_id:         Owner_ID,
	layout_id:        Layout_ID,
	generation:       Layout_Generation,
	next_node_id:     Node_ID,
	next_pane_id:     Pane_ID,
	root:             Node_Ref,
	active:           Node_Ref,
	mru:              [MAX_LIVE_PANES]Node_Ref,
	mru_count:        u16,
	node_count:       u16,
	pane_count:       u16,
	partition_count:  u16,
	nodes:            [MAX_NODES]Node_Slot,
	view_registry:    ^view.Registry,
	policy:           Policy,
	geometry_request: Geometry_Request,
	geometry_state:   Geometry_State,
	geometry_work:    u64,
	next_history_sequence: u64,
	buffer_list_generation: u64,
	buffer_list:      [MAX_TOP_LEVEL_BUFFERS]Buffer_List_Entry,
	buffer_list_count: u16,
	display_policy:    Display_Policy,
	display_policy_generation: Display_Policy_Generation,
	next_display_request_id: Display_Request_ID,
	next_hook_id:             Hook_ID,
	next_deferred_sequence:   Deferred_Sequence,
	hooks:                    [MAX_LAYOUT_HOOKS]Hook_Slot,
	hook_count:               u16,
	deferred:                 [MAX_DEFERRED_REQUESTS]Deferred_Request,
	deferred_count:           u16,
	notifying:                bool,
	processing_deferred:      bool,
	notification_snapshot:    ^Snapshot,
	notification_rounds:      u64,
	callback_calls:           u64,
	callback_failures:        u64,
	deferred_enqueued:        u64,
	deferred_processed:       u64,
	deferred_failures:        u64,
	last_hook_failure:        Failure_Context,
	last_deferred_failure:    Failure_Context,
	storage_bytes:    u64,
	allocator:        runtime.Allocator,
}

@(private)
Hook_Slot :: struct {
	live:       bool,
	hook_id:    Hook_ID,
	generation: u32,
	procedure:  Hook_Procedure,
	user_data:  rawptr,
}
