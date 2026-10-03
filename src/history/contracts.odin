// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package history owns bounded reversible editing history and its resource policy.
package history

import "../editor"
import editor_view "../view"
import "base:runtime"

/* KIBIBYTE is the binary byte unit used by history policy. */
KIBIBYTE :: u64(1024)
/* MEBIBYTE is 1,024 kibibytes. */
MEBIBYTE :: u64(1024) * KIBIBYTE
/* GIBIBYTE is 1,024 mebibytes. */
GIBIBYTE :: u64(1024) * MEBIBYTE

/* MIN_GLOBAL_RETAINED_BYTES is the smallest admitted process-wide history budget. */
MIN_GLOBAL_RETAINED_BYTES :: 16 * MEBIBYTE
/* MAX_GLOBAL_RETAINED_BYTES is the largest admitted process-wide history budget. */
MAX_GLOBAL_RETAINED_BYTES :: 8 * GIBIBYTE
/* DEFAULT_GLOBAL_RETAINED_BYTES is the measured initial process-wide history budget. */
DEFAULT_GLOBAL_RETAINED_BYTES :: 512 * MEBIBYTE
/* MIN_BUFFER_RETAINED_BYTES is the smallest admitted per-buffer history budget. */
MIN_BUFFER_RETAINED_BYTES :: 1 * MEBIBYTE
/* MAX_BUFFER_RETAINED_BYTES is the largest admitted per-buffer history budget. */
MAX_BUFFER_RETAINED_BYTES :: 2 * GIBIBYTE
/* DEFAULT_BUFFER_RETAINED_BYTES is the measured initial per-buffer history budget. */
DEFAULT_BUFFER_RETAINED_BYTES :: 256 * MEBIBYTE

/* MIN_GLOBAL_NODES is the smallest admitted process-wide node budget. */
MIN_GLOBAL_NODES :: u64(4_096)
/* MAX_GLOBAL_NODES is the largest admitted process-wide node budget. */
MAX_GLOBAL_NODES :: u64(1_000_000)
/* DEFAULT_GLOBAL_NODES is the measured initial process-wide node budget. */
DEFAULT_GLOBAL_NODES :: u64(250_000)
/* MIN_BUFFER_NODES is the smallest admitted per-buffer node budget. */
MIN_BUFFER_NODES :: u64(256)
/* DEFAULT_BUFFER_NODES is the measured initial per-buffer node budget. */
DEFAULT_BUFFER_NODES :: u64(100_000)

/* MIN_RECENT_UNITS is the smallest protected recent undo window. */
MIN_RECENT_UNITS :: u64(32)
/* MAX_RECENT_UNITS is the largest protected recent undo window. */
MAX_RECENT_UNITS :: u64(65_536)
/* DEFAULT_RECENT_UNITS is the initial protected recent undo window. */
DEFAULT_RECENT_UNITS :: u64(256)
/* MIN_RETAINED_DEPTH is the smallest admitted history depth. */
MIN_RETAINED_DEPTH :: u64(64)
/* MAX_RETAINED_DEPTH is the largest admitted history depth. */
MAX_RETAINED_DEPTH :: u64(250_000)
/* DEFAULT_RETAINED_DEPTH is the initial history depth. */
DEFAULT_RETAINED_DEPTH :: u64(65_536)
/* MIN_SIBLING_BRANCHES is the smallest branch capacity at one node. */
MIN_SIBLING_BRANCHES :: u64(2)
/* MAX_SIBLING_BRANCHES is the largest branch capacity at one node. */
MAX_SIBLING_BRANCHES :: u64(65_536)
/* DEFAULT_SIBLING_BRANCHES is the initial branch capacity at one node. */
DEFAULT_SIBLING_BRANCHES :: u64(1_024)

