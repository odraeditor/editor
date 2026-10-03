// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package feedback_routing

import "../feedback"
import "../ui"
import "base:runtime"

@(private)
Registry_State :: struct {
	id:         Routing_Registry_ID,
	generation: Routing_Registry_Generation,
	active:     Configuration_Proposal,
	last_rejection: Failure,
	allocator:  runtime.Allocator,
}

/* registry_init validates and publishes one complete initial configuration. */
registry_init :: proc(
	registry: ^Registry,
	id: Routing_Registry_ID,
	proposal: Configuration_Proposal,
	allocator := context.allocator,
) -> (bool, Failure) {
	if registry == nil || registry.state != nil || registry.closed {
		return false, Failure{operation = .Initialize, code = .Invalid_Registry}
	}
	if id == Routing_Registry_ID(0) {
		return false, Failure{operation = .Initialize, code = .Invalid_Identity}
	}
	if allocator.procedure == nil {
		return false, Failure{operation = .Initialize, code = .Allocation}
	}
	candidate := proposal
	if valid, failure := configuration_validate(&candidate); !valid do return false, failure
	state, allocation_error := new(Registry_State, allocator)
	if allocation_error != nil do return false, Failure{operation = .Initialize, code = .Allocation}
	state^ = {id = id, generation = 1, active = proposal, allocator = allocator}
	registry.state = state
	return true, {}
}

/* registry_reload atomically replaces configuration and preserves last valid on rejection. */
registry_reload :: proc(
	registry: ^Registry,
	expected: Routing_Registry_Generation,
	proposal: Configuration_Proposal,
) -> (bool, Failure) {
	state := registry_state(registry)
	if state == nil do return false, Failure{operation = .Reload, code = .Invalid_Registry}
	if expected != state.generation || proposal.generation <= state.active.generation {
		return false, registry_reject(state, Failure {
			operation = .Reload,
			code = .Stale_Generation,
			limit = u64(state.generation),
			actual = u64(expected),
		})
	}
	candidate := proposal
	if valid, failure := configuration_validate(&candidate); !valid {
		failure.operation = .Reload
		return false, registry_reject(state, failure)
	}
	state.active = proposal
	state.generation += 1
	state.last_rejection = {}
	return true, {}
}

/* registry_resolve routes one immutable record against checked frontend evidence. */
registry_resolve :: proc(
	registry: ^Registry,
	record: feedback.Record,
	frontend: Frontend_Context,
) -> (Resolution, bool, Failure) {
	state := registry_state(registry)
	if state == nil do return {}, false, Failure{operation = .Resolve, code = .Invalid_Registry}
	resolution := Resolution {
		record_id = record.id,
		record_generation = record.generation,
		configuration = state.active.generation,
	}
	for route in state.active.routes[:state.active.route_count] {
		resolution.evaluated_routes += 1
		if !route.enabled || !route_matches(route.matcher, record) do continue
		resolution.matched_routes[resolution.matched_count] = route.id
		resolution.matched_count += 1
		if route.resolution == .Suppress_Visible {
			if record.attention != .Required && record.severity != .Error {
				resolution.destination_count = 0
				resolution.suppressed = true
				return resolution, true, {}
			}
			continue
		}
		for destination_index in 0 ..< int(route.destination_count) {
			destination_id := route.destinations[destination_index]
			if resolution_has_destination(&resolution, destination_id) do continue
			selected, selected_ok, select_failure := configuration_select_destination(
				&state.active, destination_id, frontend,
			)
			if !selected_ok {
				if record.attention == .Required || record.severity == .Error {
					return {}, false, registry_reject(state, select_failure)
				}
				continue
			}
			if !resolution_has_selected_destination(&resolution, selected.selected) &&
			   resolution.destination_count < MAX_RESOLVED_DESTINATIONS {
				resolution.destinations[resolution.destination_count] = selected
				resolution.destination_count += 1
			}
		}
		if route.resolution == .Terminal do break
	}
	if resolution.destination_count == 0 && !resolution.suppressed {
		return {}, false, registry_reject(state, Failure{operation = .Resolve, code = .No_Route})
	}
	return resolution, true, {}
}

