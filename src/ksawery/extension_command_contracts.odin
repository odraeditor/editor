// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

import "core:unicode/utf8"

/* DEFAULT_EXTENSION_COMMAND_ARGUMENTS is the initial family argument budget. */
DEFAULT_EXTENSION_COMMAND_ARGUMENTS :: u16(32)
/* MAX_EXTENSION_COMMAND_ARGUMENTS is the immutable family argument ceiling. */
MAX_EXTENSION_COMMAND_ARGUMENTS :: u16(256)
/* DEFAULT_EXTENSION_COMMAND_CHOICES is the initial per-argument choice budget. */
DEFAULT_EXTENSION_COMMAND_CHOICES :: u16(32)
/* MAX_EXTENSION_COMMAND_CHOICES is the immutable per-argument choice ceiling. */
MAX_EXTENSION_COMMAND_CHOICES :: u16(256)
/* DEFAULT_EXTENSION_COMMAND_ACTIONS is the initial family action budget. */
DEFAULT_EXTENSION_COMMAND_ACTIONS :: u16(32)
/* MAX_EXTENSION_COMMAND_ACTIONS is the immutable family action ceiling. */
MAX_EXTENSION_COMMAND_ACTIONS :: u16(256)
/* DEFAULT_EXTENSION_COMMAND_VALUE_BYTES is the initial copied argument-value budget. */
DEFAULT_EXTENSION_COMMAND_VALUE_BYTES :: u16(1 * KIBIBYTE)
/* MAX_EXTENSION_COMMAND_VALUE_BYTES is the immutable copied argument-value ceiling. */
MAX_EXTENSION_COMMAND_VALUE_BYTES :: u16(4 * KIBIBYTE)
/* DEFAULT_EXTENSION_COMMAND_RESULT_BYTES is the initial result text budget. */
DEFAULT_EXTENSION_COMMAND_RESULT_BYTES :: u16(2 * KIBIBYTE)
/* MAX_EXTENSION_COMMAND_RESULT_BYTES is the immutable result text ceiling. */
MAX_EXTENSION_COMMAND_RESULT_BYTES :: u16(4 * KIBIBYTE)
/* DEFAULT_EXTENSION_COMMAND_COPY_BYTES is the initial complete-generation budget. */
DEFAULT_EXTENSION_COMMAND_COPY_BYTES :: u64(512 * KIBIBYTE)
/* MAX_EXTENSION_COMMAND_COPY_BYTES is the immutable complete-generation ceiling. */
MAX_EXTENSION_COMMAND_COPY_BYTES :: u64(8 * MEBIBYTE)

/* Extension_Command_Family_ID identifies one contributor-owned command family. */
Extension_Command_Family_ID :: distinct u64
/* Extension_Command_Family_Generation_ID identifies one immutable family declaration. */
Extension_Command_Family_Generation_ID :: distinct u64
/* Extension_Command_Argument_ID identifies one stable family argument. */
Extension_Command_Argument_ID :: distinct u64
/* Extension_Command_Choice_ID identifies one stable closed choice. */
Extension_Command_Choice_ID :: distinct u64
/* Extension_Command_Action_ID identifies one stable family action. */
Extension_Command_Action_ID :: distinct u64
/* Extension_Command_Request_ID identifies one immutable command submission. */
Extension_Command_Request_ID :: distinct u64
/* Extension_Command_Confirmation_ID identifies one one-shot acknowledgement. */
Extension_Command_Confirmation_ID :: distinct u64

/* Extension_Command_Argument_Kind names the initial closed typed value vocabulary. */
Extension_Command_Argument_Kind :: enum u8 {
	Invalid,
	Boolean,
	Closed_Choice,
	Text,
	Selection,
	Ref,
	Revision,
	Revision_Range,
	Opaque,
}

/* Extension_Command_Operation_State reports only public operation availability. */
Extension_Command_Operation_State :: enum u8 {
	Invalid,
	Idle,
	Active,
	Sequence,
	Conflict,
}

