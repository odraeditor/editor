// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package interaction owns normalized input and bounded command resolution.
package interaction

import "base:runtime"

/* MAX_COMMAND_NAME_BYTES bounds one UTF-8 command identifier. */
MAX_COMMAND_NAME_BYTES :: 96
/* MAX_COMMAND_DESCRIPTION_BYTES bounds one diagnostic command description. */
MAX_COMMAND_DESCRIPTION_BYTES :: 256
/* MAX_COMMAND_UNAVAILABLE_REASON_BYTES bounds one catalog availability explanation. */
MAX_COMMAND_UNAVAILABLE_REASON_BYTES :: 128
/* MAX_PROTECTION_REASON_BYTES bounds one protected recovery-policy explanation. */
MAX_PROTECTION_REASON_BYTES :: 256
/* MAX_COMMANDS bounds one command registry generation. */
MAX_COMMANDS :: 2_048
/* MAX_BINDINGS bounds the legacy single-map snapshot during layered migration. */
MAX_BINDINGS :: 1_024
/* MAX_PROFILE_BINDINGS bounds one complete compiled layered profile. */
MAX_PROFILE_BINDINGS :: 16_384
/* MAX_MAPS bounds the definitions admitted by one interaction profile. */
MAX_MAPS :: 128
/* MAX_ACTIVE_MAPS bounds the maps selected by one checked context. */
MAX_ACTIVE_MAPS :: 16
/* MAX_BINDINGS_PER_MAP bounds one immutable map definition. */
MAX_BINDINGS_PER_MAP :: 4_096
/* MAX_ORDERING_CONSTRAINTS bounds explicit same-layer order per map. */
MAX_ORDERING_CONSTRAINTS :: 64
/* MAX_INSPECTION_ALTERNATIVES lets inspection cover every admitted profile binding. */
MAX_INSPECTION_ALTERNATIVES :: MAX_PROFILE_BINDINGS
/* MAX_ACTIVE_SNAPSHOTS bounds one registry to the single active map capability. */
MAX_ACTIVE_SNAPSHOTS :: 1
/* MAX_SEQUENCE_STROKES bounds one exact or pending key sequence. */
MAX_SEQUENCE_STROKES :: 16
/* MAX_KEYMAP_BYTES bounds persistent storage owned by one snapshot. */
MAX_KEYMAP_BYTES :: 32 * 1_024 * 1_024
/* MAX_DEFINITION_BYTES bounds copied profile and map input before compilation. */
MAX_DEFINITION_BYTES :: 8 * 1_024 * 1_024
/* MAX_IDENTITY_BYTES bounds one stable profile, map, context, or owner name. */
MAX_IDENTITY_BYTES :: 96
/* MAX_SOURCE_BYTES bounds one provider or source descriptor. */
MAX_SOURCE_BYTES :: 256
/* MAX_LOCATION_BYTES bounds one optional declaration location. */
MAX_LOCATION_BYTES :: 512
/* MAX_TEXT_BYTES bounds one normalized text payload. */
MAX_TEXT_BYTES :: 4 * 1_024
/* MAX_INTERACTION_PROFILES bounds one immutable profile catalog. */
MAX_INTERACTION_PROFILES :: 32
/* MAX_INTERACTION_STATES_PER_PROFILE bounds state definitions in one profile. */
MAX_INTERACTION_STATES_PER_PROFILE :: 16
/* MAX_INTERACTION_STATES bounds all states retained by one catalog. */
MAX_INTERACTION_STATES :: MAX_INTERACTION_PROFILES * MAX_INTERACTION_STATES_PER_PROFILE
/* MAX_SHARED_BINDING_SELECTORS bounds one explicit continuity contribution. */
MAX_SHARED_BINDING_SELECTORS :: 64
/* MAX_PROFILE_BINDING_SELECTORS bounds all shared selectors in one catalog. */
MAX_PROFILE_BINDING_SELECTORS :: 65_536
/* MAX_COMMAND_ENTRY_SURFACES bounds registered command-entry presentations. */
MAX_COMMAND_ENTRY_SURFACES :: 8
/* MAX_PROFILE_CATALOG_BYTES bounds retained compatibility metadata. */
MAX_PROFILE_CATALOG_BYTES :: 32 * 1_024 * 1_024
/* MAX_MODAL_PENDING_STROKES bounds one retained modal composition prefix. */
MAX_MODAL_PENDING_STROKES :: MAX_SEQUENCE_STROKES
/* MAX_MODAL_PENDING_TEXT_BYTES bounds one copied character target or slot name. */
MAX_MODAL_PENDING_TEXT_BYTES :: MAX_IDENTITY_BYTES
/* MAX_MODAL_COUNT bounds checked decimal composition without machine-width dependence. */
MAX_MODAL_COUNT :: u64(max(u32))

