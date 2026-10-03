// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package editor_session owns bounded editor-session identity, admission, and lifecycle coordination.
package editor_session

import "../document"
import "../editor"
import "../history"
import "../project"
import "../search"
import editor_view "../view"
import "base:runtime"

/* KIBIBYTE is the binary byte unit used by editor-session policy. */
KIBIBYTE :: u64(1_024)
/* MEBIBYTE is 1,024 kibibytes. */
MEBIBYTE :: u64(1_024) * KIBIBYTE
/* GIBIBYTE is 1,024 mebibytes. */
GIBIBYTE :: u64(1_024) * MEBIBYTE

/* MIN_LIVE_BUFFERS is the smallest admitted live-buffer capacity. */
MIN_LIVE_BUFFERS :: u32(16)
/* MAX_LIVE_BUFFERS is the largest validated live-buffer capacity. */
MAX_LIVE_BUFFERS :: u32(1_024)
/* DEFAULT_LIVE_BUFFERS is the measured initial live-buffer capacity. */
DEFAULT_LIVE_BUFFERS :: u32(128)
/* MIN_LIVE_DOCUMENTS is the smallest admitted live-document capacity. */
MIN_LIVE_DOCUMENTS :: u32(16)
/* MAX_LIVE_DOCUMENTS is the largest validated live-document capacity. */
MAX_LIVE_DOCUMENTS :: u32(1_024)
/* DEFAULT_LIVE_DOCUMENTS is the measured initial live-document capacity. */
DEFAULT_LIVE_DOCUMENTS :: u32(128)
/* MIN_AGGREGATE_TEXT_BYTES is the smallest admitted canonical-text budget. */
MIN_AGGREGATE_TEXT_BYTES :: 256 * MEBIBYTE
/* MAX_AGGREGATE_TEXT_BYTES is the largest validated canonical-text budget. */
MAX_AGGREGATE_TEXT_BYTES :: 16 * GIBIBYTE
/* DEFAULT_AGGREGATE_TEXT_BYTES is the measured initial canonical-text budget. */
DEFAULT_AGGREGATE_TEXT_BYTES :: 4 * GIBIBYTE
/* MIN_NAME_BYTES is the smallest admitted unassociated-buffer name bound. */
MIN_NAME_BYTES :: u64(64)
/* MAX_NAME_BYTES is the largest validated unassociated-buffer name bound. */
MAX_NAME_BYTES :: u64(4_096)
/* DEFAULT_NAME_BYTES is the initial unassociated-buffer name bound. */
DEFAULT_NAME_BYTES :: u64(256)
/* MIN_RETAINED_LABEL_BYTES is the smallest aggregate label and path budget. */
MIN_RETAINED_LABEL_BYTES :: 64 * KIBIBYTE
/* MAX_RETAINED_LABEL_BYTES is the largest validated aggregate label and path budget. */
MAX_RETAINED_LABEL_BYTES :: 16 * MEBIBYTE
/* DEFAULT_RETAINED_LABEL_BYTES is the measured aggregate label and path budget. */
DEFAULT_RETAINED_LABEL_BYTES :: 4 * MEBIBYTE
/* MIN_DESCRIPTOR_BATCH is the smallest admitted copied descriptor batch. */
MIN_DESCRIPTOR_BATCH :: u32(16)
/* MAX_DESCRIPTOR_BATCH is the largest validated copied descriptor batch. */
MAX_DESCRIPTOR_BATCH :: u32(4_096)
/* DEFAULT_DESCRIPTOR_BATCH is the initial copied descriptor batch bound. */
DEFAULT_DESCRIPTOR_BATCH :: u32(256)
/* MIN_INVENTORY_MARKS is the smallest admitted simultaneous mark capacity. */
MIN_INVENTORY_MARKS :: u32(16)
/* MAX_INVENTORY_MARKS is the largest validated simultaneous mark capacity. */
MAX_INVENTORY_MARKS :: u32(1_024)
/* DEFAULT_INVENTORY_MARKS is the initial simultaneous mark capacity. */
DEFAULT_INVENTORY_MARKS :: u32(128)
/* MIN_CAPABILITIES is the smallest admitted outstanding capability capacity. */
MIN_CAPABILITIES :: u32(32)
/* MAX_CAPABILITIES is the largest validated outstanding capability capacity. */
MAX_CAPABILITIES :: u32(8_192)
/* DEFAULT_CAPABILITIES is the initial outstanding capability capacity. */
DEFAULT_CAPABILITIES :: u32(2_048)
/* MIN_PREPARED_OPERATIONS is the smallest admitted global preparation capacity. */
MIN_PREPARED_OPERATIONS :: u32(1)
/* MAX_PREPARED_OPERATIONS is the largest validated global preparation capacity. */
MAX_PREPARED_OPERATIONS :: u32(64)
/* DEFAULT_PREPARED_OPERATIONS is the initial global preparation capacity. */
DEFAULT_PREPARED_OPERATIONS :: u32(16)
/* MIN_DETACH_PARTICIPANTS is the smallest admitted no-fail detach set. */
MIN_DETACH_PARTICIPANTS :: u32(16)
/* MAX_DETACH_PARTICIPANTS is the largest validated no-fail detach set. */
MAX_DETACH_PARTICIPANTS :: u32(1_024)
/* DEFAULT_DETACH_PARTICIPANTS is the initial no-fail detach set bound. */
DEFAULT_DETACH_PARTICIPANTS :: u32(128)
/* MIN_CLEANUP_ENTRIES_PER_TURN is the smallest admitted cleanup progress bound. */
MIN_CLEANUP_ENTRIES_PER_TURN :: u32(1)
/* MAX_CLEANUP_ENTRIES_PER_TURN is the largest validated cleanup progress bound. */
MAX_CLEANUP_ENTRIES_PER_TURN :: u32(256)
/* DEFAULT_CLEANUP_ENTRIES_PER_TURN is the initial cleanup progress bound. */
DEFAULT_CLEANUP_ENTRIES_PER_TURN :: u32(64)
/* MIN_SESSION_ROOTS is the smallest admitted active root-set capacity. */
MIN_SESSION_ROOTS :: u32(1)
/* MAX_SESSION_ROOTS is the largest validated active root-set capacity. */
MAX_SESSION_ROOTS :: u32(256)
/* DEFAULT_SESSION_ROOTS is the initial active root-set capacity. */
DEFAULT_SESSION_ROOTS :: u32(32)
/* MIN_ROOT_PATH_BYTES is the smallest retained root-path budget. */
MIN_ROOT_PATH_BYTES :: 64 * KIBIBYTE
/* MAX_ROOT_PATH_BYTES is the largest validated retained root-path budget. */
MAX_ROOT_PATH_BYTES :: 16 * MEBIBYTE
/* DEFAULT_ROOT_PATH_BYTES is the initial retained root-path budget. */
DEFAULT_ROOT_PATH_BYTES :: 4 * MEBIBYTE
/* DEFAULT_SEARCH_HISTORY_ENTRIES bounds accepted queries retained per session. */
DEFAULT_SEARCH_HISTORY_ENTRIES :: u32(64)
/* DEFAULT_SEARCH_HISTORY_BYTES bounds copied accepted query text per session. */
DEFAULT_SEARCH_HISTORY_BYTES :: u64(256 * KIBIBYTE)
/* MAX_TERMINAL_WORKING_CONTEXT_BYTES bounds one copied terminal directory. */
MAX_TERMINAL_WORKING_CONTEXT_BYTES :: 4 * KIBIBYTE