/* Extension_Command_Operation_Requirement constrains one action to public operation state. */
Extension_Command_Operation_Requirement :: enum u8 {
	Invalid,
	Any,
	Idle,
	Active,
	Sequence,
	Conflict,
}

/* Extension_Command_Target_Families is one admitted exact target-family set. */
Extension_Command_Target_Families :: bit_set[Extension_Annotation_Target_Family; u16]

/* Extension_Command_Choice is one copied member of a closed argument vocabulary. */
Extension_Command_Choice :: struct {
	id:       Extension_Command_Choice_ID,
	identity: Extension_Identity,
	label:    Extension_Label,
}

/* Extension_Command_Argument_Definition declares one typed inert family input. */
Extension_Command_Argument_Definition :: struct {
	id:        Extension_Command_Argument_ID,
	identity:  Extension_Identity,
	label:     Extension_Label,
	kind:      Extension_Command_Argument_Kind,
	required:  bool,
	max_bytes: u16,
	choices:   []Extension_Command_Choice,
}

/* Extension_Command_Action_Definition declares one stable checked action identity. */
Extension_Command_Action_Definition :: struct {
	id:                    Extension_Command_Action_ID,
	identity:              Extension_Identity,
	label:                 Extension_Label,
	authority:             Extension_Authority,
	observations:          Extension_Observation_Families,
	target_families:       Extension_Command_Target_Families,
	operation_requirement: Extension_Command_Operation_Requirement,
	core_operation:        Repository_Operation_Kind,
	mutates_repository:    bool,
	confirmation_required: bool,
}

/* Extension_Command_Family_Generation is one complete immutable command surface. */
Extension_Command_Family_Generation :: struct {
	contributor:          Contributor_Handle,
	contributor_identity: Contributor_Identity,
	contribution:         Contribution_ID,
	family:               Extension_Command_Family_ID,
	identity:             Extension_Identity,
	label:                Extension_Label,
	generation:           Extension_Command_Family_Generation_ID,
	observations:         Extension_Observation_Families,
	arguments:            []Extension_Command_Argument_Definition,
	actions:              []Extension_Command_Action_Definition,
}

/* Extension_Command_Context copies the exact repository truth admitted to one command. */
Extension_Command_Context :: struct {
	contributor:           Contributor_Handle,
	repository:            Repository_Context,
	repository_generation: Repository_Generation,
	worktree_generation:   Worktree_Generation,
	observation:           Extension_Observation_Family,
	observation_generation: u64,
	surface:               Extension_Surface,
	surface_generation:    Extension_Surface_Generation,
	selection_generation:  u64,
	target_present:        bool,
	target:                Extension_Annotation_Target,
	operation_state:       Extension_Command_Operation_State,
	mutation_available:    bool,
	capability_generation: Extension_Capability_Generation,
	observation_truncated: bool,
	privacy_filtered:      bool,
}

/* Extension_Command_Value_Bytes owns bounded copied text or opaque provider data. */
Extension_Command_Value_Bytes :: struct {
	bytes:  [MAX_EXTENSION_COMMAND_VALUE_BYTES]u8,
	length: u16,
}

/* Extension_Command_Argument_Value owns one typed inert argument value. */
Extension_Command_Argument_Value :: struct {
	argument: Extension_Command_Argument_ID,
	kind:     Extension_Command_Argument_Kind,
	boolean:  bool,
	choice:   Extension_Command_Choice_ID,
	content:  Extension_Command_Value_Bytes,
	target:   Extension_Annotation_Target,
}

/* Extension_Command_Request binds typed arguments and one action to exact current truth. */
Extension_Command_Request :: struct {
	id:                 Extension_Command_Request_ID,
	family:             Extension_Command_Family_ID,
	family_generation:  Extension_Command_Family_Generation_ID,
	action:             Extension_Command_Action_ID,
	command_context:    Extension_Command_Context,
	arguments:          []Extension_Command_Argument_Value,
	confirmation:       Extension_Command_Confirmation_ID,
}

/* Extension_Command_Result_Status classifies one bounded command turn outcome. */
Extension_Command_Result_Status :: enum u8 {
	Invalid,
	Completed,
	Rejected,
	Cancelled,
	Failed,
}

