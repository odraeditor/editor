// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package darek owns bounded hierarchical explorer state independently of
// filesystem authority, UI composition, layout, commands, and frontends.
package darek

import "../filesystem"
import "../project"
import "../ui"
import "base:runtime"

KIBIBYTE :: u64(1_024)
MEBIBYTE :: u64(1_024) * KIBIBYTE

/* MAX_NODES bounds one complete visible Darek tree generation. */
MAX_NODES :: u32(4_096)
/* MAX_DEPTH bounds visible root-to-node hierarchy. */
MAX_DEPTH :: u16(64)
/* MAX_RETAINED_TEXT_BYTES bounds copied labels and paths. */
MAX_RETAINED_TEXT_BYTES :: u64(16) * MEBIBYTE
/* MAX_DIAGNOSTIC_BYTES bounds one copied failure explanation. */
MAX_DIAGNOSTIC_BYTES :: u64(4) * KIBIBYTE
MIN_PANEL_WIDTH :: u32(16)
DEFAULT_PANEL_WIDTH :: u32(32)
EXTRA_PANEL_WIDTH :: u32(48)
MAX_PANEL_WIDTH :: u32(80)
PANEL_WIDTH_STEP :: u32(4)
/* MAX_FILTER_BYTES bounds one copied tree-name filter. */
MAX_FILTER_BYTES :: 256
/* MAX_WATCH_HINTS bounds coalesced filesystem activity before refresh. */
MAX_WATCH_HINTS :: u32(1_024)

Instance_ID :: distinct u64
Instance_Generation :: distinct u64
Node_ID :: distinct u64
Node_Generation :: distinct u64
Provider_ID :: distinct u64
Provider_Generation :: distinct u64
Task_Generation :: distinct u64
Selection_Generation :: distinct u64

/* Workspace_Reference identifies one exact durable Workspace and root publication. */
Workspace_Reference :: struct {
	id:              string,
	generation:      u64,
	root_generation: u64,
}

/* Root_Mode identifies the canonical context represented by one Darek instance. */
Root_Mode :: enum u8 {
	Invalid,
	Directory,
	Project,
	Workspace,
}

/* Node_Kind classifies the initial filesystem hierarchy. */
Node_Kind :: enum u8 {
	Invalid,
	Project,
	Directory,
	File,
	Symbol,
}

/* Child_State distinguishes collapsed, complete, and failed child observations. */
Child_State :: enum u8 {
	Invalid,
	Leaf,
	Collapsed,
	Loading,
	Expanded,
	Unavailable,
	Failed,
}

/* Action_Role identifies semantic behavior without storing callbacks. */
Action_Role :: enum u8 {
	Structure,
	Visit,
	Collapse,
}

Action_Roles :: bit_set[Action_Role; u8]

/* Project_Collapse_Scope selects which visible Project roots to collapse. */
Project_Collapse_Scope :: enum u8 {
	Invalid,
	Current,
	Others,
	All,
}

/* Sort_Mode selects deterministic sibling ordering without changing identity. */
Sort_Mode :: enum u8 {
	Invalid,
	Name_Ascending,
	Name_Descending,
}

/* Version_Control_State is copied presentation data owned by a provider. */
Version_Control_State :: enum u8 {
	None,
	Clean,
	Modified,
	Added,
	Deleted,
	Conflicted,
}

/* Diagnostic_State is copied aggregate presentation data owned by diagnostics. */
Diagnostic_State :: enum u8 {
	None,
	Information,
	Warning,
	Error,
}

/* Watch_Hint classifies bounded provider notifications without treating them as evidence. */
Watch_Hint :: enum u8 {
	Invalid,
	Activity,
	Loss,
	Overflow,
}

/* Watch_Status distinguishes disabled, current, and refresh-required observation. */
Watch_Status :: enum u8 {
	Disabled,
	Watching,
	Refresh_Required,
}

/* Panel_Side is retained Darek presentation policy without layout geometry ownership. */
Panel_Side :: enum u8 {
	Invalid,
	Left,
	Right,
}

/* Policy contains selected runtime resource bounds. */
Policy :: struct {
	nodes:          u32,
	depth:          u16,
	retained_bytes: u64,
}

DEFAULT_POLICY :: Policy {
	nodes = MAX_NODES,
	depth = MAX_DEPTH,
	retained_bytes = MAX_RETAINED_TEXT_BYTES,
}

/* Root_Request borrows one canonical root while opening an instance. */
Root_Request :: struct {
	mode:      Root_Mode,
	path:      string,
	resource:  filesystem.Resource_ID,
	project:   project.Project_Handle,
	workspace: Workspace_Reference,
}

/* Root_Descriptor borrows the checked copied root retained by one instance. */
Root_Descriptor :: struct {
	mode:      Root_Mode,
	path:      string,
	resource:  filesystem.Resource_ID,
	project:   project.Project_Handle,
	workspace: Workspace_Reference,
}

/* Project_Root_Source borrows one canonical Project resolution for publication. */
Project_Root_Source :: struct {
	project:             project.Project_Handle,
	resource:            filesystem.Resource_ID,
	label:               string,
	path:                string,
	provider_generation: Provider_Generation,
	available:           bool,
}

/* Node_Handle rejects references across instance or tree replacement. */
Node_Handle :: struct {
	instance_id:         Instance_ID,
	instance_generation: Instance_Generation,
	node_generation:     Node_Generation,
	id:                  Node_ID,
}

/* Preview_Request copies one exact selected file intent for integration work. */
Preview_Request :: struct {
	instance_id:          Instance_ID,
	instance_generation:  Instance_Generation,
	node_generation:      Node_Generation,
	selection_generation: Selection_Generation,
	task_generation:      Task_Generation,
	target:               Node_Handle,
	resource:             filesystem.Resource_ID,
	path:                 string,
}

