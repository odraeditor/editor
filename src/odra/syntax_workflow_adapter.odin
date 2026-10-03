// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package main

import syntax_workflow "../syntax_workflow"

@(private)
Syntax_Workflow_State :: syntax_workflow.Workflow_State

@(private)
Syntax_Analysis_Entry :: syntax_workflow.Analysis_Entry

@(private)
Syntax_Commit_Observer_Context :: syntax_workflow.Commit_Observer_Context

syntax_workflow_init :: syntax_workflow.Syntax_Workflow_Init

syntax_workflow_reconcile :: syntax_workflow.Syntax_Workflow_Reconcile

syntax_workflow_maintain :: syntax_workflow.Syntax_Workflow_Maintain

syntax_workflow_project_visible :: syntax_workflow.Syntax_Workflow_Project_Visible

syntax_workflow_close :: syntax_workflow.Syntax_Workflow_Close

syntax_workflow_find_buffer :: syntax_workflow.Syntax_Workflow_Find_Buffer

syntax_workflow_inspect_buffer :: syntax_workflow.Syntax_Workflow_Inspect_Buffer

syntax_workflow_structural_context :: syntax_workflow.Syntax_Workflow_Structural_Context

syntax_workflow_symbol_at_point :: syntax_workflow.Syntax_Workflow_Symbol_At_Point

syntax_workflow_symbol_index :: syntax_workflow.Syntax_Workflow_Symbol_Index

syntax_workflow_commit_observer :: syntax_workflow.Syntax_Workflow_Commit_Observer

syntax_workflow_entry_language_association :: syntax_workflow.Syntax_Workflow_Entry_Language_Association

syntax_workflow_is_live :: syntax_workflow.Syntax_Workflow_Is_Live
