// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../interaction"

/* JAN_STRUCTURED_COMMAND_COUNT is the complete Stage 2 public command catalog. */
JAN_STRUCTURED_COMMAND_COUNT :: 88

/* jan_structured_command_definitions returns every public Stage 2 command identity. */
jan_structured_command_definitions :: proc() -> [JAN_STRUCTURED_COMMAND_COUNT]interaction.Command_Definition {
	return {
		jan_view_definition(.Jan_Cycle, "jan-cycle", "Cycle visibility at the current Jan structure."),
		jan_view_definition(.Jan_Toggle_Drawer, "jan-toggle-drawer", "Toggle the current Jan drawer body in this view."),
		jan_view_definition(.Jan_Global_Cycle, "jan-global-cycle", "Cycle global Jan document visibility."),
		jan_view_definition(.Jan_Show_Overview, "jan-show-overview", "Show the Jan outline overview."),
		jan_view_definition(.Jan_Show_Contents, "jan-show-contents", "Show Jan outline contents."),
		jan_view_definition(.Jan_Show_All, "jan-show-all", "Reveal the complete Jan document."),
		jan_view_definition(.Jan_Sparse_View, "jan-sparse-view", "Derive a bounded sparse Jan outline view."),
		jan_view_definition(.Jan_Next_Heading, "jan-next-heading", "Move to the next visible Jan heading."),
		jan_view_definition(.Jan_Previous_Heading, "jan-previous-heading", "Move to the previous visible Jan heading."),
		jan_view_definition(.Jan_Next_Same_Level_Heading, "jan-next-same-level-heading", "Move to the next same-level Jan heading."),
		jan_view_definition(.Jan_Previous_Same_Level_Heading, "jan-previous-same-level-heading", "Move to the previous same-level Jan heading."),
		jan_view_definition(.Jan_Parent_Heading, "jan-parent-heading", "Move to the parent Jan heading."),
		jan_view_definition(.Jan_First_Child_Heading, "jan-first-child-heading", "Move to the first child Jan heading."),
		jan_view_definition(.Jan_Subtree_Start, "jan-subtree-start", "Move to the current Jan subtree start."),
		jan_view_definition(.Jan_Subtree_End, "jan-subtree-end", "Move to the current Jan subtree end."),
		jan_view_definition(.Jan_Next_Structural_Element, "jan-next-structural-element", "Move to the next Jan structural element."),
		jan_view_definition(.Jan_Previous_Structural_Element, "jan-previous-structural-element", "Move to the previous Jan structural element."),
		jan_view_definition(.Jan_Next_List_Item, "jan-next-list-item", "Move to the next Jan list item."),
		jan_view_definition(.Jan_Previous_List_Item, "jan-previous-list-item", "Move to the previous Jan list item."),
		jan_view_definition(.Jan_Next_Table_Row, "jan-next-table-row", "Move to the next Jan table row."),
		jan_view_definition(.Jan_Previous_Table_Row, "jan-previous-table-row", "Move to the previous Jan table row."),
		jan_view_definition(.Jan_Next_Table_Cell, "jan-next-table-cell", "Move to the next Jan table cell."),
		jan_view_definition(.Jan_Previous_Table_Cell, "jan-previous-table-cell", "Move to the previous Jan table cell."),
		jan_view_definition(.Jan_Next_Drawer, "jan-next-drawer", "Move to the next Jan drawer."),
		jan_view_definition(.Jan_Previous_Drawer, "jan-previous-drawer", "Move to the previous Jan drawer."),
		jan_view_definition(.Jan_Next_Block, "jan-next-block", "Move to the next Jan block."),
		jan_view_definition(.Jan_Previous_Block, "jan-previous-block", "Move to the previous Jan block."),
		jan_view_definition(.Jan_Next_Footnote, "jan-next-footnote", "Move to the next Jan footnote."),
		jan_view_definition(.Jan_Previous_Footnote, "jan-previous-footnote", "Move to the previous Jan footnote."),
		jan_edit_definition(.Jan_Insert_Heading_Before, "jan-insert-heading-before", "Insert a sibling heading before the current heading."),
		jan_edit_definition(.Jan_Insert_Heading_After, "jan-insert-heading-after", "Insert a sibling heading after the current heading."),
		jan_edit_definition(.Jan_Insert_Heading_Below, "jan-insert-heading-below", "Insert a child heading below the current heading."),
		jan_edit_definition(.Jan_Split_Heading, "jan-split-heading", "Split the current Jan heading at point."),
		jan_edit_definition(.Jan_Promote_Heading, "jan-promote-heading", "Promote the current Jan heading and descendants."),
		jan_edit_definition(.Jan_Demote_Heading, "jan-demote-heading", "Demote the current Jan heading and descendants."),
		jan_edit_definition(.Jan_Move_Subtree_Up, "jan-move-subtree-up", "Move the current Jan subtree before its sibling."),
		jan_edit_definition(.Jan_Move_Subtree_Down, "jan-move-subtree-down", "Move the current Jan subtree after its sibling."),
		jan_edit_definition(.Jan_Clone_Subtree, "jan-clone-subtree", "Clone the current Jan subtree."),
		jan_edit_definition(.Jan_Kill_Subtree, "jan-kill-subtree", "Delete the current complete Jan subtree."),
		jan_edit_definition(.Jan_Sort_Child_Headings, "jan-sort-child-headings", "Sort direct child headings by source key."),
		jan_edit_definition(.Jan_Heading_To_List_Item, "jan-heading-to-list-item", "Convert the current leaf heading to a list item."),
		jan_edit_definition(.Jan_List_Item_To_Heading, "jan-list-item-to-heading", "Convert the current list item to a heading."),
		jan_edit_definition(.Jan_Insert_List_Item_Before, "jan-insert-list-item-before", "Insert a Jan list item before the current item."),
		jan_edit_definition(.Jan_Insert_List_Item_After, "jan-insert-list-item-after", "Insert a Jan list item after the current item."),
		jan_edit_definition(.Jan_Delete_List_Item, "jan-delete-list-item", "Delete the current complete Jan list item."),
		jan_edit_definition(.Jan_Promote_List_Item, "jan-promote-list-item", "Promote the current Jan list item."),
		jan_edit_definition(.Jan_Demote_List_Item, "jan-demote-list-item", "Demote the current Jan list item."),
		jan_edit_definition(.Jan_Move_List_Item_Up, "jan-move-list-item-up", "Move the current Jan list item up."),
		jan_edit_definition(.Jan_Move_List_Item_Down, "jan-move-list-item-down", "Move the current Jan list item down."),
		jan_edit_definition(.Jan_Duplicate_List_Item, "jan-duplicate-list-item", "Duplicate the current Jan list item."),
		jan_edit_definition(.Jan_Sort_List_Items, "jan-sort-list-items", "Sort sibling Jan list items by source key."),
		jan_edit_definition(.Jan_Cycle_List_Bullet, "jan-cycle-list-bullet", "Cycle the current Jan list bullet."),
		jan_edit_definition(.Jan_Repair_List_Indentation, "jan-repair-list-indentation", "Repair indentation for the current Jan list item."),
		jan_edit_definition(.Jan_Insert_Drawer, "jan-insert-drawer", "Insert a complete Jan drawer."),
		jan_edit_definition(.Jan_Insert_Block, "jan-insert-block", "Insert a complete Jan source block."),
		jan_view_definition(.Jan_Select_Structure, "jan-select-structure", "Select the current complete Jan drawer or block."),
		jan_edit_definition(.Jan_Move_Structure_Up, "jan-move-structure-up", "Move the current Jan drawer or block up."),
		jan_edit_definition(.Jan_Move_Structure_Down, "jan-move-structure-down", "Move the current Jan drawer or block down."),
		jan_edit_definition(.Jan_Delete_Structure, "jan-delete-structure", "Delete the current complete Jan drawer or block."),
		jan_edit_definition(.Jan_Create_Table, "jan-create-table", "Create a bounded Jan table."),
		jan_edit_definition(.Jan_Align_Table, "jan-align-table", "Align the current Jan table source."),
		jan_edit_definition(.Jan_Insert_Table_Row, "jan-insert-table-row", "Insert a row after the current Jan table row."),
		jan_edit_definition(.Jan_Delete_Table_Row, "jan-delete-table-row", "Delete the current Jan table row."),
		jan_edit_definition(.Jan_Move_Table_Row_Up, "jan-move-table-row-up", "Move the current Jan table row up."),
		jan_edit_definition(.Jan_Move_Table_Row_Down, "jan-move-table-row-down", "Move the current Jan table row down."),
		jan_edit_definition(.Jan_Duplicate_Table_Row, "jan-duplicate-table-row", "Duplicate the current Jan table row."),
		jan_edit_definition(.Jan_Insert_Table_Column, "jan-insert-table-column", "Insert a column after the current Jan table cell."),
		jan_edit_definition(.Jan_Delete_Table_Column, "jan-delete-table-column", "Delete the current Jan table column."),
		jan_edit_definition(.Jan_Move_Table_Column_Left, "jan-move-table-column-left", "Move the current Jan table column left."),
		jan_edit_definition(.Jan_Move_Table_Column_Right, "jan-move-table-column-right", "Move the current Jan table column right."),
		jan_edit_definition(.Jan_Duplicate_Table_Column, "jan-duplicate-table-column", "Duplicate the current Jan table column."),
		jan_edit_definition(.Jan_Insert_Table_Separator, "jan-insert-table-separator", "Insert a separator after the current Jan table row."),
		jan_edit_definition(.Jan_Delete_Table_Separator, "jan-delete-table-separator", "Delete the current Jan table separator."),
		jan_edit_definition(.Jan_Edit_Table_Cell, "jan-edit-table-cell", "Edit the current Jan table cell as canonical source."),
		jan_view_definition(.Jan_Visit_Footnote, "jan-visit-footnote", "Visit the matching local Jan footnote."),
		jan_edit_definition(.Jan_Create_Footnote, "jan-create-footnote", "Create a local Jan footnote definition."),
		jan_edit_definition(.Jan_Normalize_Footnote, "jan-normalize-footnote", "Normalize the current Jan footnote form."),
		jan_edit_definition(.Jan_Renumber_Footnotes, "jan-renumber-footnotes", "Renumber local Jan footnotes."),
		jan_edit_definition(.Jan_Move_Footnote_Up, "jan-move-footnote-up", "Move the current Jan footnote definition up."),
		jan_edit_definition(.Jan_Move_Footnote_Down, "jan-move-footnote-down", "Move the current Jan footnote definition down."),
		jan_view_definition(.Jan_Complete, "jan-complete", "Present bounded Jan completion candidates."),
		jan_edit_definition(.Jan_Expand_Template, "jan-expand-template", "Expand a factory Jan structure template."),
		jan_edit_definition(.Jan_Indent, "jan-indent", "Apply explicit Jan source indentation."),
		jan_edit_definition(.Jan_Context_Action, "jan-context-action", "Invoke the deterministic Jan action at point."),
		jan_view_definition(.Jan_Repeat, "jan-repeat", "Repeat the latest Jan semantic action on a fresh target."),
		jan_view_definition(.Jan_Present, "jan-present", "Refresh rich Jan source presentation."),
		jan_view_definition(.Jan_Request_Preview, "jan-request-preview", "Request a bounded Jan preview or source fallback."),
		jan_view_definition(.Jan_Inspect_Availability, "jan-inspect-availability", "Inspect operational and later-stage Jan capabilities."),
	}
}

@(private)
jan_view_definition :: proc(route: Native_Route, name, description: string) -> interaction.Command_Definition {
	return native_definition(route, name, {.View, .Lifecycle}, description)
}

@(private)
jan_edit_definition :: proc(route: Native_Route, name, description: string) -> interaction.Command_Definition {
	return native_definition(route, name, {.Buffer, .View, .Lifecycle, .Text_Mutation}, description)
}
