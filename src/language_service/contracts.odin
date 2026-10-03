// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package language_service owns bounded external language-service contracts,
// process and protocol lifetimes, copied state, accounting, and inspection.
package language_service

/* KIBIBYTE is the binary byte unit used by language-service limits. */
KIBIBYTE :: u64(1_024)
/* MEBIBYTE is 1,024 kibibytes. */
MEBIBYTE :: u64(1_024) * KIBIBYTE

/* MAX_NAME_BYTES bounds one copied service or provider display name. */
MAX_NAME_BYTES :: 96
/* MAX_REQUEST_ID_TEXT_BYTES bounds one copied JSON-RPC string identifier. */
MAX_REQUEST_ID_TEXT_BYTES :: 128
/* MAX_FAILURE_TEXT_BYTES bounds one copied contained failure explanation. */
MAX_FAILURE_TEXT_BYTES :: 4 * 1_024
/* MAX_LANGUAGE_IDENTITIES bounds one definition's copied language selectors. */
MAX_LANGUAGE_IDENTITIES :: 64
/* MAX_ROOT_MARKERS bounds one definition's relative root selectors. */
MAX_ROOT_MARKERS :: 16
/* MAX_COMPLETION_TRIGGER_CHARACTERS bounds copied server trigger characters. */
MAX_COMPLETION_TRIGGER_CHARACTERS :: 32
/* MAX_COMPLETION_TRIGGER_BYTES bounds one copied server trigger character. */
MAX_COMPLETION_TRIGGER_BYTES :: 16
/* MAX_SEMANTIC_TOKEN_TYPES bounds one copied server legend. */
MAX_SEMANTIC_TOKEN_TYPES :: 128

/* Registry_ID identifies one language-service owner; zero is invalid. */
Registry_ID :: distinct u64
/* Registry_Generation identifies one live language-service owner generation. */
Registry_Generation :: distinct u64
/* Definition_ID identifies one admitted service definition; zero is invalid. */
Definition_ID :: distinct u64
/* Definition_Generation identifies one exact service-definition publication. */
Definition_Generation :: distinct u64
/* Provider_ID identifies one admitted provider; zero is invalid. */
Provider_ID :: distinct u64
/* Provider_Generation identifies one exact provider state. */
Provider_Generation :: distinct u64
/* Session_ID identifies one server session; zero is invalid. */
Session_ID :: distinct u64
/* Session_Generation identifies one exact server-process lifecycle. */
Session_Generation :: distinct u64
/* Process_ID identifies one owned child-process record; zero is invalid. */
Process_ID :: distinct u64
/* Process_Generation identifies one exact child-process incarnation. */
Process_Generation :: distinct u64
/* Transport_ID identifies one owned protocol transport; zero is invalid. */
Transport_ID :: distinct u64
/* Transport_Generation identifies one exact transport incarnation. */
Transport_Generation :: distinct u64
/* Request_Generation identifies one outstanding-request table generation. */
Request_Generation :: distinct u64
/* Document_Binding_ID identifies one session-owned document binding. */
Document_Binding_ID :: distinct u64
/* Document_Binding_Generation identifies one exact document binding. */
Document_Binding_Generation :: distinct u64
/* Synchronization_Generation identifies one exact queued synchronization state. */
Synchronization_Generation :: distinct u64
/* Inspection_Generation identifies one copied inspection publication. */
Inspection_Generation :: distinct u64
/* Diagnostic_Generation identifies one complete document diagnostic publication. */
Diagnostic_Generation :: distinct u64
/* Diagnostic_ID identifies one diagnostic inside its complete generation. */
Diagnostic_ID :: distinct u64

/* Completion_Trigger_Text stores one bounded copied server trigger character. */
Completion_Trigger_Text :: struct {
	bytes:  [MAX_COMPLETION_TRIGGER_BYTES]u8,
	length: u8,
}

/* Completion_Capability_Values copies the negotiated provider behavior. */
Completion_Capability_Values :: struct {
	available:          bool,
	resolve:            bool,
	trigger_characters: [MAX_COMPLETION_TRIGGER_CHARACTERS]Completion_Trigger_Text,
	trigger_count:      u8,
}

