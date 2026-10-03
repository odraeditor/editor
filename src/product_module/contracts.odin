// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package product_module

/* ABI_VERSION identifies the current native product-module calling convention. */
ABI_VERSION :: u32(5)
/* MAX_IDENTITY_BYTES bounds one copied module or provider identity. */
MAX_IDENTITY_BYTES :: 128
/* MAX_VERSION_BYTES bounds one copied semantic version. */
MAX_VERSION_BYTES :: 64
/* MAX_ENTRYPOINT_BYTES bounds one exported symbol name. */
MAX_ENTRYPOINT_BYTES :: 128
/* MAX_ARTIFACT_PATH_BYTES bounds one absolute verified module path. */
MAX_ARTIFACT_PATH_BYTES :: 4096
/* MAX_ARTIFACT_BYTES bounds one loadable native product-module artifact. */
MAX_ARTIFACT_BYTES :: u64(512 * 1024 * 1024)
/* MAX_CALL_BYTES bounds one copied payload and its transport envelope at the native boundary. */
MAX_CALL_BYTES :: u64(8 * 1024 * 1024 + 64 * 1024)

/* Role identifies one neutral replaceable product responsibility. */
Role :: enum u32 {
	Invalid,
	Source_Control,
	File_Management,
	Workspace_Hierarchy,
	Structured_Document,
}

/* Lifecycle identifies one module instance state visible to the host. */
Lifecycle :: enum u32 {
	Invalid,
	Loaded,
	Active,
	Failed,
	Closed,
}

/* Operation identifies one generic module lifecycle or product invocation. */
Operation :: enum u32 {
	Invalid,
	Activate,
	Invoke,
	Step,
	Inspect,
	Deactivate,
	Input,
	Select,
	Configure,
}

/* CONFIGURATION_REQUEST_SCHEMA_VERSION identifies copied module configuration. */
CONFIGURATION_REQUEST_SCHEMA_VERSION :: u32(1)

/* Configuration_Disposition identifies one host-owned personal configuration transition. */
Configuration_Disposition :: enum u32 {
	Invalid,
	Confirmed,
	Rejected,
	Removed,
}

/* Configuration_Request_Header prefixes one complete module configuration generation. */
Configuration_Request_Header :: struct #align(8) {
	schema_version: u32,
	disposition:    Configuration_Disposition,
	generation:     u64,
	payload_length: u64,
}

/* INVOCATION_REQUEST_SCHEMA_VERSION identifies one copied registered-command invocation. */
INVOCATION_REQUEST_SCHEMA_VERSION :: u32(1)

/* Invocation_Request_Header prefixes a registered command name with its typed route. */
Invocation_Request_Header :: struct #align(8) {
	schema_version: u32,
	provider:       u16,
	operation:      u16,
	name_length:    u32,
	_reserved:      u32,
}

/* Host_Operation identifies one public host capability requested by a module. */
Host_Operation :: enum u32 {
	Invalid,
	Diagnostic,
	Command,
	Prompt,
	Session,
	UI,
	Process,
	Provider,
	Tree_UI,
	Clipboard,
	Filesystem,
	Workspace,
	Document,
}

/* PROCESS_REQUEST_SCHEMA_VERSION identifies one checked module process request. */
PROCESS_REQUEST_SCHEMA_VERSION :: u32(1)

/* Process_Action selects one host-owned shell task presentation. */
Process_Action :: enum u32 {
	Invalid,
	Shell,
	Async_Shell,
}

/* Process_Request_Header prefixes one copied working directory and command. */
Process_Request_Header :: struct #align(8) {
	schema_version:           u32,
	action:                   Process_Action,
	working_directory_length: u32,
	command_length:           u32,
}

/* DOCUMENT_REQUEST_SCHEMA_VERSION identifies one checked active-document request. */
DOCUMENT_REQUEST_SCHEMA_VERSION :: u32(1)

