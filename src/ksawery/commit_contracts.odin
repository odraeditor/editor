// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package ksawery

import "base:runtime"
import "core:unicode/utf8"

/* MAX_COMMIT_MESSAGE_BYTES bounds one owned normalized commit message. */
MAX_COMMIT_MESSAGE_BYTES :: 64 * KIBIBYTE
/* MAX_COMMIT_TARGET_SUBJECT_BYTES bounds one copied History subject used to identify a commit target. */
MAX_COMMIT_TARGET_SUBJECT_BYTES :: 16 * KIBIBYTE
/* FIXUP_SUBJECT_PREFIX is Git's standard non-rewriting fixup subject prefix. */
FIXUP_SUBJECT_PREFIX :: "fixup! "

/* Commit_Generation identifies one exact checked repository commit precondition. */
Commit_Generation :: distinct u64
/* Commit_Operation_ID identifies one admitted repository-commit attempt. */
Commit_Operation_ID :: distinct u64
/* Commit_Confirmation_ID identifies one explicit amend confirmation. */
Commit_Confirmation_ID :: distinct u64

/* Commit_Head_Kind distinguishes an unborn repository from one exact observed HEAD. */
Commit_Head_Kind :: enum u8 {
	Invalid,
	Unborn,
	Revision,
}

/* Commit_Head binds a checked normal commit to an unborn state or one exact HEAD revision. */
Commit_Head :: struct {
	kind:     Commit_Head_Kind,
	revision: Revision_Identity,
}

/* Index_Tree_Identity gives the index tree its own semantic identity class. */
Index_Tree_Identity :: struct {
	object: Revision_Identity,
}

/* Commit_Precondition is one checked repository, HEAD, index tree, and operation state. */
Commit_Precondition :: struct {
	repository:   Repository_Context,
	generation:   Commit_Generation,
	head:         Commit_Head,
	index_tree:   Index_Tree_Identity,
	operation:    Operation_State,
	staged_paths: u32,
	unmerged_paths: u32,
}

/* Commit_Message owns normalized bounded message bytes and the subject boundary. */
Commit_Message :: struct {
	bytes:          [MAX_COMMIT_MESSAGE_BYTES]u8,
	length:         u32,
	subject_length: u32,
}

/* Commit_Target_Subject owns one bounded single-line History subject. */
Commit_Target_Subject :: struct {
	bytes:  [MAX_COMMIT_TARGET_SUBJECT_BYTES]u8,
	length: u32,
}

/* Commit_Revision_Target binds a History generation, full identity, and copied subject. */
Commit_Revision_Target :: struct {
	observation: History_Target,
	subject:     Commit_Target_Subject,
}

/* Commit_Mode selects one admitted checked commit family. */
Commit_Mode :: enum u8 {
	Invalid,
	Normal,
	Amend,
	Fixup,
}

/* Amend_Confirmation binds explicit confirmation to one exact amend input. */
Amend_Confirmation :: struct {
	id:           Commit_Confirmation_ID,
	precondition: Commit_Precondition,
	target:       Commit_Revision_Target,
	message:      Commit_Message,
	confirmed:    bool,
	consumed:     bool,
}

/* Commit_Arguments declares the closed mode-specific mutation argument surface. */
Commit_Arguments :: struct {
	amend_confirmation: Commit_Confirmation_ID,
	target:             Commit_Revision_Target,
}

/* Commit_Lineage identifies the prior, resulting, replaced, or fixup-target revision without rendered text. */
Commit_Lineage :: struct {
	prior_head:   Commit_Head,
	resulting:    Revision_Identity,
	replaced:     Revision_Identity,
	fixup_target: Revision_Identity,
}

/* Commit_Request binds one owned message to an exact checked normal-commit precondition. */
Commit_Request :: struct {
	operation:    Commit_Operation_ID,
	mode:         Commit_Mode,
	precondition: Commit_Precondition,
	message:      Commit_Message,
	arguments:    Commit_Arguments,
	limits:       Process_Limits,
}