/* Semantic_Token_Capability_Values copies the negotiated server legend. */
Semantic_Token_Capability_Values :: struct {
	available:   bool,
	delta:       bool,
	token_types: [MAX_SEMANTIC_TOKEN_TYPES]Name_Text,
	token_count: u16,
}

/* Name_Text stores one bounded copied UTF-8 name. */
Name_Text :: struct {
	bytes:  [MAX_NAME_BYTES]u8,
	length: u16,
}

/* Request_ID_Text stores one bounded copied JSON-RPC string identifier. */
Request_ID_Text :: struct {
	bytes:  [MAX_REQUEST_ID_TEXT_BYTES]u8,
	length: u16,
}

/* Failure_Text stores one bounded copied failure explanation. */
Failure_Text :: struct {
	bytes:  [MAX_FAILURE_TEXT_BYTES]u8,
	length: u16,
}

/* Storage_Range identifies copied bytes in one generation-owned byte store. */
Storage_Range :: struct {
	storage_generation: u64,
	offset:             u64,
	length:             u64,
}

/* Record_Range identifies copied records in one generation-owned record store. */
Record_Range :: struct {
	first: u32,
	count: u32,
}

/* Registry_Handle is one checked pointer-free owner identity. */
Registry_Handle :: struct {
	id:         Registry_ID,
	generation: Registry_Generation,
}

/* Definition_Handle is one checked pointer-free service-definition identity. */
Definition_Handle :: struct {
	registry:   Registry_Handle,
	id:         Definition_ID,
	generation: Definition_Generation,
}

/* Provider_Handle is one checked pointer-free provider identity. */
Provider_Handle :: struct {
	definition: Definition_Handle,
	id:         Provider_ID,
	generation: Provider_Generation,
}

/* Session_Handle is one checked pointer-free session identity. */
Session_Handle :: struct {
	provider:   Provider_Handle,
	id:         Session_ID,
	generation: Session_Generation,
}

/* Process_Handle is one checked pointer-free child-process identity. */
Process_Handle :: struct {
	session:    Session_Handle,
	id:         Process_ID,
	generation: Process_Generation,
}

/* Transport_Handle is one checked pointer-free transport identity. */
Transport_Handle :: struct {
	process:    Process_Handle,
	id:         Transport_ID,
	generation: Transport_Generation,
}

/* Document_Binding_Handle is one checked pointer-free document identity. */
Document_Binding_Handle :: struct {
	session:    Session_Handle,
	id:         Document_Binding_ID,
	generation: Document_Binding_Generation,
}

/* Provider_Kind identifies the source of one admitted provider definition. */
Provider_Kind :: enum u8 {
	Invalid,
	Factory,
	Native,
	Programmable,
}

/* Provider_State reports one provider lifecycle state. */
Provider_State :: enum u8 {
	Invalid,
	Admitted,
	Confirmed,
	Selected,
	Disabled,
	Failed,
	Closed,
}

/* Executable_Availability reports the latest bounded discovery result. */
Executable_Availability :: enum u8 {
	Unknown,
	Available,
	Unavailable,
	Changed,
	Rejected,
}

/* Executable_Source identifies the safe provenance of one resolved executable. */
Executable_Source :: enum u8 {
	Invalid,
	Explicit,
	Package_Artifact,
	Distributed_Artifact,
	Search_Path,
}

/* Health reports one server-session lifecycle state. */
Health :: enum u8 {
	Stopped,
	Discovering,
	Starting,
	Initializing,
	Active,
	Cancelling,
	Restarting,
	Shutting_Down,
	Terminating,
	Failed,
	Closed,
}

/* Process_State reports one child-process ownership state. */
Process_State :: enum u8 {
	None,
	Starting,
	Running,
	Exited,
	Waiting_For_Reap,
	Reaped,
	Terminated,
}

/* Transport_State reports one protocol-stream ownership state. */
Transport_State :: enum u8 {
	None,
	Opening,
	Open,
	Read_Closed,
	Write_Closed,
	Closed,
	Failed,
}

/* Request_State reports one JSON-RPC request lifecycle state. */
Request_State :: enum u8 {
	Invalid,
	Queued,
	Sent,
	Completed,
	Cancelling,
	Cancelled,
	Timed_Out,
	Failed,
}

