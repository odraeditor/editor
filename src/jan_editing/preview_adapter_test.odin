// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package jan_editing

import "../language"
import "core:testing"

/* Verifies factory capabilities admit asynchronous copied LaTeX results. */
@(test)
preview_adapters_publish_exact_copied_results :: proc(t: ^testing.T) {
	source := "Formula $x+y$ remains source.\n"
	fixture: List_Test_Fixture
	if !list_test_fixture_open(t, &fixture, source, 2_301) do return
	defer list_test_fixture_close(&fixture)
	target, found := list_test_node(&fixture.analysis, .Latex_Fragment, 0)
	testing.expect(t, found)
	if !found do return
	adapter := preview_factory_adapter(.Latex, fixture.scope.provider_generation)
	capability, inspected := preview_adapter_capability(adapter)
	testing.expect(t, inspected)
	testing.expect_value(t, capability.class, language.Jan_Availability_Class.Factory_Adapter)
	testing.expect(t, !capability.requires_resource_admission)
	cache: Preview_Cache
	initialized, init_failure := preview_cache_init(&cache, 1)
	testing.expectf(t, initialized, "preview cache init failed with %v", init_failure.code)
	if !initialized do return
	defer preview_cache_close(&cache)
	request := preview_test_request(fixture.scope, target, .Latex, adapter, 1)
	descriptor, begun, begin_failure := preview_request_begin(
		&cache,
		&fixture.analysis,
		transmute([]u8)source,
		request,
	)
	testing.expectf(t, begun, "preview request failed with %v", begin_failure.code)
	testing.expect_value(t, descriptor.status, Preview_Status.Pending)
	result := []u8{1, 2, 3, 4}
	published: bool
	publish_failure: Failure
	descriptor, published, publish_failure = preview_result_publish(
		&cache,
		request.request_id,
		fixture.scope,
		adapter.generation,
		0,
		result,
	)
	testing.expectf(t, published, "preview result failed with %v", publish_failure.code)
	testing.expect_value(t, descriptor.status, Preview_Status.Ready)
	testing.expect(t, !descriptor.source_visible)
	copied, available := preview_cache_result(&cache, request.request_id)
	testing.expect(t, available)
	testing.expect_value(t, len(copied), len(result))
	result[0] = 9
	testing.expect_value(t, copied[0], u8(1))
	testing.expect(t, list_test_buffer_matches(&fixture.buffer, source))
}

/* Verifies unsupported surfaces and missing adapters retain source fallback. */
@(test)
preview_adapters_fall_back_without_blocking_editing :: proc(t: ^testing.T) {
	source := "Formula $x+y$.\n"
	fixture: List_Test_Fixture
	if !list_test_fixture_open(t, &fixture, source, 2_302) do return
	defer list_test_fixture_close(&fixture)
	target, found := list_test_node(&fixture.analysis, .Latex_Fragment, 0)
	testing.expect(t, found)
	if !found do return
	cache: Preview_Cache
	initialized, _ := preview_cache_init(&cache, 2)
	testing.expect(t, initialized)
	if !initialized do return
	defer preview_cache_close(&cache)
	adapter := preview_factory_adapter(.Latex, fixture.scope.provider_generation)
	request := preview_test_request(fixture.scope, target, .Latex, adapter, 2)
	request.surface_supported = false
	descriptor, begun, failure := preview_request_begin(
		&cache,
		&fixture.analysis,
		transmute([]u8)source,
		request,
	)
	testing.expectf(t, begun, "fallback request failed with %v", failure.code)
	testing.expect_value(t, descriptor.status, Preview_Status.Source_Fallback)
	testing.expect(t, descriptor.source_visible)
	cache_descriptor, described := preview_cache_descriptor(&cache)
	testing.expect(t, described)
	testing.expect_value(t, cache_descriptor.entries, u32(0))
}