/* Registry_Generation identifies one immutable command registry generation. */
Registry_Generation :: distinct u64
/* Snapshot_Generation identifies one compiled keymap snapshot. */
Snapshot_Generation :: distinct u64
/* Profile_ID identifies one declared global interaction policy. */
Profile_ID :: distinct u64
/* Profile_Revision identifies one immutable revision of a profile definition. */
Profile_Revision :: distinct u64
/* Profile_Catalog_Generation identifies one immutable catalog generation. */
Profile_Catalog_Generation :: distinct u64
/* Interaction_State_ID identifies one profile-owned interaction state. */
Interaction_State_ID :: distinct u64
/* Interaction_State_Revision identifies one immutable state-policy revision. */
Interaction_State_Revision :: distinct u64
/* Command_Entry_Surface_ID identifies one canonical-name invocation presentation. */
Command_Entry_Surface_ID :: distinct u16
/* Command_Entry_Surface_Revision identifies one immutable surface revision. */
Command_Entry_Surface_Revision :: distinct u64
/* Map_ID identifies one keymap independently of load order and allocation. */
Map_ID :: distinct u64
/* Map_Revision identifies one immutable revision of a map definition. */
Map_Revision :: distinct u64
/* Context_ID identifies one checked interaction context. */
Context_ID :: distinct u64
/* Context_Generation identifies one admitted state of an interaction context. */
Context_Generation :: distinct u64
/* Owner_ID identifies the lifecycle owner of one contextual map. */
Owner_ID :: distinct u64
/* Owner_Generation identifies one checked lifecycle incarnation. */
Owner_Generation :: distinct u64
/* Command_Provider_ID identifies one execution-route owner. */
Command_Provider_ID :: distinct u16

/* Logical_Key_Kind classifies frontend-independent keys admitted by the resolver. */
Logical_Key_Kind :: enum u8 {
	Invalid,
	Unicode_Scalar,
	Left,
	Right,
	Up,
	Down,
	Home,
	End,
	Backspace,
	Delete,
	Enter,
	Tab,
	Insert,
	Prior,
	Next,
	Escape,
	F4,
}

/* Modifier identifies one logical modifier without encoding frontend bytes. */
Modifier :: enum u8 {
	Control,
	Meta,
	Alt,
	Super,
	Shift,
}

/* Modifiers is the supported logical modifier set for one key stroke. */
Modifiers :: bit_set[Modifier; u8]

/* Precedence_Class orders active maps from recovery policy through fallback. */
Precedence_Class :: enum u8 {
	Invalid,
	Protected_Recovery,
	Transient_Interaction,
	Component_Tool,
	Buffer_Local,
	Language_Context,
	Project,
	User_Global,
	Profile_Base,
	Factory_Fallback,
}

/* Ordering_Relation declares an explicit same-class dependency between maps. */
Ordering_Relation :: enum u8 {
	Invalid,
	Before,
	After,
}

/* Binding_Operation describes how one declaration affects its owning map. */
Binding_Operation :: enum u8 {
	Invalid,
	Bind,
	Replace,
	Unbind,
	Mask,
}

/* Unmatched_Input_Policy selects contextual fallthrough, insertion, or rejection. */
Unmatched_Input_Policy :: enum u8 {
	Invalid,
	Fallthrough,
	Text_Input,
	Reject,
}

/* Inspection_Query_Kind selects one bounded immutable snapshot view. */
Inspection_Query_Kind :: enum u8 {
	Invalid,
	Sequence,
	Command,
	Map,
	Active_Maps,
	Bindings,
	Snapshot,
	Compatibility,
	Latest_Rejection,
}

/* Inspection_Disposition explains how one definition participates in resolution. */
Inspection_Disposition :: enum u8 {
	Invalid,
	Effective,
	Shadowed,
	Masked,
	Inactive,
	Rejected,
}

/* Inspection_Record_Kind identifies the definition represented by one inspection row. */
Inspection_Record_Kind :: enum u8 {
	Invalid,
	Binding,
	Remap,
	Map,
	Snapshot,
	Catalog,
	Profile,
	State,
	Surface,
	Rejection,
}

/* Key_Stroke is one normalized logical key and modifier combination. */
Key_Stroke :: struct {
	kind:      Logical_Key_Kind,
	scalar:    rune,
	modifiers: Modifiers,
}

/* Key_Sequence stores one complete bounded normalized input sequence by value. */
Key_Sequence :: struct {
	strokes:      [MAX_SEQUENCE_STROKES]Key_Stroke,
	stroke_count: u8,
}

/* Input_Kind distinguishes normalized key, text, and pointer input. */
Input_Kind :: enum u8 {
	Invalid,
	Key,
	Text_Commit,
	Pointer,
}

/* Input is a borrowed normalized event; text remains caller-owned for the call. */
Input :: struct {
	kind:    Input_Kind,
	stroke:  Key_Stroke,
	text:    string,
	pointer: Pointer_Event,
}