/* Commit_Result_Descriptor reports one bounded noninteractive checked-commit outcome. */
Commit_Result_Descriptor :: struct {
	request:          Commit_Request,
	lineage:          Commit_Lineage,
	exit_status:      i32,
	output_bytes:     u64,
	diagnostic_bytes: u64,
	failure:          Failure_Code,
	succeeded:        bool,
}

/* Commit_Usage reports exact fixed request and retained outcome payload sizes. */
Commit_Usage :: struct {
	message_bytes:        u64,
	target_subject_bytes: u64,
	output_bytes:         u64,
	diagnostic_bytes:     u64,
}

/* Commit_Result owns copied bounded process output for one normal-commit attempt. */
Commit_Result :: struct {
	state: rawptr,
}

@(private)
Commit_Result_Data :: struct {
	descriptor: Commit_Result_Descriptor,
	output:     [dynamic]u8,
	diagnostic: [dynamic]u8,
	allocator:  runtime.Allocator,
}

/* Commit_Feedback classifies stable normal-commit admission and process outcomes. */
Commit_Feedback :: enum u8 {
	Invalid,
	Completed,
	Stale,
	Unavailable,
	Rejected,
	Failed,
	Limited,
	Timed_Out,
	Cancelled,
}

/* commit_message_assign copies LF-normalized message content with a nonempty subject. */
commit_message_assign :: proc(message: ^Commit_Message, text: string) -> bool {
	if message == nil do return false
	message^ = {}
	if len(text) == 0 || u64(len(text)) > MAX_COMMIT_MESSAGE_BYTES || !utf8.valid_string(text) do return false
	write := 0
	for index := 0; index < len(text); index += 1 {
		byte := text[index]
		if byte == 0 do return false
		if byte == '\r' {
			if index + 1 < len(text) && text[index + 1] == '\n' do index += 1
			byte = '\n'
		}
		if write >= len(message.bytes) do return false
		message.bytes[write] = byte
		write += 1
	}
	for write > 0 && message.bytes[write - 1] == '\n' {
		write -= 1
		message.bytes[write] = 0
	}
	if write == 0 do return false
	subject_length := write
	for index in 0 ..< write {
		if message.bytes[index] == '\n' {
			subject_length = index
			break
		}
	}
	if !commit_message_subject_is_nonempty(message.bytes, subject_length) do return false
	message.length = u32(write)
	message.subject_length = u32(subject_length)
	return true
}

/* commit_message_is_valid checks one normalized owned message without borrowing caller storage. */
commit_message_is_valid :: proc(message: Commit_Message) -> bool {
	if message.length == 0 || int(message.length) > len(message.bytes) ||
	   message.subject_length == 0 || message.subject_length > message.length {
		return false
	}
	if message.subject_length < message.length && message.bytes[message.subject_length] != '\n' do return false
	for index in 0 ..< int(message.length) {
		if message.bytes[index] == 0 || message.bytes[index] == '\r' do return false
	}
	for index in int(message.length) ..< len(message.bytes) {
		if message.bytes[index] != 0 do return false
	}
	return commit_message_bytes_are_valid_utf8(message.bytes, int(message.length)) &&
	       commit_message_subject_is_nonempty(message.bytes, int(message.subject_length))
}

/* commit_message_text returns borrowed normalized message bytes. */
commit_message_text :: proc(message: ^Commit_Message) -> ([]u8, bool) {
	if message == nil || !commit_message_is_valid(message^) do return nil, false
	return message.bytes[:message.length], true
}

/* commit_target_subject_assign copies one bounded single-line History subject. */
commit_target_subject_assign :: proc(subject: ^Commit_Target_Subject, text: []u8) -> bool {
	if subject == nil do return false
	subject^ = {}
	if len(text) > len(subject.bytes) || !utf8.valid_string(string(text)) do return false
	for byte in text {
		if byte == 0 || byte == '\r' || byte == '\n' do return false
	}
	if len(text) > 0 do copy(subject.bytes[:len(text)], text)
	subject.length = u32(len(text))
	return true
}