/* registry_inspect copies current configuration, occupancy, and last rejection. */
registry_inspect :: proc(registry: ^Registry) -> (Routing_Inspection, bool, Failure) {
	state := registry_state(registry)
	if state == nil do return {}, false, Failure{operation = .Inspect, code = .Invalid_Registry}
	return Routing_Inspection {
		stats = {
			registry_id = state.id,
			registry_generation = state.generation,
			configuration = state.active.generation,
			routes = state.active.route_count,
			destinations = state.active.destination_count,
			projections = state.active.projection_count,
			retained_bytes = size_of(Registry_State),
		},
		configuration = state.active,
		last_rejection = state.last_rejection,
	}, true, {}
}

/* registry_close releases one routing registry exactly once. */
registry_close :: proc(registry: ^Registry) -> (bool, Failure) {
	state := registry_state(registry)
	if state == nil do return false, Failure{operation = .Close, code = .Invalid_Registry}
	allocator := state.allocator
	free(state, allocator)
	registry^ = Registry{closed = true}
	return true, {}
}

/* configuration_validate checks one complete route graph without mutation. */
configuration_validate :: proc(proposal: ^Configuration_Proposal) -> (bool, Failure) {
	if proposal == nil do return false, Failure{operation = .Initialize, code = .Invalid_Registry}
	if proposal.generation == Configuration_Generation(0) {
		return false, Failure{operation = .Initialize, code = .Invalid_Generation}
	}
	if proposal.route_count == 0 || proposal.route_count > MAX_ROUTES {
		return false, Failure{operation = .Initialize, code = .Route_Limit, limit = MAX_ROUTES, actual = u64(proposal.route_count)}
	}
	if proposal.destination_count == 0 || proposal.destination_count > MAX_DESTINATIONS {
		return false, Failure{operation = .Initialize, code = .Destination_Limit, limit = MAX_DESTINATIONS, actual = u64(proposal.destination_count)}
	}
	if proposal.projection_count == 0 || proposal.projection_count > MAX_PROJECTIONS {
		return false, Failure{operation = .Initialize, code = .Projection_Limit, limit = MAX_PROJECTIONS, actual = u64(proposal.projection_count)}
	}
	for projection, index in proposal.projections[:proposal.projection_count] {
		name := projection.name
		if projection.id == Projection_ID(0) || projection.generation == Projection_Generation(0) ||
		   len(text_view(&name)) == 0 || projection.maximum_bytes < MIN_PROJECTION_BYTES ||
		   projection.maximum_bytes > MAX_PROJECTION_BYTES {
			return false, Failure{operation = .Initialize, code = .Invalid_Projection, projection = projection.id}
		}
		for prior in proposal.projections[:index] {
			if prior.id == projection.id do return false, Failure{operation = .Initialize, code = .Duplicate_Identity, projection = projection.id}
		}
	}
	for destination, index in proposal.destinations[:proposal.destination_count] {
		name := destination.name
		if destination.id == Destination_ID(0) || destination.generation == Destination_Generation(0) ||
		   len(text_view(&name)) == 0 || destination.kind == .Invalid ||
		   destination.focus == .Invalid || destination.capacity == 0 || destination.content_bytes == 0 ||
		   destination.content_bytes > MAX_PROJECTION_BYTES {
			return false, Failure{operation = .Initialize, code = .Invalid_Destination, destination = destination.id}
		}
		if configuration_projection_index(proposal, destination.projection) < 0 {
			return false, Failure{operation = .Initialize, code = .Missing_Projection, destination = destination.id, projection = destination.projection}
		}
		if (destination.kind == .Floating || destination.kind == .Anchored_Detail) &&
		   (destination.focus != .Preserve || destination.profile.profile_id == ui.Presentation_Profile_ID(0)) {
			return false, Failure{operation = .Initialize, code = .Invalid_Destination, destination = destination.id}
		}
		for prior in proposal.destinations[:index] {
			if prior.id == destination.id do return false, Failure{operation = .Initialize, code = .Duplicate_Identity, destination = destination.id}
		}
	}
	for destination in proposal.destinations[:proposal.destination_count] {
		if destination.fallback == Destination_ID(0) do continue
		if destination.fallback == destination.id || configuration_destination_index(proposal, destination.fallback) < 0 {
			return false, Failure{operation = .Initialize, code = .Invalid_Fallback, destination = destination.id}
		}
		if failure := configuration_validate_fallback(proposal, destination.id); failure.code != .None {
			failure.operation = .Initialize
			return false, failure
		}
	}
	safety_attention := false
	safety_error := false
	previous_layer := Policy_Layer.Invalid
	previous_order: i16
	previous_id := Route_ID(0)
	for route, index in proposal.routes[:proposal.route_count] {
		name := route.name
		if route.id == Route_ID(0) || route.generation == Route_Generation(0) ||
		   len(text_view(&name)) == 0 || route.layer == .Invalid || route.resolution == .Invalid ||
		   !matcher_is_valid(route.matcher) {
			return false, Failure{operation = .Initialize, code = .Invalid_Route, route = route.id}
		}
		if index > 0 && (route.layer < previous_layer ||
		   (route.layer == previous_layer && (route.order < previous_order ||
		   (route.order == previous_order && route.id <= previous_id)))) {
			return false, Failure{operation = .Initialize, code = .Invalid_Order, route = route.id}
		}
		previous_layer = route.layer
		previous_order = route.order
		previous_id = route.id
		for prior in proposal.routes[:index] {
			if prior.id == route.id do return false, Failure{operation = .Initialize, code = .Duplicate_Identity, route = route.id}
		}
		if route.protected && route.layer != .Safety {
			return false, Failure{operation = .Initialize, code = .Protected_Route, route = route.id}
		}
		if route.resolution == .Suppress_Visible {
			if route.destination_count != 0 || route.protected {
				return false, Failure{operation = .Initialize, code = .Invalid_Route, route = route.id}
			}
		} else if route.destination_count == 0 || route.destination_count > MAX_ROUTE_DESTINATIONS {
			return false, Failure{operation = .Initialize, code = .Invalid_Route, route = route.id}
		}
		inspectable := false
		for route_destination_index in 0 ..< int(route.destination_count) {
			destination_id := route.destinations[route_destination_index]
			destination_index := configuration_destination_index(proposal, destination_id)
			if destination_index < 0 {
				return false, Failure{operation = .Initialize, code = .Missing_Destination, route = route.id, destination = destination_id}
			}
			inspectable = inspectable || proposal.destinations[destination_index].inspectable
		}
		if route.enabled && route.protected && route.layer == .Safety && route.resolution != .Suppress_Visible && inspectable {
			safety_attention = safety_attention || (route.matcher.match_attention && route.matcher.attention == .Required)
			safety_error = safety_error || (route.matcher.match_severity && route.matcher.severity == .Error)
		}
	}
	if !safety_attention || !safety_error {
		return false, Failure{operation = .Initialize, code = .Missing_Safety_Route}
	}
	return true, {}
}