/* Command_Handle is a checked runtime identity scoped to one registry generation. */
Command_Handle :: struct {
	registry_generation: Registry_Generation,
	slot:                u16,
	entry_generation:    u32,
}

/* Implementation_Class selects the owner of admitted command execution. */
Implementation_Class :: enum u8 {
	Invalid,
	Native,
	Racket,
}

/* Invocation_Class identifies resolver behavior required before command dispatch. */
Invocation_Class :: enum u8 {
	Invalid,
	Ordinary,
	Text_Input,
	Cancellation,
}

/* Text_Requirement declares whether a command accepts normalized text. */
Text_Requirement :: enum u8 {
	Invalid,
	Prohibited,
	Optional,
	Required,
}

/* Command_Effect identifies canonical state that successful execution may change. */
Command_Effect :: enum u8 {
	Buffer,
	View,
	Lifecycle,
	Text_Mutation,
}

/* Command_Effects is the bounded effect declaration for one command. */
Command_Effects :: bit_set[Command_Effect; u8]

/* Command_Route is one provider-owned internal implementation identity. */
Command_Route :: struct {
	provider:  Command_Provider_ID,
	operation: u16,
}

/* Command_Requirement identifies editor state required for interactive admission. */
Command_Requirement :: enum u8 {
	Active_Buffer,
	Active_Document,
	Active_Region,
	Active_Terminal,
}

/* Command_Requirements is the bounded interactive admission requirement set. */
Command_Requirements :: bit_set[Command_Requirement; u8]

/* Command_Availability classifies one command in an immutable catalog view. */
Command_Availability :: enum u8 {
	Invalid,
	Available,
	Unavailable,
}

/* Command_Definition borrows one command declaration during registry construction. */
Command_Definition :: struct {
	name:             string,
	route:            Command_Route,
	implementation:   Implementation_Class,
	invocation:       Invocation_Class,
	text_requirement: Text_Requirement,
	effects:          Command_Effects,
	description:      string,
	interactive:      bool,
	requirements:     Command_Requirements,
	provenance:       Definition_Provenance,
}

/* Command_Metadata is an immutable copied view of one registered command. */
Command_Metadata :: struct {
	handle:           Command_Handle,
	name:             string,
	route:            Command_Route,
	implementation:   Implementation_Class,
	invocation:       Invocation_Class,
	text_requirement: Text_Requirement,
	effects:          Command_Effects,
	description:      string,
	interactive:      bool,
	requirements:     Command_Requirements,
	provenance:       Definition_Provenance,
}

/* Command_Catalog_Context records state used for checked interactive availability. */
Command_Catalog_Context :: struct {
	active_buffer:   bool,
	active_document: bool,
	active_region:   bool,
	active_terminal: bool,
	profile:         Profile_Identity,
	state:           Interaction_State_Identity,
	admits_text_input: bool,
	admitted_effects: Command_Effects,
	command_entry_surface: Command_Entry_Surface_Identity,
}

/* Command_Catalog_Entry is one immutable interactive command and active binding set. */
Command_Catalog_Entry :: struct {
	metadata:           Command_Metadata,
	availability:       Command_Availability,
	unavailable_reason: string,
	bindings:           []Key_Sequence,
}

/* Command_Catalog owns a bounded immutable command projection until explicit close. */
Command_Catalog :: struct {
	registry_generation: Registry_Generation,
	snapshot_generation: Snapshot_Generation,
	command_entry_surface: Command_Entry_Surface_Identity,
	entries:             []Command_Catalog_Entry,
	state:               rawptr,
}

/* Command_Registry is an opaque owner of one immutable command generation. */
Command_Registry :: struct {
	state:  rawptr,
	closed: bool,
}

/* Map_Identity identifies one stable immutable map revision. */
Map_Identity :: struct {
	id:       Map_ID,
	revision: Map_Revision,
}

/* Profile_Identity identifies one stable immutable profile revision. */
Profile_Identity :: struct {
	id:       Profile_ID,
	revision: Profile_Revision,
}

/* Interaction_State_Identity identifies one immutable profile-owned policy. */
Interaction_State_Identity :: struct {
	id:       Interaction_State_ID,
	revision: Interaction_State_Revision,
}

/* Modal_Pending_Kind classifies bounded transient modal composition. */
Modal_Pending_Kind :: enum u8 {
	None,
	Count,
	Operator,
	Character_Target,
	Named_Slot,
	Command_Entry,
}

/* Modal_Character_Target_Kind identifies one line-local character movement. */
Modal_Character_Target_Kind :: enum u8 {
	None,
	Find_Next,
	Find_Previous,
	Till_Next,
	Till_Previous,
}