/* MIN_RECORDS_PER_UNIT is the smallest admitted atomic unit. */
MIN_RECORDS_PER_UNIT :: u64(1)
/* MAX_RECORDS_PER_UNIT matches the transaction splice admission ceiling. */
MAX_RECORDS_PER_UNIT :: u64(100_000)
/* DEFAULT_RECORDS_PER_UNIT admits the complete transaction splice ceiling. */
DEFAULT_RECORDS_PER_UNIT :: MAX_RECORDS_PER_UNIT
/* MIN_PAYLOAD_BYTES_PER_UNIT is the smallest configurable retained payload ceiling. */
MIN_PAYLOAD_BYTES_PER_UNIT :: 64 * KIBIBYTE
/* MAX_PAYLOAD_BYTES_PER_UNIT matches the transaction retained-text ceiling. */
MAX_PAYLOAD_BYTES_PER_UNIT :: 1 * GIBIBYTE
/* DEFAULT_PAYLOAD_BYTES_PER_UNIT is the initial retained payload ceiling. */
DEFAULT_PAYLOAD_BYTES_PER_UNIT :: 256 * MEBIBYTE

/* MIN_MULTIBUFFER_PARTICIPANTS is the smallest admitted participant set. */
MIN_MULTIBUFFER_PARTICIPANTS :: u64(1)
/* MAX_MULTIBUFFER_PARTICIPANTS matches the transaction participant ceiling. */
MAX_MULTIBUFFER_PARTICIPANTS :: u64(10_000)
/* DEFAULT_MULTIBUFFER_PARTICIPANTS is the initial linked participant ceiling. */
DEFAULT_MULTIBUFFER_PARTICIPANTS :: u64(1_000)
/* MIN_SELECTIVE_OPERATIONS is the smallest selective-analysis work budget. */
MIN_SELECTIVE_OPERATIONS :: u64(1_024)
/* MAX_SELECTIVE_OPERATIONS is the largest selective-analysis work budget. */
MAX_SELECTIVE_OPERATIONS :: u64(10_000_000)
/* DEFAULT_SELECTIVE_OPERATIONS is the initial selective-analysis work budget. */
DEFAULT_SELECTIVE_OPERATIONS :: u64(1_000_000)
/* MIN_INSPECTION_NODES is the smallest bounded inspection result. */
MIN_INSPECTION_NODES :: u64(8)
/* MAX_INSPECTION_NODES is the largest bounded inspection result. */
MAX_INSPECTION_NODES :: u64(4_096)
/* DEFAULT_INSPECTION_NODES is the initial inspection result ceiling. */
DEFAULT_INSPECTION_NODES :: u64(256)
/* MIN_PRUNING_OPERATIONS is the smallest pruning work budget per editor turn. */
MIN_PRUNING_OPERATIONS :: u64(64)
/* MAX_PRUNING_OPERATIONS is the largest pruning work budget per editor turn. */
MAX_PRUNING_OPERATIONS :: u64(65_536)
/* DEFAULT_PRUNING_OPERATIONS is the initial pruning work budget per editor turn. */
DEFAULT_PRUNING_OPERATIONS :: u64(4_096)
/* MAX_ORIGIN_BYTES bounds one retained UTF-8 origin descriptor. */
MAX_ORIGIN_BYTES :: u64(256)
/* MAX_COMMAND_BYTES bounds one retained UTF-8 command identity. */
MAX_COMMAND_BYTES :: u64(256)
/* DEFAULT_TYPING_GROUP_IDLE_MILLISECONDS is the maximum idle gap between compatible typing records. */
DEFAULT_TYPING_GROUP_IDLE_MILLISECONDS :: u64(1_000)

/* Store_ID identifies one live history store; zero is invalid. */
Store_ID :: distinct u64
/* History_ID identifies one buffer history for the lifetime of its store. */
History_ID :: distinct u64
/* Unit_ID identifies one complete user-visible undo unit; zero is invalid. */
Unit_ID :: distinct u64
/* Record_ID identifies one immutable buffer contribution; zero is invalid. */
Record_ID :: distinct u64
/* Link_ID identifies one complete multibuffer relation; zero is invalid. */
Link_ID :: distinct u64
/* Policy_Generation identifies one complete authoritative policy. */
Policy_Generation :: distinct u64
/* Source_Transaction_ID preserves the originating transaction identity without coupling packages. */
Source_Transaction_ID :: distinct u64
/* Source_Undo_Unit_ID preserves the originating transaction undo identity. */
Source_Undo_Unit_ID :: distinct u64