@(private)
matcher_is_valid :: proc(matcher: Matcher) -> bool {
	if matcher.match_class && matcher.class == .Invalid do return false
	if matcher.match_severity && matcher.severity == .Invalid do return false
	if matcher.match_source && matcher.source == feedback.Source_ID(0) do return false
	if matcher.match_lifecycle && matcher.lifecycle == .Invalid do return false
	if matcher.match_progress && matcher.progress == .Invalid do return false
	if matcher.match_extent && matcher.extent == .Invalid do return false
	return true
}

@(private)
route_matches :: proc(matcher: Matcher, record: feedback.Record) -> bool {
	if matcher.match_class && matcher.class != record.class do return false
	if matcher.match_severity && matcher.severity != record.severity do return false
	if matcher.match_source && matcher.source != record.source.id do return false
	if matcher.match_lifecycle && matcher.lifecycle != record.lifecycle do return false
	if matcher.match_progress && matcher.progress != record.progress.state do return false
	if matcher.match_attention && matcher.attention != record.attention do return false
	if matcher.match_retention && matcher.retention != record.retention do return false
	if matcher.match_actions && matcher.has_actions != (len(record.actions) > 0) do return false
	if matcher.match_extent && matcher.extent != record_extent(record) do return false
	return true
}

@(private)
record_extent :: proc(record: feedback.Record) -> Content_Extent {
	if len(record.title) + len(record.message) <= 160 do return .Compact
	return .Expanded
}

@(private)
configuration_destination_index :: proc(configuration: ^Configuration_Proposal, id: Destination_ID) -> int {
	for destination, index in configuration.destinations[:configuration.destination_count] {
		if destination.id == id do return index
	}
	return -1
}

