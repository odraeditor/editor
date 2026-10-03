// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package language_service_workflow

import syntax_workflow "../syntax_workflow"

@(private)
Syntax_Workflow_State :: syntax_workflow.Workflow_State

syntax_workflow_init :: syntax_workflow.Syntax_Workflow_Init
syntax_workflow_reconcile :: syntax_workflow.Syntax_Workflow_Reconcile
syntax_workflow_close :: syntax_workflow.Syntax_Workflow_Close
syntax_workflow_entry_language_association :: syntax_workflow.Syntax_Workflow_Entry_Language_Association
syntax_workflow_is_live :: syntax_workflow.Syntax_Workflow_Is_Live
