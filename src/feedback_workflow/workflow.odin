// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package feedback_workflow

import "../feedback"
import "../feedback_routing"
import "../ui"

/* workflow_init creates one complete last-valid editor feedback workflow. */
workflow_init :: proc(
	workflow: ^Workflow,
	id: u64,
	profile: ui.Presentation_Profile_Handle,
	allocators: feedback.Allocator_Set,
	frontend: feedback_routing.Frontend_Context,
) -> (bool, Failure) {
	if workflow == nil || workflow.initialized || id == 0 || allocators.temporary.procedure == nil {
		return false, Failure{code = .Invalid_Workflow}
	}
	registry_ready, registry_failure := feedback.registry_init(
		&workflow.registry,
		feedback.Registry_ID(id),
		allocators,
	)
	if !registry_ready {
		return false, Failure{code = .Feedback_Rejected, feedback = registry_failure}
	}
	routing_ready, routing_failure := feedback_routing.registry_init(
		&workflow.routing,
		feedback_routing.Routing_Registry_ID(id),
		feedback_routing.factory_configuration(1, profile),
		allocators.persistent,
	)
	if !routing_ready {
		_, _ = feedback.registry_close(&workflow.registry)
		return false, Failure{code = .Routing_Rejected, routing = routing_failure}
	}
	workflow.frontend = frontend
	workflow.temporary = allocators.temporary
	workflow.initialized = true
	return true, {}
}

/* workflow_publish_notification admits and presents one producer notification. */
workflow_publish_notification :: proc(
	workflow: ^Workflow,
	request: Notification_Request,
) -> (Publication, bool, Failure) {
	index, valid := channel_index(request.channel)
	if !workflow_is_ready(workflow) || !valid {
		return {}, false, Failure{code = .Invalid_Channel, channel = request.channel}
	}
	if request.channel == .Long_Operation || len(request.message) == 0 ||
	   request.class == .Invalid || request.class == .Progress || request.class == .Completion ||
	   request.severity == .Invalid || request.lifecycle == .Invalid || request.visibility == .Invalid ||
	   len(request.actions) > MAX_ACTIONS {
		return {}, false, Failure{code = .Invalid_Request, channel = request.channel}
	}
	actions, actions_ok := workflow_actions(request.actions)
	if !actions_ok do return {}, false, Failure{code = .Invalid_Request, channel = request.channel}
	generation := workflow.generations[index] + 1
	metadata: [1]feedback.Metadata_Proposal
	metadata_count := 0
	if len(request.detail) > 0 {
		metadata[0] = {key = "diagnostic-detail", value = request.detail}
		metadata_count = 1
	}
	record, published, feedback_failure := feedback.registry_publish(
		&workflow.registry,
		feedback.Proposal {
			id = feedback.Record_ID(u64(request.channel)),
			generation = generation,
			replacement = feedback.Record_ID(u64(request.channel)) if workflow.live[index] else 0,
			source = {id = feedback.Source_ID(u64(request.channel)), generation = 1},
			kind = .Notification,
			class = request.class,
			severity = request.severity,
			attention = request.attention,
			lifecycle = request.lifecycle,
			retention = request.retention,
			visibility = request.visibility,
			sensitivity = request.sensitivity,
			title = request.message,
			metadata = metadata[:metadata_count],
			actions = actions[:len(request.actions)],
		},
	)
	if !published {
		return {}, false, Failure{code = .Feedback_Rejected, channel = request.channel, feedback = feedback_failure}
	}
	workflow.generations[index] = generation
	workflow.live[index] = true
	return workflow_present_record(workflow, request.channel, record)
}