/* Node_ID is a checked non-pointer identity for one exact retained node generation. */
Node_ID :: struct {
	history_id: History_ID,
	slot:       u64,
	generation: u64,
}

/* Record_Origin classifies an admitted record producer without granting authority. */
Record_Origin :: enum u8 {
	Invalid,
	Built_In,
	Racket,
	Language_Tool,
	External_Proposal,
}

/* Grouping_Kind declares whether one record may participate in bounded semantic coalescence. */
Grouping_Kind :: enum u8 {
	Invalid,
	Independent,
	Typing_Insert,
	Typing_Backspace,
	Query_Replacement,
}

/*
Grouping_Context identifies one command turn without making elapsed time the source of intent.
The caller advances event_sequence for every resolved command and changes continuity when
cursor, selection, buffer, mode, or another semantic boundary ends the active group.
*/
Grouping_Context :: struct {
	kind:                   Grouping_Kind,
	view_id:                editor_view.View_ID,
	view_generation:        u32,
	continuity:             u64,
	event_sequence:         u64,
	monotonic_milliseconds: u64,
}

/* Navigation_Kind selects one semantic history operation. */
Navigation_Kind :: enum u8 {
	Invalid,
	Undo,
	Redo,
	Select_Branch,
	Selective_Undo,
}

/* Navigation_Outcome classifies a completed request without hiding expected alternatives. */
Navigation_Outcome :: enum u8 {
	Invalid,
	Applied,
	Already_Active,
	At_Root,
	No_Child,
	Branch_Choice_Required,
	Rejected,
}

/* Policy_Field identifies one resource field in a validation diagnostic. */
Policy_Field :: enum u8 {
	Invalid,
	Global_Retained_Bytes,
	Buffer_Retained_Bytes,
	Global_Nodes,
	Buffer_Nodes,
	Guaranteed_Recent_Units,
	Retained_Depth,
	Sibling_Branches,
	Records_Per_Unit,
	Payload_Bytes_Per_Unit,
	Multibuffer_Participants,
	Selective_Operations,
	Inspection_Nodes,
	Pruning_Operations,
}

/* Policy contains every global in-memory retention and work bound. */
Policy :: struct {
	global_retained_bytes:      u64,
	buffer_retained_bytes:      u64,
	global_nodes:               u64,
	buffer_nodes:               u64,
	guaranteed_recent_units:    u64,
	retained_depth:             u64,
	sibling_branches:           u64,
	records_per_unit:           u64,
	payload_bytes_per_unit:     u64,
	multibuffer_participants:   u64,
	selective_operations:       u64,
	inspection_nodes:           u64,
	pruning_operations:         u64,
}

/* DEFAULT_POLICY is the measured initial in-memory history policy. */
DEFAULT_POLICY :: Policy {
	global_retained_bytes = DEFAULT_GLOBAL_RETAINED_BYTES,
	buffer_retained_bytes = DEFAULT_BUFFER_RETAINED_BYTES,
	global_nodes = DEFAULT_GLOBAL_NODES,
	buffer_nodes = DEFAULT_BUFFER_NODES,
	guaranteed_recent_units = DEFAULT_RECENT_UNITS,
	retained_depth = DEFAULT_RETAINED_DEPTH,
	sibling_branches = DEFAULT_SIBLING_BRANCHES,
	records_per_unit = DEFAULT_RECORDS_PER_UNIT,
	payload_bytes_per_unit = DEFAULT_PAYLOAD_BYTES_PER_UNIT,
	multibuffer_participants = DEFAULT_MULTIBUFFER_PARTICIPANTS,
	selective_operations = DEFAULT_SELECTIVE_OPERATIONS,
	inspection_nodes = DEFAULT_INSPECTION_NODES,
	pruning_operations = DEFAULT_PRUNING_OPERATIONS,
}

/* Policy_Snapshot is one copied inspectable policy generation and its accounted usage. */
Policy_Snapshot :: struct {
	policy:             Policy,
	policy_generation: Policy_Generation,
	usage:              Resource_Usage,
}