/* commit_target_subject_is_valid checks one owned single-line History subject. */
commit_target_subject_is_valid :: proc(subject: Commit_Target_Subject) -> bool {
	if int(subject.length) > len(subject.bytes) do return false
	for index in 0 ..< int(subject.length) {
		byte := subject.bytes[index]
		if byte == 0 || byte == '\r' || byte == '\n' do return false
	}
	for index in int(subject.length) ..< len(subject.bytes) {
		if subject.bytes[index] != 0 do return false
	}
	local := subject
	return utf8.valid_string(string(local.bytes[:local.length]))
}

/* commit_target_subject_text returns borrowed copied History subject bytes. */
commit_target_subject_text :: proc(subject: ^Commit_Target_Subject) -> ([]u8, bool) {
	if subject == nil || !commit_target_subject_is_valid(subject^) do return nil, false
	return subject.bytes[:subject.length], true
}

/* commit_revision_target_is_valid checks one exact History identity and copied subject. */
commit_revision_target_is_valid :: proc(target: Commit_Revision_Target) -> bool {
	return history_target_is_valid(target.observation) && commit_target_subject_is_valid(target.subject)
}

/* commit_head_is_valid checks the complete mutually exclusive HEAD representation. */
commit_head_is_valid :: proc(head: Commit_Head) -> bool {
	switch head.kind {
	case .Unborn: return head.revision == {}
	case .Revision: return revision_identity_is_valid(head.revision)
	case .Invalid: return false
	}
	return false
}

/* index_tree_identity_is_valid checks one exact Git tree object identity. */
index_tree_identity_is_valid :: proc(identity: Index_Tree_Identity) -> bool {
	return revision_identity_is_valid(identity.object)
}

/* commit_precondition_is_valid checks one exact checked repository state. */
commit_precondition_is_valid :: proc(precondition: Commit_Precondition) -> bool {
	return repository_context_is_valid(precondition.repository) &&
	       precondition.generation != Commit_Generation(0) &&
	       commit_head_is_valid(precondition.head) &&
	       index_tree_identity_is_valid(precondition.index_tree) &&
	       precondition.operation != .Unknown &&
	       precondition.staged_paths <= MAX_STATUS_PATHS &&
	       precondition.unmerged_paths <= MAX_STATUS_PATHS
}

@(private)
commit_precondition_admits_normal :: proc(precondition: Commit_Precondition) -> bool {
	return precondition.operation == .Normal && precondition.staged_paths > 0 &&
	       precondition.unmerged_paths == 0
}

@(private)
commit_precondition_admits_amend :: proc(precondition: Commit_Precondition) -> bool {
	return precondition.operation == .Normal && precondition.head.kind == .Revision &&
	       precondition.unmerged_paths == 0
}

@(private)
amend_confirmation_input_is_valid :: proc(confirmation: Amend_Confirmation) -> bool {
	return confirmation.id != Commit_Confirmation_ID(0) &&
	       commit_precondition_is_valid(confirmation.precondition) &&
	       commit_precondition_admits_amend(confirmation.precondition) &&
	       commit_revision_target_is_valid(confirmation.target) &&
	       confirmation.target.observation.revision == confirmation.precondition.head.revision &&
	       commit_message_is_valid(confirmation.message)
}