/* workflow_publish_progress admits and presents one long-operation generation. */
workflow_publish_progress :: proc(
	workflow: ^Workflow,
	request: Progress_Request,
) -> (Publication, bool, Failure) {
	index, _ := channel_index(.Long_Operation)
	if !workflow_is_ready(workflow) || request.state == .Invalid ||
	   request.measurement == .Invalid || len(request.message) == 0 ||
	   len(request.actions) > MAX_ACTIONS {
		return {}, false, Failure{code = .Invalid_Request, channel = .Long_Operation}
	}
	actions, actions_ok := workflow_actions(request.actions)
	if !actions_ok do return {}, false, Failure{code = .Invalid_Request, channel = .Long_Operation}
	generation := workflow.generations[index] + 1
	terminal := request.state == .Succeeded || request.state == .Failed || request.state == .Cancelled
	severity := feedback.Severity.Information
	attention := feedback.Attention.Ordinary
	if request.state == .Failed {
		severity = .Error
		attention = .Required
	}
	metadata: [1]feedback.Metadata_Proposal
	metadata_count := 0
	if len(request.detail) > 0 {
		metadata[0] = {key = "diagnostic-detail", value = request.detail}
		metadata_count = 1
	}
	record, published, feedback_failure := feedback.registry_publish(
		&workflow.registry,
		feedback.Proposal {
			id = feedback.Record_ID(u64(Channel.Long_Operation)),
			generation = generation,
			replacement = feedback.Record_ID(u64(Channel.Long_Operation)) if workflow.live[index] else 0,
			source = {id = feedback.Source_ID(u64(Channel.Long_Operation)), generation = 1},
			kind = .Progress,
			class = .Completion if terminal else .Progress,
			severity = severity,
			attention = attention,
			lifecycle = .Retained,
			retention = .History,
			visibility = .Public,
			title = request.message,
			progress = {
				state = request.state,
				measurement = request.measurement,
				current = request.current,
				total = request.total,
				phase = request.phase,
			},
			metadata = metadata[:metadata_count],
			actions = actions[:len(request.actions)],
		},
	)
	if !published {
		return {}, false, Failure{code = .Feedback_Rejected, channel = .Long_Operation, feedback = feedback_failure}
	}
	workflow.generations[index] = generation
	workflow.live[index] = !terminal || request.state == .Failed
	return workflow_present_record(workflow, .Long_Operation, record)
}

/* workflow_resolve_action revalidates and copies one exact command authority. */
workflow_resolve_action :: proc(
	workflow: ^Workflow,
	publication: Publication,
	action: feedback.Action_ID,
) -> (feedback.Action_Authority, bool, Failure) {
	if !workflow_is_ready(workflow) {
		return {}, false, Failure{code = .Invalid_Workflow}
	}
	authority, resolved, feedback_failure := feedback.registry_resolve_action(
		&workflow.registry,
		{
			record_id = publication.record_id,
			record_generation = publication.record_generation,
			source = publication.source,
			action_id = action,
		},
		workflow.temporary,
	)
	if !resolved {
		return {}, false, Failure{code = .Feedback_Rejected, feedback = feedback_failure}
	}
	return authority, true, {}
}

/* workflow_status_projection copies the newest root-edge feedback projection. */
workflow_status_projection :: proc(workflow: ^Workflow) -> (feedback_routing.Projection, bool) {
	if !workflow_is_ready(workflow) do return {}, false
	for reverse_index in 0 ..< int(workflow.presentations.item_count) {
		index := int(workflow.presentations.item_count) - 1 - reverse_index
		projection := workflow.presentations.items[index]
		if projection.destination == feedback_routing.FACTORY_STATUS_DESTINATION {
			return projection, true
		}
	}
	return {}, false
}