/* Document_State reports one bound document lifecycle state. */
Document_State :: enum u8 {
	Invalid,
	Opening,
	Open,
	Changing,
	Saving,
	Closing,
	Closed,
	Failed,
}

/* Synchronization_Mode is the server-selected document update strategy. */
Synchronization_Mode :: enum u8 {
	None,
	Full,
	Incremental,
}

/* Root_Policy selects the trusted Project-derived root used by one definition. */
Root_Policy :: enum u8 {
	Invalid,
	Project_Membership,
	Workspace_Folder,
}

/* Synchronization_State reports one document synchronization disposition. */
Synchronization_State :: enum u8 {
	Idle,
	Queued,
	Sending,
	Current,
	Coalesced,
	Recovering,
	Failed,
}

/* Position_Encoding names the negotiated LSP position unit. */
Position_Encoding :: enum u8 {
	Invalid,
	UTF_8,
	UTF_16,
	UTF_32,
}

/* Capability names one implemented language-service protocol behavior. */
Capability :: enum u8 {
	Initialize,
	Shutdown,
	Cancellation,
	Full_Synchronization,
	Incremental_Synchronization,
	Save_Notification,
	Push_Diagnostics,
	Log_Message,
	Completion,
	Hover,
	Definition,
	References,
	Document_Symbols,
	Workspace_Symbols,
	Signature_Help,
	Semantic_Tokens,
}

/* Capabilities is one bounded admitted protocol capability set. */
Capabilities :: bit_set[Capability; u16]

/* Service_Feature names one user-facing language-independent editor feature. */
Service_Feature :: enum u8 {
	Diagnostics,
	Completion,
	Navigation,
	Hover,
	References,
	Symbols,
	Signature_Help,
	Rename,
	Formatting,
	Semantic_Tokens,
	Code_Actions,
}

/* Service_Features is one bounded symbolic feature policy. */
Service_Features :: bit_set[Service_Feature; u16]

/* Request_ID_Kind identifies the admitted JSON-RPC identifier representation. */
Request_ID_Kind :: enum u8 {
	Invalid,
	Integer,
	Text,
}

/* Request_ID is one copied JSON-RPC request identity. */
Request_ID :: struct {
	kind:    Request_ID_Kind,
	integer: i64,
	text:    Request_ID_Text,
}

/* Deadline_Kind identifies one bounded lifecycle or request deadline. */
Deadline_Kind :: enum u8 {
	Discovery,
	Initialization,
	Request,
	Cancellation,
	Idle_Step,
	Restart_Stability,
	Shutdown,
	Forced_Termination,
}

/* Deadline_Policy selects monotonic deadline durations in nanoseconds. */
Deadline_Policy :: struct {
	discovery_ns:          i64,
	initialization_ns:     i64,
	request_ns:            i64,
	cancellation_ns:       i64,
	idle_step_ns:          i64,
	restart_stability_ns:  i64,
	shutdown_ns:           i64,
	forced_termination_ns: i64,
}

/* Restart_Policy selects the bounded automatic restart budget. */
Restart_Policy :: struct {
	automatic_restarts: u8,
	stability_ns:       i64,
}

/* Service_Limits selects all admitted topology, byte, and work ceilings. */
Service_Limits :: struct {
	service_definitions:       u16,
	providers:                 u16,
	sessions:                  u16,
	documents_per_session:     u16,
	documents_total:           u32,
	executable_bytes:          u64,
	arguments:                 u16,
	argument_bytes:            u64,
	environment_entries:       u16,
	environment_bytes:         u64,
	root_bytes:                u64,
	uri_bytes:                 u64,
	options_bytes:             u64,
	frame_header_bytes:        u64,
	json_depth:                u16,
	message_bytes:             u64,
	buffered_stream_bytes:     u64,
	outstanding_requests:      u32,
	notifications:             u32,
	queue_depth:               u32,
	queue_bytes:               u64,
	synchronization_changes:   u32,
	synchronization_bytes:     u64,
	diagnostics_per_document:  u32,
	diagnostics_per_project:   u32,
	diagnostic_fields:         u16,
	diagnostic_message_bytes:  u64,
	related_locations:         u16,
	diagnostic_bytes:          u64,
	candidates:                u32,
	candidate_text_bytes:      u64,
	standard_error_bytes:      u64,
	work_bytes_per_turn:       u64,
	retained_bytes:            u64,
	temporary_bytes:           u64,
}