/* Modal_Operator_Kind identifies one bounded operator-pending action. */
Modal_Operator_Kind :: enum u8 {
	None,
	Delete,
	Change,
	Yank,
	Indent,
	Outdent,
	Replace,
}

/* Modal_Operator_Stage identifies the incomplete suffix retained by one operator. */
Modal_Operator_Stage :: enum u8 {
	None,
	Target,
	Text_Object,
	Character_Target,
	Buffer_Start,
}

/* Modal_Operator_Target_Kind identifies one complete semantic operator target. */
Modal_Operator_Target_Kind :: enum u8 {
	None,
	Previous_Grapheme,
	Next_Grapheme,
	Previous_Line,
	Next_Line,
	Previous_Page,
	Next_Page,
	Line_Start,
	Line_End,
	Line_First_Non_Whitespace,
	Previous_Word,
	Next_Word_Start,
	Word_End,
	Buffer_Start,
	Buffer_End,
	Character_Target,
	Repeat_Character_Target,
	Search_Forward,
	Search_Backward,
	Search_Next,
	Search_Previous,
	Named_Slot_Before,
	Named_Slot_After,
	Line,
	Inner_Word,
	Around_Word,
	Inner_Paragraph,
	Around_Paragraph,
	Active_Selection,
}

/* Modal_Visual_Kind identifies one canonical selection presentation. */
Modal_Visual_Kind :: enum u8 {
	None,
	Character,
	Line,
	Block,
}

/* Modal_Visual_State retains active-end intent while the canonical region owns the range. */
Modal_Visual_State :: struct {
	active:              bool,
	kind:                Modal_Visual_Kind,
	profile:             Profile_Identity,
	state:               Interaction_State_Identity,
	catalog_generation:  Profile_Catalog_Generation,
	snapshot_generation: Snapshot_Generation,
	ctx:                 Context_Handle,
	view_identity:       u64,
	view_generation:     u32,
	buffer_identity:     u64,
	buffer_revision:     u64,
	anchor_offset:       u64,
	cursor_offset:       u64,
}

/* Modal_Operator_Disposition describes one bounded operator composition result. */
Modal_Operator_Disposition :: enum u8 {
	Invalid,
	Pass_Through,
	Pending,
	Ready,
	Cancelled,
}

/* Modal_Navigation_Disposition describes one bounded navigation composition result. */
Modal_Navigation_Disposition :: enum u8 {
	Invalid,
	Pass_Through,
	Pending,
	Character_Target,
	Repeat_Character_Target,
	Cancelled,
}

/* Modal_Pending_Request borrows one complete transient modal candidate. */
Modal_Pending_Request :: struct {
	kind:                Modal_Pending_Kind,
	profile:             Profile_Identity,
	state:               Interaction_State_Identity,
	catalog_generation:  Profile_Catalog_Generation,
	snapshot_generation: Snapshot_Generation,
	ctx:                 Context_Handle,
	view_identity:       u64,
	view_generation:     u32,
	buffer_identity:     u64,
	buffer_revision:     u64,
	operator_origin:     u64,
	sequence:            Key_Sequence,
	text:                string,
	count:               u64,
	character_target:    Modal_Character_Target_Kind,
	operator:            Modal_Operator_Kind,
	operator_stage:      Modal_Operator_Stage,
	target_count:        u64,
	operator_count_explicit: bool,
	target_count_explicit: bool,
	named_slot:          string,
	command_entry_surface: Command_Entry_Surface_Identity,
}

/* Modal_Pending_State owns one copied bounded transient modal interaction. */
Modal_Pending_State :: struct {
	kind:                Modal_Pending_Kind,
	profile:             Profile_Identity,
	state:               Interaction_State_Identity,
	catalog_generation:  Profile_Catalog_Generation,
	snapshot_generation: Snapshot_Generation,
	ctx:                 Context_Handle,
	view_identity:       u64,
	view_generation:     u32,
	buffer_identity:     u64,
	buffer_revision:     u64,
	operator_origin:     u64,
	strokes:             [MAX_MODAL_PENDING_STROKES]Key_Stroke,
	stroke_count:        u8,
	text:                [MAX_MODAL_PENDING_TEXT_BYTES]u8,
	text_length:         u8,
	count:               u64,
	character_target:    Modal_Character_Target_Kind,
	operator:            Modal_Operator_Kind,
	operator_stage:      Modal_Operator_Stage,
	target_count:        u64,
	operator_count_explicit: bool,
	target_count_explicit: bool,
	named_slot:          [MAX_MODAL_PENDING_TEXT_BYTES]u8,
	named_slot_length:   u8,
	command_entry_surface: Command_Entry_Surface_Identity,
}