@(private)
commit_history_target_resolve :: proc(
	history: ^History_Observation,
	precondition: Commit_Precondition,
	target: History_Target,
) -> (Commit_Revision_Target, bool) {
	if !history_target_is_valid(target) || precondition.head.kind != .Revision do return {}, false
	descriptor, described := history_observation_descriptor(history)
	if !described || descriptor.state != .Available || descriptor.repository != precondition.repository ||
	   descriptor.head != precondition.head.revision || target.generation != descriptor.generation {
		return {}, false
	}
	for ordinal in 0 ..< descriptor.revision_count {
		revision, found := history_observation_revision(history, ordinal)
		if !found || revision.identity != target.revision do continue
		text, copied := history_observation_text(history, revision.subject)
		subject: Commit_Target_Subject
		if !copied || !commit_target_subject_assign(&subject, text) do return {}, false
		return {observation = target, subject = subject}, true
	}
	return {}, false
}

/* amend_confirmation_prepare binds one explicit amend confirmation to exact checked input. */
amend_confirmation_prepare :: proc(
	precondition: Commit_Precondition,
	history: ^History_Observation,
	message: Commit_Message,
	id: Commit_Confirmation_ID,
) -> (Amend_Confirmation, bool, Failure_Code) {
	if id == Commit_Confirmation_ID(0) || !commit_precondition_is_valid(precondition) {
		return {}, false, .Invalid_Request
	}
	if !commit_message_is_valid(message) do return {}, false, .Commit_Message_Invalid
	if !commit_precondition_admits_amend(precondition) do return {}, false, .Commit_Unavailable
	descriptor, described := history_observation_descriptor(history)
	if !described do return {}, false, .Invalid_Request
	target, resolved := commit_history_target_resolve(
		history,
		precondition,
		{generation = descriptor.generation, revision = precondition.head.revision},
	)
	if !resolved do return {}, false, .Stale_Observation
	return {id = id, precondition = precondition, target = target, message = message}, true, .None
}

/* amend_confirmation_confirm accepts only the exact one-shot confirmation identity. */
amend_confirmation_confirm :: proc(
	confirmation: ^Amend_Confirmation,
	id: Commit_Confirmation_ID,
) -> (bool, Failure_Code) {
	if confirmation == nil || !amend_confirmation_input_is_valid(confirmation^) {
		return false, .Invalid_Request
	}
	if confirmation.id != id || confirmation.confirmed || confirmation.consumed do return false, .Confirmation_Mismatch
	confirmation.confirmed = true
	return true, .None
}

/* amend_request_prepare admits one confirmed replacement of the exact observed HEAD. */
amend_request_prepare :: proc(
	precondition: Commit_Precondition,
	message: Commit_Message,
	operation: Commit_Operation_ID,
	confirmation: ^Amend_Confirmation,
	limits := DEFAULT_PROCESS_LIMITS,
) -> (Commit_Request, bool, Failure_Code) {
	if operation == Commit_Operation_ID(0) || !process_limits_are_valid(limits) ||
	   !commit_precondition_is_valid(precondition) {
		return {}, false, .Invalid_Request
	}
	if !commit_message_is_valid(message) do return {}, false, .Commit_Message_Invalid
	if !commit_precondition_admits_amend(precondition) do return {}, false, .Commit_Unavailable
	if confirmation == nil || !confirmation.confirmed do return {}, false, .Confirmation_Required
	if confirmation.consumed || !amend_confirmation_input_is_valid(confirmation^) ||
	   confirmation.precondition != precondition || confirmation.message != message {
		return {}, false, .Confirmation_Mismatch
	}
	confirmation.consumed = true
	request := Commit_Request {
		operation = operation,
		mode = .Amend,
		precondition = precondition,
		message = message,
		arguments = {amend_confirmation = confirmation.id, target = confirmation.target},
		limits = limits,
	}
	return request, commit_request_is_valid(request), .None
}

