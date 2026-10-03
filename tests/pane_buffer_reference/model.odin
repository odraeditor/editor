// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package pane_buffer_reference

MAX_PANES :: 8
MAX_BUFFERS :: 16
MAX_HISTORY :: 4

Pane :: struct {
	live:          bool,
	current:       int,
	history:       [MAX_HISTORY]int,
	history_count: int,
}

Model :: struct {
	panes:             [MAX_PANES]Pane,
	pane_count:        int,
	active:            int,
	live_buffers:      [MAX_BUFFERS]bool,
	next_buffer:       int,
	buffer_list:       [MAX_BUFFERS]int,
	buffer_list_count: int,
}

model_init :: proc() -> Model {
	model: Model
	model.panes[0] = Pane{live = true, current = 1}
	model.pane_count = 1
	model.live_buffers[1] = true
	model.next_buffer = 2
	model_touch_history(&model.panes[0], 1)
	model_touch_list(&model, 1)
	assert(model_validate(&model))
	return model
}

model_create :: proc(model: ^Model) -> (int, bool) {
	if model == nil || model.next_buffer >= MAX_BUFFERS {
		return 0, false
	}
	buffer := model.next_buffer
	model.next_buffer += 1
	model.live_buffers[buffer] = true
	model_touch_list(model, buffer)
	return buffer, model_validate(model)
}

model_replace :: proc(model: ^Model, buffer: int) -> bool {
	if !model_validate(model) || buffer <= 0 || buffer >= MAX_BUFFERS ||
	   !model.live_buffers[buffer] {
		return false
	}
	pane := &model.panes[model.active]
	model_touch_history(pane, pane.current)
	pane.current = buffer
	model_touch_history(pane, buffer)
	model_touch_list(model, buffer)
	return model_validate(model)
}

model_split :: proc(model: ^Model) -> bool {
	if !model_validate(model) || model.pane_count >= MAX_PANES {
		return false
	}
	created := model.pane_count
	model.panes[created] = model.panes[model.active]
	model.panes[created].live = true
	model.pane_count += 1
	return model_validate(model)
}

model_focus :: proc(model: ^Model, pane: int) -> bool {
	if !model_validate(model) || pane < 0 || pane >= model.pane_count || !model.panes[pane].live {
		return false
	}
	model.active = pane
	return model_validate(model)
}

model_kill :: proc(model: ^Model, buffer: int) -> bool {
	if !model_validate(model) || buffer <= 0 || buffer >= MAX_BUFFERS ||
	   !model.live_buffers[buffer] {
		return false
	}
	remaining := false
	for live, index in model.live_buffers {
		if live && index != buffer {
			remaining = true
			break
		}
	}
	if !remaining {
		_, created := model_create(model)
		if !created {
			return false
		}
	}
	model.live_buffers[buffer] = false
	for &pane in model.panes[:model.pane_count] {
		if pane.current == buffer {
			fallback, found := model_pane_fallback(model, &pane, buffer)
			if !found {
				return false
			}
			pane.current = fallback
			model_touch_history(&pane, fallback)
		}
		model_purge_history(&pane, buffer)
	}
	model_purge_list(model, buffer)
	return model_validate(model)
}

model_validate :: proc(model: ^Model) -> bool {
	if model == nil || model.pane_count <= 0 || model.pane_count > MAX_PANES ||
	   model.active < 0 || model.active >= model.pane_count ||
	   model.buffer_list_count <= 0 || model.buffer_list_count >= MAX_BUFFERS {
		return false
	}
	for &pane, pane_index in model.panes {
		if pane_index < model.pane_count {
			if !pane.live || pane.current <= 0 || pane.current >= MAX_BUFFERS ||
			   !model.live_buffers[pane.current] || pane.history_count <= 0 ||
			   pane.history_count > MAX_HISTORY {
				return false
			}
			for buffer, index in pane.history[:pane.history_count] {
				if buffer <= 0 || buffer >= MAX_BUFFERS || !model.live_buffers[buffer] {
					return false
				}
				for previous in pane.history[:index] {
					if previous == buffer {
						return false
					}
				}
			}
		} else if pane.live {
			return false
		}
	}
	for buffer, index in model.buffer_list[:model.buffer_list_count] {
		if buffer <= 0 || buffer >= MAX_BUFFERS || !model.live_buffers[buffer] {
			return false
		}
		for previous in model.buffer_list[:index] {
			if previous == buffer {
				return false
			}
		}
	}
	return true
}

@(private)
model_pane_fallback :: proc(model: ^Model, pane: ^Pane, killed: int) -> (int, bool) {
	for candidate in pane.history[:pane.history_count] {
		if candidate != killed && model.live_buffers[candidate] {
			return candidate, true
		}
	}
	for candidate in model.buffer_list[:model.buffer_list_count] {
		if candidate != killed && model.live_buffers[candidate] {
			return candidate, true
		}
	}
	return 0, false
}

@(private)
model_touch_history :: proc(pane: ^Pane, buffer: int) {
	index := pane.history_count
	for candidate, candidate_index in pane.history[:pane.history_count] {
		if candidate == buffer {
			index = candidate_index
			break
		}
	}
	if index == pane.history_count && pane.history_count < MAX_HISTORY {
		pane.history_count += 1
	}
	if index >= MAX_HISTORY {
		index = MAX_HISTORY - 1
	}
	for index > 0 {
		pane.history[index] = pane.history[index - 1]
		index -= 1
	}
	pane.history[0] = buffer
}

@(private)
model_touch_list :: proc(model: ^Model, buffer: int) {
	index := model.buffer_list_count
	for candidate, candidate_index in model.buffer_list[:model.buffer_list_count] {
		if candidate == buffer {
			index = candidate_index
			break
		}
	}
	if index == model.buffer_list_count {
		model.buffer_list_count += 1
	}
	for index > 0 {
		model.buffer_list[index] = model.buffer_list[index - 1]
		index -= 1
	}
	model.buffer_list[0] = buffer
}

@(private)
model_purge_history :: proc(pane: ^Pane, killed: int) {
	write: int
	for candidate in pane.history[:pane.history_count] {
		if candidate != killed {
			pane.history[write] = candidate
			write += 1
		}
	}
	for index in write ..< pane.history_count {
		pane.history[index] = 0
	}
	pane.history_count = write
}

@(private)
model_purge_list :: proc(model: ^Model, killed: int) {
	write: int
	for candidate in model.buffer_list[:model.buffer_list_count] {
		if candidate != killed {
			model.buffer_list[write] = candidate
			write += 1
		}
	}
	for index in write ..< model.buffer_list_count {
		model.buffer_list[index] = 0
	}
	model.buffer_list_count = write
}