/* DEFAULT_DEADLINES is the measured factory lifecycle deadline policy. */
DEFAULT_DEADLINES :: Deadline_Policy {
	discovery_ns = 500_000_000,
	initialization_ns = 10_000_000_000,
	request_ns = 5_000_000_000,
	cancellation_ns = 1_000_000_000,
	idle_step_ns = 50_000_000,
	restart_stability_ns = 30_000_000_000,
	shutdown_ns = 3_000_000_000,
	forced_termination_ns = 1_000_000_000,
}

/* DEFAULT_RESTART_POLICY admits one automatic restart per active generation. */
DEFAULT_RESTART_POLICY :: Restart_Policy {
	automatic_restarts = 1,
	stability_ns = DEFAULT_DEADLINES.restart_stability_ns,
}

/* DEFAULT_LIMITS is the selected bounded language-service resource policy. */
DEFAULT_LIMITS :: Service_Limits {
	service_definitions = 64,
	providers = 64,
	sessions = 32,
	documents_per_session = 256,
	documents_total = 4_096,
	executable_bytes = 4 * KIBIBYTE,
	arguments = 64,
	argument_bytes = 64 * KIBIBYTE,
	environment_entries = 64,
	environment_bytes = 64 * KIBIBYTE,
	root_bytes = 16 * KIBIBYTE,
	uri_bytes = 32 * KIBIBYTE,
	options_bytes = 1 * MEBIBYTE,
	frame_header_bytes = 8 * KIBIBYTE,
	json_depth = 64,
	message_bytes = 16 * MEBIBYTE,
	buffered_stream_bytes = 32 * MEBIBYTE,
	outstanding_requests = 1_024,
	notifications = 4_096,
	queue_depth = 4_096,
	queue_bytes = 64 * MEBIBYTE,
	synchronization_changes = 4_096,
	synchronization_bytes = 64 * MEBIBYTE,
	diagnostics_per_document = 4_096,
	diagnostics_per_project = 65_536,
	diagnostic_fields = 32,
	diagnostic_message_bytes = 64 * KIBIBYTE,
	related_locations = 32,
	diagnostic_bytes = 128 * MEBIBYTE,
	candidates = 65_536,
	candidate_text_bytes = 64 * MEBIBYTE,
	standard_error_bytes = 1 * MEBIBYTE,
	work_bytes_per_turn = 256 * KIBIBYTE,
	retained_bytes = 512 * MEBIBYTE,
	temporary_bytes = 128 * MEBIBYTE,
}

/* Service_Definition is one admitted data-only external server definition. */
Service_Definition :: struct {
	handle:                  Definition_Handle,
	name:                    Name_Text,
	executable:              Storage_Range,
	arguments:               Record_Range,
	environment:             Record_Range,
	languages:               Record_Range,
	root_policy:             Root_Policy,
	initialization_options:  Storage_Range,
	client_settings:         Storage_Range,
	feature_policy:          Service_Features,
	requested_capabilities:  Capabilities,
	preferred_encoding:      Position_Encoding,
	preferred_sync:          Synchronization_Mode,
	limits:                  Service_Limits,
	deadlines:               Deadline_Policy,
	restart:                 Restart_Policy,
}

/* Provider_Descriptor is one copied admitted provider state. */
Provider_Descriptor :: struct {
	handle:       Provider_Handle,
	kind:         Provider_Kind,
	state:        Provider_State,
	name:         Name_Text,
	capabilities: Capabilities,
}

/* Session_Descriptor is one copied root-scoped server-session state. */
Session_Descriptor :: struct {
	handle:                 Session_Handle,
	health:                 Health,
	root:                   Storage_Range,
	capabilities:           Capabilities,
	position_encoding:      Position_Encoding,
	synchronization_mode:   Synchronization_Mode,
	automatic_restarts:     u8,
	bound_documents:        u32,
	outstanding_requests:   u32,
	queued_notifications:   u32,
}

