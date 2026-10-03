// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package syntax_workflow

// Workflow_State owns language recognition, syntax-provider selection, and
// retained Odin and Jan analysis for the active editor session.
Workflow_State :: Syntax_Workflow_State

// Analysis_Entry is a borrowed workflow entry used by application adapters.
Analysis_Entry :: Syntax_Analysis_Entry

// Commit_Observer_Context binds an editor commit to retained syntax state.
Commit_Observer_Context :: Syntax_Commit_Observer_Context