/* Policy_Replacement_Request proposes one complete atomic policy generation. */
Policy_Replacement_Request :: struct {
	expected_generation: Policy_Generation,
	policy:              Policy,
	operation_limit:     u64,
	cancelled:           bool,
}

/* Policy_Replacement_Result reports one completed replacement and its bounded pruning. */
Policy_Replacement_Result :: struct {
	previous_generation: Policy_Generation,
	policy_generation:   Policy_Generation,
	pruned_nodes:        u64,
	usage:               Resource_Usage,
}

/* Allocator_Set supplies retained history storage and per-operation scratch storage. */
Allocator_Set :: struct {
	// The caller keeps this allocator alive until store_close returns.
	persistent: runtime.Allocator,
	// The caller keeps this allocator alive for every history operation.
	temporary:  runtime.Allocator,
}

/* Cursor_Context is the optional initiating logical selection context retained by one unit. */
Cursor_Context :: struct {
	present:                bool,
	view:                   editor_view.View_Handle,
	buffer_id:              editor.Buffer_ID,
	base_revision:          editor.Revision,
	result_revision:        editor.Revision,
	before_byte_offset:     editor.Byte_Offset,
	after_byte_offset:      editor.Byte_Offset,
	before_desired_column:  u32,
	after_desired_column:   u32,
	before_mark_present:    bool,
	after_mark_present:     bool,
	before_mark_offset:     editor.Byte_Offset,
	after_mark_offset:      editor.Byte_Offset,
	before_region_active:   bool,
	after_region_active:    bool,
	before_selection_shape: editor.Selection_Shape,
	after_selection_shape:  editor.Selection_Shape,
	before_rectangle_column_policy: editor.Rectangle_Column_Policy,
	after_rectangle_column_policy:  editor.Rectangle_Column_Policy,
}

/* Cursor_Restore is the bounded logical view outcome selected for one navigation. */
Cursor_Restore :: struct {
	present:                bool,
	initiating_view:        editor_view.View_Handle,
	buffer_id:              editor.Buffer_ID,
	byte_offset:            editor.Byte_Offset,
	desired_display_column: u32,
	mark_present:           bool,
	mark_offset:            editor.Byte_Offset,
	region_active:          bool,
	selection_shape:        editor.Selection_Shape,
	rectangle_column_policy: editor.Rectangle_Column_Policy,
}

/* Edit_Payload describes one normalized owned transition in base coordinates. */
Edit_Payload :: struct {
	start:            editor.Byte_Offset,
	end:              editor.Byte_Offset,
	replacement_text: string,
	removed_text:     string,
}

/* Record_Input is borrowed only for reservation and copied into retained storage on success. */
Record_Input :: struct {
	source_transaction_id: Source_Transaction_ID,
	source_undo_unit_id:   Source_Undo_Unit_ID,
	buffer_id:             editor.Buffer_ID,
	base_revision:         editor.Revision,
	result_revision:       editor.Revision,
	edits:                 []Edit_Payload,
	origin:                Record_Origin,
	origin_descriptor:     string,
	command:               string,
	cursor:                Cursor_Context,
	grouping:              Grouping_Context,
}

/* Navigation_Edit is one borrowed sequential transition prepared for publication. */
Navigation_Edit :: struct {
	start:       editor.Byte_Offset,
	end:         editor.Byte_Offset,
	replacement: string,
}

/* Resource_Usage reports the complete accounted storage and bounded work of a store. */
Resource_Usage :: struct {
	retained_bytes:       u64,
	retained_nodes:       u64,
	retained_records:     u64,
	retained_payload_bytes: u64,
	retained_links:       u64,
	pruning_operations:   u64,
	selective_operations: u64,
}

/* Node_Projection is a copied bounded description that reveals no internal pointer. */
Node_Projection :: struct {
	id:                  Node_ID,
	unit_id:             Unit_ID,
	parent:              Node_ID,
	preferred_child:     Node_ID,
	command:             string,
	creation_order:      u64,
	retained_bytes:      u64,
	record_count:        u64,
	payload_bytes:       u64,
	depth:               u64,
	child_count:         u64,
}