/* Modal_Command_Entry_Request binds one command surface to its exact source context. */
Modal_Command_Entry_Request :: struct {
	profile:             Profile_Identity,
	state:               Interaction_State_Identity,
	catalog_generation:  Profile_Catalog_Generation,
	snapshot_generation: Snapshot_Generation,
	ctx:                 Context_Handle,
	view_identity:       u64,
	view_generation:     u32,
	buffer_identity:     u64,
	buffer_revision:     u64,
	sequence:            Key_Sequence,
	surface:             Command_Entry_Surface_Identity,
}

/* Modal_Navigation_Request binds one input to the exact editable context it observed. */
Modal_Navigation_Request :: struct {
	profile:             Profile_Identity,
	state:               Interaction_State_Identity,
	catalog_generation:  Profile_Catalog_Generation,
	snapshot_generation: Snapshot_Generation,
	ctx:                 Context_Handle,
	view_identity:       u64,
	view_generation:     u32,
	buffer_identity:     u64,
	buffer_revision:     u64,
	point_offset:        u64,
	input:               Input,
}

/* Modal_Navigation_Result owns the bounded target text for immediate dispatch. */
Modal_Navigation_Result :: struct {
	disposition:     Modal_Navigation_Disposition,
	count:           u64,
	count_explicit:  bool,
	character_target: Modal_Character_Target_Kind,
	text:            [MAX_MODAL_PENDING_TEXT_BYTES]u8,
	text_length:     u8,
}

/* Modal_Operator_Request binds one input to the exact editable context it observed. */
Modal_Operator_Request :: struct {
	profile:             Profile_Identity,
	state:               Interaction_State_Identity,
	catalog_generation:  Profile_Catalog_Generation,
	snapshot_generation: Snapshot_Generation,
	ctx:                 Context_Handle,
	view_identity:       u64,
	view_generation:     u32,
	buffer_identity:     u64,
	buffer_revision:     u64,
	point_offset:        u64,
	input:               Input,
}

/* Modal_Operator_Capture freezes the source identity observed before execution. */
Modal_Operator_Capture :: struct {
	profile:             Profile_Identity,
	state:               Interaction_State_Identity,
	catalog_generation:  Profile_Catalog_Generation,
	snapshot_generation: Snapshot_Generation,
	ctx:                 Context_Handle,
	view_identity:       u64,
	view_generation:     u32,
	buffer_identity:     u64,
	buffer_revision:     u64,
	point_offset:        u64,
}

/* Modal_Operator_Result owns one complete semantic operation for immediate execution. */
Modal_Operator_Result :: struct {
	disposition:      Modal_Operator_Disposition,
	operator:         Modal_Operator_Kind,
	target:           Modal_Operator_Target_Kind,
	count:            u64,
	count_explicit:   bool,
	character_target: Modal_Character_Target_Kind,
	text:             [MAX_MODAL_PENDING_TEXT_BYTES]u8,
	text_length:      u8,
	named_slot:       [MAX_MODAL_PENDING_TEXT_BYTES]u8,
	named_slot_length: u8,
	sequence:         Key_Sequence,
	capture:          Modal_Operator_Capture,
}

/* Modal_Operator_Execution_State retains one checked operation across a prompt turn. */
Modal_Operator_Execution_State :: struct {
	active:       bool,
	deferred:     bool,
	operation:    Modal_Operator_Result,
	start_offset: u64,
	end_offset:   u64,
	slot_generation: u64,
	backward:     bool,
}

/* Modal_Character_Search_State retains the last admitted line-character search. */
Modal_Character_Search_State :: struct {
	valid:               bool,
	profile:             Profile_Identity,
	state:               Interaction_State_Identity,
	ctx:                 Context_Handle,
	view_identity:       u64,
	view_generation:     u32,
	buffer_identity:     u64,
	buffer_revision:     u64,
	character_target:    Modal_Character_Target_Kind,
	text:                [MAX_MODAL_PENDING_TEXT_BYTES]u8,
	text_length:         u8,
}

/* State_Transition_Request identifies one exact checked state change. */
State_Transition_Request :: struct {
	catalog_generation:  Profile_Catalog_Generation,
	snapshot_generation: Snapshot_Generation,
	profile:             Profile_Identity,
	source:              Interaction_State_Identity,
	target:              Interaction_State_Identity,
}

/* Profile_Selection_Request identifies one exact session-only profile change. */
Profile_Selection_Request :: struct {
	catalog_generation:  Profile_Catalog_Generation,
	snapshot_generation: Snapshot_Generation,
	target:              Profile_Identity,
}

/* Command_Entry_Surface_Identity identifies one immutable command-entry presentation. */
Command_Entry_Surface_Identity :: struct {
	id:       Command_Entry_Surface_ID,
	revision: Command_Entry_Surface_Revision,
}

/* Binding_Scope declares profile and state applicability for one contribution. */
Binding_Scope :: enum u8 {
	Invalid,
	Protected_Recovery,
	Shared_Continuity,
	Profile_Specific,
	State_Specific,
}