/* Document_Action identifies one generic structured-document capability. */
Document_Action :: enum u32 {
	Invalid,
	Inspect,
	Apply_Rewrite,
	Move_Point,
	Replace_Visibility,
}

/* Document_Request_Header prefixes one copied document capability request. */
Document_Request_Header :: struct #align(8) {
	schema_version: u32,
	action:         Document_Action,
	base_revision: u64,
	point:         u64,
	count:         u32,
	_reserved:     u32,
	payload_length: u64,
}

/* Document_Snapshot_Header prefixes one immutable source copy. */
Document_Snapshot_Header :: struct #align(8) {
	schema_version:       u32,
	flags:                u32,
	buffer_id:            u64,
	revision:             u64,
	point:                u64,
	mark:                 u64,
	view_generation:      u64,
	visibility_generation: u64,
	source_length:        u64,
	hidden_range_count:   u32,
	_reserved:            u32,
}

/* DOCUMENT_SNAPSHOT_MARK_PRESENT reports one retained mark. */
DOCUMENT_SNAPSHOT_MARK_PRESENT :: u32(1 << 0)
/* DOCUMENT_SNAPSHOT_REGION_ACTIVE reports an active region. */
DOCUMENT_SNAPSHOT_REGION_ACTIVE :: u32(1 << 1)

/* Document_Splice prefixes one replacement stored in the request payload. */
Document_Splice :: struct #align(8) {
	start:       u64,
	end:         u64,
	text_offset: u64,
	text_length: u64,
}

/* Document_Range identifies one half-open source interval. */
Document_Range :: struct #align(8) {
	start: u64,
	end:   u64,
}

/* FILESYSTEM_REQUEST_SCHEMA_VERSION identifies one checked local-resource request. */
FILESYSTEM_REQUEST_SCHEMA_VERSION :: u32(1)

/* Filesystem_Action identifies one bounded local-resource mutation. */
Filesystem_Action :: enum u32 {
	Invalid,
	Create_File,
	Create_Directory,
	Rename,
	Move,
	Copy,
	Delete,
}

/* Filesystem_Resource copies one provider-scoped resource identity. */
Filesystem_Resource :: struct #align(8) {
	provider: u64,
	device:   u64,
	inode:    u64,
}

/* Filesystem_Request_Header prefixes two bounded copied path or name operands. */
Filesystem_Request_Header :: struct #align(8) {
	schema_version:     u32,
	action:             Filesystem_Action,
	resource:           Filesystem_Resource,
	source_length:      u32,
	destination_length: u32,
}

/* WORKSPACE_REQUEST_SCHEMA_VERSION identifies one active-Workspace request. */
WORKSPACE_REQUEST_SCHEMA_VERSION :: u32(1)

/* Workspace_Action identifies one bounded active-Workspace transition. */
Workspace_Action :: enum u32 {
	Invalid,
	Next,
	Remove_Project,
	Move_Project_Earlier,
	Move_Project_Later,
	Rename_Project,
}

/* Workspace_Request_Header prefixes copied project-path and name operands. */
Workspace_Request_Header :: struct #align(8) {
	schema_version: u32,
	action:         Workspace_Action,
	project_length: u32,
	value_length:   u32,
}

/* PROVIDER_REQUEST_SCHEMA_VERSION identifies the generic copied provider envelope. */
PROVIDER_REQUEST_SCHEMA_VERSION :: u32(1)

/* Provider_Request_Header prefixes one generic programmable-provider invocation. */
Provider_Request_Header :: struct #align(8) {
	schema_version:      u32,
	_reserved:           u32,
	provider_generation: u64,
	operation:           u64,
	service_length:      u32,
	name_length:         u32,
	payload_length:      u64,
}

/* SYMBOL_PROVIDER_RESPONSE_SCHEMA_VERSION identifies one copied language-owned symbol generation. */
SYMBOL_PROVIDER_RESPONSE_SCHEMA_VERSION :: u32(1)

