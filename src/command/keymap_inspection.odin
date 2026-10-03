// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../interaction"
import "base:runtime"

/* Keymap_Inspection_Request identifies one active-profile inspection operation. */
Keymap_Inspection_Request :: struct {
	registry:   ^interaction.Command_Registry,
	activation: ^interaction.Profile_Activation,
	pending:    ^interaction.Pending_State,
	query:      interaction.Inspection_Query,
	allocator:  runtime.Allocator,
}

/* keymap_inspection_run returns one copied result without exposing resolver storage. */
keymap_inspection_run :: proc(
	request: Keymap_Inspection_Request,
) -> (result: interaction.Inspection_Result, ok: bool, failure: Failure_Context) {
	if request.registry == nil || request.activation == nil || request.pending == nil ||
	   request.allocator.procedure == nil {
		return {}, false, Failure_Context{code = .Invalid_Command}
	}
	inspected: bool
	inspection_failure: interaction.Failure_Context
	result, inspected, inspection_failure = interaction.keymap_inspect(
		request.registry,
		request.activation,
		request.pending,
		request.query,
		request.allocator,
	)
	if !inspected {
		code := Failure_Code.Invalid_Command
		if inspection_failure.code == .Inspection_Limit {
			code = .Inspection_Limit
		}
		return {}, false, Failure_Context {
			code = code,
			interaction_code = inspection_failure.code,
			command = inspection_failure.command,
			limit = inspection_failure.limit,
			actual = inspection_failure.actual,
		}
	}
	return result, true, {}
}