/* Profile_State_Selector names one exact compatibility target. */
Profile_State_Selector :: struct {
	profile_id: Profile_ID,
	state_id:   Interaction_State_ID,
}

/* Interaction_State_Definition borrows one checked state policy. */
Interaction_State_Definition :: struct {
	identity:              Interaction_State_Identity,
	name:                  string,
	admits_text_input:     bool,
	admitted_effects:      Command_Effects,
	provenance:            Definition_Provenance,
}

/* Command_Entry_Surface_Definition borrows one canonical registry presentation. */
Command_Entry_Surface_Definition :: struct {
	identity:   Command_Entry_Surface_Identity,
	name:       string,
	provenance: Definition_Provenance,
}

/* Context_Handle is valid only for one checked interaction-context generation. */
Context_Handle :: struct {
	id:         Context_ID,
	generation: Context_Generation,
}

/* Owner_Handle is valid only for one checked contextual-owner generation. */
Owner_Handle :: struct {
	id:         Owner_ID,
	generation: Owner_Generation,
}

/* Definition_Provenance borrows bounded source metadata during compilation. */
Definition_Provenance :: struct {
	provider: string,
	source:   string,
	location: string,
}

/* Ordering_Constraint borrows one explicit same-class map relation. */
Ordering_Constraint :: struct {
	relation: Ordering_Relation,
	other:    Map_ID,
}

/* Context_Requirement declares the checked owner needed to activate one map. */
Context_Requirement :: struct {
	ctx:   Context_Handle,
	owner: Owner_Handle,
}

/* Binding_Definition borrows one command name and one bounded logical sequence. */
Binding_Definition :: struct {
	strokes:      [MAX_SEQUENCE_STROKES]Key_Stroke,
	stroke_count: u8,
	command_name: string,
}

/* Layered_Binding_Definition borrows one attributed map operation during compilation. */
Layered_Binding_Definition :: struct {
	sequence:     Key_Sequence,
	command_name: string,
	operation:    Binding_Operation,
	scope:        Binding_Scope,
	selectors:    []Profile_State_Selector,
	provenance:   Definition_Provenance,
	protection_reason: string,
}

/* Command_Remap_Definition redirects one semantic command inside one map. */
Command_Remap_Definition :: struct {
	from_command_name: string,
	to_command_name:   string,
	provenance:        Definition_Provenance,
}

/* Map_Definition borrows one immutable contextual map during private compilation. */
Map_Definition :: struct {
	identity:              Map_Identity,
	name:                  string,
	owner:                 Owner_Handle,
	precedence:            Precedence_Class,
	priority:              i32,
	context_requirement:   Context_Requirement,
	bindings:              []Layered_Binding_Definition,
	remaps:                []Command_Remap_Definition,
	ordering_constraints:  []Ordering_Constraint,
	unmatched_input_policy: Unmatched_Input_Policy,
	provenance:            Definition_Provenance,
}

/* Profile_Definition borrows one complete global policy during candidate compilation. */
Profile_Definition :: struct {
	identity:           Profile_Identity,
	name:               string,
	states:             []Interaction_State_Definition,
	initial_state:      Interaction_State_ID,
	maps:               []Map_Definition,
	text_fallback_name: string,
}

/* Profile_Catalog_Definition borrows one complete atomic compatibility candidate. */
Profile_Catalog_Definition :: struct {
	generation:       Profile_Catalog_Generation,
	profiles:         []Profile_Definition,
	active_profile:   Profile_ID,
	active_state:     Interaction_State_ID,
	surfaces:         []Command_Entry_Surface_Definition,
}

/* Profile_Compatibility_Policy fixes catalog limits selected by resource evidence. */
Profile_Compatibility_Policy :: struct {
	max_profiles:                 u16,
	max_states_per_profile:       u16,
	max_total_states:             u16,
	max_shared_selectors:         u16,
	max_total_selectors:          u32,
	max_command_entry_surfaces:   u16,
	max_catalog_bytes:            u64,
}

/* DEFAULT_PROFILE_COMPATIBILITY_POLICY is the measured initial catalog policy. */
DEFAULT_PROFILE_COMPATIBILITY_POLICY :: Profile_Compatibility_Policy {
	max_profiles = MAX_INTERACTION_PROFILES,
	max_states_per_profile = MAX_INTERACTION_STATES_PER_PROFILE,
	max_total_states = MAX_INTERACTION_STATES,
	max_shared_selectors = MAX_SHARED_BINDING_SELECTORS,
	max_total_selectors = MAX_PROFILE_BINDING_SELECTORS,
	max_command_entry_surfaces = MAX_COMMAND_ENTRY_SURFACES,
	max_catalog_bytes = MAX_PROFILE_CATALOG_BYTES,
}

/* Profile_Catalog is an opaque immutable catalog owner until explicit close. */
Profile_Catalog :: struct {
	state:  rawptr,
	closed: bool,
}