/* fixup_request_prepare admits one staged Git fixup child tied to an exact observed History revision. */
fixup_request_prepare :: proc(
	precondition: Commit_Precondition,
	history: ^History_Observation,
	target: History_Target,
	operation: Commit_Operation_ID,
	limits := DEFAULT_PROCESS_LIMITS,
) -> (Commit_Request, bool, Failure_Code) {
	if operation == Commit_Operation_ID(0) || !process_limits_are_valid(limits) ||
	   !commit_precondition_is_valid(precondition) {
		return {}, false, .Invalid_Request
	}
	if !commit_precondition_admits_normal(precondition) do return {}, false, .Commit_Unavailable
	resolved_target, resolved := commit_history_target_resolve(history, precondition, target)
	if !resolved do return {}, false, .Stale_Observation
	message: Commit_Message
	if !commit_fixup_message_assign(&message, resolved_target) do return {}, false, .Commit_Message_Invalid
	request := Commit_Request {
		operation = operation,
		mode = .Fixup,
		precondition = precondition,
		message = message,
		arguments = {target = resolved_target},
		limits = limits,
	}
	return request, commit_request_is_valid(request), .None
}

/* commit_request_prepare admits one ordinary commit only from a checked normal operation with staged content. */
commit_request_prepare :: proc(
	precondition: Commit_Precondition,
	message: Commit_Message,
	operation: Commit_Operation_ID,
	limits := DEFAULT_PROCESS_LIMITS,
) -> (Commit_Request, bool, Failure_Code) {
	if operation == Commit_Operation_ID(0) || !process_limits_are_valid(limits) ||
	   !commit_precondition_is_valid(precondition) {
		return {}, false, .Invalid_Request
	}
	if !commit_message_is_valid(message) do return {}, false, .Commit_Message_Invalid
	if !commit_precondition_admits_normal(precondition) {
		return {}, false, .Commit_Unavailable
	}
	request := Commit_Request {
		operation = operation,
		mode = .Normal,
		precondition = precondition,
		message = message,
		limits = limits,
	}
	return request, commit_request_is_valid(request), .None
}

/* commit_request_is_valid checks one closed checked-commit request shape. */
commit_request_is_valid :: proc(request: Commit_Request) -> bool {
	if request.operation == Commit_Operation_ID(0) || !commit_precondition_is_valid(request.precondition) ||
	   !commit_message_is_valid(request.message) || !process_limits_are_valid(request.limits) {
		return false
	}
	switch request.mode {
	case .Normal:
		return commit_precondition_admits_normal(request.precondition) && request.arguments == {}
	case .Amend:
		return commit_precondition_admits_amend(request.precondition) &&
		       request.arguments.amend_confirmation != Commit_Confirmation_ID(0) &&
		       commit_revision_target_is_valid(request.arguments.target) &&
		       request.arguments.target.observation.revision == request.precondition.head.revision
	case .Fixup:
		return commit_precondition_admits_normal(request.precondition) &&
		       request.arguments.amend_confirmation == Commit_Confirmation_ID(0) &&
		       commit_revision_target_is_valid(request.arguments.target)
	case .Invalid:
		return false
	}
	return false
}

/* commit_request_revalidate proves the exact checked state remains current before process start. */
commit_request_revalidate :: proc(
	current: Commit_Precondition,
	request: Commit_Request,
) -> (bool, Failure_Code) {
	if !commit_request_is_valid(request) || !commit_precondition_is_valid(current) {
		return false, .Invalid_Request
	}
	if current.repository != request.precondition.repository || current.generation != request.precondition.generation ||
	   current.head != request.precondition.head || current.index_tree != request.precondition.index_tree {
		return false, .Stale_Observation
	}
	switch request.mode {
	case .Normal, .Fixup:
		if !commit_precondition_admits_normal(current) do return false, .Commit_Unavailable
	case .Amend:
		if !commit_precondition_admits_amend(current) do return false, .Commit_Unavailable
	case .Invalid:
		return false, .Invalid_Request
	}
	return true, .None
}

/* commit_request_lineage derives immutable requested revision relationships from one valid request. */
commit_request_lineage :: proc(request: Commit_Request) -> (Commit_Lineage, bool) {
	if !commit_request_is_valid(request) do return {}, false
	lineage := Commit_Lineage{prior_head = request.precondition.head}
	switch request.mode {
	case .Amend:
		lineage.replaced = request.precondition.head.revision
	case .Fixup:
		lineage.fixup_target = request.arguments.target.observation.revision
	case .Normal:
	case .Invalid:
		return {}, false
	}
	return lineage, true
}

