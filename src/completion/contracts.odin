// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package completion owns provider-independent language completion semantics.
package completion

/* MAX_COMPLETION_CANDIDATES bounds normalized items in one batch. */
MAX_COMPLETION_CANDIDATES :: 128
/* MAX_COMPLETION_ADDITIONAL_EDITS bounds secondary edits per candidate. */
MAX_COMPLETION_ADDITIONAL_EDITS :: 8
/* MAX_COMPLETION_TEXT_BYTES bounds each ordinary copied text field. */
MAX_COMPLETION_TEXT_BYTES :: 256
/* MAX_COMPLETION_DETAIL_BYTES bounds copied detail and documentation fields. */
MAX_COMPLETION_DETAIL_BYTES :: 1 * 1_024
/* MAX_COMPLETION_RESOLVE_BYTES bounds one opaque copied resolve token. */
MAX_COMPLETION_RESOLVE_BYTES :: 512
/* MAX_COMPLETION_ROLES is the fixed replaceable-role count. */
MAX_COMPLETION_ROLES :: 3
/* MAX_COMPLETION_IMPLEMENTATIONS bounds one registry lifetime. */
MAX_COMPLETION_IMPLEMENTATIONS :: 16
/* MAX_COMPLETION_NAME_BYTES bounds implementation identity and provenance. */
MAX_COMPLETION_NAME_BYTES :: 96
/* MAX_COMPLETION_REPLACEMENTS bounds role replacements per registry lifetime. */
MAX_COMPLETION_REPLACEMENTS :: 1_024
/* MAX_COMPLETION_REQUEST_REPLACEMENTS bounds request updates per session. */
MAX_COMPLETION_REQUEST_REPLACEMENTS :: 1_024
/* MAX_ACTIVE_COMPLETION_SESSIONS_PER_CONTROLLER fixes singular session ownership. */
MAX_ACTIVE_COMPLETION_SESSIONS_PER_CONTROLLER :: 1
/* MAX_RETAINED_COMPLETION_BATCHES_PER_SESSION fixes singular batch ownership. */
MAX_RETAINED_COMPLETION_BATCHES_PER_SESSION :: 1

/* Controller_ID identifies one controller lifetime; zero is invalid. */
Controller_ID :: distinct u64
/* Controller_Generation identifies one exact controller generation. */
Controller_Generation :: distinct u64
/* Document_ID identifies the canonical document bound to a request. */
Document_ID :: distinct u64
/* Buffer_ID identifies the canonical buffer bound to a request. */
Buffer_ID :: distinct u64
/* Document_Revision identifies one exact canonical document revision. */
Document_Revision :: distinct u64
/* View_ID identifies the focused editor view bound to a request. */
View_ID :: distinct u64
/* View_Generation identifies one exact editor-view generation. */
View_Generation :: distinct u64
/* Language_ID identifies the selected language responsibility. */
Language_ID :: distinct u64
/* Language_Generation identifies one exact language selection. */
Language_Generation :: distinct u64
/* Server_Session_ID identifies the producing service session. */
Server_Session_ID :: distinct u64
/* Server_Session_Generation identifies one exact service-session generation. */
Server_Session_Generation :: distinct u64
/* Document_Binding_ID identifies the service-owned document binding. */
Document_Binding_ID :: distinct u64
/* Document_Binding_Generation identifies one exact binding generation. */
Document_Binding_Generation :: distinct u64
/* Provider_ID identifies the selected completion provider. */
Provider_ID :: distinct u64
/* Provider_Generation identifies one exact provider generation. */
Provider_Generation :: distinct u64
/* Request_ID identifies one completion request in a controller lifetime. */
Request_ID :: distinct u64
/* Request_Generation orders request replacement. */
Request_Generation :: distinct u64
/* Batch_ID identifies one normalized provider publication. */
Batch_ID :: distinct u64
/* Batch_Generation identifies one immutable batch generation. */
Batch_Generation :: distinct u64
/* Projection_Generation identifies one immutable filtered projection. */
Projection_Generation :: distinct u64
/* Resolve_Generation orders selected-candidate detail requests. */
Resolve_Generation :: distinct u64
/* Candidate_ID identifies one source-owned item within a batch generation. */
Candidate_ID :: distinct u64
/* Session_ID identifies one completion interaction. */
Session_ID :: distinct u64
/* Session_Generation orders completion-session replacement. */
Session_Generation :: distinct u64
/* Role_Registry_ID identifies one completion role-registry lifetime. */
Role_Registry_ID :: distinct u64
/* Role_Registry_Generation identifies one exact registry snapshot. */
Role_Registry_Generation :: distinct u64
/* Implementation_ID identifies one role implementation for a registry lifetime. */
Implementation_ID :: distinct u64
/* Implementation_Generation identifies one exact immutable implementation. */
Implementation_Generation :: distinct u64
/* Composition_Generation identifies one exact complete role selection. */
Composition_Generation :: distinct u64