@(private)
configuration_projection_index :: proc(configuration: ^Configuration_Proposal, id: Projection_ID) -> int {
	for projection, index in configuration.projections[:configuration.projection_count] {
		if projection.id == id do return index
	}
	return -1
}

@(private)
configuration_select_destination :: proc(
	configuration: ^Configuration_Proposal,
	requested: Destination_ID,
	frontend: Frontend_Context,
) -> (Destination_Resolution, bool, Failure) {
	selected, depth, failure := configuration_follow_fallback(configuration, requested, frontend)
	if failure.code != .None do return {}, false, failure
	return {requested = requested, selected = selected.id, fallback_depth = depth, degraded = depth > 0}, true, {}
}

@(private)
configuration_validate_fallback :: proc(
	configuration: ^Configuration_Proposal,
	requested: Destination_ID,
) -> Failure {
	current := requested
	visited: [MAX_FALLBACK_DEPTH + 1]Destination_ID
	for depth in 0 ..= MAX_FALLBACK_DEPTH {
		index := configuration_destination_index(configuration, current)
		if index < 0 do return Failure{code = .Missing_Destination, destination = current}
		destination := configuration.destinations[index]
		for prior in visited[:depth] {
			if prior == current do return Failure{code = .Fallback_Cycle, destination = current}
		}
		visited[depth] = current
		if destination.fallback == Destination_ID(0) do return {}
		current = destination.fallback
	}
	return Failure{code = .Fallback_Depth, destination = requested, limit = MAX_FALLBACK_DEPTH}
}

@(private)
configuration_follow_fallback :: proc(
	configuration: ^Configuration_Proposal,
	requested: Destination_ID,
	frontend: Frontend_Context,
) -> (Destination, u8, Failure) {
	current := requested
	visited: [MAX_FALLBACK_DEPTH + 1]Destination_ID
	for depth in 0 ..= MAX_FALLBACK_DEPTH {
		index := configuration_destination_index(configuration, current)
		if index < 0 do return {}, 0, Failure{operation = .Resolve, code = .Missing_Destination, destination = current}
		destination := configuration.destinations[index]
		for prior in visited[:depth] {
			if prior == current do return {}, 0, Failure{operation = .Resolve, code = .Fallback_Cycle, destination = current}
		}
		visited[depth] = current
		if frontend.profile == ui.Renderer_Profile_ID(0) || destination_is_available(destination, frontend) {
			return destination, u8(depth), {}
		}
		if destination.fallback == Destination_ID(0) {
			return {}, 0, Failure{operation = .Resolve, code = .Unavailable_Destination, destination = destination.id}
		}
		current = destination.fallback
	}
	return {}, 0, Failure{operation = .Resolve, code = .Fallback_Depth, destination = requested, limit = MAX_FALLBACK_DEPTH}
}

@(private)
destination_is_available :: proc(destination: Destination, frontend: Frontend_Context) -> bool {
	if destination.required_capabilities & frontend.capabilities != destination.required_capabilities do return false
	if frontend.rows < u32(destination.minimum_rows) || frontend.columns < u32(destination.minimum_columns) do return false
	switch destination.kind {
	case .Status: return frontend.status_available
	case .Floating, .Anchored_Detail: return frontend.overlap_available
	case .History: return frontend.surface_available
	case .Diagnostic: return frontend.diagnostic_available
	case .Invalid: return false
	}
	return false
}

@(private)
resolution_has_destination :: proc(resolution: ^Resolution, requested: Destination_ID) -> bool {
	for item in resolution.destinations[:resolution.destination_count] {
		if item.requested == requested do return true
	}
	return false
}

@(private)
resolution_has_selected_destination :: proc(resolution: ^Resolution, selected: Destination_ID) -> bool {
	for item in resolution.destinations[:resolution.destination_count] {
		if item.selected == selected do return true
	}
	return false
}

@(private)
registry_state :: proc(registry: ^Registry) -> ^Registry_State {
	if registry == nil || registry.state == nil || registry.closed do return nil
	return cast(^Registry_State)registry.state
}

@(private)
registry_reject :: proc(state: ^Registry_State, failure: Failure) -> Failure {
	if state != nil do state.last_rejection = failure
	return failure
}