/* Session_ID identifies one editor session; zero is invalid. */
Session_ID :: distinct u64
/* Session_Generation identifies one complete live session generation. */
Session_Generation :: distinct u64
/* Registry_Generation identifies one complete registry publication generation. */
Registry_Generation :: distinct u64
/* Entry_ID identifies one buffer entry for the lifetime of its session. */
Entry_ID :: distinct u64
/* Activation_Sequence orders successful buffer activations; zero means never activated. */
Activation_Sequence :: distinct u64
/* Root_ID identifies one root publication for the lifetime of its session. */
Root_ID :: distinct u64
/* Root_Generation rejects references after root replacement or removal. */
Root_Generation :: distinct u64
/* Root_Set_Generation identifies one complete ordered root publication. */
Root_Set_Generation :: distinct u64

/* Search_History_Descriptor borrows one accepted query from a live batch. */
Search_History_Descriptor :: struct {
	kind:    search.Pattern_Kind,
	pattern: string,
	policy:  search.Policy,
}

/* Search_History_Recall borrows one recalled query until the next history mutation. */
Search_History_Recall :: struct {
	present:              bool,
	restored_in_progress: bool,
	descriptor:           Search_History_Descriptor,
}

/* Search_History_Batch owns copied descriptors until explicit close. */
Search_History_Batch :: struct {
	state:       rawptr,
	descriptors: []Search_History_Descriptor,
}

/* Session_Handle is a checked non-pointer reference to one live session generation. */
Session_Handle :: struct {
	session_id: Session_ID,
	generation: Session_Generation,
}

/* Registry_Handle is a checked reference to one registry generation in a live session. */
Registry_Handle :: struct {
	session:    Session_Handle,
	generation: Registry_Generation,
}

/* Entry_Handle is the runtime identity used to select and mutate one exact buffer entry. */
Entry_Handle :: struct {
	registry:   Registry_Handle,
	entry_id:   Entry_ID,
	slot:       u32,
	generation: u32,
}

/* Root_Handle is a checked reference to one exact session root publication. */
Root_Handle :: struct {
	session:    Session_Handle,
	id:         Root_ID,
	generation: Root_Generation,
}

/* Root_Kind distinguishes ordinary Dirs from validated Project projections. */
Root_Kind :: enum u8 {
	Invalid,
	Dir,
	Project,
}

/* Root_Proposal describes one borrowed normalized root before atomic publication. */
Root_Proposal :: struct {
	kind:    Root_Kind,
	path:    string,
	project: project.Project_Handle,
}

/* Root_Descriptor is one copied root projection in session order. */
Root_Descriptor :: struct {
	handle:  Root_Handle,
	kind:    Root_Kind,
	path:    string,
	dir:     project.Dir_Handle,
	project: project.Project_Handle,
}

/* Root_Batch owns copied root descriptors and paths until explicit close. */
Root_Batch :: struct {
	state:      rawptr,
	generation: Root_Set_Generation,
	descriptors: []Root_Descriptor,
}

/* Root_Replace_Request describes one complete ordered root-set replacement. */
Root_Replace_Request :: struct {
	session: Session_Handle,
	roots:   []Root_Proposal,
}

/* Root_Replace_Result reports one complete atomic root publication. */
Root_Replace_Result :: struct {
	generation: Root_Set_Generation,
	root_count: u32,
	path_bytes: u64,
}