/* Link_Participant identifies one exact buffer node in a complete multibuffer unit. */
Link_Participant :: struct {
	store_id:       Store_ID,
	history_id:     History_ID,
	buffer_id:      editor.Buffer_ID,
	node_id:        Node_ID,
	base_revision:  editor.Revision,
	result_revision: editor.Revision,
}

/* Link_Projection is a caller-owned copy of one complete multibuffer relation. */
Link_Projection :: struct {
	id:                    Link_ID,
	source_transaction_id: Source_Transaction_ID,
	source_undo_unit_id:   Source_Undo_Unit_ID,
	participants:          []Link_Participant,
}

/* Multibuffer_Record_Input binds one borrowed record input to its owning history store. */
Multibuffer_Record_Input :: struct {
	store: ^Store,
	record: Record_Input,
}

/* Multibuffer_Navigation_Request selects one complete linked traversal. */
Multibuffer_Navigation_Request :: struct {
	kind:           Navigation_Kind,
	target_link_id: Link_ID,
}

/* Multibuffer_Navigation_Buffer exposes one participant's borrowed prepared edits. */
Multibuffer_Navigation_Buffer :: struct {
	buffer_id: editor.Buffer_ID,
	edits:     []Navigation_Edit,
}

/* Multibuffer_Navigation_Plan owns all participant plans until commit or abort. */
Multibuffer_Navigation_Plan :: struct {
	state:   rawptr,
	kind:    Navigation_Kind,
	link_id: Link_ID,
	buffers: []Multibuffer_Navigation_Buffer,
}

/* Multibuffer_Selective_Request names one linked unit and a per-participant work budget. */
Multibuffer_Selective_Request :: struct {
	target_link_id:      Link_ID,
	analysis_operations: u64,
	cancelled:           bool,
}

/* Multibuffer_Selective_Plan owns every proven compensating participant edit. */
Multibuffer_Selective_Plan :: struct {
	state:   rawptr,
	link_id: Link_ID,
	buffers: []Multibuffer_Navigation_Buffer,
}

/* Inspection_Request supplies exact state and explicit result and traversal ceilings. */
Inspection_Request :: struct {
	buffer_id:           editor.Buffer_ID,
	current_revision:    editor.Revision,
	active_node:         Node_ID,
	policy_generation:   Policy_Generation,
	result_limit:        u64,
	traversal_limit:     u64,
}

/* Inspection is an owned bounded projection that the caller releases with its allocator. */
Inspection :: struct {
	active:              Node_ID,
	parent:              Node_ID,
	preferred_child:     Node_ID,
	active_projection:   Node_Projection,
	parent_projection:   Node_Projection,
	preferred_projection: Node_Projection,
	has_parent:          bool,
	has_preferred_child: bool,
	children:            []Node_Projection,
	child_count:         u64,
	traversed_nodes:     u64,
	truncated:           bool,
	policy_generation:   Policy_Generation,
}

/* Navigation_Request identifies one checked bounded transition request. */
Navigation_Request :: struct {
	kind:                 Navigation_Kind,
	buffer_id:            editor.Buffer_ID,
	current_revision:     editor.Revision,
	active_node:          Node_ID,
	target_node:          Node_ID,
	selective_unit:       Unit_ID,
	policy_generation:    Policy_Generation,
	analysis_operations: u64,
}

/* Navigation_Result reports one semantic result and the fresh confirmed revision when applied. */
Navigation_Result :: struct {
	outcome:              Navigation_Outcome,
	active_node:          Node_ID,
	result_revision:      editor.Revision,
	policy_generation:    Policy_Generation,
}

/* Navigation_Plan owns bounded scratch coordinates until committed or aborted. */
Navigation_Plan :: struct {
	reservation:          Reservation,
	kind:                 Navigation_Kind,
	source_node:          Node_ID,
	target_node:          Node_ID,
	edits:                []Navigation_Edit,
	cursor:               Cursor_Restore,
}

/* Selective_Range is an optional current-revision range resolved from stable anchors. */
Selective_Range :: struct {
	present:              bool,
	revision:             editor.Revision,
	start:                editor.Byte_Offset,
	end:                  editor.Byte_Offset,
}