/* Symbol_Provider_Response_Header prefixes one immutable symbol generation and its retained names. */
Symbol_Provider_Response_Header :: struct #align(8) {
	schema_version:      u32,
	complete:            u32,
	provider_generation: u64,
	source_revision:     u64,
	record_count:        u32,
	text_bytes:          u32,
}

/* Symbol_Provider_Record copies one provider-neutral symbol and its exact source range. */
Symbol_Provider_Record :: struct #align(8) {
	id:              u64,
	parent_id:       u64,
	start:           u64,
	end:             u64,
	name_offset:     u32,
	name_length:     u16,
	hierarchy_depth: u16,
	kind:            u8,
	_reserved:       [7]u8,
}

/* SESSION_REQUEST_SCHEMA_VERSION identifies copied host session requests. */
SESSION_REQUEST_SCHEMA_VERSION :: u32(1)

/* Session_Action identifies one neutral editor-session capability. */
Session_Action :: enum u32 {
	Invalid,
	Present_Surface,
	Restore_Target,
	Inspect_Documents,
	Open_Path,
	Present_Entry,
	Present_Preview,
	Clear_Preview,
	Scroll_Preview,
	Inspect_Active_Document,
	Present_Position,
}

/* Session_Request_Header prefixes one copied editor-session capability request. */
Session_Request_Header :: struct #align(8) {
	schema_version: u32,
	action:         Session_Action,
	target:         u64,
	flags:          u64,
	payload_length: u64,
}

/* Session_Response returns only opaque handles and bounded aggregate state. */
Session_Response :: struct #align(8) {
	target:   u64,
	total:    u32,
	modified: u32,
	flags:    u64,
}

/* Session_Position identifies one exact byte position in a copied document generation. */
Session_Position :: struct #align(8) {
	revision: u64,
	point:    u64,
}

/* SESSION_PATH_EXACT requests one exact document path. */
SESSION_PATH_EXACT :: u64(1 << 0)
/* SESSION_PATH_PREFIX requests all documents below one directory path. */
SESSION_PATH_PREFIX :: u64(1 << 1)
/* SESSION_DOCUMENT_OPEN reports that one exact document is open. */
SESSION_DOCUMENT_OPEN :: u64(1 << 8)
/* SESSION_DOCUMENT_MODIFIED reports that one exact document has unsaved changes. */
SESSION_DOCUMENT_MODIFIED :: u64(1 << 9)
/* SESSION_PRESENT_OTHER_PANE requests presentation beside the module return target. */
SESSION_PRESENT_OTHER_PANE :: u64(1 << 16)
/* SESSION_PRESENT_FOCUS requests focus for an entry presented in another pane. */
SESSION_PRESENT_FOCUS :: u64(1 << 17)
/* SESSION_PRESENT_SPLIT_BELOW requests a new pane below the return target. */
SESSION_PRESENT_SPLIT_BELOW :: u64(1 << 18)
/* SESSION_PRESENT_SPLIT_RIGHT requests a new pane right of the return target. */
SESSION_PRESENT_SPLIT_RIGHT :: u64(1 << 19)
/* SESSION_SCROLL_BACKWARD reverses one preview-scroll request. */
SESSION_SCROLL_BACKWARD :: u64(1 << 20)
/* SESSION_SCROLL_PAGE uses the preview pane height instead of one line. */
SESSION_SCROLL_PAGE :: u64(1 << 21)

/* COMMAND_REQUEST_SCHEMA_VERSION identifies copied host command requests. */
COMMAND_REQUEST_SCHEMA_VERSION :: u32(1)

/* Command_Action identifies one neutral command-registry capability. */
Command_Action :: enum u32 {
	Invalid,
	Reload,
	Present_Navigation,
	Present_Workspace_Navigation,
	Present_Project_Navigation,
	Present_File_Management,
	Invoke,
}

/* Command_Request_Header prefixes one copied command capability request. */
Command_Request_Header :: struct #align(8) {
	schema_version: u32,
	action:         Command_Action,
	payload_length: u64,
}