/* MAX_WORKSPACE_ID_BYTES matches the durable lifecycle identity boundary. */
MAX_WORKSPACE_ID_BYTES :: 128
/* MAX_WORKSPACE_NAME_BYTES matches the durable lifecycle display-name boundary. */
MAX_WORKSPACE_NAME_BYTES :: 1_024

/* Workspace_ID owns one copied filename-compatible durable identity. */
Workspace_ID :: struct {
	bytes:  [MAX_WORKSPACE_ID_BYTES]u8,
	length: u32,
}

/* Workspace_Name owns one copied bounded UTF-8 display name. */
Workspace_Name :: struct {
	bytes:  [MAX_WORKSPACE_NAME_BYTES]u8,
	length: u32,
}

/* Workspace_Descriptor is the copied active composition identity. */
Workspace_Descriptor :: struct {
	id:            Workspace_ID,
	generation:    u64,
	name:          Workspace_Name,
	root_set:      Root_Set_Generation,
	project_count: u32,
}

/* Workspace_Activation_Outcome identifies admission work before publication. */
Workspace_Activation_Outcome :: enum u8 {
	Invalid,
	Ready,
	Unavailable_Members,
	Dirty_Protection_Required,
}

/* Workspace_Project_Proposal describes one resolved one-root Project member. */
Workspace_Project_Proposal :: struct {
	project_id:         project.Project_ID,
	project_generation: project.Project_Generation,
	durable_id:         string,
	name:               string,
	root:               string,
	trust:              project.Trust_State,
}

/* Workspace_Activation_Proposal describes one resolved durable composition. */
Workspace_Activation_Proposal :: struct {
	session:              Session_Handle,
	expected_root_set:    Root_Set_Generation,
	id:                   string,
	generation:           u64,
	name:                 string,
	projects:             []Workspace_Project_Proposal,
	unavailable_members:  u32,
}

/* Workspace_Activation_Preparation owns one copied checked proposal until admission. */
Workspace_Activation_Preparation :: struct {
	state:                rawptr,
	session:              Session_Handle,
	expected_root_set:    Root_Set_Generation,
	outcome:              Workspace_Activation_Outcome,
	project_count:        u32,
	unavailable_members:  u32,
	dirty_entries:        u32,
}

/* Workspace_Activation_Result reports one atomic Workspace and root publication. */
Workspace_Activation_Result :: struct {
	workspace: Workspace_Descriptor,
	roots:     Root_Replace_Result,
}

/* Active_Workspace_Snapshot reports zero or one active durable composition. */
Active_Workspace_Snapshot :: struct {
	active:     bool,
	descriptor: Workspace_Descriptor,
}

/* Dir_Abandonment_Action identifies the pending operation that would leave one ordinary Dir. */
Dir_Abandonment_Action :: enum u8 {
	Invalid,
	Remove_Root,
	Replace_Roots,
	Exit,
}

/* Dir_Abandonment_Outcome reports whether an unsuppressed Dir needs a user decision. */
Dir_Abandonment_Outcome :: enum u8 {
	Invalid,
	Ready,
	Decision_Required,
}

/* Dir_Abandonment_Decision records one explicit abandonment response. */
Dir_Abandonment_Decision :: enum u8 {
	Invalid,
	Continue,
	Convert,
	Decline,
	Disable_Prompt,
	Cancel,
}

/* Dir_Abandonment_Admission distinguishes continuation from preserved-session cancellation. */
Dir_Abandonment_Admission :: enum u8 {
	Invalid,
	Continue,
	Cancelled,
}

/* Dir_Abandonment_Preparation retains one exact root generation and copied path. */
Dir_Abandonment_Preparation :: struct {
	session:     Session_Handle,
	root:        Root_Handle,
	root_set:    Root_Set_Generation,
	action:      Dir_Abandonment_Action,
	outcome:     Dir_Abandonment_Outcome,
	path:        [document.MAX_PATH_BYTES]u8,
	path_length: u32,
}

/* dir_abandonment_path_text returns the copied path retained by one preparation. */
dir_abandonment_path_text :: proc(prepared: ^Dir_Abandonment_Preparation) -> string {
	if prepared == nil || prepared.path_length == 0 ||
	   prepared.path_length > u32(len(prepared.path)) {
		return ""
	}
	return string(prepared.path[:prepared.path_length])
}

/* Object_Graph_Identity names every responsibility-owned object retained by one entry. */
Object_Graph_Identity :: struct {
	entry:          Entry_Handle,
	kind:           Entry_Kind,
	buffer_id:      editor.Buffer_ID,
	history_id:     history.History_ID,
	primary_view:   editor_view.View_Handle,
	has_document:   bool,
	document_id:    document.Document_ID,
}

/*
Entry_Resources transfers responsibility-owned live objects into one private
session preparation. Successful preparation clears the supplied wrappers;
failure leaves them owned by the caller.
*/
Entry_Resources :: struct {
	buffer:        ^editor.Buffer,
	history_store: ^history.Store,
	document:      ^document.Document,
	has_document:  bool,
}

/* Entry_Prepare_Request describes one complete graph and its retained selection metadata. */
Entry_Prepare_Request :: struct {
	session:         Session_Handle,
	kind:            Entry_Kind,
	selection_label: string,
	normalized_path: string,
	association:     Association_Kind,
	terminal:        Terminal_Buffer_Source,
	resources:       Entry_Resources,
	view_config:     editor_view.Config,
}

