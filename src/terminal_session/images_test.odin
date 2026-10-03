// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package terminal_session

import "core:testing"
import "../terminal_emulator"

/* Verifies decoded Kitty images project as bounded pointer-free placement metadata. */
@(test)
images_project_valid_replacement_and_malformed_payloads :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry)
	testing.expect(t, initialized)
	if !initialized do return
	defer if registry.state != nil do _, _ = registry_close(&registry)
	record, opened, _ := registry_open(
		&registry,
		test_open_request("images", arguments = []string{"-c", "sleep 30"}),
	)
	testing.expect(t, opened)
	if !opened do return

	transmit := transmute([]u8)(string(
		"\x1b_Ga=T,f=32,s=1,v=1,i=7,c=2,r=1;/////w==\x1b\\",
	))
	testing.expect_value(
		t, terminal_emulator.write(record.emulator, transmit), terminal_emulator.Result.OK,
	)
	revision, projected, project_failure := registry_project_render(&registry, record.ref)
	testing.expectf(t, projected, "image projection failed: %v", project_failure.code)
	if !projected do return
	testing.expect_value(t, revision.image_count, u64(1))
	testing.expect(t, !revision.images_truncated)
	testing.expect_value(t, revision.image_bytes, u64(4))
	images: [MAX_IMAGE_PLACEMENTS]Image_Placement
	count, copied, copy_failure := registry_copy_image_placements(
		&registry, record.ref, images[:],
	)
	testing.expectf(t, copied, "image copy failed: %v", copy_failure.code)
	if copied && count == 1 {
		testing.expect_value(t, images[0].image_id, u32(7))
		testing.expect_value(t, images[0].image_width, u32(1))
		testing.expect_value(t, images[0].image_height, u32(1))
		testing.expect(t, images[0].visible)
		testing.expect(t, !images[0].pending)
		testing.expect(t, !images[0].rejected)
	}

	first_generation := revision.image_generation
	replacement := transmute([]u8)(string(
		"\x1b_Ga=T,f=32,s=1,v=1,i=7,c=2,r=1;AAAA/w==\x1b\\",
	))
	testing.expect_value(
		t, terminal_emulator.write(record.emulator, replacement), terminal_emulator.Result.OK,
	)
	revision, projected, _ = registry_project_render(&registry, record.ref)
	testing.expect(t, projected)
	if projected do testing.expect(t, revision.image_generation > first_generation)

	malformed := transmute([]u8)(string("\x1b_Ga=T,f=32,s=2,v=2,i=9;bad\x1b\\"))
	testing.expect_value(
		t, terminal_emulator.write(record.emulator, malformed), terminal_emulator.Result.OK,
	)
	revision, projected, _ = registry_project_render(&registry, record.ref)
	testing.expect(t, projected)
	if projected do testing.expect_value(t, revision.image_count, u64(1))
}

/* Verifies excessive placement count is rejected and evicted at the adapter boundary. */
@(test)
images_reject_excess_placements_without_growing_projection :: proc(t: ^testing.T) {
	registry: Registry
	initialized, _ := registry_init(&registry)
	if !initialized do return
	defer if registry.state != nil do _, _ = registry_close(&registry)
	record, opened, _ := registry_open(
		&registry,
		test_open_request("image ceiling", arguments = []string{"-c", "sleep 30"}),
	)
	testing.expect(t, opened)
	if !opened do return
	commands := transmute([]u8)(string(
		"\x1b_Ga=T,f=32,s=1,v=1,i=1;/////w==\x1b\\" +
		"\x1b_Ga=T,f=32,s=1,v=1,i=2;/////w==\x1b\\" +
		"\x1b_Ga=T,f=32,s=1,v=1,i=3;/////w==\x1b\\" +
		"\x1b_Ga=T,f=32,s=1,v=1,i=4;/////w==\x1b\\" +
		"\x1b_Ga=T,f=32,s=1,v=1,i=5;/////w==\x1b\\" +
		"\x1b_Ga=T,f=32,s=1,v=1,i=6;/////w==\x1b\\" +
		"\x1b_Ga=T,f=32,s=1,v=1,i=7;/////w==\x1b\\" +
		"\x1b_Ga=T,f=32,s=1,v=1,i=8;/////w==\x1b\\" +
		"\x1b_Ga=T,f=32,s=1,v=1,i=9;/////w==\x1b\\",
	))
	testing.expect_value(
		t, terminal_emulator.write(record.emulator, commands), terminal_emulator.Result.OK,
	)
	revision, projected, project_failure := registry_project_render(&registry, record.ref)
	testing.expectf(t, projected, "bounded image projection failed: %v", project_failure.code)
	if !projected do return
	testing.expect_value(t, revision.image_count, u64(MAX_IMAGE_PLACEMENTS))
	testing.expect(t, revision.images_truncated)
	images: [MAX_IMAGE_PLACEMENTS]Image_Placement
	count, copied, _ := registry_copy_image_placements(&registry, record.ref, images[:])
	testing.expect(t, copied)
	if copied {
		testing.expect_value(t, count, MAX_IMAGE_PLACEMENTS)
		for image in images[:count] do testing.expect(t, image.rejected)
	}

	next: Render_Revision
	next, projected, _ = registry_project_render(&registry, record.ref)
	testing.expect(t, projected)
	if projected do testing.expect_value(t, next.image_count, u64(0))
}