/* Extension_Command_Result_Text owns one bounded public presentation or diagnostic. */
Extension_Command_Result_Text :: struct {
	bytes:  [MAX_EXTENSION_COMMAND_RESULT_BYTES]u8,
	length: u16,
}

/* Extension_Command_Result binds one bounded outcome to its exact request and action. */
Extension_Command_Result :: struct {
	request:             Extension_Command_Request_ID,
	family:              Extension_Command_Family_ID,
	family_generation:   Extension_Command_Family_Generation_ID,
	action:               Extension_Command_Action_ID,
	status:               Extension_Command_Result_Status,
	presentation:         Extension_Command_Result_Text,
	diagnostic:           Extension_Command_Result_Text,
	core_action_requested: bool,
	external_operation_requested: bool,
}

/* Extension_Command_Limits bounds one complete family, request, and result. */
Extension_Command_Limits :: struct {
	arguments:    u16,
	choices:      u16,
	actions:      u16,
	value_bytes:  u16,
	result_bytes: u16,
	copy_bytes:   u64,
}

/* DEFAULT_EXTENSION_COMMAND_LIMITS selects the initial bounded command envelope. */
DEFAULT_EXTENSION_COMMAND_LIMITS :: Extension_Command_Limits {
	arguments = DEFAULT_EXTENSION_COMMAND_ARGUMENTS,
	choices = DEFAULT_EXTENSION_COMMAND_CHOICES,
	actions = DEFAULT_EXTENSION_COMMAND_ACTIONS,
	value_bytes = DEFAULT_EXTENSION_COMMAND_VALUE_BYTES,
	result_bytes = DEFAULT_EXTENSION_COMMAND_RESULT_BYTES,
	copy_bytes = DEFAULT_EXTENSION_COMMAND_COPY_BYTES,
}

/* MAX_EXTENSION_COMMAND_LIMITS records every immutable command ceiling. */
MAX_EXTENSION_COMMAND_LIMITS :: Extension_Command_Limits {
	arguments = MAX_EXTENSION_COMMAND_ARGUMENTS,
	choices = MAX_EXTENSION_COMMAND_CHOICES,
	actions = MAX_EXTENSION_COMMAND_ACTIONS,
	value_bytes = MAX_EXTENSION_COMMAND_VALUE_BYTES,
	result_bytes = MAX_EXTENSION_COMMAND_RESULT_BYTES,
	copy_bytes = MAX_EXTENSION_COMMAND_COPY_BYTES,
}

/* Extension_Command_Usage reports exact retained declaration or request content. */
Extension_Command_Usage :: struct {
	arguments:   u32,
	choices:     u32,
	actions:     u32,
	value_bytes: u64,
	copy_bytes:  u64,
}

/* Extension_Repository_Command_Failure_Code classifies expected command-contract rejection. */
Extension_Repository_Command_Failure_Code :: enum u16 {
	None,
	Invalid_Family,
	Invalid_Context,
	Invalid_Argument,
	Invalid_Choice,
	Invalid_Action,
	Invalid_Result,
	Duplicate_Identity,
	Missing_Argument,
	Unknown_Argument,
	Stale_Contributor,
	Stale_Family,
	Stale_Observation,
	Stale_Target,
	Operation_Unavailable,
	Mutation_Unavailable,
	Confirmation_Required,
	Argument_Limit,
	Choice_Limit,
	Action_Limit,
	Value_Limit,
	Result_Limit,
	Copy_Limit,
}

/* Extension_Repository_Command_Failure identifies one attributable bounded rejection. */
Extension_Repository_Command_Failure :: struct {
	code:     Extension_Repository_Command_Failure_Code,
	argument: Extension_Command_Argument_ID,
	action:   Extension_Command_Action_ID,
	index:    u32,
	limit:    u64,
	actual:   u64,
}