/* Entry_Configuration resolves responsibility-owned limits for one newly initialized graph. */
Entry_Configuration :: struct {
	buffer_limits:   editor.Limits,
	history_policy:  history.Policy,
	document_limits: document.Limits,
	view_config:     editor_view.Config,
}

/* DEFAULT_ENTRY_CONFIGURATION is the initial complete graph policy for create and open. */
DEFAULT_ENTRY_CONFIGURATION :: Entry_Configuration {
	buffer_limits = editor.DEFAULT_LIMITS,
	history_policy = history.DEFAULT_POLICY,
	document_limits = document.DEFAULT_LIMITS,
	view_config = editor_view.DEFAULT_CONFIG,
}

/* Create_Buffer_Request describes one explicitly named unassociated buffer admission. */
Create_Buffer_Request :: struct {
	session:       Session_Handle,
	name:          string,
	initial_contents: string,
	configuration: Entry_Configuration,
}

/* Terminal_Session_Ref is a copied non-owning reference to one terminal generation. */
Terminal_Session_Ref :: struct {
	id:         u32,
	generation: u32,
}

/* Terminal_Lifecycle is the editor-visible terminal state vocabulary. */
Terminal_Lifecycle :: enum u8 {
	Invalid,
	Running,
	Exited,
	Failed,
}

/* Terminal_Buffer_Source identifies the non-owning source of one terminal projection. */
Terminal_Buffer_Source :: struct {
	ref:             Terminal_Session_Ref,
	lifecycle:       Terminal_Lifecycle,
	working_context: string,
}

/* Create_Terminal_Buffer_Request describes one copied terminal projection admission. */
Create_Terminal_Buffer_Request :: struct {
	session:           Session_Handle,
	name:              string,
	terminal:          Terminal_Buffer_Source,
	copied_projection: string,
	configuration:     Entry_Configuration,
}

/* Terminal_Buffer_Update_Request refreshes copied projection and lifecycle atomically. */
Terminal_Buffer_Update_Request :: struct {
	entry:             Entry_Handle,
	terminal:          Terminal_Session_Ref,
	lifecycle:         Terminal_Lifecycle,
	copied_projection: string,
}

/* Rename_Terminal_Buffer_Request changes only one stable editor-visible terminal name. */
Rename_Terminal_Buffer_Request :: struct {
	entry:    Entry_Handle,
	terminal: Terminal_Session_Ref,
	name:     string,
}

/* Terminal_Working_Context is one copied bounded directory retained by inspection. */
Terminal_Working_Context :: struct {
	bytes:  [int(MAX_TERMINAL_WORKING_CONTEXT_BYTES)]u8,
	length: u16,
}

/* Terminal_Buffer_State is one immutable copied terminal-backed buffer inspection. */
Terminal_Buffer_State :: struct {
	entry:               Entry_Handle,
	terminal:            Terminal_Session_Ref,
	lifecycle:           Terminal_Lifecycle,
	projection_revision: editor.Revision,
	working_context:     Terminal_Working_Context,
}

/* Open_Path_Request describes one local document admission or normalized-path reuse. */
Open_Path_Request :: struct {
	session:       Session_Handle,
	path:          string,
	encoding:      document.Encoding_Policy,
	configuration: Entry_Configuration,
}

/* MAX_CLOSURE_LABEL_BYTES bounds copied metadata retained after one entry closes. */
MAX_CLOSURE_LABEL_BYTES :: max(MAX_NAME_BYTES, document.MAX_PATH_BYTES)

/* Close_Authority records whether modified canonical text may be discarded. */
Close_Authority :: enum u8 {
	Preserve_Modified,
	Discard_Modified,
}

/* Close_Buffer_Request identifies one exact entry and its explicit discard authority. */
Close_Buffer_Request :: struct {
	entry:     Entry_Handle,
	authority: Close_Authority,
}

/* Close_Buffer_Set_Result reports one fully detached and released admitted set. */
Close_Buffer_Set_Result :: struct {
	closed_entries: u32,
	usage:          Resource_Usage,
}

/* Associate_Save_Request identifies one unassociated entry and its first-save target. */
Associate_Save_Request :: struct {
	entry:  Entry_Handle,
	path:   string,
	limits: document.Limits,
}

/* Associate_Save_Result reports the committed session association and external save. */
Associate_Save_Result :: struct {
	entry:           Entry_Handle,
	selection_label: Closure_Label,
	save:            document.Save_Result,
	usage:           Resource_Usage,
}

/* Closure_Outcome distinguishes a completed close from required dirty-state authority. */
Closure_Outcome :: enum u8 {
	Invalid,
	Ready,
	Discard_Required,
	Closed,
}

/* Closure_Label owns one bounded copied selection label after entry storage is released. */
Closure_Label :: struct {
	bytes:  [int(MAX_CLOSURE_LABEL_BYTES)]u8,
	length: u32,
}

/* Closure_Result reports checked admission, successor selection, and completed cleanup. */
Closure_Result :: struct {
	outcome:        Closure_Outcome,
	graph:          Object_Graph_Identity,
	selection_label: Closure_Label,
	association:    Association_Kind,
	modified:       bool,
	was_visible:    bool,
	successor:      Visible_Target,
	last_buffer:    bool,
	usage:          Resource_Usage,
	cleanup:        Cleanup_Progress,
}