/* workflow_dismiss removes one exact visible channel generation and active record. */
workflow_dismiss :: proc(workflow: ^Workflow, publication: Publication) -> (bool, Failure) {
	if !workflow_is_ready(workflow) do return false, Failure{code = .Invalid_Workflow}
	presentations := workflow.presentations
	index := 0
	for index < int(presentations.item_count) {
		item := presentations.items[index]
		if item.record_id != publication.record_id {
			index += 1
			continue
		}
		dismissed, routing_failure := feedback_routing.presentation_dismiss(
			&presentations,
			item.record_id,
			item.destination,
			.Explicit,
		)
		if !dismissed {
			return false, Failure{code = .Presentation_Rejected, routing = routing_failure}
		}
	}
	dismissed, feedback_failure := feedback.registry_dismiss(
		&workflow.registry,
		publication.record_id,
		publication.record_generation,
	)
	if !dismissed do return false, Failure{code = .Feedback_Rejected, feedback = feedback_failure}
	workflow.presentations = presentations
	channel := Channel(u8(publication.record_id))
	if channel_index_value, valid := channel_index(channel); valid do workflow.live[channel_index_value] = false
	return true, {}
}

/* workflow_inspect copies bounded registry and routing occupancy. */
workflow_inspect :: proc(workflow: ^Workflow) -> (Inspection, bool, Failure) {
	if !workflow_is_ready(workflow) do return {}, false, Failure{code = .Invalid_Workflow}
	feedback_stats, feedback_ok, feedback_failure := feedback.registry_stats(&workflow.registry)
	if !feedback_ok do return {}, false, Failure{code = .Feedback_Rejected, feedback = feedback_failure}
	routing_inspection, routing_ok, routing_failure := feedback_routing.registry_inspect(&workflow.routing)
	if !routing_ok do return {}, false, Failure{code = .Routing_Rejected, routing = routing_failure}
	return {
		feedback = feedback_stats,
		routing = routing_inspection.stats,
		presentations = workflow.presentations.item_count,
	}, true, {}
}

/* workflow_close releases the complete consumer workflow exactly once. */
workflow_close :: proc(workflow: ^Workflow) -> (bool, Failure) {
	if !workflow_is_ready(workflow) do return false, Failure{code = .Invalid_Workflow}
	routing_closed, routing_failure := feedback_routing.registry_close(&workflow.routing)
	feedback_closed, feedback_failure := feedback.registry_close(&workflow.registry)
	if !routing_closed {
		return false, Failure{code = .Routing_Rejected, routing = routing_failure}
	}
	if !feedback_closed {
		return false, Failure{code = .Feedback_Rejected, feedback = feedback_failure}
	}
	workflow^ = {}
	return true, {}
}

@(private)
workflow_present_record :: proc(workflow: ^Workflow, channel: Channel, record: feedback.Record) -> (Publication, bool, Failure) {
	routed, resolved, routing_failure := feedback_routing.registry_route_and_project(
		&workflow.routing,
		record,
		workflow.frontend,
	)
	if !resolved {
		return {}, false, Failure{code = .Routing_Rejected, channel = channel, routing = routing_failure}
	}
	applied, presentation_failure := feedback_routing.presentation_apply(&workflow.presentations, routed)
	if !applied {
		return {}, false, Failure{code = .Presentation_Rejected, channel = channel, routing = presentation_failure}
	}
	return {
		record_id = record.id,
		record_generation = record.generation,
		source = record.source,
		presentation_generation = workflow.presentations.generation,
	}, true, {}
}

@(private)
workflow_actions :: proc(definitions: []Action_Definition) -> ([MAX_ACTIONS]feedback.Action_Proposal, bool) {
	actions: [MAX_ACTIONS]feedback.Action_Proposal
	for definition, index in definitions {
		if definition.id == feedback.Action_ID(0) || definition.kind <= .Invalid ||
		   definition.kind > .Show_Log || len(definition.command) == 0 {
			return {}, false
		}
		actions[index] = {
			id = definition.id,
			command = definition.command,
			argument = definition.argument,
			cancel = definition.kind == .Cancel,
			sensitive = definition.sensitive,
		}
	}
	return actions, true
}

@(private)
channel_index :: proc(channel: Channel) -> (int, bool) {
	if channel <= .Invalid || channel > .Long_Operation do return 0, false
	return int(channel) - 1, true
}

@(private)
workflow_is_ready :: proc(workflow: ^Workflow) -> bool {
	return workflow != nil && workflow.initialized
}