/* Profile_Compatibility_Usage reports exact catalog definitions and storage. */
Profile_Compatibility_Usage :: struct {
	profile_count:              u16,
	state_count:                u16,
	scoped_binding_count:       u32,
	shared_selector_count:      u32,
	command_entry_surface_count: u16,
	definition_bytes:           u64,
	retained_bytes:             u64,
	temporary_peak_bytes:       u64,
}

/* Active_Context borrows the checked owners used to select contextual maps. */
Active_Context :: struct {
	identity: Context_Handle,
	owners:   []Owner_Handle,
}

/* Frontend_Key_Capabilities declares normalized protected strokes a frontend can produce. */
Frontend_Key_Capabilities :: struct {
	control_modified_unicode: bool,
	meta_modified_unicode:    bool,
}

/* Keymap_Definition borrows one complete map during private compilation. */
Keymap_Definition :: struct {
	registry_generation: Registry_Generation,
	bindings:            []Binding_Definition,
	text_fallback_name:  string,
}

/* Resolution_Policy fixes resource bounds and protected-policy enforcement. */
Resolution_Policy :: struct {
	max_maps:                    u16,
	max_active_maps:             u16,
	max_bindings_per_map:        u16,
	max_total_bindings:          u32,
	max_sequence_strokes:        u8,
	max_ordering_constraints:    u16,
	max_definition_bytes:        u64,
	max_snapshot_bytes:          u64,
	max_inspection_alternatives: u16,
	enforce_protected_policy:    bool,
	frontend:                    Frontend_Key_Capabilities,
}

/* DEFAULT_RESOLUTION_POLICY is the measured initial layered-keymap policy. */
DEFAULT_RESOLUTION_POLICY :: Resolution_Policy {
	max_maps = MAX_MAPS,
	max_active_maps = MAX_ACTIVE_MAPS,
	max_bindings_per_map = MAX_BINDINGS_PER_MAP,
	max_total_bindings = MAX_PROFILE_BINDINGS,
	max_sequence_strokes = MAX_SEQUENCE_STROKES,
	max_ordering_constraints = MAX_ORDERING_CONSTRAINTS,
	max_definition_bytes = MAX_DEFINITION_BYTES,
	max_snapshot_bytes = MAX_KEYMAP_BYTES,
	max_inspection_alternatives = MAX_INSPECTION_ALTERNATIVES,
	enforce_protected_policy = true,
	frontend = {
		control_modified_unicode = true,
		meta_modified_unicode = true,
	},
}

/* Resolution_Snapshot is an opaque owner of one immutable compiled keymap. */
Resolution_Snapshot :: struct {
	state:  rawptr,
	closed: bool,
}

/* Snapshot_Identity binds one compiled generation to its registry and profile. */
Snapshot_Identity :: struct {
	generation:          Snapshot_Generation,
	registry_generation: Registry_Generation,
	profile:             Profile_Identity,
	ctx:                 Context_Handle,
}

/* Pending_State owns at most one unresolved sequence for one active snapshot. */
Pending_State :: struct {
	snapshot_generation: Snapshot_Generation,
	strokes:             [MAX_SEQUENCE_STROKES]Key_Stroke,
	stroke_count:        u8,
}

/* Resolution_Kind classifies every admitted resolver outcome. */
Resolution_Kind :: enum u8 {
	Invalid,
	Command,
	Pending,
	Unbound,
	Rejected,
}

/* Resolution reports one checked command and a borrowed optional text argument. */
Resolution :: struct {
	kind:    Resolution_Kind,
	command: Command_Handle,
	text:    string,
}

/* Inspection_Query borrows one selector for a bounded immutable snapshot query. */
Inspection_Query :: struct {
	kind:         Inspection_Query_Kind,
	sequence:     Key_Sequence,
	command_name: string,
	map_id:       Map_ID,
	include_inactive: bool,
}

/* Inspection_Record is one copied winner, shadow, mask, inactive, or rejected entry. */
Inspection_Record :: struct {
	kind:        Inspection_Record_Kind,
	disposition: Inspection_Disposition,
	sequence:    Key_Sequence,
	command:     Command_Handle,
	command_name: string,
	original_command: Command_Handle,
	original_command_name: string,
	remap_target: Command_Handle,
	remap_target_name: string,
	map_identity: Map_Identity,
	map_name:     string,
	owner:        Owner_Handle,
	precedence:  Precedence_Class,
	priority:    i32,
	active:      bool,
	operation:   Binding_Operation,
	provenance:  Definition_Provenance,
	protected:   bool,
	protection_reason: string,
	catalog_generation: Profile_Catalog_Generation,
	profile:     Profile_Identity,
	profile_name: string,
	state:       Interaction_State_Identity,
	state_name:  string,
	state_admits_text_input: bool,
	state_admitted_effects: Command_Effects,
	binding_scope: Binding_Scope,
	selectors:   []Profile_State_Selector,
	command_entry_surface: Command_Entry_Surface_Identity,
	command_entry_surface_name: string,
	effects_admitted: bool,
	failure:     Failure_Context,
}