/* Process_Descriptor is one copied child-process ownership state. */
Process_Descriptor :: struct {
	handle:          Process_Handle,
	state:           Process_State,
	os_process_id:   i64,
	started_ns:      i64,
	exited_ns:       i64,
	exit_status:     i32,
	termination_due_ns: i64,
}

/* Transport_Descriptor is one copied protocol transport state. */
Transport_Descriptor :: struct {
	handle:            Transport_Handle,
	state:             Transport_State,
	buffered_read:     u64,
	buffered_write:    u64,
	frames_received:   u64,
	frames_sent:       u64,
	malformed_frames:  u64,
	discarded_bytes:   u64,
}

/* Request_Descriptor is one copied outstanding JSON-RPC request state. */
Request_Descriptor :: struct {
	session:             Session_Handle,
	table_generation:    Request_Generation,
	id:                  Request_ID,
	state:               Request_State,
	method:              Name_Text,
	queued_ns:           i64,
	deadline_ns:         i64,
	payload_bytes:       u64,
}

/* Document_Binding_Descriptor is one copied exact-revision document state. */
Document_Binding_Descriptor :: struct {
	handle:                     Document_Binding_Handle,
	state:                      Document_State,
	document_identity:          u64,
	buffer_identity:            u64,
	canonical_revision:         u64,
	transmitted_revision:       u64,
	document_version:           i64,
	uri:                        Storage_Range,
	position_encoding:          Position_Encoding,
	synchronization_mode:       Synchronization_Mode,
	synchronization_generation: Synchronization_Generation,
}

/* Synchronization_Record is one copied queued document update. */
Synchronization_Record :: struct {
	binding:              Document_Binding_Handle,
	generation:           Synchronization_Generation,
	state:                Synchronization_State,
	base_revision:        u64,
	target_revision:      u64,
	document_version:     i64,
	changes:              Record_Range,
	payload:              Storage_Range,
	coalesced_operations: u32,
}

/* Resource_Usage reports exact logical and allocated service resources. */
Resource_Usage :: struct {
	service_definitions:       u32,
	providers:                 u32,
	sessions:                  u32,
	documents:                 u32,
	outstanding_requests:      u32,
	notifications:             u32,
	queue_depth:               u32,
	queue_bytes:               u64,
	synchronization_changes:   u32,
	synchronization_bytes:     u64,
	diagnostics:               u32,
	diagnostic_bytes:          u64,
	candidates:                u32,
	candidate_text_bytes:      u64,
	standard_error_bytes:      u64,
	retained_bytes:            u64,
	temporary_bytes:           u64,
	work_bytes:                u64,
}

/* Resource_Kind identifies one bounded language-service resource. */
Resource_Kind :: enum u8 {
	None,
	Definition,
	Provider,
	Session,
	Document,
	Executable_Bytes,
	Argument,
	Environment,
	Root_Bytes,
	URI_Bytes,
	Option_Bytes,
	Frame_Header_Bytes,
	JSON_Depth,
	Message_Bytes,
	Stream_Bytes,
	Request,
	Notification,
	Queue,
	Queue_Bytes,
	Synchronization_Change,
	Synchronization_Bytes,
	Diagnostic,
	Diagnostic_Bytes,
	Candidate,
	Candidate_Text_Bytes,
	Standard_Error_Bytes,
	Retained_Bytes,
	Temporary_Bytes,
	Work_Bytes,
}

/* Failure_Code classifies contained definition, process, protocol, and owner failures. */
Failure_Code :: enum u16 {
	None,
	Invalid_Input,
	Invalid_Definition,
	Invalid_Provider,
	Invalid_Session,
	Invalid_Process,
	Invalid_Transport,
	Invalid_Request,
	Invalid_Document,
	Invalid_Diagnostic,
	Invalid_Range,
	Invalid_Severity,
	Project_Scope,
	Untrusted_Root,
	Outside_Root,
	Revoked,
	Stale_Generation,
	Resource_Limit,
	Arithmetic_Overflow,
	Executable_Not_Found,
	Spawn,
	Pipe,
	Framing,
	Malformed_JSON,
	Protocol,
	Unsupported_Capability,
	Unknown_Method,
	Timeout,
	Cancelled,
	Process_Exit,
	Restart_Exhausted,
	Shutdown,
	Termination,
	Reap,
	Allocation,
	Closed,
}