/* Selective_Request identifies one retained unit and one bounded dependency proof. */
Selective_Request :: struct {
	buffer_id:            editor.Buffer_ID,
	current_revision:     editor.Revision,
	active_node:          Node_ID,
	target_unit:          Unit_ID,
	policy_generation:    Policy_Generation,
	analysis_operations:  u64,
	range:                Selective_Range,
	cancelled:            bool,
}

/* Selective_Plan owns copied compensating edits until publication or abort. */
Selective_Plan :: struct {
	state:                rawptr,
	target_node:          Node_ID,
	target_unit:          Unit_ID,
	edits:                []Navigation_Edit,
	analysis_operations:  u64,
}

/* Store_Stats reports one single-buffer store without exposing retained pointers. */
Store_Stats :: struct {
	store_id:             Store_ID,
	history_id:           History_ID,
	buffer_id:            editor.Buffer_ID,
	current_revision:     editor.Revision,
	active_node:          Node_ID,
	active_parent:        Node_ID,
	active_preferred_child: Node_ID,
	active_child_count:   u64,
	active_record_count:  u64,
	active_payload_bytes: u64,
	active_grouping_kind: Grouping_Kind,
	policy_generation:    Policy_Generation,
	usage:                Resource_Usage,
}

/* Failure_Code classifies expected history rejection without changing canonical state. */
Failure_Code :: enum u16 {
	None,
	Invalid_Identity,
	Invalid_State,
	Invalid_Policy,
	Policy_Range,
	Policy_Relationship,
	Policy_Retention_Blocked,
	Wrong_Buffer,
	Stale_Revision,
	Stale_Generation,
	At_Retained_Root,
	No_Redo_Child,
	Branch_Choice_Required,
	Missing_Payload,
	Dependency_Conflict,
	Incomplete_Participant_Set,
	Divergent_Participant,
	Participant_Limit,
	Retained_Bytes_Limit,
	Node_Limit,
	Record_Limit,
	Branch_Limit,
	Depth_Limit,
	Inspection_Limit,
	Work_Limit,
	Persistent_Memory_Limit,
	Temporary_Memory_Limit,
	Cancelled,
}

/* Failure_Context identifies the rejected state, policy field, and violated bound. */
Failure_Context :: struct {
	code:                 Failure_Code,
	field:                Policy_Field,
	store_id:             Store_ID,
	history_id:           History_ID,
	node_id:              Node_ID,
	buffer_id:            editor.Buffer_ID,
	revision:             editor.Revision,
	policy_generation:    Policy_Generation,
	minimum:              u64,
	maximum:              u64,
	actual:               u64,
}

/* Store is an opaque owner of every live buffer history and the global policy. */
Store :: struct {
	state: rawptr,
}

/* Reservation is an opaque transaction-bound record prepared before publication. */
Reservation :: struct {
	state: rawptr,
}

/* Multibuffer_Reservation owns one complete linked record set before publication. */
Multibuffer_Reservation :: struct {
	state: rawptr,
}

/* node_id_is_valid reports whether an identity contains a live-shape nonzero value. */
node_id_is_valid :: proc(id: Node_ID) -> bool {
	return id.history_id != History_ID(0) && id.slot != 0 && id.generation != 0
}

