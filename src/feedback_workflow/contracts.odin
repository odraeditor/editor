// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package feedback_workflow connects editor-owned semantic producers to the
// canonical feedback registry and presentation router.
package feedback_workflow

import "../feedback"
import "../feedback_routing"
import "base:runtime"

/* CHANNEL_COUNT is the number of maintained editor feedback producer families. */
CHANNEL_COUNT :: 7
/* MAX_ACTIONS is the copied action bound inherited from semantic feedback. */
MAX_ACTIONS :: feedback.MAX_ACTIONS

/* Channel identifies one maintained editor feedback producer family. */
Channel :: enum u8 {
	Invalid,
	Command,
	Save,
	Recovery,
	Language_Service,
	Project,
	Package,
	Long_Operation,
}

/* Action_Kind classifies the initial checked feedback action vocabulary. */
Action_Kind :: enum u8 {
	Invalid,
	Inspect,
	Retry,
	Cancel,
	Open_Source,
	Show_Log,
}

/* Action_Definition borrows one command-backed semantic action. */
Action_Definition :: struct {
	id:        feedback.Action_ID,
	kind:      Action_Kind,
	command:   string,
	argument:  string,
	sensitive: bool,
}

/* Notification_Request borrows one human-facing notification and diagnostic detail. */
Notification_Request :: struct {
	channel:    Channel,
	class:      feedback.Semantic_Class,
	severity:   feedback.Severity,
	attention:  feedback.Attention,
	lifecycle:  feedback.Lifecycle_Policy,
	retention:  feedback.Retention_Policy,
	visibility: feedback.Visibility,
	sensitivity: feedback.Sensitivity,
	message:    string,
	detail:     string,
	actions:    []Action_Definition,
}

/* Progress_Request borrows one complete long-operation generation. */
Progress_Request :: struct {
	state:       feedback.Progress_State,
	measurement: feedback.Measurement_Kind,
	current:     u64,
	total:       u64,
	phase:       string,
	message:     string,
	detail:      string,
	actions:     []Action_Definition,
}

/* Publication identifies one exact admitted semantic feedback generation. */
Publication :: struct {
	record_id:         feedback.Record_ID,
	record_generation: feedback.Record_Generation,
	source:            feedback.Source_Reference,
	presentation_generation: u64,
}

/* Inspection reports current registry, routing, and presentation occupancy. */
Inspection :: struct {
	feedback:      feedback.Registry_Stats,
	routing:       feedback_routing.Routing_Stats,
	presentations: u8,
}

/* Failure_Code classifies checked consumer workflow rejection. */
Failure_Code :: enum u8 {
	None,
	Invalid_Workflow,
	Invalid_Channel,
	Invalid_Request,
	Feedback_Rejected,
	Routing_Rejected,
	Presentation_Rejected,
}

/* Failure identifies the failed owner without exposing diagnostic detail. */
Failure :: struct {
	code:         Failure_Code,
	channel:      Channel,
	feedback:     feedback.Failure,
	routing:      feedback_routing.Failure,
}

/* Workflow owns semantic feedback, routing, and visible presentation state. */
Workflow :: struct {
	registry:       feedback.Registry,
	routing:        feedback_routing.Registry,
	presentations:  feedback_routing.Presentation_Cache,
	generations:    [CHANNEL_COUNT]feedback.Record_Generation,
	live:           [CHANNEL_COUNT]bool,
	frontend:       feedback_routing.Frontend_Context,
	temporary:      runtime.Allocator,
	initialized:    bool,
}

/* status_frontend returns the conservative terminal root-edge presentation profile. */
status_frontend :: proc(columns := u32(120)) -> feedback_routing.Frontend_Context {
	return {
		profile = 1,
		capabilities = {.Cell_Geometry, .Clipping, .Semantic_Attributes, .Atomic_Generation},
		color = .True_Color,
		rows = 1,
		columns = max(columns, 12),
		status_available = true,
	}
}

/* channel_title returns the stable human-facing title for one producer family. */
channel_title :: proc(channel: Channel) -> string {
	switch channel {
	case .Command:          return "Command"
	case .Save:             return "Save"
	case .Recovery:         return "Recovery"
	case .Language_Service: return "Language service"
	case .Project:          return "Project"
	case .Package:          return "Package"
	case .Long_Operation:   return "Operation"
	case .Invalid:          return ""
	}
	return ""
}