/* Failure_Context identifies one contained failure and its applicable bound. */
Failure_Context :: struct {
	code:       Failure_Code,
	resource:   Resource_Kind,
	definition: Definition_Handle,
	provider:   Provider_Handle,
	session:    Session_Handle,
	process:    Process_Handle,
	transport:  Transport_Handle,
	binding:    Document_Binding_Handle,
	request_id: Request_ID,
	deadline:   Deadline_Kind,
	limit:      u64,
	actual:     u64,
	detail:     Failure_Text,
}

/* Inspection_Kind selects one bounded copied language-service view. */
Inspection_Kind :: enum u8 {
	Registry,
	Definition,
	Provider,
	Session,
	Process,
	Transport,
	Document,
	Diagnostics,
	Resources,
	Latest_Failure,
}

/* Inspection_Query selects one generation-checked copied inspection view. */
Inspection_Query :: struct {
	kind:       Inspection_Kind,
	registry:   Registry_Handle,
	definition: Definition_Handle,
	provider:   Provider_Handle,
	session:    Session_Handle,
	binding:    Document_Binding_Handle,
}

/* Inspection_Record is one pointer-free copied language-service view. */
Inspection_Record :: struct {
	generation: Inspection_Generation,
	kind:       Inspection_Kind,
	definition: Service_Definition,
	provider:   Provider_Descriptor,
	session:    Session_Descriptor,
	process:    Process_Descriptor,
	transport:  Transport_Descriptor,
	document:   Document_Binding_Descriptor,
	usage:      Resource_Usage,
	limits:     Service_Limits,
	failure:    Failure_Context,
}

/* storage_range_valid reports whether a copied range fits its owner storage. */
storage_range_valid :: proc(value: Storage_Range, storage_bytes: u64) -> bool {
	if value.length > storage_bytes || value.offset > storage_bytes - value.length {
		return false
	}
	return value.length == 0 || value.storage_generation != 0
}

/* deadline_policy_valid reports whether every selected duration is positive and ordered. */
deadline_policy_valid :: proc(policy: Deadline_Policy) -> bool {
	return policy.idle_step_ns > 0 &&
		policy.discovery_ns > policy.idle_step_ns &&
		policy.cancellation_ns >= policy.discovery_ns &&
		policy.forced_termination_ns >= policy.cancellation_ns &&
		policy.shutdown_ns >= policy.forced_termination_ns &&
		policy.request_ns >= policy.shutdown_ns &&
		policy.initialization_ns >= policy.request_ns &&
		policy.restart_stability_ns >= policy.initialization_ns
}