/* extension_command_limits_are_valid checks one policy against immutable ceilings. */
extension_command_limits_are_valid :: proc(limits: Extension_Command_Limits) -> bool {
	return limits.arguments > 0 && limits.arguments <= MAX_EXTENSION_COMMAND_ARGUMENTS &&
		limits.choices > 0 && limits.choices <= MAX_EXTENSION_COMMAND_CHOICES &&
		limits.actions > 0 && limits.actions <= MAX_EXTENSION_COMMAND_ACTIONS &&
		limits.value_bytes > 0 && limits.value_bytes <= MAX_EXTENSION_COMMAND_VALUE_BYTES &&
		limits.result_bytes > 0 && limits.result_bytes <= MAX_EXTENSION_COMMAND_RESULT_BYTES &&
		limits.copy_bytes > 0 && limits.copy_bytes <= MAX_EXTENSION_COMMAND_COPY_BYTES
}

/* extension_command_value_assign_text copies one bounded UTF-8 argument. */
extension_command_value_assign_text :: proc(
	value: ^Extension_Command_Value_Bytes,
	text: string,
) -> bool {
	if value == nil do return false
	value^ = {}
	if len(text) > len(value.bytes) || !utf8.valid_string(text) do return false
	copy(value.bytes[:len(text)], transmute([]u8)text)
	value.length = u16(len(text))
	return true
}

/* extension_command_value_assign_opaque copies one bounded authority-free provider value. */
extension_command_value_assign_opaque :: proc(
	value: ^Extension_Command_Value_Bytes,
	content: []u8,
) -> bool {
	if value == nil do return false
	value^ = {}
	if len(content) > len(value.bytes) do return false
	copy(value.bytes[:len(content)], content)
	value.length = u16(len(content))
	return true
}

/* extension_command_result_text_assign copies one bounded public UTF-8 result. */
extension_command_result_text_assign :: proc(
	value: ^Extension_Command_Result_Text,
	text: string,
) -> bool {
	if value == nil do return false
	value^ = {}
	if len(text) > len(value.bytes) || !utf8.valid_string(text) do return false
	copy(value.bytes[:len(text)], transmute([]u8)text)
	value.length = u16(len(text))
	return true
}

/* extension_command_family_validate checks one complete immutable declaration. */
extension_command_family_validate :: proc(
	family: Extension_Command_Family_Generation,
	limits := DEFAULT_EXTENSION_COMMAND_LIMITS,
) -> (usage: Extension_Command_Usage, failure: Extension_Repository_Command_Failure) {
	if !extension_command_limits_are_valid(limits) ||
	   !contributor_handle_is_valid(family.contributor) ||
	   !contributor_identity_is_valid(family.contributor_identity) ||
	   family.contribution == Contribution_ID(0) ||
	   family.family == Extension_Command_Family_ID(0) ||
	   !extension_identity_is_valid(family.identity) || !extension_label_is_valid(family.label) ||
	   family.generation == Extension_Command_Family_Generation_ID(0) || family.observations == {} {
		return {}, {code = .Invalid_Family}
	}
	if len(family.arguments) > int(limits.arguments) {
		return {}, {code = .Argument_Limit, limit = u64(limits.arguments), actual = u64(len(family.arguments))}
	}
	if len(family.actions) == 0 || len(family.actions) > int(limits.actions) {
		return {}, {code = .Action_Limit, limit = u64(limits.actions), actual = u64(len(family.actions))}
	}
	usage.arguments = u32(len(family.arguments))
	usage.actions = u32(len(family.actions))
	usage.copy_bytes = u64(size_of(Extension_Command_Family_Generation)) +
		u64(len(family.arguments) * size_of(Extension_Command_Argument_Definition)) +
		u64(len(family.actions) * size_of(Extension_Command_Action_Definition))
	for argument, index in family.arguments {
		if !extension_command_argument_definition_is_valid(argument, limits) {
			return {}, {code = .Invalid_Argument, argument = argument.id, index = u32(index)}
		}
		if len(argument.choices) > int(limits.choices) {
			return {}, {code = .Choice_Limit, argument = argument.id, index = u32(index),
				limit = u64(limits.choices), actual = u64(len(argument.choices))}
		}
		usage.choices += u32(len(argument.choices))
		usage.copy_bytes += u64(len(argument.choices) * size_of(Extension_Command_Choice))
		for choice, choice_index in argument.choices {
			if !extension_command_choice_is_valid(choice) {
				return {}, {code = .Invalid_Choice, argument = argument.id, index = u32(choice_index)}
			}
			for prior in 0 ..< choice_index {
				if argument.choices[prior].id == choice.id || argument.choices[prior].identity == choice.identity {
					return {}, {code = .Duplicate_Identity, argument = argument.id, index = u32(choice_index)}
				}
			}
		}
		for prior in 0 ..< index {
			if family.arguments[prior].id == argument.id || family.arguments[prior].identity == argument.identity {
				return {}, {code = .Duplicate_Identity, argument = argument.id, index = u32(index)}
			}
		}
	}
	for action, index in family.actions {
		if !extension_command_action_definition_is_valid(action) {
			return {}, {code = .Invalid_Action, action = action.id, index = u32(index)}
		}
		if action.observations & family.observations != action.observations {
			return {}, {code = .Invalid_Action, action = action.id, index = u32(index)}
		}
		for prior in 0 ..< index {
			if family.actions[prior].id == action.id || family.actions[prior].identity == action.identity {
				return {}, {code = .Duplicate_Identity, action = action.id, index = u32(index)}
			}
		}
	}
	if usage.copy_bytes > limits.copy_bytes {
		return {}, {code = .Copy_Limit, limit = limits.copy_bytes, actual = usage.copy_bytes}
	}
	return usage, {}
}

