// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_computation

/* Execution_Feedback_Kind is the stable user-facing execution outcome vocabulary. */
Execution_Feedback_Kind :: enum u8 {
	Invalid,
	Completed,
	Adapter_Unavailable,
	Malformed_Source,
	Authority_Rejected,
	Cancelled,
	Execution_Failed,
}

/* Execution_Feedback separates expected unavailability from execution failure. */
Execution_Feedback :: struct {
	kind:             Execution_Feedback_Kind,
	message:          string,
	source_preserved: bool,
	retryable:        bool,
}

/* execution_feedback_from_failure normalizes internal failures for editor feedback. */
execution_feedback_from_failure :: proc(code: Failure_Code) -> Execution_Feedback {
	switch code {
	case .None:
		return {.Completed, "execution completed", true, false}
	case .Unavailable:
		return {.Adapter_Unavailable, "no adapter is configured", true, true}
	case .Invalid_Request, .Malformed, .Stale, .Conflict, .Cycle, .Conversion:
		return {.Malformed_Source, "source is malformed or no longer current", true, true}
	case .Unauthorized, .Confirmation_Required:
		return {.Authority_Rejected, "execution authority was rejected", true, true}
	case .Cancelled:
		return {.Cancelled, "execution was cancelled", true, true}
	case .Timed_Out, .Limited, .Allocation_Failed, .Adapter, .Process,
	     .Evaluation, .Result_Decoding, .Publication, .Quarantined:
		return {.Execution_Failed, "execution failed", true, true}
	}
	return {.Invalid, "execution outcome is unavailable", true, false}
}
