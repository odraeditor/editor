// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package pane_buffer_reference

import "core:testing"

/* Ensures pane-local history wins and final closure creates one scratch buffer. */
@(test)
model_uses_history_and_final_scratch :: proc(t: ^testing.T) {
	model := model_init()
	second, second_ok := model_create(&model)
	third, third_ok := model_create(&model)
	model_replace(&model, second)
	model_replace(&model, 1)
	model_split(&model)
	model_focus(&model, 1)
	model_replace(&model, third)
	model_replace(&model, 1)
	killed := model_kill(&model, 1)
	testing.expect(t, second_ok && third_ok && killed)
	testing.expect_value(t, model.panes[0].current, second)
	testing.expect_value(t, model.panes[1].current, third)
	model_kill(&model, second)
	model_kill(&model, third)
	testing.expect(t, model_validate(&model))
	testing.expect_value(t, model.pane_count, 2)
	testing.expect(t, model.panes[0].current == model.panes[1].current)
}

/* Exercises generated pane-buffer traces against ownership invariants. */
@(test)
generated_trace_keeps_invariants :: proc(t: ^testing.T) {
	model := model_init()
	for _ in 0 ..< 6 {
		model_create(&model)
	}
	seed := u64(0x510e527fade682d1)
	for step in 0 ..< 1_024 {
		seed = seed * 6_364_136_223_846_793_005 + 1_442_695_040_888_963_407
		switch seed % 5 {
		case 0:
			if model.pane_count < MAX_PANES {
				model_split(&model)
			}
		case 1:
			model_focus(&model, int((seed >> 16) % u64(model.pane_count)))
		case 2, 3:
			live: [MAX_BUFFERS]int
			count: int
			for buffer, index in model.live_buffers {
				if buffer && index > 0 {
					live[count] = index
					count += 1
				}
			}
			model_replace(&model, live[int((seed >> 24) % u64(count))])
		case 4:
			if step % 41 == 0 {
				candidate := model.panes[model.active].current
				model_kill(&model, candidate)
			}
		}
		testing.expectf(t, model_validate(&model), "invalid generated state at step %d", step)
	}
}