/* extension_command_context_validate checks copied repository and selection generations. */
extension_command_context_validate :: proc(
	command_context: Extension_Command_Context,
) -> Extension_Repository_Command_Failure {
	if !contributor_handle_is_valid(command_context.contributor) ||
	   !repository_context_is_valid(command_context.repository) ||
	   command_context.repository_generation == Repository_Generation(0) ||
	   command_context.worktree_generation == Worktree_Generation(0) ||
	   command_context.observation > .Process || command_context.observation_generation == 0 ||
	   command_context.surface == .Invalid ||
	   command_context.surface_generation == Extension_Surface_Generation(0) ||
	   command_context.selection_generation == 0 ||
	   command_context.operation_state == .Invalid ||
	   command_context.capability_generation == Extension_Capability_Generation(0) {
		return {code = .Invalid_Context}
	}
	if command_context.target_present {
		if !extension_annotation_target_is_valid(command_context.target) ||
		   command_context.target.generation != command_context.observation_generation ||
		   !extension_command_target_supports_observation(
			command_context.target.family, command_context.observation,
		   ) {
			return {code = .Stale_Target}
		}
	} else if command_context.target != (Extension_Annotation_Target{}) {
		return {code = .Invalid_Context}
	}
	return {}
}

/* extension_command_action_available checks target, observation, operation, and mutation state. */
extension_command_action_available :: proc(
	action: Extension_Command_Action_Definition,
	command_context: Extension_Command_Context,
) -> (bool, Extension_Repository_Command_Failure) {
	if !extension_command_action_definition_is_valid(action) {
		return false, {code = .Invalid_Action, action = action.id}
	}
	if failure := extension_command_context_validate(command_context); failure.code != .None {
		return false, failure
	}
	if command_context.observation not_in action.observations {
		return false, {code = .Stale_Observation, action = action.id}
	}
	if action.target_families != {} {
		if !command_context.target_present || command_context.target.family not_in action.target_families {
			return false, {code = .Stale_Target, action = action.id}
		}
	}
	if !extension_command_operation_requirement_is_satisfied(
		action.operation_requirement, command_context.operation_state,
	) {
		return false, {code = .Operation_Unavailable, action = action.id}
	}
	if action.mutates_repository && !command_context.mutation_available {
		return false, {code = .Mutation_Unavailable, action = action.id}
	}
	return true, {}
}