/* Preview_State_View exposes bounded preview policy and current request identity. */
Preview_State_View :: struct {
	enabled:              bool,
	selection_generation: Selection_Generation,
	task_generation:      Task_Generation,
	target:               Node_ID,
}

/* Follow_State_View exposes bounded file-follow policy and newest observation. */
Follow_State_View :: struct {
	enabled:             bool,
	observed_generation: u64,
	task_generation:     Task_Generation,
}

/* Panel_State_View exposes Darek-owned presentation policy without geometry ownership. */
Panel_State_View :: struct {
	side:                  Panel_Side,
	width:                 u32,
	extra_width:           bool,
	width_locked:          bool,
	directory_compression: bool,
	current_project_only:  bool,
	show_hidden:           bool,
	show_ignored:          bool,
	show_version_control:  bool,
	show_diagnostics:      bool,
	sort_mode:             Sort_Mode,
	filter:                string,
}

/* Watch_State_View exposes bounded watcher state without an operating-system handle. */
Watch_State_View :: struct {
	enabled:            bool,
	status:             Watch_Status,
	generation:         u64,
	pending_hints:      u32,
	provider_generation: Provider_Generation,
}

/* Node_Annotation is one copied provider decoration for a stable resource. */
Node_Annotation :: struct {
	resource:            filesystem.Resource_ID,
	provider_generation: Provider_Generation,
	version_control:     Version_Control_State,
	diagnostic:          Diagnostic_State,
	ignored:             bool,
}

/* Symbol_Source borrows one language-owned symbol tied to an exact file revision. */
Symbol_Source :: struct {
	id:              u64,
	parent_id:       u64,
	hierarchy_depth: u16,
	name:            string,
	start:           u64,
	end:             u64,
}

/* Node_Descriptor borrows one immutable node from the current generation. */
Node_Descriptor :: struct {
	handle:              Node_Handle,
	parent:              Node_ID,
	provider_id:         Provider_ID,
	provider_generation: Provider_Generation,
	kind:                Node_Kind,
	project:             project.Project_Handle,
	resource:            filesystem.Resource_ID,
	label:               string,
	path:                string,
	depth:               u16,
	children:            Child_State,
	actions:             Action_Roles,
	hidden:              bool,
	ignored:             bool,
	version_control:     Version_Control_State,
	diagnostic:          Diagnostic_State,
	symbol_id:           u64,
	source_revision:     u64,
	start:               u64,
	end:                 u64,
}

/* Instance_View borrows one complete current Darek state generation. */
Instance_View :: struct {
	id:                  Instance_ID,
	generation:          Instance_Generation,
	node_generation:     Node_Generation,
	task_generation:     Task_Generation,
	root:                Root_Descriptor,
	nodes:               []Node_Descriptor,
	selected:            Node_ID,
	has_selection:       bool,
	first_visible:       u32,
	viewport_nodes:      u32,
	visible:             bool,
	panel_side:          Panel_Side,
	selection_generation: Selection_Generation,
	preview:             Preview_State_View,
	follow:              Follow_State_View,
	watch:               Watch_State_View,
	annotation_generation: Provider_Generation,
	symbol_generation:   Provider_Generation,
	panel:               Panel_State_View,
}

/* Instance owns one non-copyable Darek lifecycle. */
Instance :: struct {
	state:  rawptr,
	closed: bool,
}

/* Tree_Projection owns one copied generic UI tree definition generation. */
Tree_Projection :: struct {
	state: rawptr,
}

/* Tree_Projection_View borrows generic nodes for one exact Darek generation. */
Tree_Projection_View :: struct {
	instance_id:     Instance_ID,
	node_generation: Node_Generation,
	nodes:           []ui.Tree_Node_Definition,
	current_node:    i32,
	first_visible:   u32,
	viewport_nodes:  u32,
}

/* Config supplies explicit lifecycle identity, policy, and allocation. */
Config :: struct {
	id:         Instance_ID,
	generation: Instance_Generation,
	policy:     Policy,
	allocator:  runtime.Allocator,
}

/* Usage reports current retained instance resources. */
Usage :: struct {
	nodes:          u32,
	retained_bytes: u64,
	allocation_bytes: u64,
}

/* Operation identifies the Darek transition that produced a failure. */
Operation :: enum u8 {
	None,
	Open,
	Inspect,
	Publish,
	Navigate,
	Expand,
	Refresh,
	Visibility,
	Close,
}

/* Failure_Code classifies expected Darek rejections. */
Failure_Code :: enum u16 {
	None,
	Invalid_Instance,
	Closed_Instance,
	Invalid_Config,
	Invalid_Policy,
	Invalid_Root,
	Invalid_Generation,
	Stale_Generation,
	Invalid_Node,
	Node_Not_Found,
	Duplicate_Node,
	Invalid_Parent,
	Node_Limit,
	Depth_Limit,
	Retained_Byte_Limit,
	Filesystem_Failure,
	Allocation,
}

/* Failure_Context reports one bounded Darek failure without partial publication. */
Failure_Context :: struct {
	operation:          Operation,
	code:               Failure_Code,
	instance_id:        Instance_ID,
	instance_generation: Instance_Generation,
	node_generation:    Node_Generation,
	node:               Node_ID,
	limit:              u64,
	actual:             u64,
	filesystem_failure: filesystem.Failure_Context,
}

/* policy_is_valid checks one complete selected runtime policy. */
policy_is_valid :: proc(policy: Policy) -> bool {
	return policy.nodes > 0 && policy.nodes <= MAX_NODES &&
		policy.depth > 0 && policy.depth <= MAX_DEPTH &&
		policy.retained_bytes > 0 && policy.retained_bytes <= MAX_RETAINED_TEXT_BYTES
}