/* Verifies image authority and asynchronous identities reject safely. */
@(test)
preview_adapters_require_image_admission_and_reject_stale_results :: proc(t: ^testing.T) {
	source := "Image [[file:diagram.png]].\n"
	fixture: List_Test_Fixture
	if !list_test_fixture_open(t, &fixture, source, 2_303) do return
	defer list_test_fixture_close(&fixture)
	target, found := list_test_node(&fixture.analysis, .Regular_Link, 0)
	testing.expect(t, found)
	if !found do return
	adapter := preview_factory_adapter(.Image, fixture.scope.provider_generation)
	capability, inspected := preview_adapter_capability(adapter)
	testing.expect(t, inspected && capability.requires_resource_admission)
	cache: Preview_Cache
	initialized, _ := preview_cache_init(&cache, 3)
	testing.expect(t, initialized)
	if !initialized do return
	defer preview_cache_close(&cache)
	request := preview_test_request(fixture.scope, target, .Image, adapter, 3)
	request.resource_generation = 7
	_, begun, failure := preview_request_begin(
		&cache,
		&fixture.analysis,
		transmute([]u8)source,
		request,
	)
	testing.expect(t, !begun)
	testing.expect_value(t, failure.code, Failure_Code.Unavailable)
	request.resource_admitted = true
	_, begun, failure = preview_request_begin(
		&cache,
		&fixture.analysis,
		transmute([]u8)source,
		request,
	)
	testing.expectf(t, begun, "admitted image request failed with %v", failure.code)
	stale := fixture.scope
	stale.analysis.source_revision += 1
	descriptor, published, publish_failure := preview_result_publish(
		&cache,
		request.request_id,
		stale,
		adapter.generation,
		7,
		[]u8{1},
	)
	testing.expect(t, !published)
	testing.expect_value(t, publish_failure.code, Failure_Code.Stale)
	testing.expect_value(t, descriptor.status, Preview_Status.Source_Fallback)
	testing.expect(t, descriptor.source_visible)
}

/* Verifies bounded result publication evicts the oldest copied preview. */
@(test)
preview_cache_evicts_oldest_ready_result :: proc(t: ^testing.T) {
	source := "Formula $x+y$.\n"
	fixture: List_Test_Fixture
	if !list_test_fixture_open(t, &fixture, source, 2_304) do return
	defer list_test_fixture_close(&fixture)
	target, found := list_test_node(&fixture.analysis, .Latex_Fragment, 0)
	testing.expect(t, found)
	if !found do return
	limits := DEFAULT_LIMITS
	limits.preview_result_bytes = 4
	limits.preview_cache_bytes = 6
	cache: Preview_Cache
	initialized, _ := preview_cache_init(&cache, 4, limits)
	testing.expect(t, initialized)
	if !initialized do return
	defer preview_cache_close(&cache)
	adapter := preview_factory_adapter(.Latex, fixture.scope.provider_generation)
	for request_id in Preview_Request_ID(10) ..= Preview_Request_ID(11) {
		request := preview_test_request(fixture.scope, target, .Latex, adapter, request_id)
		_, begun, _ := preview_request_begin(&cache, &fixture.analysis, transmute([]u8)source, request)
		testing.expect(t, begun)
		_, published, failure := preview_result_publish(
			&cache,
			request_id,
			fixture.scope,
			adapter.generation,
			0,
			[]u8{1, 2, 3, 4},
		)
		testing.expectf(t, published, "bounded result failed with %v", failure.code)
	}
	_, oldest_present := preview_cache_inspect(&cache, 10)
	_, newest_present := preview_cache_inspect(&cache, 11)
	testing.expect(t, !oldest_present && newest_present)
	descriptor, described := preview_cache_descriptor(&cache)
	testing.expect(t, described)
	testing.expect_value(t, descriptor.ready, u32(1))
}

@(private)
preview_test_request :: proc(
	scope: Scope,
	target: language.Jan_Node_Record,
	kind: Preview_Kind,
	adapter: Preview_Adapter_Handle,
	request_id: Preview_Request_ID,
) -> Preview_Request {
	return {
		request_id = request_id,
		operation_id = Operation_ID(request_id),
		scope = scope,
		target_id = target.id,
		range = target.range,
		kind = kind,
		adapter = adapter,
		surface_supported = true,
	}
}