/* extension_command_request_validate checks one typed inert submission against its family. */
extension_command_request_validate :: proc(
	request: Extension_Command_Request,
	family: Extension_Command_Family_Generation,
	limits := DEFAULT_EXTENSION_COMMAND_LIMITS,
) -> (usage: Extension_Command_Usage, failure: Extension_Repository_Command_Failure) {
	_, family_failure := extension_command_family_validate(family, limits)
	if family_failure.code != .None do return {}, family_failure
	if request.id == Extension_Command_Request_ID(0) || request.family != family.family ||
	   request.family_generation != family.generation {
		return {}, {code = .Stale_Family}
	}
	if request.command_context.contributor != family.contributor {
		return {}, {code = .Stale_Contributor}
	}
	if request.command_context.observation not_in family.observations {
		return {}, {code = .Stale_Observation}
	}
	context_failure := extension_command_context_validate(request.command_context)
	if context_failure.code != .None do return {}, context_failure
	action, action_found := extension_command_family_action(family, request.action)
	if !action_found do return {}, {code = .Invalid_Action, action = request.action}
	available, available_failure := extension_command_action_available(action, request.command_context)
	if !available do return {}, available_failure
	if action.confirmation_required && request.confirmation == Extension_Command_Confirmation_ID(0) {
		return {}, {code = .Confirmation_Required, action = request.action}
	}
	if !action.confirmation_required && request.confirmation != Extension_Command_Confirmation_ID(0) {
		return {}, {code = .Invalid_Action, action = request.action}
	}
	if len(request.arguments) > int(limits.arguments) {
		return {}, {code = .Argument_Limit, limit = u64(limits.arguments), actual = u64(len(request.arguments))}
	}
	usage.arguments = u32(len(request.arguments))
	usage.copy_bytes = u64(size_of(Extension_Command_Request)) +
		u64(len(request.arguments) * size_of(Extension_Command_Argument_Value))
	for value, index in request.arguments {
		definition, found := extension_command_family_argument(family, value.argument)
		if !found do return {}, {code = .Unknown_Argument, argument = value.argument, index = u32(index)}
		for prior in 0 ..< index {
			if request.arguments[prior].argument == value.argument {
				return {}, {code = .Duplicate_Identity, argument = value.argument, index = u32(index)}
			}
		}
		value_failure := extension_command_argument_value_validate(value, definition, request.command_context, limits)
		if value_failure.code != .None {
			value_failure.index = u32(index)
			return {}, value_failure
		}
		usage.value_bytes += u64(value.content.length)
	}
	for definition in family.arguments {
		if !definition.required do continue
		found := false
		for value in request.arguments {
			if value.argument == definition.id {
				found = true
				break
			}
		}
		if !found do return {}, {code = .Missing_Argument, argument = definition.id}
	}
	if usage.copy_bytes > limits.copy_bytes {
		return {}, {code = .Copy_Limit, limit = limits.copy_bytes, actual = usage.copy_bytes}
	}
	return usage, {}
}

/* extension_command_result_validate checks one bounded outcome against its request. */
extension_command_result_validate :: proc(
	result: Extension_Command_Result,
	request: Extension_Command_Request,
	limits := DEFAULT_EXTENSION_COMMAND_LIMITS,
) -> Extension_Repository_Command_Failure {
	if !extension_command_limits_are_valid(limits) || result.request != request.id ||
	   result.family != request.family || result.family_generation != request.family_generation ||
	   result.action != request.action || result.status == .Invalid {
		return {code = .Invalid_Result, action = result.action}
	}
	if int(result.presentation.length) > len(result.presentation.bytes) ||
	   int(result.diagnostic.length) > len(result.diagnostic.bytes) ||
	   u64(result.presentation.length) + u64(result.diagnostic.length) > u64(limits.result_bytes) {
		return {code = .Result_Limit, action = result.action, limit = u64(limits.result_bytes),
			actual = u64(result.presentation.length) + u64(result.diagnostic.length)}
	}
	presentation := result.presentation
	diagnostic := result.diagnostic
	if !utf8.valid_string(string(presentation.bytes[:presentation.length])) ||
	   !utf8.valid_string(string(diagnostic.bytes[:diagnostic.length])) {
		return {code = .Invalid_Result, action = result.action}
	}
	if result.core_action_requested && result.external_operation_requested {
		return {code = .Invalid_Result, action = result.action}
	}
	if (result.status == .Rejected || result.status == .Cancelled) &&
	   (result.core_action_requested || result.external_operation_requested) {
		return {code = .Invalid_Result, action = result.action}
	}
	return {}
}