/* Entry_Access is a checked native capability for one exact live entry generation. */
Entry_Access :: struct {
	state: rawptr,
	entry: Entry_Handle,
}

/* Project_Registry_Access is a checked native capability for the session-owned Project registry. */
Project_Registry_Access :: struct {
	state:   rawptr,
	project: project.Project_Handle,
}

/*
Entry_Borrow supplies responsibility-owned objects for one immediate native operation.
The returned pointers expire on the next session lifecycle mutation and must not be retained.
*/
Entry_Borrow :: struct {
	kind:          Entry_Kind,
	buffer:        ^editor.Buffer,
	history_store: ^history.Store,
	document:      ^document.Document,
	has_document:  bool,
	view_registry: ^editor_view.Registry,
	primary_view:  editor_view.View_Handle,
	terminal:      Terminal_Buffer_Source,
}

/* Entry_Kind distinguishes editable text entries from terminal projections. */
Entry_Kind :: enum u8 {
	Invalid,
	Text,
	Terminal,
}

/* Association_Kind distinguishes named unassociated buffers from document-backed buffers. */
Association_Kind :: enum u8 {
	Invalid,
	Unassociated,
	Document,
}

/* Operation_State reports whether an entry may participate in a lifecycle mutation. */
Operation_State :: enum u8 {
	Invalid,
	Idle,
	Preparing,
	Busy,
	Detaching,
}

/* Visible_Target_Kind classifies the one target selected for presentation. */
Visible_Target_Kind :: enum u8 {
	None,
	Primary_View,
	UI_Root,
}

/* UI_Target is a copied identity for one frontend-independent UI workflow. */
UI_Target :: struct {
	owner_id:   u64,
	model_id:   u64,
	generation: u64,
}

/* Visible_Target identifies one primary view or frontend-independent UI workflow without owning it. */
Visible_Target :: struct {
	kind:         Visible_Target_Kind,
	entry:        Entry_Handle,
	primary_view: editor_view.View_Handle,
	ui:           UI_Target,
}

/* Entry_Descriptor is a copied bounded projection of one live buffer entry. */
Entry_Descriptor :: struct {
	graph:               Object_Graph_Identity,
	kind:                Entry_Kind,
	selection_label:     string,
	association:         Association_Kind,
	persistence:         document.Persistence_State,
	operation:           Operation_State,
	active:              bool,
	modified:            bool,
	activation_sequence: Activation_Sequence,
	terminal:            Terminal_Buffer_Source,
}

/* Descriptor_Batch owns copied descriptors and labels until explicitly released. */
Descriptor_Batch :: struct {
	state:       rawptr,
	descriptors: []Entry_Descriptor,
}

/* Project_Update_Request describes one checked complete active-Project replacement. */
Project_Update_Request :: struct {
	session:      Session_Handle,
	expected:     project.Project_Handle,
	project_id:   project.Project_ID,
	name:         string,
	directories:  []project.Directory_Proposal,
	temporary:    bool,
}

/* Project_Update_Result reports one atomic active-Project publication. */
Project_Update_Result :: struct {
	previous:   project.Project_Handle,
	active:     project.Project_Descriptor,
	usage:      project.Resource_Usage,
}

/* Project_Directory_Open_Request carries one resolved exact-directory catalog outcome. */
Project_Directory_Open_Request :: struct {
	session:                       Session_Handle,
	expected:                      project.Project_Handle,
	expected_catalog_generation:   u64,
	actual_catalog_generation:     u64,
	normalized_path:               string,
	matching_projects:             u32,
	project_id:                    project.Project_ID,
	project_generation:            project.Project_Generation,
	durable_id:                    string,
	name:                          string,
	trust:                         project.Trust_State,
	temporary:                     bool,
}

/* Project_Directory_Open_Result reports activation or preserved ambiguity. */
Project_Directory_Open_Result :: struct {
	resolution: project.Directory_Open_Resolution,
	active:     project.Project_Descriptor,
	usage:      project.Resource_Usage,
}

/* Active_Project_Snapshot is a copied account of the session-owned Project state. */
Active_Project_Snapshot :: struct {
	active:     bool,
	descriptor: project.Project_Descriptor,
	usage:      project.Resource_Usage,
}

/* Project_Buffer_Scope classifies one live buffer against one Project generation. */
Project_Buffer_Scope :: enum u8 {
	Invalid,
	Unassociated,
	Project_Owned,
	External,
}

/* Project_Buffer_Descriptor is one copied live-buffer and normalized-document projection. */
Project_Buffer_Descriptor :: struct {
	graph:             Object_Graph_Identity,
	normalized_path:   string,
	scope:             Project_Buffer_Scope,
	membership_offset: u32,
	membership_count:  u32,
	active:            bool,
}

/* Project_Buffer_Batch owns copied buffer descriptors, paths, and overlap matches. */
Project_Buffer_Batch :: struct {
	state:          rawptr,
	project_handle: project.Project_Handle,
	descriptors:    []Project_Buffer_Descriptor,
	memberships:    []project.Membership_Handle,
}

/* Policy_Field identifies one editor-session policy field in validation diagnostics. */
Policy_Field :: enum u8 {
	Invalid,
	Live_Buffers,
	Live_Documents,
	Aggregate_Text_Bytes,
	Name_Bytes,
	Retained_Label_Bytes,
	Descriptor_Batch,
	Inventory_Marks,
	Capabilities,
	Prepared_Operations,
	Detach_Participants,
	Cleanup_Entries_Per_Turn,
	Session_Roots,
	Root_Path_Bytes,
}