/* INPUT_REQUEST_SCHEMA_VERSION identifies copied normalized input requests. */
INPUT_REQUEST_SCHEMA_VERSION :: u32(1)

/* Input_Kind distinguishes normalized key and committed-text input. */
Input_Kind :: enum u8 {
	Invalid,
	Key,
	Text_Commit,
}

/* Key_Kind mirrors the public frontend-independent logical key vocabulary. */
Key_Kind :: enum u8 {
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
}

/* Input_Request_Header prefixes one copied normalized input event. */
Input_Request_Header :: struct #align(8) {
	schema_version: u32,
	kind:           Input_Kind,
	key_kind:       Key_Kind,
	modifiers:      u8,
	_reserved:      u8,
	scalar:         i32,
	text_length:    u32,
}

/* Selection_Request selects one exact item from the latest module projection. */
Selection_Request :: struct #align(8) {
	schema_version: u32,
	_reserved:      u32,
	item_id:        u64,
}

/* UI_LIST_SCHEMA_VERSION identifies copied semantic list projections. */
UI_LIST_SCHEMA_VERSION :: u32(1)
/* UI_LIST_MAX_STYLE_SPANS matches the bounded public UI row vocabulary. */
UI_LIST_MAX_STYLE_SPANS :: 16

/* UI_List_Style_Span copies one semantic style range without private UI layouts. */
UI_List_Style_Span :: struct {
	start_byte: u32,
	end_byte:   u32,
	style_role: u8,
	_reserved:  [3]u8,
}

/* UI_List_Row copies one bounded semantic row and its source-owned action. */
UI_List_Row :: struct #align(8) {
	id:                u64,
	text_offset:       u64,
	text_length:       u32,
	emphasis_bytes:    u32,
	action_owner_id:   u64,
	action_id:         u64,
	action_generation: u64,
	icon_role:         u8,
	icon_style_role:   u8,
	mark:              u8,
	passive:           u8,
	emphasis_style:    u8,
	style_span_count:  u8,
	_reserved:         [2]u8,
	style_spans:       [UI_LIST_MAX_STYLE_SPANS]UI_List_Style_Span,
}

/* UI_List_Header prefixes one complete copied list projection. */
UI_List_Header :: struct #align(8) {
	schema_version:          u32,
	row_count:               u32,
	presentation_generation: u64,
	current_item:            i32,
	first_visible_item:      u32,
	viewport_items:          u32,
	selection_owner:         u8,
	mark_lane:               u8,
	_reserved:               [2]u8,
	text_bytes:              u64,
}

/* UI_TREE_PANEL_SCHEMA_VERSION identifies one copied persistent tree-panel projection. */
UI_TREE_PANEL_SCHEMA_VERSION :: u32(1)

/* UI_Tree_Panel_Row copies one visible preorder node without private UI layouts. */
UI_Tree_Panel_Row :: struct #align(8) {
	id:                u64,
	parent:            u64,
	text_offset:       u64,
	text_length:       u32,
	icon_offset:       u32,
	icon_length:       u16,
	depth:             u16,
	indent_depth:      u16,
	expandable:        u8,
	expanded:          u8,
	icon_role:         u8,
	icon_style_role:   u8,
	action_owner_id:   u64,
	action_id:         u64,
	action_generation: u64,
}

/* UI_Tree_Panel_Header prefixes one complete copied persistent panel generation. */
UI_Tree_Panel_Header :: struct #align(8) {
	schema_version:          u32,
	row_count:               u32,
	presentation_generation: u64,
	current_item:            i32,
	first_visible_item:      u32,
	viewport_items:          u32,
	panel_width:             u32,
	panel_edge:              u8,
	visible:                 u8,
	focused:                 u8,
	_reserved:               u8,
	text_bytes:              u64,
}

/* Status reports one pointer-free ABI outcome. */
Status :: enum u32 {
	Ok,
	Invalid_Argument,
	Incompatible_ABI,
	Denied,
	Stale,
	Limit,
	Failed,
	Unavailable,
}