/* service_limits_valid reports whether a policy stays inside selected native maxima. */
service_limits_valid :: proc(limits: Service_Limits) -> bool {
	return limits.service_definitions > 0 && limits.service_definitions <= DEFAULT_LIMITS.service_definitions &&
		limits.providers > 0 && limits.providers <= DEFAULT_LIMITS.providers &&
		limits.sessions > 0 && limits.sessions <= DEFAULT_LIMITS.sessions &&
		limits.documents_per_session > 0 && limits.documents_per_session <= DEFAULT_LIMITS.documents_per_session &&
		limits.documents_total > 0 && limits.documents_total <= DEFAULT_LIMITS.documents_total &&
		limits.executable_bytes > 0 && limits.executable_bytes <= DEFAULT_LIMITS.executable_bytes &&
		limits.arguments <= DEFAULT_LIMITS.arguments && limits.argument_bytes <= DEFAULT_LIMITS.argument_bytes &&
		limits.environment_entries <= DEFAULT_LIMITS.environment_entries && limits.environment_bytes <= DEFAULT_LIMITS.environment_bytes &&
		limits.root_bytes > 0 && limits.root_bytes <= DEFAULT_LIMITS.root_bytes &&
		limits.uri_bytes > 0 && limits.uri_bytes <= DEFAULT_LIMITS.uri_bytes &&
		limits.options_bytes <= DEFAULT_LIMITS.options_bytes &&
		limits.frame_header_bytes > 0 && limits.frame_header_bytes <= DEFAULT_LIMITS.frame_header_bytes &&
		limits.json_depth > 0 && limits.json_depth <= DEFAULT_LIMITS.json_depth &&
		limits.message_bytes > 0 && limits.message_bytes <= DEFAULT_LIMITS.message_bytes &&
		limits.buffered_stream_bytes >= limits.message_bytes && limits.buffered_stream_bytes <= DEFAULT_LIMITS.buffered_stream_bytes &&
		limits.outstanding_requests > 0 && limits.outstanding_requests <= DEFAULT_LIMITS.outstanding_requests &&
		limits.notifications > 0 && limits.notifications <= DEFAULT_LIMITS.notifications &&
		limits.queue_depth > 0 && limits.queue_depth <= DEFAULT_LIMITS.queue_depth &&
		limits.queue_bytes >= limits.message_bytes && limits.queue_bytes <= DEFAULT_LIMITS.queue_bytes &&
		limits.synchronization_changes > 0 && limits.synchronization_changes <= DEFAULT_LIMITS.synchronization_changes &&
		limits.synchronization_bytes >= limits.message_bytes && limits.synchronization_bytes <= DEFAULT_LIMITS.synchronization_bytes &&
		limits.diagnostics_per_document > 0 && limits.diagnostics_per_document <= DEFAULT_LIMITS.diagnostics_per_document &&
		limits.diagnostics_per_project >= limits.diagnostics_per_document && limits.diagnostics_per_project <= DEFAULT_LIMITS.diagnostics_per_project &&
		limits.diagnostic_fields > 0 && limits.diagnostic_fields <= DEFAULT_LIMITS.diagnostic_fields &&
		limits.diagnostic_message_bytes > 0 && limits.diagnostic_message_bytes <= DEFAULT_LIMITS.diagnostic_message_bytes &&
		limits.related_locations <= DEFAULT_LIMITS.related_locations &&
		limits.diagnostic_bytes >= limits.diagnostic_message_bytes && limits.diagnostic_bytes <= DEFAULT_LIMITS.diagnostic_bytes &&
		limits.candidates >= limits.diagnostics_per_project && limits.candidates <= DEFAULT_LIMITS.candidates &&
		limits.candidate_text_bytes > 0 && limits.candidate_text_bytes <= DEFAULT_LIMITS.candidate_text_bytes &&
		limits.standard_error_bytes > 0 && limits.standard_error_bytes <= DEFAULT_LIMITS.standard_error_bytes &&
		limits.work_bytes_per_turn > 0 && limits.work_bytes_per_turn <= DEFAULT_LIMITS.work_bytes_per_turn &&
		limits.retained_bytes > 0 && limits.retained_bytes <= DEFAULT_LIMITS.retained_bytes &&
		limits.temporary_bytes > 0 && limits.temporary_bytes <= DEFAULT_LIMITS.temporary_bytes
}

/* resource_usage_valid reports whether current aggregate usage fits a policy. */
resource_usage_valid :: proc(usage: Resource_Usage, limits: Service_Limits) -> bool {
	return usage.service_definitions <= u32(limits.service_definitions) &&
		usage.providers <= u32(limits.providers) &&
		usage.sessions <= u32(limits.sessions) && usage.documents <= limits.documents_total &&
		usage.outstanding_requests <= limits.outstanding_requests &&
		usage.notifications <= limits.notifications && usage.queue_depth <= limits.queue_depth &&
		usage.queue_bytes <= limits.queue_bytes &&
		usage.synchronization_changes <= limits.synchronization_changes &&
		usage.synchronization_bytes <= limits.synchronization_bytes &&
		usage.diagnostics <= limits.diagnostics_per_project && usage.diagnostic_bytes <= limits.diagnostic_bytes &&
		usage.candidates <= limits.candidates && usage.candidate_text_bytes <= limits.candidate_text_bytes &&
		usage.standard_error_bytes <= limits.standard_error_bytes &&
		usage.retained_bytes <= limits.retained_bytes && usage.temporary_bytes <= limits.temporary_bytes &&
		usage.work_bytes <= limits.work_bytes_per_turn
}