/* Policy contains every aggregate registry, copied-value, and lifecycle-work bound. */
Policy :: struct {
	live_buffers:             u32,
	live_documents:           u32,
	aggregate_text_bytes:     u64,
	name_bytes:               u64,
	retained_label_bytes:     u64,
	descriptor_batch:         u32,
	inventory_marks:          u32,
	capabilities:             u32,
	prepared_operations:      u32,
	detach_participants:      u32,
	cleanup_entries_per_turn: u32,
	session_roots:            u32,
	root_path_bytes:          u64,
}

/* DEFAULT_POLICY is the measured initial editor-session resource policy. */
DEFAULT_POLICY :: Policy {
	live_buffers = DEFAULT_LIVE_BUFFERS,
	live_documents = DEFAULT_LIVE_DOCUMENTS,
	aggregate_text_bytes = DEFAULT_AGGREGATE_TEXT_BYTES,
	name_bytes = DEFAULT_NAME_BYTES,
	retained_label_bytes = DEFAULT_RETAINED_LABEL_BYTES,
	descriptor_batch = DEFAULT_DESCRIPTOR_BATCH,
	inventory_marks = DEFAULT_INVENTORY_MARKS,
	capabilities = DEFAULT_CAPABILITIES,
	prepared_operations = DEFAULT_PREPARED_OPERATIONS,
	detach_participants = DEFAULT_DETACH_PARTICIPANTS,
	cleanup_entries_per_turn = DEFAULT_CLEANUP_ENTRIES_PER_TURN,
	session_roots = DEFAULT_SESSION_ROOTS,
	root_path_bytes = DEFAULT_ROOT_PATH_BYTES,
}

/* Resource_Usage reports exact live counts and storage charged to one session. */
Resource_Usage :: struct {
	live_buffers:            u32,
	live_documents:          u32,
	live_primary_views:      u32,
	activation_entries:      u32,
	canonical_text_bytes:    u64,
	retained_label_bytes:    u64,
	view_anchors:            u64,
	view_context_bytes:      u64,
	history_bytes:           u64,
	registry_bytes:          u64,
	outstanding_capabilities: u32,
	prepared_operations:     u32,
	detached_cleanup_entries: u32,
	session_roots:            u32,
	root_path_bytes:          u64,
}

/* Graph_Reservation records the complete aggregate charge required before publication. */
Graph_Reservation :: struct {
	buffers:             u32,
	documents:           u32,
	primary_views:       u32,
	activation_entries:  u32,
	canonical_text_bytes: u64,
	label_bytes:         u64,
	view_anchors:        u64,
	view_context_bytes:  u64,
	history_bytes:       u64,
	registry_bytes:      u64,
	capabilities:        u32,
	prepared_operations: u32,
}

/* Ownership_State reports which lifecycle owns one complete object graph. */
Ownership_State :: enum u8 {
	Invalid,
	Private_Preparation,
	Published_Session,
	Detached_Cleanup,
	Released,
}

/* Ownership_Snapshot is a copied account of one complete graph and its current owner. */
Ownership_Snapshot :: struct {
	graph:       Object_Graph_Identity,
	state:       Ownership_State,
	reservation: Graph_Reservation,
}

/* Operation identifies the editor-session transition that produced a result or failure. */
Operation :: enum u8 {
	None,
	Initialize,
	Inspect,
	Create_Buffer,
	Create_Terminal_Buffer,
	Open_Path,
	Associate_Path,
	Refresh_Terminal_Buffer,
	Rename_Terminal_Buffer,
	Relocate_Paths,
	Close_Buffer,
	Prepare_Entry,
	Publish_Entry,
	Abort_Entry,
	Find_Label,
	Find_Path,
	Activate,
	Present_UI,
	Inspect_Roots,
	Replace_Roots,
	Prepare_Workspace,
	Activate_Workspace,
	Inspect_Workspace,
	Prepare_Dir_Abandonment,
	Admit_Dir_Abandonment,
	Inspect_Project,
	Replace_Project,
	Prepare_Detach,
	Detach,
	Cleanup,
	Close,
}

/* Path_Relocation_Request identifies one exact file or directory prefix replacement. */
Path_Relocation_Request :: struct {
	from:      string,
	to:        string,
	directory: bool,
}

/* Path_Relocation_Result reports associated document paths updated atomically in memory. */
Path_Relocation_Result :: struct {
	relocated: u32,
}

/* closure_label_text returns the copied label retained in one closure result. */
closure_label_text :: proc(label: ^Closure_Label) -> string {
	if label == nil || label.length > u32(len(label.bytes)) {
		return ""
	}
	return string(label.bytes[:label.length])
}

/* Admission_Outcome classifies complete-graph preparation and publication. */
Admission_Outcome :: enum u8 {
	Invalid,
	Prepared,
	Published,
	Reused,
	Rejected,
}

/* Admission_Result reports one complete entry admission without exposing owned storage. */
Admission_Result :: struct {
	outcome:  Admission_Outcome,
	entry:    Entry_Handle,
	visible:  Visible_Target,
	usage:    Resource_Usage,
}

/* Activation_Result reports one atomic visible-target and MRU publication. */
Activation_Result :: struct {
	entry:             Entry_Handle,
	previous:          Visible_Target,
	visible:           Visible_Target,
	sequence:          Activation_Sequence,
	changed:           bool,
}

