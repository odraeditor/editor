// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_service_workflow

import "../language_service"

// Workflow_State owns resolved language-service definitions, processes,
// protocol sessions, document synchronization, and retained diagnostics.
Workflow_State :: Language_Service_Workflow_State

// Workflow_Session is a borrowed live service session used by completion.
Workflow_Session :: Language_Service_Workflow_Session

// Workflow_Document is a borrowed synchronized document used by completion.
Workflow_Document :: Language_Service_Workflow_Document

// Visible_Observation describes service health and diagnostics for one buffer.
Visible_Observation :: Language_Service_Visible_Observation

// Context_Projection resolves the language identity and service health shown by adapters.
Context_Projection :: Language_Context_Projection

// Service_Health is the presentation-neutral language-service lifecycle state.
Service_Health :: Language_Service_Workflow_Phase

// Diagnostic_Source owns a copied diagnostic candidate projection.
Diagnostic_Source :: Language_Service_Diagnostic_Source

// Support_Candidate owns one prepared language-support catalog generation.
Support_Candidate :: Language_Support_Workflow_Candidate

// Inspection_State owns copied, bounded rows for an adapter-rendered service view.
Inspection_State :: Language_Service_Inspection_Workflow_State

// Completion_Integration keeps completion orchestration above the service
// runtime while allowing service failure and protocol messages to be routed.
Completion_Integration :: struct {
	state: rawptr,
	matches_service: proc(state: rawptr, owner: ^Workflow_Session) -> bool,
	end_session: proc(state: rawptr, owner: ^Workflow_Session, send_cancel: bool),
	receive_message: proc(
		state: rawptr,
		owner: ^Workflow_Session,
		message: ^language_service.Message,
	) -> (handled, changed: bool),
}