@(private)
extension_command_choice_is_valid :: proc(choice: Extension_Command_Choice) -> bool {
	return choice.id != Extension_Command_Choice_ID(0) &&
		extension_identity_is_valid(choice.identity) && extension_label_is_valid(choice.label)
}

@(private)
extension_command_argument_definition_is_valid :: proc(
	argument: Extension_Command_Argument_Definition,
	limits: Extension_Command_Limits,
) -> bool {
	if argument.id == Extension_Command_Argument_ID(0) ||
	   !extension_identity_is_valid(argument.identity) || !extension_label_is_valid(argument.label) ||
	   argument.kind == .Invalid {
		return false
	}
	if argument.kind == .Closed_Choice {
		return len(argument.choices) > 0 && argument.max_bytes == 0
	}
	if len(argument.choices) != 0 do return false
	if argument.kind == .Text || argument.kind == .Opaque {
		return argument.max_bytes > 0 && argument.max_bytes <= limits.value_bytes
	}
	return argument.max_bytes == 0
}

@(private)
extension_command_action_definition_is_valid :: proc(action: Extension_Command_Action_Definition) -> bool {
	if action.id == Extension_Command_Action_ID(0) || !extension_identity_is_valid(action.identity) ||
	   !extension_label_is_valid(action.label) || action.observations == {} ||
	   action.operation_requirement == .Invalid {
		return false
	}
	if .Invalid in action.target_families do return false
	if action.authority == .Submit_External_Operation {
		return action.confirmation_required && action.core_operation == .Invalid
	}
	if action.mutates_repository {
		return action.authority == .Request_Core_Action && action.confirmation_required &&
			extension_command_core_operation_is_admitted(action)
	}
	return action.authority <= .Assist_Conflict && action.core_operation == .Invalid
}

@(private)
extension_command_core_operation_is_admitted :: proc(
	action: Extension_Command_Action_Definition,
) -> bool {
	switch action.core_operation {
	case .Stage, .Unstage, .Discard, .Commit:
		return .Status in action.observations
	case .Amend, .Fixup, .Cherry_Pick, .Revert,
	     .Bisect, .Bisect_Good, .Bisect_Bad, .Bisect_Skip, .Bisect_Reset:
		return .History in action.observations
	case .Fetch, .Push, .Create_Branch, .Switch_Branch, .Rename_Branch,
	     .Delete_Branch, .Create_Tag, .Delete_Tag, .Merge, .Rebase:
		return .Refs in action.observations
	case .Continue_Merge, .Abort_Merge, .Continue_Rebase, .Skip_Rebase, .Abort_Rebase,
	     .Continue_Cherry_Pick, .Skip_Cherry_Pick, .Abort_Cherry_Pick,
	     .Continue_Revert, .Skip_Revert, .Abort_Revert:
		return .Sequence in action.observations || .Conflict in action.observations
	case .Resolve_Conflict:
		return .Conflict in action.observations
	case .Invalid, .Status, .Sequence, .History, .Refs, .Revision_Detail,
	     .Revision_Range, .Path_Detail, .Stash, .Worktree, .Blame, .Reflog,
	     .External_Operation, .Raw_Command:
		return false
	}
	return false
}

@(private)
extension_command_operation_requirement_is_satisfied :: proc(
	requirement: Extension_Command_Operation_Requirement,
	state: Extension_Command_Operation_State,
) -> bool {
	switch requirement {
	case .Any:      return state != .Invalid
	case .Idle:     return state == .Idle
	case .Active:   return state == .Active || state == .Sequence || state == .Conflict
	case .Sequence: return state == .Sequence || state == .Conflict
	case .Conflict: return state == .Conflict
	case .Invalid:  return false
	}
	return false
}