/*
Detachment_Result contains copied metadata retained by its Detached_Entry.
Its selection label remains valid until detached_entry_release consumes that owner.
*/
Detachment_Result :: struct {
	entry:               Entry_Handle,
	selection_label:     string,
	was_visible:         bool,
	successor:           Visible_Target,
	detached_graphs:     u32,
	detached_bytes:      u64,
}

/* Cleanup_Progress reports bounded deterministic release work and its first failure. */
Cleanup_Progress :: struct {
	processed_entries: u32,
	remaining_entries: u32,
	released_bytes:    u64,
	complete:          bool,
	first_failure:     Failure_Context,
}

/* Failure_Code classifies expected session rejection without partial publication. */
Failure_Code :: enum u16 {
	None,
	Invalid_Session,
	Wrong_Session,
	Stale_Session,
	Closed_Session,
	Retained_Entries,
	Retained_Preparations,
	Retained_Cleanup,
	Invalid_Registry,
	Stale_Registry,
	Invalid_Entry,
	Stale_Entry,
	Invalid_Object_Graph,
	Invalid_Terminal,
	Stale_Terminal,
	Invalid_Terminal_Transition,
	Terminal_Coordination_Required,
	Invalid_Visible_Target,
	Invalid_Policy,
	Policy_Range,
	Policy_Relationship,
	Invalid_Name,
	Malformed_Label,
	Label_Limit,
	Invalid_Path,
	Name_Collision,
	Path_Collision,
	Buffer_Limit,
	Document_Limit,
	Aggregate_Text_Limit,
	Retained_Label_Limit,
	Descriptor_Limit,
	Mark_Limit,
	Capability_Limit,
	Operation_Limit,
	Detach_Limit,
	Activation_Limit,
	Identity_Limit,
	Root_Limit,
	Root_Path_Limit,
	Invalid_Root,
	Duplicate_Root,
	Invalid_Workspace,
	Stale_Workspace,
	Unavailable_Workspace_Members,
	Dirty_Protection_Required,
	Busy,
	Invalid_Reservation,
	Persistent_Memory_Limit,
	Temporary_Memory_Limit,
	Editor_Failure,
	History_Failure,
	Document_Failure,
	View_Failure,
	Project_Failure,
	Project_Scope,
	Cancelled,
	Invariant_Violation,
}

/* Failure_Context identifies the rejected session object, policy bound, and owner failure. */
Failure_Context :: struct {
	code:             Failure_Code,
	operation:        Operation,
	field:            Policy_Field,
	session:          Session_Handle,
	registry:         Registry_Handle,
	entry:            Entry_Handle,
	terminal:         Terminal_Session_Ref,
	root:             Root_Handle,
	minimum:          u64,
	maximum:          u64,
	actual:           u64,
	editor_failure:   editor.Failure_Context,
	history_failure:  history.Failure_Context,
	document_failure: document.Failure_Context,
	view_failure:     editor_view.Failure_Context,
	project_failure:  project.Failure_Context,
}

/* terminal_session_ref_is_valid reports whether a copied terminal identity is live-shaped. */
terminal_session_ref_is_valid :: proc(ref: Terminal_Session_Ref) -> bool {
	return ref.id != 0 && ref.generation != 0
}

/* terminal_working_context_text borrows one checked copied terminal directory. */
terminal_working_context_text :: proc(value: ^Terminal_Working_Context) -> string {
	if value == nil || value.length == 0 || int(value.length) > len(value.bytes) {
		return ""
	}
	return string(value.bytes[:value.length])
}

/* Allocator_Set supplies session-retained and per-operation allocation domains. */
Allocator_Set :: struct {
	// The caller keeps this allocator alive until session_close completes.
	persistent: runtime.Allocator,
	// The caller keeps this allocator alive for every session operation.
	temporary: runtime.Allocator,
}

/* Session is the opaque owner of registry identity, indexes, order, and aggregate usage. */
Session :: struct {
	state:  rawptr,
	closed: bool,
}

/* Prepared_Entry privately owns a complete unpublished object graph. */
Prepared_Entry :: struct {
	state: rawptr,
}

/* Detached_Entry owns an unreachable graph until bounded cleanup releases it. */
Detached_Entry :: struct {
	state: rawptr,
}

/* session_handle_is_valid reports whether a session handle has a live-shaped identity. */
session_handle_is_valid :: proc(handle: Session_Handle) -> bool {
	return handle.session_id != Session_ID(0) &&
	       handle.generation != Session_Generation(0)
}

/* registry_handle_is_valid reports whether a registry handle has a live-shaped identity. */
registry_handle_is_valid :: proc(handle: Registry_Handle) -> bool {
	return session_handle_is_valid(handle.session) &&
	       handle.generation != Registry_Generation(0)
}

/* entry_handle_is_valid reports whether an entry handle has a live-shaped identity. */
entry_handle_is_valid :: proc(handle: Entry_Handle) -> bool {
	return registry_handle_is_valid(handle.registry) &&
	       handle.entry_id != Entry_ID(0) &&
	       handle.generation != 0
}

/* root_handle_is_valid reports whether a root handle names one exact live publication. */
root_handle_is_valid :: proc(handle: Root_Handle) -> bool {
	return session_handle_is_valid(handle.session) && handle.id != Root_ID(0) &&
	       handle.generation != Root_Generation(0)
}