/* commit_request_usage reports exact fixed message storage in one valid request. */
commit_request_usage :: proc(request: Commit_Request) -> (Commit_Usage, bool) {
	if !commit_request_is_valid(request) do return {}, false
	usage := Commit_Usage{message_bytes = u64(request.message.length)}
	if request.mode != .Normal do usage.target_subject_bytes = u64(request.arguments.target.subject.length)
	return usage, true
}

/* commit_result_open copies one bounded checked-commit process outcome and verified lineage. */
commit_result_open :: proc(
	request: Commit_Request,
	resulting: Revision_Identity,
	exit_status: i32,
	output: []u8,
	diagnostic: []u8,
	process_failure := Failure_Code.None,
	allocator := context.allocator,
) -> (Commit_Result, bool, Failure_Code) {
	if allocator.procedure == nil || !commit_request_is_valid(request) do return {}, false, .Invalid_Request
	if u64(len(output)) > request.limits.stdout_bytes || u64(len(diagnostic)) > request.limits.diagnostic_bytes {
		return {}, false, .Output_Limit
	}
	succeeded := process_failure == .None && exit_status == 0
	lineage, derived := commit_result_lineage(request, resulting, succeeded)
	if !derived do return {}, false, .Invalid_Request
	state, allocation_error := new(Commit_Result_Data, allocator)
	if allocation_error != nil do return {}, false, .Allocation
	state.allocator = allocator
	state.descriptor = {
		request = request,
		lineage = lineage,
		exit_status = exit_status,
		output_bytes = u64(len(output)),
		diagnostic_bytes = u64(len(diagnostic)),
		failure = process_failure,
		succeeded = succeeded,
	}
	state.output, allocation_error = make([dynamic]u8, 0, len(output), allocator)
	if allocation_error == nil do state.diagnostic, allocation_error = make([dynamic]u8, 0, len(diagnostic), allocator)
	if allocation_error == nil && len(output) > 0 do _, allocation_error = append(&state.output, ..output)
	if allocation_error == nil && len(diagnostic) > 0 do _, allocation_error = append(&state.diagnostic, ..diagnostic)
	if allocation_error != nil {
		commit_result_data_destroy(state)
		return {}, false, .Allocation
	}
	return Commit_Result{state = state}, true, .None
}

/* commit_result_lineage derives verified result identity only for a successful requested transition. */
commit_result_lineage :: proc(
	request: Commit_Request,
	resulting: Revision_Identity,
	succeeded: bool,
) -> (Commit_Lineage, bool) {
	lineage, derived := commit_request_lineage(request)
	if !derived do return {}, false
	if !succeeded do return lineage, resulting == {}
	if !revision_identity_is_valid(resulting) do return {}, false
	if request.precondition.head.kind == .Revision && resulting == request.precondition.head.revision {
		return {}, false
	}
	lineage.resulting = resulting
	return lineage, true
}

/* commit_result_descriptor returns copied normal-commit outcome metadata. */
commit_result_descriptor :: proc(result: ^Commit_Result) -> (Commit_Result_Descriptor, bool) {
	state := commit_result_data(result)
	if state == nil do return {}, false
	return state.descriptor, true
}

/* commit_result_usage reports exact copied message, output, and diagnostic bytes. */
commit_result_usage :: proc(result: ^Commit_Result) -> (Commit_Usage, bool) {
	state := commit_result_data(result)
	if state == nil do return {}, false
	return {
		message_bytes = u64(state.descriptor.request.message.length),
		target_subject_bytes = state.descriptor.request.mode != .Normal ? u64(state.descriptor.request.arguments.target.subject.length) : 0,
		output_bytes = u64(len(state.output)),
		diagnostic_bytes = u64(len(state.diagnostic)),
	}, true
}