/* policy_validate checks every field and cross-field relationship without changing state. */
policy_validate :: proc(policy: Policy) -> (ok: bool, failure: Failure_Context) {
	if valid, field_failure := policy_field_validate(policy.global_retained_bytes, MIN_GLOBAL_RETAINED_BYTES, MAX_GLOBAL_RETAINED_BYTES, .Global_Retained_Bytes); !valid {
		return false, field_failure
	}
	if valid, field_failure := policy_field_validate(policy.buffer_retained_bytes, MIN_BUFFER_RETAINED_BYTES, MAX_BUFFER_RETAINED_BYTES, .Buffer_Retained_Bytes); !valid {
		return false, field_failure
	}
	if valid, field_failure := policy_field_validate(policy.global_nodes, MIN_GLOBAL_NODES, MAX_GLOBAL_NODES, .Global_Nodes); !valid {
		return false, field_failure
	}
	if valid, field_failure := policy_field_validate(policy.buffer_nodes, MIN_BUFFER_NODES, policy.global_nodes, .Buffer_Nodes); !valid {
		return false, field_failure
	}
	if valid, field_failure := policy_field_validate(policy.guaranteed_recent_units, MIN_RECENT_UNITS, MAX_RECENT_UNITS, .Guaranteed_Recent_Units); !valid {
		return false, field_failure
	}
	if valid, field_failure := policy_field_validate(policy.retained_depth, MIN_RETAINED_DEPTH, MAX_RETAINED_DEPTH, .Retained_Depth); !valid {
		return false, field_failure
	}
	if valid, field_failure := policy_field_validate(policy.sibling_branches, MIN_SIBLING_BRANCHES, MAX_SIBLING_BRANCHES, .Sibling_Branches); !valid {
		return false, field_failure
	}
	if valid, field_failure := policy_field_validate(policy.records_per_unit, MIN_RECORDS_PER_UNIT, MAX_RECORDS_PER_UNIT, .Records_Per_Unit); !valid {
		return false, field_failure
	}
	if valid, field_failure := policy_field_validate(policy.payload_bytes_per_unit, MIN_PAYLOAD_BYTES_PER_UNIT, MAX_PAYLOAD_BYTES_PER_UNIT, .Payload_Bytes_Per_Unit); !valid {
		return false, field_failure
	}
	if valid, field_failure := policy_field_validate(policy.multibuffer_participants, MIN_MULTIBUFFER_PARTICIPANTS, MAX_MULTIBUFFER_PARTICIPANTS, .Multibuffer_Participants); !valid {
		return false, field_failure
	}
	if valid, field_failure := policy_field_validate(policy.selective_operations, MIN_SELECTIVE_OPERATIONS, MAX_SELECTIVE_OPERATIONS, .Selective_Operations); !valid {
		return false, field_failure
	}
	if valid, field_failure := policy_field_validate(policy.inspection_nodes, MIN_INSPECTION_NODES, MAX_INSPECTION_NODES, .Inspection_Nodes); !valid {
		return false, field_failure
	}
	if valid, field_failure := policy_field_validate(policy.pruning_operations, MIN_PRUNING_OPERATIONS, MAX_PRUNING_OPERATIONS, .Pruning_Operations); !valid {
		return false, field_failure
	}

	if policy.buffer_retained_bytes > policy.global_retained_bytes {
		return false, policy_relationship_failure(.Buffer_Retained_Bytes, policy.global_retained_bytes, policy.buffer_retained_bytes)
	}
	if policy.guaranteed_recent_units > policy.buffer_nodes {
		return false, policy_relationship_failure(.Guaranteed_Recent_Units, policy.buffer_nodes, policy.guaranteed_recent_units)
	}
	if policy.retained_depth > policy.buffer_nodes {
		return false, policy_relationship_failure(.Retained_Depth, policy.buffer_nodes, policy.retained_depth)
	}
	if policy.payload_bytes_per_unit > policy.global_retained_bytes {
		return false, policy_relationship_failure(.Payload_Bytes_Per_Unit, policy.global_retained_bytes, policy.payload_bytes_per_unit)
	}
	if policy.multibuffer_participants > policy.records_per_unit {
		return false, policy_relationship_failure(.Multibuffer_Participants, policy.records_per_unit, policy.multibuffer_participants)
	}
	return true, {}
}

@(private)
policy_field_validate :: proc(value, minimum, maximum: u64, field: Policy_Field) -> (ok: bool, failure: Failure_Context) {
	if value < minimum || value > maximum {
		return false, Failure_Context {
			code = .Policy_Range,
			field = field,
			minimum = minimum,
			maximum = maximum,
			actual = value,
		}
	}
	return true, {}
}

@(private)
policy_relationship_failure :: proc(field: Policy_Field, maximum, actual: u64) -> Failure_Context {
	return Failure_Context {
		code = .Policy_Relationship,
		field = field,
		maximum = maximum,
		actual = actual,
	}
}