/* Host_Call is the only callback surface exposed to one native module. */
Host_Call :: proc "c" (
	capability: u64,
	operation: Host_Operation,
	input: ^u8,
	input_length: u64,
	output: ^u8,
	output_capacity: u64,
	output_length: ^u64,
) -> Status

/* Open creates one inactive module instance bound to one scoped host capability. */
Open :: proc "c" (
	host_call: Host_Call,
	capability: u64,
	instance: ^u64,
) -> Status

/* Call performs one bounded lifecycle or product turn on an existing instance. */
Call :: proc "c" (
	instance: u64,
	operation: Operation,
	input: ^u8,
	input_length: u64,
	output: ^u8,
	output_capacity: u64,
	output_length: ^u64,
) -> Status

/* Close revokes one instance and releases all module-owned resources. */
Close :: proc "c" (instance: u64) -> Status

/* Entrypoint writes one complete immutable module descriptor. */
Entrypoint :: proc "c" (descriptor: ^Descriptor, descriptor_size: u64) -> Status

/* Descriptor is the fixed-width native module declaration returned at load time. */
Descriptor :: struct #align(8) {
	struct_size:    u64,
	abi_minimum:    u32,
	abi_maximum:    u32,
	role:           Role,
	_reserved:      u32,
	identity:       [MAX_IDENTITY_BYTES]u8,
	identity_length: u16,
	version:        [MAX_VERSION_BYTES]u8,
	version_length: u16,
	open:           Open,
	call:           Call,
	close:          Close,
}

/* Artifact is one integrity-bound native module declaration. */
Artifact :: struct {
	identity:          [MAX_IDENTITY_BYTES]u8,
	identity_length:   u16,
	version:           [MAX_VERSION_BYTES]u8,
	version_length:    u16,
	path:              [MAX_ARTIFACT_PATH_BYTES]u8,
	path_length:       u16,
	digest:            [32]u8,
	size:              u64,
	entrypoint:        [MAX_ENTRYPOINT_BYTES]u8,
	entrypoint_length: u16,
	abi_minimum:       u32,
	abi_maximum:       u32,
	role:              Role,
}

/* artifact_identity returns the expected semantic module identity. */
artifact_identity :: proc(artifact: ^Artifact) -> string {
	if artifact == nil || artifact.identity_length == 0 ||
	   int(artifact.identity_length) > len(artifact.identity) {
		return ""
	}
	return string(artifact.identity[:artifact.identity_length])
}

/* artifact_version returns the expected semantic module version. */
artifact_version :: proc(artifact: ^Artifact) -> string {
	if artifact == nil || artifact.version_length == 0 ||
	   int(artifact.version_length) > len(artifact.version) {
		return ""
	}
	return string(artifact.version[:artifact.version_length])
}

/* Failure_Code classifies one contained loader or lifecycle failure. */
Failure_Code :: enum u32 {
	None,
	Invalid_Artifact,
	Artifact_Missing,
	Artifact_Size,
	Artifact_Digest,
	Library_Load,
	Symbol_Missing,
	Descriptor,
	ABI,
	Role,
	Identity,
	Version,
	Open,
	Call,
	Close,
}

/* Failure reports one bounded native product-module failure. */
Failure :: struct {
	code:   Failure_Code,
	status: Status,
	limit:  u64,
	actual: u64,
}

/* Inspection copies module identity and lifecycle without foreign handles. */
Inspection :: struct {
	lifecycle: Lifecycle,
	role:      Role,
	identity:  [MAX_IDENTITY_BYTES]u8,
	identity_length: u16,
	version:   [MAX_VERSION_BYTES]u8,
	version_length: u16,
	abi_minimum: u32,
	abi_maximum: u32,
	latest_failure: Failure,
}