/* commit_result_output returns borrowed copied process output and diagnostics. */
commit_result_output :: proc(result: ^Commit_Result) -> (output, diagnostic: []u8, ok: bool) {
	state := commit_result_data(result)
	if state == nil do return nil, nil, false
	return state.output[:], state.diagnostic[:], true
}

/* commit_result_close releases every owned normal-commit result allocation. */
commit_result_close :: proc(result: ^Commit_Result) {
	state := commit_result_data(result)
	if state == nil do return
	commit_result_data_destroy(state)
	result^ = {}
}

/* commit_feedback maps normal-commit admission and process failures to application feedback. */
commit_feedback :: proc(failure: Failure_Code) -> Commit_Feedback {
	#partial switch failure {
	case .None: return .Completed
	case .Stale_Observation, .History_Continuation_Stale: return .Stale
	case .Commit_Unavailable, .History_Unborn, .Revision_Unavailable: return .Unavailable
	case .Invalid_Context, .Invalid_Limits, .Invalid_Request, .Commit_Message_Invalid,
	     .Confirmation_Required, .Confirmation_Mismatch: return .Rejected
	case .Output_Limit, .History_Limit, .History_Metadata_Limit, .History_Message_Limit,
	     .History_Topology_Limit, .History_Temporary_Limit, .History_Truncated: return .Limited
	case .Timeout: return .Timed_Out
	case .Cancelled: return .Cancelled
	case .Executable_Unavailable, .Process_Failed, .Parse, .Allocation, .Cleanup: return .Failed
	case .Path_Unavailable, .Action_Unavailable, .Diff_Unsupported, .Diff_Truncated,
	     .Diff_Unit_Unavailable, .Patch_Unavailable, .Target_Duplicate, .Target_Incompatible,
	     .Target_Overlap, .Target_Limit, .Modified_Buffer, .Parent_Limit,
	     .Presentation_Unavailable: return .Unavailable
	}
	return .Invalid
}

@(private)
commit_message_subject_is_nonempty :: proc(
	bytes: [MAX_COMMIT_MESSAGE_BYTES]u8,
	length: int,
) -> bool {
	if length <= 0 || length > len(bytes) do return false
	for index in 0 ..< length {
		byte := bytes[index]
		if byte != ' ' && byte != '\t' do return true
	}
	return false
}

@(private)
commit_message_bytes_are_valid_utf8 :: proc(
	bytes: [MAX_COMMIT_MESSAGE_BYTES]u8,
	length: int,
) -> bool {
	if length <= 0 || length > len(bytes) do return false
	local := bytes
	return utf8.valid_string(string(local[:length]))
}

@(private)
commit_fixup_message_assign :: proc(message: ^Commit_Message, target: Commit_Revision_Target) -> bool {
	if message == nil || !commit_revision_target_is_valid(target) do return false
	message^ = {}
	required := len(FIXUP_SUBJECT_PREFIX) + int(target.subject.length)
	if required > len(message.bytes) do return false
	copy(message.bytes[:len(FIXUP_SUBJECT_PREFIX)], FIXUP_SUBJECT_PREFIX)
	if target.subject.length > 0 {
		subject := target.subject
		copy(message.bytes[len(FIXUP_SUBJECT_PREFIX):required], subject.bytes[:subject.length])
	}
	message.length = u32(required)
	message.subject_length = u32(required)
	return commit_message_is_valid(message^)
}

@(private)
commit_result_data :: proc(result: ^Commit_Result) -> ^Commit_Result_Data {
	if result == nil || result.state == nil do return nil
	return cast(^Commit_Result_Data)result.state
}

@(private)
commit_result_data_destroy :: proc(state: ^Commit_Result_Data) {
	if state == nil do return
	delete(state.output)
	delete(state.diagnostic)
	free(state, state.allocator)
}