/* Trigger_Kind classifies why one completion request began. */
Trigger_Kind :: enum u8 {
	Invalid,
	Explicit,
	Identifier,
	Trigger_Character,
	Incomplete,
}

/* Request_State records the checked lifecycle of one provider request. */
Request_State :: enum u8 {
	Invalid,
	Prepared,
	Queued,
	Sent,
	Completed,
	Cancelled,
	Timed_Out,
	Failed,
}

/* Session_State records the checked lifecycle of one completion session. */
Session_State :: enum u8 {
	Invalid,
	Requesting,
	Ready,
	Empty,
	Failed,
	Dismissed,
	Retired,
}

/* Selection_Movement names bounded movement inside one filtered projection. */
Selection_Movement :: enum u8 {
	Invalid,
	Next,
	Previous,
	First,
	Last,
}

/* Batch_Disposition distinguishes locally reusable and incomplete results. */
Batch_Disposition :: enum u8 {
	Invalid,
	Complete,
	Incomplete,
}

/* Candidate_Kind provides the fixed semantic grouping vocabulary. */
Candidate_Kind :: enum u8 {
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

/* Candidate_Availability records whether one item can be accepted. */
Candidate_Availability :: enum u8 {
	Invalid,
	Available,
	Deprecated,
	Unavailable,
}

/* Documentation_Format identifies admitted copied documentation content. */
Documentation_Format :: enum u8 {
	Invalid,
	Plain_Text,
	Markdown,
}

/* Detail_State describes selected-candidate detail readiness without transport policy. */
Detail_State :: enum u8 {
	Invalid,
	Ready,
	Resolve_Required,
	Resolving,
	Unavailable,
}

/* Role identifies one replaceable completion responsibility. */
Role :: enum u8 {
	Invalid,
	Provider,
	Policy,
	Presentation,
}

/* Implementation_Kind records maintained or extension provenance. */
Implementation_Kind :: enum u8 {
	Invalid,
	Factory,
	Package,
	Personal,
}

/* Operation identifies one checked completion action. */
Operation :: enum u8 {
	Invalid,
	Initialize,
	Inspect,
	Register,
	Select,
	Replace,
	Restore,
	Disable,
	Start,
	Queue,
	Send,
	Update,
	Publish,
	Cancel,
	Fail,
	Dismiss,
	Retire,
	Close,
	Resolve,
	Accept,
}

/* Failure_Code classifies expected completion rejection. */
Failure_Code :: enum u16 {
	None,
	Invalid_Controller,
	Closed_Controller,
	Invalid_Registry,
	Closed_Registry,
	Invalid_Identity,
	Invalid_Generation,
	Invalid_Role,
	Invalid_Kind,
	Invalid_Name,
	Invalid_Request,
	Invalid_Batch,
	Invalid_Candidate,
	Invalid_Range,
	Invalid_State,
	Duplicate_Implementation,
	Implementation_Limit,
	Candidate_Limit,
	Edit_Limit,
	Text_Limit,
	Detail_Limit,
	Resolve_Limit,
	Replacement_Limit,
	Request_Limit,
	Stale_Scope,
	Stale_Implementation,
	Stale_Request,
	Stale_Document,
	Stale_Provider,
	Provider_Unavailable,
	Write_Forbidden,
	Transaction_Rejected,
	Generation_Limit,
	Allocation,
}

/* Capabilities is one bounded implementation capability set. */
Capabilities :: bit_set[Capability; u16]

/* Capability identifies one normalized completion behavior. */
Capability :: enum u8 {
	Explicit,
	Identifier,
	Trigger_Character,
	Incomplete,
	Resolve,
	Additional_Edits,
	Documentation,
}

/* Text stores one bounded copied ordinary text field. */
Text :: struct {
	bytes:      [MAX_COMPLETION_TEXT_BYTES]u8,
	byte_count: u16,
}

/* Detail_Text stores one bounded copied detail or documentation field. */
Detail_Text :: struct {
	bytes:      [MAX_COMPLETION_DETAIL_BYTES]u8,
	byte_count: u16,
}

/* Resolve_Token stores bounded opaque provider data without authority. */
Resolve_Token :: struct {
	bytes:      [MAX_COMPLETION_RESOLVE_BYTES]u8,
	byte_count: u16,
}

/* Name stores one bounded copied implementation identity. */
Name :: struct {
	bytes:      [MAX_COMPLETION_NAME_BYTES]u8,
	byte_count: u8,
}

/* Byte_Range is one canonical half-open UTF-8 byte range. */
Byte_Range :: struct {
	start: u64,
	end:   u64,
}

/* Request_Scope captures every authority generation required for publication. */
Request_Scope :: struct {
	document_id:                Document_ID,
	buffer_id:                  Buffer_ID,
	document_revision:          Document_Revision,
	view_id:                    View_ID,
	view_generation:            View_Generation,
	language_id:                Language_ID,
	language_generation:        Language_Generation,
	provider_id:                Provider_ID,
	provider_generation:        Provider_Generation,
	server_session_id:          Server_Session_ID,
	server_session_generation:  Server_Session_Generation,
	document_binding_id:        Document_Binding_ID,
	document_binding_generation: Document_Binding_Generation,
	transmitted_revision:       Document_Revision,
}

/* Request is one immutable provider-independent completion request. */
Request :: struct {
	id:                Request_ID,
	generation:        Request_Generation,
	scope:             Request_Scope,
	cursor_byte:       u64,
	query_range:       Byte_Range,
	query:             Text,
	trigger:           Trigger_Kind,
	trigger_character: Text,
	provider_capabilities: Capabilities,
	state:             Request_State,
}

/* Text_Edit is one normalized revision-bound replacement proposal. */
Text_Edit :: struct {
	range:    Byte_Range,
	new_text: Text,
}

/* Provenance identifies the exact provider and original item order. */
Provenance :: struct {
	provider_id:         Provider_ID,
	provider_generation: Provider_Generation,
	provider_order:      u32,
}

/* Candidate is one bounded normalized completion item. */
Candidate :: struct {
	id:                    Candidate_ID,
	kind:                  Candidate_Kind,
	availability:          Candidate_Availability,
	label:                 Text,
	label_detail:          Text,
	description:           Text,
	filter_text:           Text,
	sort_text:             Text,
	insertion_text:        Text,
	primary_edit:          Text_Edit,
	has_primary_edit:      bool,
	additional_edits:      [MAX_COMPLETION_ADDITIONAL_EDITS]Text_Edit,
	additional_edit_count: u8,
	detail:                Detail_Text,
	documentation:         Detail_Text,
	documentation_format:  Documentation_Format,
	resolve_token:         Resolve_Token,
	resolved:              bool,
	provenance:            Provenance,
	copied_bytes:          u64,
}

/* Batch is one immutable normalized provider publication. */
Batch :: struct {
	id:                       Batch_ID,
	generation:               Batch_Generation,
	request_id:               Request_ID,
	request_generation:       Request_Generation,
	scope:                    Request_Scope,
	request_cursor_byte:      u64,
	query_range:              Byte_Range,
	disposition:              Batch_Disposition,
	items:                    []Candidate,
	item_count:               u16,
	rejected_item_count:      u16,
	normalization_warning_count: u16,
	copied_bytes:             u64,
}

/* Implementation_Handle is one checked pointer-free role identity. */
Implementation_Handle :: struct {
	registry_id:               Role_Registry_ID,
	role:                      Role,
	implementation_id:         Implementation_ID,
	implementation_generation: Implementation_Generation,
}

/* Implementation_Definition is one complete copied role proposal. */
Implementation_Definition :: struct {
	name:         Name,
	source:       Name,
	role:         Role,
	kind:         Implementation_Kind,
	capabilities: Capabilities,
}

/* Implementation_Record pairs one exact handle and immutable definition. */
Implementation_Record :: struct {
	handle:     Implementation_Handle,
	definition: Implementation_Definition,
}

/* Registry_Stats reports exact role-registry occupancy and generations. */
Registry_Stats :: struct {
	registry_id:            Role_Registry_ID,
	registry_generation:    Role_Registry_Generation,
	composition_generation: Composition_Generation,
	live_implementations:   u16,
	factory_implementations: u16,
	package_implementations: u16,
	personal_implementations: u16,
	replacements:           u16,
	retained_bytes:         u64,
}

/* Role_Selection records selected and maintained factory implementations. */
Role_Selection :: struct {
	role:                  Role,
	selected:              Implementation_Handle,
	selected_capabilities: Capabilities,
	factory:               Implementation_Handle,
	factory_capabilities:  Capabilities,
}

/* Composition_Scope is one complete checked role-selection snapshot. */
Composition_Scope :: struct {
	registry_id:         Role_Registry_ID,
	registry_generation: Role_Registry_Generation,
	composition_generation: Composition_Generation,
	selections:          [MAX_COMPLETION_ROLES]Role_Selection,
	enabled:             bool,
}

/* Registry_Inspection is one bounded copied registry snapshot. */
Registry_Inspection :: struct {
	stats:          Registry_Stats,
	composition:    Composition_Scope,
	implementations: [MAX_COMPLETION_IMPLEMENTATIONS]Implementation_Record,
	implementation_count: u16,
	last_rejection: Failure,
}

/* Role_Registry owns bounded implementation definitions and selections. */
Role_Registry :: struct {
	state:  rawptr,
	closed: bool,
}

/* Controller owns one bounded provider-independent completion session. */
Controller :: struct {
	state:  rawptr,
	closed: bool,
}

/* Acceptance_Scope copies every completion identity required to accept one exact item. */
Acceptance_Scope :: struct {
	controller_id:         Controller_ID,
	controller_generation: Controller_Generation,
	session_id:            Session_ID,
	session_generation:    Session_Generation,
	request_id:            Request_ID,
	request_generation:    Request_Generation,
	request_scope:         Request_Scope,
	batch_id:              Batch_ID,
	batch_generation:      Batch_Generation,
	projection_generation: Projection_Generation,
	candidate_id:          Candidate_ID,
}

/* Limits contains one explicit completion resource policy. */
Limits :: struct {
	candidates:        u16,
	additional_edits:  u8,
	text_bytes:        u16,
	detail_bytes:      u16,
	resolve_bytes:     u16,
	implementations:   u16,
	replacements:      u16,
	request_replacements: u16,
}

/* DEFAULT_LIMITS is the initial bounded completion policy. */
DEFAULT_LIMITS :: Limits {
	candidates = MAX_COMPLETION_CANDIDATES,
	additional_edits = MAX_COMPLETION_ADDITIONAL_EDITS,
	text_bytes = MAX_COMPLETION_TEXT_BYTES,
	detail_bytes = MAX_COMPLETION_DETAIL_BYTES,
	resolve_bytes = MAX_COMPLETION_RESOLVE_BYTES,
	implementations = MAX_COMPLETION_IMPLEMENTATIONS,
	replacements = MAX_COMPLETION_REPLACEMENTS,
	request_replacements = MAX_COMPLETION_REQUEST_REPLACEMENTS,
}

/* Failure reports one rejected completion operation. */
Failure :: struct {
	operation:          Operation,
	code:               Failure_Code,
	role:               Role,
	implementation:     Implementation_Handle,
	request_id:         Request_ID,
	request_generation: Request_Generation,
	limit:              u64,
	actual:             u64,
}

/* Session_Inspection is one copied observable controller snapshot. */
Session_Inspection :: struct {
	controller_id:                 Controller_ID,
	controller_generation:         Controller_Generation,
	session_id:                    Session_ID,
	session_generation:            Session_Generation,
	state:                         Session_State,
	request:                       Request,
	batch_id:                      Batch_ID,
	batch_generation:              Batch_Generation,
	projection_generation:         Projection_Generation,
	candidate_count:                u16,
	filtered_candidate_count:       u16,
	deduplicated_candidate_count: u16,
	rejected_candidate_count:       u16,
	normalization_warning_count:    u16,
	additional_edit_count:          u16,
	resolved_candidate_count:       u16,
	deprecated_candidate_count:     u16,
	match_class_counts:             [4]u16,
	selected_candidate:             Candidate_ID,
	selected_resolved:              bool,
	detail_state:                   Detail_State,
	resolve_pending:                bool,
	query_range:                    Byte_Range,
	query:                          Text,
	trigger:                        Trigger_Kind,
	current_revision:               Document_Revision,
	transmitted_revision:           Document_Revision,
	batch_disposition:              Batch_Disposition,
	retained_during_refresh:        bool,
	policy:                         Session_Policy,
	copied_candidate_bytes:         u64,
	composition:                    Composition_Scope,
	retained_bytes:                 u64,
	last_rejection:                 Failure,
}

/* Candidate_Detail copies the selected candidate's bounded inspectable content. */
Candidate_Detail :: struct {
	controller_id:        Controller_ID,
	controller_generation: Controller_Generation,
	session_id:           Session_ID,
	session_generation:   Session_Generation,
	batch_id:             Batch_ID,
	batch_generation:     Batch_Generation,
	projection_generation: Projection_Generation,
	candidate_id:         Candidate_ID,
	kind:                 Candidate_Kind,
	availability:         Candidate_Availability,
	label:                Text,
	detail:               Detail_Text,
	documentation:        Detail_Text,
	documentation_format: Documentation_Format,
	state:                Detail_State,
}

/* Resolve_Request binds opaque provider data to one exact selected candidate generation. */
Resolve_Request :: struct {
	generation:           Resolve_Generation,
	controller_id:        Controller_ID,
	controller_generation: Controller_Generation,
	session_id:           Session_ID,
	session_generation:   Session_Generation,
	batch_id:             Batch_ID,
	batch_generation:     Batch_Generation,
	projection_generation: Projection_Generation,
	candidate_id:         Candidate_ID,
	provider_id:          Provider_ID,
	provider_generation:  Provider_Generation,
	document_revision:    Document_Revision,
	token:                Resolve_Token,
}

/* Candidate_Resolution contains only detail fields allowed to change after publication. */
Candidate_Resolution :: struct {
	request:              Resolve_Request,
	detail:               Detail_Text,
	documentation:        Detail_Text,
	documentation_format: Documentation_Format,
}

/* text_copy copies one bounded ordinary text field. */
text_copy :: proc(value: string) -> (Text, bool) {
	if len(value) > MAX_COMPLETION_TEXT_BYTES {
		return {}, false
	}
	result: Text
	result.byte_count = u16(copy(result.bytes[:], transmute([]u8)value))
	return result, true
}

/* text_view borrows the populated bytes of one copied ordinary text field. */
text_view :: proc(value: ^Text) -> string {
	if value == nil || int(value.byte_count) > len(value.bytes) {
		return ""
	}
	return string(value.bytes[:value.byte_count])
}

/* detail_copy copies one bounded detail or documentation field. */
detail_copy :: proc(value: string) -> (Detail_Text, bool) {
	if len(value) > MAX_COMPLETION_DETAIL_BYTES {
		return {}, false
	}
	result: Detail_Text
	result.byte_count = u16(copy(result.bytes[:], transmute([]u8)value))
	return result, true
}

/* detail_view borrows the populated bytes of one copied detail field. */
detail_view :: proc(value: ^Detail_Text) -> string {
	if value == nil || int(value.byte_count) > len(value.bytes) {
		return ""
	}
	return string(value.bytes[:value.byte_count])
}

/* resolve_token_copy copies one bounded opaque provider token. */
resolve_token_copy :: proc(value: string) -> (Resolve_Token, bool) {
	if len(value) > MAX_COMPLETION_RESOLVE_BYTES {
		return {}, false
	}
	result: Resolve_Token
	result.byte_count = u16(copy(result.bytes[:], transmute([]u8)value))
	return result, true
}

/* resolve_token_view borrows the populated bytes of one copied resolve token. */
resolve_token_view :: proc(value: ^Resolve_Token) -> string {
	if value == nil || int(value.byte_count) > len(value.bytes) {
		return ""
	}
	return string(value.bytes[:value.byte_count])
}

/* name_copy copies one non-empty bounded implementation name. */
name_copy :: proc(value: string) -> (Name, bool) {
	if len(value) == 0 || len(value) > MAX_COMPLETION_NAME_BYTES {
		return {}, false
	}
	result: Name
	result.byte_count = u8(copy(result.bytes[:], transmute([]u8)value))
	return result, true
}

/* name_view borrows the populated bytes of one copied implementation name. */
name_view :: proc(value: ^Name) -> string {
	if value == nil || value.byte_count == 0 || int(value.byte_count) > len(value.bytes) {
		return ""
	}
	return string(value.bytes[:value.byte_count])
}

/* range_is_valid reports whether one half-open range is ordered. */
range_is_valid :: proc(value: Byte_Range) -> bool {
	return value.start <= value.end
}

/* request_scope_is_valid validates every required request authority. */
request_scope_is_valid :: proc(scope: Request_Scope) -> bool {
	return scope.document_id != Document_ID(0) && scope.buffer_id != Buffer_ID(0) &&
		scope.view_id != View_ID(0) && scope.view_generation != View_Generation(0) &&
		scope.language_id != Language_ID(0) &&
		scope.language_generation != Language_Generation(0) && scope.provider_id != Provider_ID(0) &&
		scope.provider_generation != Provider_Generation(0) &&
		scope.server_session_id != Server_Session_ID(0) &&
		scope.server_session_generation != Server_Session_Generation(0) &&
		scope.document_binding_id != Document_Binding_ID(0) &&
		scope.document_binding_generation != Document_Binding_Generation(0) &&
		scope.transmitted_revision == scope.document_revision
}

/* request_is_valid validates one prepared provider-independent request. */
request_is_valid :: proc(request: ^Request) -> bool {
	return request != nil && request.id != Request_ID(0) &&
		request.generation != Request_Generation(0) && request_scope_is_valid(request.scope) &&
		range_is_valid(request.query_range) && request.cursor_byte >= request.query_range.end &&
		request.trigger != .Invalid && request.state == .Prepared &&
		(request.trigger == .Trigger_Character) == (request.trigger_character.byte_count > 0)
}

/* candidate_is_valid validates one normalized item against its provider scope. */
candidate_is_valid :: proc(candidate: ^Candidate, scope: Request_Scope, limits := DEFAULT_LIMITS) -> bool {
	if candidate == nil || candidate.id == Candidate_ID(0) || candidate.kind == .Invalid ||
	   candidate.availability == .Invalid || candidate.label.byte_count == 0 ||
	   int(candidate.additional_edit_count) > int(limits.additional_edits) ||
	   int(candidate.additional_edit_count) > len(candidate.additional_edits) ||
	   candidate.provenance.provider_id != scope.provider_id ||
	   candidate.provenance.provider_generation != scope.provider_generation {
		return false
	}
	if candidate.has_primary_edit && !range_is_valid(candidate.primary_edit.range) {
		return false
	}
	for index in 0 ..< int(candidate.additional_edit_count) {
		if !range_is_valid(candidate.additional_edits[index].range) {
			return false
		}
	}
	return true
}

/* batch_is_valid validates one exact immutable request publication. */
batch_is_valid :: proc(batch: ^Batch, request: ^Request, limits := DEFAULT_LIMITS) -> bool {
	if batch == nil || request == nil || batch.id == Batch_ID(0) ||
	   batch.generation == Batch_Generation(0) || batch.request_id != request.id ||
	   batch.request_generation != request.generation || batch.scope != request.scope ||
	   batch.request_cursor_byte != request.cursor_byte || batch.query_range != request.query_range ||
	   batch.disposition == .Invalid || batch.item_count > limits.candidates ||
	   int(batch.item_count) != len(batch.items) {
		return false
	}
	for index in 0 ..< int(batch.item_count) {
		if !candidate_is_valid(&batch.items[index], batch.scope, limits) {
			return false
		}
	}
	return true
}

/* limits_are_valid validates one bounded completion resource policy. */
limits_are_valid :: proc(limits: Limits) -> bool {
	return limits.candidates > 0 && limits.candidates <= MAX_COMPLETION_CANDIDATES &&
		limits.additional_edits <= MAX_COMPLETION_ADDITIONAL_EDITS &&
		limits.text_bytes > 0 && limits.text_bytes <= MAX_COMPLETION_TEXT_BYTES &&
		limits.detail_bytes > 0 && limits.detail_bytes <= MAX_COMPLETION_DETAIL_BYTES &&
		limits.resolve_bytes > 0 && limits.resolve_bytes <= MAX_COMPLETION_RESOLVE_BYTES &&
		limits.implementations >= MAX_COMPLETION_ROLES &&
		limits.implementations <= MAX_COMPLETION_IMPLEMENTATIONS &&
		limits.replacements > 0 && limits.replacements <= MAX_COMPLETION_REPLACEMENTS &&
		limits.request_replacements > 0 &&
		limits.request_replacements <= MAX_COMPLETION_REQUEST_REPLACEMENTS
}