/* visible_target_is_valid checks the discriminant and required checked identity shape. */
visible_target_is_valid :: proc(target: Visible_Target) -> bool {
	switch target.kind {
	case .None:
		return target.entry == Entry_Handle{} &&
		       target.primary_view == editor_view.View_Handle{} &&
		       target.ui == UI_Target{}
	case .Primary_View:
		return entry_handle_is_valid(target.entry) &&
		       target.primary_view.registry_id != editor_view.Registry_ID(0) &&
		       target.primary_view.view_id != editor_view.View_ID(0) &&
		       target.primary_view.generation != 0 &&
		       target.ui == UI_Target{}
	case .UI_Root:
		return target.entry == Entry_Handle{} &&
		       target.primary_view == editor_view.View_Handle{} &&
		       target.ui.owner_id != 0 && target.ui.model_id != 0 &&
		       target.ui.generation != 0
	}
	return false
}

/* policy_validate checks every field and cross-field relationship without changing state. */
policy_validate :: proc(policy: Policy) -> (ok: bool, failure: Failure_Context) {
	if valid, field_failure := policy_field_validate(u64(policy.live_buffers), u64(MIN_LIVE_BUFFERS), u64(MAX_LIVE_BUFFERS), .Live_Buffers); !valid {
		return false, field_failure
	}
	if valid, field_failure := policy_field_validate(u64(policy.live_documents), u64(MIN_LIVE_DOCUMENTS), u64(MAX_LIVE_DOCUMENTS), .Live_Documents); !valid {
		return false, field_failure
	}
	if valid, field_failure := policy_field_validate(policy.aggregate_text_bytes, MIN_AGGREGATE_TEXT_BYTES, MAX_AGGREGATE_TEXT_BYTES, .Aggregate_Text_Bytes); !valid {
		return false, field_failure
	}
	if valid, field_failure := policy_field_validate(policy.name_bytes, MIN_NAME_BYTES, MAX_NAME_BYTES, .Name_Bytes); !valid {
		return false, field_failure
	}
	if valid, field_failure := policy_field_validate(policy.retained_label_bytes, MIN_RETAINED_LABEL_BYTES, MAX_RETAINED_LABEL_BYTES, .Retained_Label_Bytes); !valid {
		return false, field_failure
	}
	if valid, field_failure := policy_field_validate(u64(policy.descriptor_batch), u64(MIN_DESCRIPTOR_BATCH), u64(MAX_DESCRIPTOR_BATCH), .Descriptor_Batch); !valid {
		return false, field_failure
	}
	if valid, field_failure := policy_field_validate(u64(policy.inventory_marks), u64(MIN_INVENTORY_MARKS), u64(MAX_INVENTORY_MARKS), .Inventory_Marks); !valid {
		return false, field_failure
	}
	if valid, field_failure := policy_field_validate(u64(policy.capabilities), u64(MIN_CAPABILITIES), u64(MAX_CAPABILITIES), .Capabilities); !valid {
		return false, field_failure
	}
	if valid, field_failure := policy_field_validate(u64(policy.prepared_operations), u64(MIN_PREPARED_OPERATIONS), u64(MAX_PREPARED_OPERATIONS), .Prepared_Operations); !valid {
		return false, field_failure
	}
	if valid, field_failure := policy_field_validate(u64(policy.detach_participants), u64(MIN_DETACH_PARTICIPANTS), u64(MAX_DETACH_PARTICIPANTS), .Detach_Participants); !valid {
		return false, field_failure
	}
	if valid, field_failure := policy_field_validate(u64(policy.cleanup_entries_per_turn), u64(MIN_CLEANUP_ENTRIES_PER_TURN), u64(MAX_CLEANUP_ENTRIES_PER_TURN), .Cleanup_Entries_Per_Turn); !valid {
		return false, field_failure
	}
	if valid, field_failure := policy_field_validate(u64(policy.session_roots), u64(MIN_SESSION_ROOTS), u64(MAX_SESSION_ROOTS), .Session_Roots); !valid {
		return false, field_failure
	}
	if valid, field_failure := policy_field_validate(policy.root_path_bytes, MIN_ROOT_PATH_BYTES, MAX_ROOT_PATH_BYTES, .Root_Path_Bytes); !valid {
		return false, field_failure
	}

	if policy.live_documents > policy.live_buffers {
		return false, policy_relationship_failure(.Live_Documents, u64(policy.live_buffers), u64(policy.live_documents))
	}
	if policy.inventory_marks > policy.live_buffers {
		return false, policy_relationship_failure(.Inventory_Marks, u64(policy.live_buffers), u64(policy.inventory_marks))
	}
	if policy.detach_participants > policy.live_buffers {
		return false, policy_relationship_failure(.Detach_Participants, u64(policy.live_buffers), u64(policy.detach_participants))
	}

	return true, {}
}

@(private)
policy_field_validate :: proc(
	actual: u64,
	minimum: u64,
	maximum: u64,
	field: Policy_Field,
) -> (ok: bool, failure: Failure_Context) {
	if actual < minimum || actual > maximum {
		return false, Failure_Context {
			code = .Policy_Range,
			field = field,
			minimum = minimum,
			maximum = maximum,
			actual = actual,
		}
	}
	return true, {}
}

@(private)
policy_relationship_failure :: proc(
	field: Policy_Field,
	maximum: u64,
	actual: u64,
) -> Failure_Context {
	return Failure_Context {
		code = .Policy_Relationship,
		field = field,
		maximum = maximum,
		actual = actual,
	}
}