/* Inspection_Result owns bounded copied records until inspection_result_close. */
Inspection_Result :: struct {
	snapshot: Snapshot_Identity,
	catalog_generation: Profile_Catalog_Generation,
	active_state: Interaction_State_Identity,
	pending:  Pending_State,
	latest_rejection: Failure_Context,
	records:  []Inspection_Record,
	usage:    Keymap_Usage,
	state:    rawptr,
	closed:   bool,
}

/* Failure_Code classifies expected registry, compilation, and resolution failures. */
Failure_Code :: enum u16 {
	None,
	Invalid_Registry,
	Invalid_Command,
	Duplicate_Command,
	Command_Limit,
	Invalid_Name,
	Invalid_Description,
	Invalid_Implementation,
	Invalid_Route,
	Duplicate_Route,
	Invalid_Text_Requirement,
	Invalid_Effects,
	Persistent_Memory_Limit,
	Retained_Snapshot,
	Snapshot_Limit,
	Invalid_Snapshot,
	Stale_Registry,
	Stale_Snapshot,
	Invalid_Binding,
	Duplicate_Binding,
	Ambiguous_Binding,
	Unknown_Command,
	Binding_Limit,
	Sequence_Limit,
	Keymap_Memory_Limit,
	Invalid_Input,
	Malformed_Text,
	Text_Limit,
	Missing_Text_Fallback,
	Invalid_Text_Fallback,
	Generation_Limit,
	Invalid_Profile,
	Invalid_Map,
	Invalid_Context,
	Invalid_Owner,
	Stale_Profile,
	Stale_Context,
	Stale_Owner,
	Map_Limit,
	Active_Map_Limit,
	Map_Binding_Limit,
	Definition_Memory_Limit,
	Invalid_Precedence,
	Invalid_Ordering,
	Ordering_Cycle,
	Ordering_Conflict,
	Invalid_Operation,
	Invalid_Provenance,
	Invalid_Remap,
	Protected_Binding,
	Unsupported_Protected_Input,
	Inspection_Limit,
	Invalid_Context_Map,
	Context_Map_Limit,
	Context_Input_Rejected,
	Invalid_Profile_Catalog,
	Stale_Profile_Catalog,
	Profile_Catalog_Limit,
	Invalid_Interaction_State,
	Stale_Interaction_State,
	Interaction_State_Limit,
	Invalid_Binding_Scope,
	Invalid_Shared_Selector,
	Shared_Selector_Limit,
	Incompatible_Shared_Binding,
	Invalid_Command_Entry_Surface,
	Command_Entry_Surface_Limit,
	Command_Effect_Rejected,
	Profile_Catalog_Memory_Limit,
}

/* Failure_Context identifies the rejected identity, resource, and applicable bound. */
Failure_Context :: struct {
	code:                Failure_Code,
	registry_generation: Registry_Generation,
	snapshot_generation: Snapshot_Generation,
	command:             Command_Handle,
	binding_index:       u32,
	stroke_count:        u8,
	limit:               u64,
	actual:              u64,
	profile:             Profile_Identity,
	catalog_generation:  Profile_Catalog_Generation,
	state:               Interaction_State_Identity,
	binding_scope:       Binding_Scope,
	selector_index:      u32,
	command_entry_surface: Command_Entry_Surface_Identity,
	map_identity:        Map_Identity,
	ctx:                 Context_Handle,
	owner:               Owner_Handle,
}

/* Keymap_Usage reports exact admitted definitions, active indexes, and owned bytes. */
Keymap_Usage :: struct {
	map_count:               u16,
	active_map_count:        u16,
	binding_count:           u32,
	remap_count:             u32,
	ordering_constraint_count: u32,
	definition_bytes:        u64,
	snapshot_bytes:          u64,
	temporary_peak_bytes:    u64,
	inspection_records:      u16,
}

/* Registry_Stats reports immutable registry occupancy and owned storage. */
Registry_Stats :: struct {
	generation:    Registry_Generation,
	command_count: u16,
	storage_bytes: u64,
}

/* Snapshot_Stats reports compiled map occupancy and owned storage. */
Snapshot_Stats :: struct {
	generation:          Snapshot_Generation,
	registry_generation: Registry_Generation,
	binding_count:       u16,
	storage_bytes:       u64,
	profile:             Profile_Identity,
	ctx:                 Context_Handle,
	map_count:           u16,
	active_map_count:    u16,
}

/* Allocator_Set supplies the persistent allocation domain for registry and snapshot owners. */
Allocator_Set :: struct {
	persistent: runtime.Allocator,
}