@(private)
extension_command_family_action :: proc(
	family: Extension_Command_Family_Generation,
	id: Extension_Command_Action_ID,
) -> (Extension_Command_Action_Definition, bool) {
	for action in family.actions {
		if action.id == id do return action, true
	}
	return {}, false
}

@(private)
extension_command_family_argument :: proc(
	family: Extension_Command_Family_Generation,
	id: Extension_Command_Argument_ID,
) -> (Extension_Command_Argument_Definition, bool) {
	for argument in family.arguments {
		if argument.id == id do return argument, true
	}
	return {}, false
}

/* extension_command_argument_value_validate checks one typed value against exact copied context. */
extension_command_argument_value_validate :: proc(
	value: Extension_Command_Argument_Value,
	definition: Extension_Command_Argument_Definition,
	command_context: Extension_Command_Context,
	limits: Extension_Command_Limits,
) -> Extension_Repository_Command_Failure {
	failure := Extension_Repository_Command_Failure{argument = value.argument}
	if value.argument != definition.id || value.kind != definition.kind ||
	   int(value.content.length) > len(value.content.bytes) || value.content.length > limits.value_bytes {
		failure.code = .Invalid_Argument
		return failure
	}
	switch value.kind {
	case .Boolean:
		if value.choice != Extension_Command_Choice_ID(0) || value.content.length != 0 ||
		   value.target != (Extension_Annotation_Target{}) {
			failure.code = .Invalid_Argument
		}
	case .Closed_Choice:
		if value.choice == Extension_Command_Choice_ID(0) || value.boolean || value.content.length != 0 ||
		   value.target != (Extension_Annotation_Target{}) {
			failure.code = .Invalid_Choice
			break
		}
		found := false
		for choice in definition.choices {
			if choice.id == value.choice {
				found = true
				break
			}
		}
		if !found do failure.code = .Invalid_Choice
	case .Text:
		content := value.content
		if value.boolean || value.choice != Extension_Command_Choice_ID(0) ||
		   value.target != (Extension_Annotation_Target{}) || value.content.length > definition.max_bytes ||
		   !utf8.valid_string(string(content.bytes[:content.length])) {
			failure.code = .Invalid_Argument
		}
	case .Opaque:
		if value.boolean || value.choice != Extension_Command_Choice_ID(0) ||
		   value.target != (Extension_Annotation_Target{}) || value.content.length > definition.max_bytes {
			failure.code = .Invalid_Argument
		}
	case .Selection, .Ref, .Revision, .Revision_Range:
		if value.boolean || value.choice != Extension_Command_Choice_ID(0) || value.content.length != 0 ||
		   !extension_annotation_target_is_valid(value.target) ||
		   value.target.generation != command_context.observation_generation {
			failure.code = .Stale_Target
			break
		}
		expected := Extension_Annotation_Target_Family.Invalid
		if value.kind == .Ref do expected = .Ref
		if value.kind == .Revision do expected = .Revision
		if value.kind == .Revision_Range do expected = .Revision_Range
		if expected != .Invalid && value.target.family != expected {
			failure.code = .Invalid_Argument
		} else if !extension_command_target_supports_observation(
			value.target.family, command_context.observation,
		) {
			failure.code = .Stale_Target
		}
	case .Invalid:
		failure.code = .Invalid_Argument
	}
	return failure
}

@(private)
extension_command_target_supports_observation :: proc(
	target: Extension_Annotation_Target_Family,
	observation: Extension_Observation_Family,
) -> bool {
	switch target {
	case .Path, .Diff_Unit:          return observation == .Status
	case .Revision, .Revision_Range: return observation == .History
	case .Ref, .Remote:              return observation == .Refs
	case .Conflict:                  return observation == .Conflict || observation == .Sequence
	case .Sequence:                  return observation == .Sequence
	case .Process:                   return observation == .Process
	case .Invalid:                   return false
	}
	return false
}