/* descriptor_is_valid rejects malformed or incompatible module declarations. */
descriptor_is_valid :: proc(descriptor: ^Descriptor, expected_role: Role) -> (bool, Failure) {
	if descriptor == nil || descriptor.struct_size != size_of(Descriptor) {
		return false, {code = .Descriptor}
	}
	if descriptor.abi_minimum == 0 || descriptor.abi_minimum > descriptor.abi_maximum ||
	   ABI_VERSION < descriptor.abi_minimum || ABI_VERSION > descriptor.abi_maximum {
		return false, {code = .ABI, limit = u64(descriptor.abi_maximum), actual = u64(ABI_VERSION)}
	}
	if descriptor.role == .Invalid || descriptor.role != expected_role {
		return false, {code = .Role, limit = u64(expected_role), actual = u64(descriptor.role)}
	}
	if descriptor.identity_length == 0 || int(descriptor.identity_length) > len(descriptor.identity) ||
	   !semantic_identity_is_valid(descriptor.identity[:descriptor.identity_length]) {
		return false, {code = .Identity}
	}
	if descriptor.version_length == 0 || int(descriptor.version_length) > len(descriptor.version) ||
	   !semantic_version_is_valid(descriptor.version[:descriptor.version_length]) {
		return false, {code = .Version}
	}
	if descriptor.open == nil || descriptor.call == nil || descriptor.close == nil {
		return false, {code = .Descriptor}
	}
	return true, {}
}

/* artifact_path returns the declared absolute module path. */
artifact_path :: proc(artifact: ^Artifact) -> string {
	if artifact == nil || artifact.path_length == 0 || int(artifact.path_length) > len(artifact.path) {
		return ""
	}
	return string(artifact.path[:artifact.path_length])
}

/* artifact_entrypoint returns the declared exported symbol. */
artifact_entrypoint :: proc(artifact: ^Artifact) -> string {
	if artifact == nil || artifact.entrypoint_length == 0 ||
	   int(artifact.entrypoint_length) > len(artifact.entrypoint) {
		return ""
	}
	return string(artifact.entrypoint[:artifact.entrypoint_length])
}

/* descriptor_identity returns copied module identity text. */
descriptor_identity :: proc(descriptor: ^Descriptor) -> string {
	if descriptor == nil || descriptor.identity_length == 0 ||
	   int(descriptor.identity_length) > len(descriptor.identity) {
		return ""
	}
	return string(descriptor.identity[:descriptor.identity_length])
}

/* descriptor_version returns copied module version text. */
descriptor_version :: proc(descriptor: ^Descriptor) -> string {
	if descriptor == nil || descriptor.version_length == 0 ||
	   int(descriptor.version_length) > len(descriptor.version) {
		return ""
	}
	return string(descriptor.version[:descriptor.version_length])
}

@(private)
semantic_identity_is_valid :: proc(value: []u8) -> bool {
	if len(value) == 0 do return false
	separator := false
	for byte in value {
		if byte >= 'a' && byte <= 'z' || byte >= '0' && byte <= '9' {
			separator = false
			continue
		}
		if (byte == '.' || byte == '-') && !separator {
			separator = true
			continue
		}
		return false
	}
	return !separator
}

@(private)
semantic_version_is_valid :: proc(value: []u8) -> bool {
	if len(value) == 0 do return false
	dots := 0
	component_bytes := 0
	for byte, index in value {
		if byte >= '0' && byte <= '9' {
			component_bytes += 1
			continue
		}
		if byte == '.' && dots < 2 && component_bytes > 0 {
			dots += 1
			component_bytes = 0
			continue
		}
		if byte == '-' && dots == 2 && component_bytes > 0 && index + 1 < len(value) {
			for suffix in value[index + 1:] {
				if !(suffix >= '0' && suffix <= '9' || suffix >= 'A' && suffix <= 'Z' ||
				     suffix >= 'a' && suffix <= 'z' || suffix == '.' || suffix == '-') {
					return false
				}
			}
			return true
		}
		return false
	}
	return dots == 2 && component_bytes > 0
}
