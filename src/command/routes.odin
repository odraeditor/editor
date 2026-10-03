// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

package command

import "../bridge"
import "../interaction"
import "base:runtime"

/* NATIVE_ROUTE_PROVIDER identifies the Odin editor command provider. */
NATIVE_ROUTE_PROVIDER :: interaction.Command_Provider_ID(1)
/* CONTEXTUAL_ROUTE_PROVIDER identifies the prompt and component provider. */
CONTEXTUAL_ROUTE_PROVIDER :: interaction.Command_Provider_ID(2)
/* RACKET_INSPECTION_ROUTE_PROVIDER identifies the Racket inspection provider. */
RACKET_INSPECTION_ROUTE_PROVIDER :: bridge.RACKET_INSPECTION_COMMAND_PROVIDER_ID
/* RACKET_RUNTIME_ROUTE_PROVIDER identifies the executable Racket command provider. */
RACKET_RUNTIME_ROUTE_PROVIDER :: bridge.RACKET_TRANSACTION_COMMAND_PROVIDER_ID
/* RACKET_PERSONAL_ROUTE_PROVIDER identifies generation-bound personal commands. */
RACKET_PERSONAL_ROUTE_PROVIDER :: bridge.RACKET_PERSONAL_COMMAND_PROVIDER_ID
/* RACKET_KSAWERY_ROUTE_PROVIDER identifies admitted programmable repository commands. */
RACKET_KSAWERY_ROUTE_PROVIDER :: interaction.Command_Provider_ID(6)

/* Native_Route identifies one Odin-owned editor command implementation. */
Native_Route :: enum u16 {
	Invalid,
	Cursor_Previous_Grapheme,
	Cursor_Next_Grapheme,
	Cursor_Previous_Line,
	Cursor_Next_Line,
	Cursor_Line_Start,
	Cursor_Line_End,
	ISearch_Forward,
	ISearch_Backward,
	ISearch_Forward_Regexp,
	ISearch_Backward_Regexp,
	Search_Symbol_At_Point,
	Search_Word,
	Occur,
	Highlight_Symbol_At_Point,
	Highlight_Phrase,
	Highlight_Regexp,
	Highlight_Lines,
	Highlight_Remove,
	Query_Replace,
	Query_Replace_Regexp,
	Replace_String,
	Replace_Regexp,
	Insert_Text,
	Insert_Text_After_Point,
	Delete_Previous_Grapheme,
	Delete_Next_Grapheme,
	Insert_Line_Break,
	Undo,
	Redo,
	Save_Associated_Document,
	Set_Mark,
	Deactivate_Mark,
	Exchange_Point_And_Mark,
	Copy_Region,
	Kill_Region,
	Kill_Line,
	Backward_Kill_Word,
	Kill_Word,
	Delete_Region,
	Delete_Blank_Lines,
	Fill_Paragraph,
	Transpose_Words,
	Upcase_Word,
	Downcase_Word,
	Capitalize_Word,
	Comment_Dwim,
	Dynamic_Abbrev_Expand,
	Yank,
	Yank_After_Point,
	Yank_Pop,
	Replace_Region_Text,
	Select_Rectangle,
	Copy_Rectangle,
	Kill_Rectangle,
	Replace_Rectangle_Text,
	Indent_Lines,
	Outdent_Lines,
	Indent_Rigidly,
	Rigid_Indent_Right,
	Rigid_Indent_Left,
	Rigid_Indent_Right_Fast,
	Rigid_Indent_Left_Fast,
	Find_File,
	Switch_To_Buffer,
	Find_File_Other_Pane,
	Switch_To_Buffer_Other_Pane,
	Display_Buffer_Other_Pane,
	Kill_Buffer,
	List_Buffers,
	Reload_Interaction_Profile,
	Reload_Personal_Commands,
	Execute_Extended_Command,
	Select_Interaction_Profile,
	Modal_Enter_Insert,
	Modal_Enter_Insert_After,
	Modal_Enter_Replace,
	Modal_Enter_Normal,
	Modal_Repeat_Last_Change,
	Describe_Modal_Repeat,
	Start_Keyboard_Macro,
	End_Keyboard_Macro,
	Call_Last_Keyboard_Macro,
	Finish_Or_Call_Keyboard_Macro,
	Name_Last_Keyboard_Macro,
	Call_Named_Keyboard_Macro,
	Select_Theme,
	Describe_Theme,
	Keyboard_Quit,
	Dir_Open,
	Project_Inspect_Active,
	Project_Promote,
	Project_Unregister,
	Project_Find_File,
	Project_Switch_Buffer,
	Project_Save_Buffers,
	Project_Close_Buffers,
	Project_Refresh,
	Project_Command_Menu,
	Describe_Project_Bindings,
	Recover_Unsaved_Work,
	Describe_Language_State,
	Structural_Forward,
	Structural_Backward,
	Structural_Up,
	Structural_Down,
	Structural_Select,
	Structural_Indent,
	Split_Pane_Below,
	Split_Pane_Right,
	Close_Pane,
	Keep_Only_Pane,
	Focus_Next_Pane,
	Enlarge_Pane_Vertically,
	Enlarge_Pane_Horizontally,
	Shrink_Pane_Horizontally,
	Balance_Panes,
	Balance_Pane_Areas,
	Request_Editor_Exit,
	Describe_Structural_State,
	List_Language_Diagnostics,
	Next_Language_Diagnostic,
	Previous_Language_Diagnostic,
	Describe_Language_Support,
	Describe_Language_Service,
	Restart_Language_Service,
	Workspace_Add_Project,
	Workspace_Remove_Project,
	Workspace_Unregister,
	Cursor_Previous_Word,
	Cursor_Next_Word,
	Cursor_Line_First_Non_Whitespace,
	Toggle_Overwrite_Mode,
	Scroll_Previous_Page,
	Scroll_Next_Page,
	Recenter,
	Help_About_Help,
	Apropos_Command,
	Info,
	Describe_Function,
	Describe_Variable,
	Describe_Syntax_Table,
	Open_Tutorial,
	Select_Word,
	Select_Paragraph,
	Select_Buffer,
	Select_Definition,
	Narrow_To_Region,
	Narrow_To_Definition,
	Widen,
	Pop_Selection_Location,
	Save_Location,
	List_Locations,
	Visit_Location,
	Store_Number,
	Increment_Number,
	Store_Text,
	Store_Region_Text,
	Store_Position,
	Insert_Slot,
	Store_Layout,
	Visit_Slot,
	Restore_Layout,
	Next_Location,
	Previous_Location,
	Symbol_Navigator,
	Project_Search_Text,
	Project_Search_Text_Regexp,
	Project_Search_Repeat,
	Status_Bar_Inspect,
	Status_Bar_Actions,
	Status_Bar_Activate_Segment,
	Gutter_Toggle_Line_Numbers,
	Gutter_Cycle_Line_Number_Mode,
	Gutter_Set_Line_Numbers_None,
	Gutter_Set_Line_Numbers_Absolute,
	Gutter_Set_Line_Numbers_Relative,
	Gutter_Set_Line_Numbers_Hybrid,
	Gutter_Set_Numbering_Logical,
	Gutter_Set_Numbering_Visual,
	Gutter_Toggle_Line_Number_Side,
	Gutter_Inspect_Numbering,
	Maksym_Open_Directory,
	Maksym_Open_Directory_Other_Pane,
	Maksym_Open_Directory_Below,
	Maksym_Open_Directory_Right,
	Maksym_Open_Containing_Directory,
	Maksym_Open_Containing_Directory_Other_Pane,
	Maksym_Next_Entry,
	Maksym_Previous_Entry,
	Maksym_Parent_Directory,
	Maksym_Jump_To_Entry,
	Maksym_Open_Entry,
	Maksym_Open_Entry_Other_Pane,
	Maksym_Display_Entry_Other_Pane,
	Maksym_Refresh,
	Maksym_Toggle_Details,
	Maksym_Cycle_Sort,
	Maksym_Toggle_Editable_Listing,
	Maksym_Apply_Editable_Listing,
	Maksym_Cancel_Editable_Listing,
	Maksym_Editable_Next_Line,
	Maksym_Editable_Previous_Line,
	Darek_Toggle,
	Darek_Select,
	Darek_Focus_Toggle,
	Darek_Show_Directory,
	Darek_Find_Current_File,
	Darek_Show_Current_Project,
	Darek_Next_Node,
	Darek_Previous_Node,
	Darek_Next_Sibling,
	Darek_Previous_Sibling,
	Darek_Next_Project,
	Darek_Previous_Project,
	Darek_Move_Project_Up,
	Darek_Move_Project_Down,
	Darek_Project_Add,
	Darek_Project_Remove,
	Darek_Project_Rename,
	Darek_Project_Collapse,
	Darek_Project_Collapse_Others,
	Darek_Workspace_Switch,
	Darek_Workspace_Next,
	Darek_Root_Parent,
	Darek_Root_Current_Directory,
	Darek_Parent_Node,
	Darek_Structure_Action,
	Darek_Visit_Action,
	Darek_Open,
	Darek_Open_Split_Below,
	Darek_Open_Split_Right,
	Darek_Open_And_Hide,
	Darek_Open_Mru_Pane,
	Darek_Open_External,
	Darek_Create_File,
	Darek_Create_Directory,
	Darek_Rename_Node,
	Darek_Move_Node,
	Darek_Copy_Node,
	Darek_Delete_Node,
	Darek_Copy_Absolute_Path,
	Darek_Copy_Project_Relative_Path,
	Darek_Copy_Project_Root,
	Darek_Copy_Name,
	Darek_Collapse_Or_Parent,
	Darek_Collapse_Parent,
	Darek_Collapse_All_Projects,
	Darek_Refresh,
	Darek_Toggle_Peek,
	Darek_Other_Pane_Next_Line,
	Darek_Other_Pane_Previous_Line,
	Darek_Other_Pane_Next_Page,
	Darek_Other_Pane_Previous_Page,
	Darek_Toggle_File_Follow,
	Darek_Toggle_Hidden_Files,
	Darek_Toggle_VCS_Ignored,
	Darek_Toggle_File_Watch,
	Darek_Toggle_VCS_Decorations,
	Darek_Toggle_Diagnostics,
	Darek_Select_Sort,
	Darek_Filter,
	Darek_Panel_Left,
	Darek_Panel_Right,
	Darek_Decrease_Width,
	Darek_Increase_Width,
	Darek_Fit_Width,
	Darek_Toggle_Extra_Width,
	Darek_Toggle_Width_Lock,
	Darek_Toggle_Directory_Compression,
	Darek_Narrow_Current_Project,
	Darek_Show_All_Projects,
	Darek_Shell_Command,
	Darek_Shell_Command_Project,
	Darek_Bulk_Actions,
	Darek_Context_Actions,
	Darek_Help,
	Darek_Help_Advanced,
	Darek_Hide,
	Darek_Close,
	Insert_Indentation,
	Gutter_Inspect_Markers,
	Gutter_Refresh_Markers,
	Gutter_Invoke_Primary_Marker_Action,
	Complete_At_Point,
	Completion_Next,
	Completion_Previous,
	Completion_First,
	Completion_Last,
	Completion_Accept,
	Completion_Cancel,
	Completion_Inspect,
	Completion_Show_Documentation,
	Terminal_Open,
	Terminal_New,
	Terminal_Open_Here,
	Terminal_Open_Project,
	Terminal_Open_Other_Pane,
	Terminal_Toggle,
	Terminal_List,
	Terminal_Rename,
	Terminal_Copy_Mode,
	Terminal_Copy_Mode_Done,
	Terminal_Yank,
	Terminal_Yank_Pop,
	Terminal_Beginning_Of_Line,
	Terminal_End_Of_Line,
	Terminal_Reset_Cursor_Point,
	Terminal_Next_Prompt,
	Terminal_Previous_Prompt,
	Terminal_Next_Error,
	Terminal_Open_Link,
	Terminal_Clear,
	Terminal_Clear_Scrollback,
	Terminal_Send_Next_Key,
	Terminal_Send_Return,
	Terminal_Send_Tab,
	Terminal_Send_Escape,
	Terminal_Send_Backspace,
	Terminal_Send_Delete,
	Terminal_Send_Up,
	Terminal_Send_Down,
	Terminal_Send_Left,
	Terminal_Send_Right,
	Terminal_Send_Prior,
	Terminal_Send_Next,
	Terminal_Send_Space,
	Terminal_Undo,
	Terminal_Terminate,
	Shell_Command,
	Async_Shell_Command,
	Compile,
	Recompile,
	Describe_Completion_State,
	Ksawery_Status,
	Cursor_Next_Word_Start,
	Cursor_Word_End,
	Cursor_Buffer_Start,
	Cursor_Buffer_End,
	Cursor_Find_Next_Character,
	Cursor_Find_Previous_Character,
	Cursor_Till_Next_Character,
	Cursor_Till_Previous_Character,
	Search_Next_Occurrence,
	Search_Previous_Occurrence,
	Modal_Enter_Visual_Character,
	Modal_Enter_Visual_Line,
	Modal_Enter_Visual_Block,
	Modal_Enter_Insert_Line_First,
	Modal_Enter_Insert_Line_End,
	Modal_Open_Line_Below,
	Modal_Open_Line_Above,
	Focus_Pane_Left,
	Focus_Pane_Down,
	Focus_Pane_Up,
	Focus_Pane_Right,
	Jan_Inspect_Syntax,
	Jan_Lint,
	Jan_Lint_Refresh,
	Jan_Language_Status,
	Jan_Cycle,
	Jan_Global_Cycle,
	Jan_Show_Overview,
	Jan_Show_Contents,
	Jan_Show_All,
	Jan_Sparse_View,
	Jan_Next_Heading,
	Jan_Previous_Heading,
	Jan_Next_Same_Level_Heading,
	Jan_Previous_Same_Level_Heading,
	Jan_Parent_Heading,
	Jan_First_Child_Heading,
	Jan_Subtree_Start,
	Jan_Subtree_End,
	Jan_Next_Structural_Element,
	Jan_Previous_Structural_Element,
	Jan_Next_List_Item,
	Jan_Previous_List_Item,
	Jan_Next_Table_Row,
	Jan_Previous_Table_Row,
	Jan_Next_Table_Cell,
	Jan_Previous_Table_Cell,
	Jan_Next_Drawer,
	Jan_Previous_Drawer,
	Jan_Next_Block,
	Jan_Previous_Block,
	Jan_Next_Footnote,
	Jan_Previous_Footnote,
	Jan_Insert_Heading_Before,
	Jan_Insert_Heading_After,
	Jan_Insert_Heading_Below,
	Jan_Split_Heading,
	Jan_Promote_Heading,
	Jan_Demote_Heading,
	Jan_Move_Subtree_Up,
	Jan_Move_Subtree_Down,
	Jan_Clone_Subtree,
	Jan_Kill_Subtree,
	Jan_Sort_Child_Headings,
	Jan_Heading_To_List_Item,
	Jan_List_Item_To_Heading,
	Jan_Insert_List_Item_Before,
	Jan_Insert_List_Item_After,
	Jan_Delete_List_Item,
	Jan_Promote_List_Item,
	Jan_Demote_List_Item,
	Jan_Move_List_Item_Up,
	Jan_Move_List_Item_Down,
	Jan_Duplicate_List_Item,
	Jan_Sort_List_Items,
	Jan_Cycle_List_Bullet,
	Jan_Repair_List_Indentation,
	Jan_Insert_Drawer,
	Jan_Insert_Block,
	Jan_Select_Structure,
	Jan_Move_Structure_Up,
	Jan_Move_Structure_Down,
	Jan_Delete_Structure,
	Jan_Create_Table,
	Jan_Align_Table,
	Jan_Insert_Table_Row,
	Jan_Delete_Table_Row,
	Jan_Move_Table_Row_Up,
	Jan_Move_Table_Row_Down,
	Jan_Duplicate_Table_Row,
	Jan_Insert_Table_Column,
	Jan_Delete_Table_Column,
	Jan_Move_Table_Column_Left,
	Jan_Move_Table_Column_Right,
	Jan_Duplicate_Table_Column,
	Jan_Insert_Table_Separator,
	Jan_Delete_Table_Separator,
	Jan_Edit_Table_Cell,
	Jan_Visit_Footnote,
	Jan_Create_Footnote,
	Jan_Normalize_Footnote,
	Jan_Renumber_Footnotes,
	Jan_Move_Footnote_Up,
	Jan_Move_Footnote_Down,
	Jan_Complete,
	Jan_Expand_Template,
	Jan_Indent,
	Jan_Context_Action,
	Jan_Repeat,
	Jan_Present,
	Jan_Request_Preview,
	Jan_Inspect_Availability,
	Language_Show_Hover,
	Language_Go_To_Definition,
	Language_Find_References,
	Language_Document_Symbols,
	Language_Workspace_Symbols,
	Language_Signature_Help,
	Language_Rename,
	Language_Format_Buffer,
	Language_Format_Region,
	Language_Code_Actions,
	Describe_Language_Bundle,
	Language_Support_Doctor,
	Language_Bundle_List,
	Language_Bundle_Search,
	Language_Bundle_Install,
	Language_Bundle_Enable,
	Language_Bundle_Disable,
	Language_Bundle_Update,
	Language_Bundle_Rollback,
	Language_Bundle_Remove,
	Language_Bundle_Refresh_Catalogs,
	Package_Catalog_List,
	Package_Catalog_Add,
	Package_Catalog_Disable,
	Package_Catalog_Remove,
	Package_Catalog_Refresh,
	Package_Catalog_Search,
	Package_Catalog_Describe,
	Package_Manual_Acquire,
	Package_Advisory_List,
	Package_Curator_Validate,
	Package_Catalog_Doctor,
	Package_List,
	Package_Discover,
	Package_Describe,
	Package_Install,
	Package_Enable,
	Package_Disable,
	Package_Update,
	Package_Rollback,
	Package_Remove,
	Package_Cleanup,
	Package_Doctor,
	Jan_Toggle_Drawer,
	Jan_Todo,
	Jan_Set_Priority,
	Jan_Toggle_Checkbox,
	Jan_Update_Statistics,
	Jan_Set_Tags,
	Jan_Set_Property,
	Jan_Property_Search,
	Jan_Column_View,
	Jan_Timestamp,
	Jan_Schedule,
	Jan_Deadline,
	Jan_Clock_In,
	Jan_Clock_Out,
	Jan_Clock_Cancel,
	Jan_Clock_Switch,
	Jan_Clock_Resume,
	Jan_Clock_Report,
	Jan_Set_Effort,
	Jan_Timer_Start,
	Jan_Timer_Pause,
	Jan_Timer_Resume,
	Jan_Timer_Stop,
	Jan_Timer_Reset,
	Jan_Refile,
	Jan_Copy_Subtree,
	Jan_Archive_Subtree,
	Jan_Toggle_Archive,
	Jan_Restore_Archive,
	Jan_Visit_Archive_Origin,
	Jan_Capture,
	Jan_Capture_Finalize,
	Jan_Capture_Abort,
	Jan_Store_Link,
	Jan_Attach,
	Jan_Attachment_Open,
	Jan_Attachment_Reveal,
	Jan_Attachment_List,
	Jan_Attachment_Rename,
	Jan_Attachment_Delete,
	Jan_Attachment_Synchronize,
	Jan_Feed_Refresh,
	Jan_Agenda,
	Jan_Agenda_Refresh,
	Jan_Agenda_Next_Entry,
	Jan_Agenda_Previous_Entry,
	Jan_Agenda_Next_Date,
	Jan_Agenda_Previous_Date,
	Jan_Agenda_Reveal_Source,
	Jan_Agenda_Set_Span,
	Jan_Agenda_Toggle_Follow,
	Jan_Agenda_Filter,
	Jan_Agenda_Change_Presentation,
	Jan_Agenda_Todo,
	Jan_Agenda_Set_Priority,
	Jan_Agenda_Set_Tags,
	Jan_Agenda_Set_Property,
	Jan_Agenda_Schedule,
	Jan_Agenda_Deadline,
	Jan_Agenda_Set_Effort,
	Jan_Agenda_Clock_In,
	Jan_Agenda_Clock_Out,
	Jan_Agenda_Refile,
	Jan_Agenda_Archive,
	Jan_Agenda_Capture,
	Jan_Agenda_Delete,
	Jan_Agenda_Apply_Selection,
	Jan_Agenda_Calendar,
	Jan_Agenda_Export,
	Jan_Agenda_Quit,
	Jan_Agenda_Close,
	Jan_Planning_Status,
	Jan_Table_Recalculate,
	Jan_Table_Recalculate_All,
	Jan_Table_Debug_Formula,
	Jan_Table_Plot,
	Jan_Execute,
	Jan_Execute_Subtree,
	Jan_Execute_Buffer,
	Jan_Call,
	Jan_Result_Remove,
	Jan_Result_Inspect,
	Jan_Edit_Source,
	Jan_Return_From_Source,
	Jan_Tangle,
	Jan_Tangle_File,
	Jan_Noweb_Inspect,
	Jan_Library_Load,
	Jan_Execute_Batch,
	Jan_Session_List,
	Jan_Session_Inspect,
	Jan_Session_Close,
	Jan_Cache_Inspect,
	Jan_Cache_Evict,
	Jan_Cache_Clear,
	Jan_Open_Result,
	Jan_Load_In_Session,
	Jan_Pop_To_Session,
	Jan_Expand_Source,
	Jan_Goto_Source_Head,
	Jan_Goto_Named_Source,
	Jan_Goto_Named_Result,
	Jan_Demarcate_Source,
	Jan_Check_Source,
	Jan_Insert_Header_Argument,
	Jan_View_Source_Info,
	Jan_Switch_To_Session_With_Code,
	Jan_Source_Hash,
	Jan_Babel_Help,
	Jan_Context_Meta_Up,
	Jan_Context_Meta_Down,
	Jan_Computation_Status,
	Jan_Export,
	Jan_Export_Region,
	Jan_Export_Plain_Text,
	Jan_Export_Html,
	Jan_Export_Markdown,
	Jan_Export_Normalized_Jan,
	Jan_Export_Beamer,
	Jan_Export_Latex,
	Jan_Export_Pdf,
	Jan_Export_Odt,
	Jan_Export_Texinfo,
	Jan_Export_Info,
	Jan_Export_Man_Page,
	Jan_Export_ICalendar,
	Jan_Citation_Insert,
	Jan_Citation_Follow,
	Jan_Bibliography_Insert,
	Jan_Publish,
	Jan_Publish_Project,
	Jan_Publish_All,
	Jan_Protocol_Handle,
	Jan_Help_At_Point,
	Jan_Encrypt_Subtree,
	Jan_Decrypt_Subtree,
	Jan_Mobile_Push,
	Jan_Mobile_Pull,
	Jan_Mobile_Reconcile,
	Jan_Dynamic_Block_Update,
	Jan_Provider_Status,
	Jan_Extension_Status,
	Jan_Output_Status,
	Normalize_Indentation_To_Tabs,
	Normalize_Indentation_To_Spaces,
	Find_Alternate_File,
	Write_File,
	Save_Some_Buffers,
	Insert_File,
	Toggle_Read_Only,
	Next_Buffer,
	Previous_Buffer,
	Goto_Line,
	Goto_Char,
}

/* native_route_is_terminal identifies the contiguous live terminal command range. */
native_route_is_terminal :: proc(route: Native_Route) -> bool {
	return route >= .Terminal_Open && route <= .Recompile
}

/* native_route_is_darek identifies the contiguous Darek command identity range. */
native_route_is_darek :: proc(route: Native_Route) -> bool {
	return route >= .Darek_Toggle && route <= .Darek_Close
}

/* native_route_is_jan_structured identifies Stage 2 routes despite later appended corrections. */
native_route_is_jan_structured :: proc(route: Native_Route) -> bool {
	return route >= .Jan_Cycle && route <= .Jan_Inspect_Availability ||
	       route == .Jan_Toggle_Drawer
}

/* native_route_is_jan_planning identifies the contiguous Planning and Agenda range. */
native_route_is_jan_planning :: proc(route: Native_Route) -> bool {
	return route >= .Jan_Todo && route <= .Jan_Planning_Status
}

/* native_route_is_jan_computation identifies the contiguous Computable Documents range. */
native_route_is_jan_computation :: proc(route: Native_Route) -> bool {
	return route >= .Jan_Table_Recalculate && route <= .Jan_Computation_Status
}

/* native_route_is_jan_output identifies the contiguous Output and Integration range. */
native_route_is_jan_output :: proc(route: Native_Route) -> bool {
	return route >= .Jan_Export && route <= .Jan_Output_Status
}

/* Contextual_Route identifies one prompt or component interaction operation. */
Contextual_Route :: enum u16 {
	Invalid,
	Prompt_Insert_Text,
	Prompt_Delete_Previous,
	Prompt_Accept,
	Cancel,
	Search_History_Newer,
	Search_History_Older,
	Search_History_Complete,
	Search_Extend_Textual,
	Search_Extend_Structural,
	Search_Extend_Transferred,
	Search_Toggle_Case,
	Search_Toggle_Pattern,
	Search_Toggle_Word,
	Search_Toggle_Symbol,
	Search_Toggle_Whitespace,
	Search_Materialize,
	Prompt_Choice_1,
	Prompt_Choice_2,
	Prompt_Choice_3,
	Prompt_Choice_4,
	Query_Replace_And_Exit,
	Query_Quit,
	Component_Previous_Row,
	Component_Next_Row,
	Component_Activate_Current,
	Component_Mark_Save,
	Component_Mark_Kill,
	Component_Unmark,
	Component_Execute,
	Component_Close,
	Component_Query_Text,
	Component_Query_Delete_Previous,
	Component_Complete_Current,
	Result_First,
	Result_Last,
	Result_Refresh,
	Result_Edit,
	Result_Apply,
	Ksawery_Mark,
	Ksawery_Unmark,
	Ksawery_Clear_Marks,
	Ksawery_Stage,
	Ksawery_Unstage,
	Ksawery_Discard,
	Ksawery_Commit,
	Ksawery_Amend,
	Ksawery_Fixup,
	Ksawery_Sequence,
	Ksawery_History,
	Ksawery_History_Next,
	Ksawery_Refs,
	Ksawery_Stashes,
	Ksawery_Worktrees,
	Ksawery_Blame,
	Ksawery_Reflog,
	Ksawery_Processes,
	Ksawery_Providers,
	Ksawery_Provider_Reload,
	Ksawery_Provider_Disable,
	Ksawery_Fetch,
	Ksawery_Push,
	Ksawery_Branch_Create,
	Ksawery_Branch_Switch,
	Ksawery_Branch_Rename,
	Ksawery_Branch_Delete,
	Ksawery_Tag_Create,
	Ksawery_Tag_Delete,
	Ksawery_Merge_Fast_Forward,
	Ksawery_Merge,
	Ksawery_Merge_No_Fast_Forward,
	Ksawery_Merge_Continue,
	Ksawery_Merge_Abort,
	Ksawery_Rebase,
	Ksawery_Rebase_Autosquash,
	Ksawery_Rebase_Continue,
	Ksawery_Rebase_Skip,
	Ksawery_Rebase_Abort,
	Ksawery_Sequence_Mark,
	Ksawery_Sequence_Unmark,
	Ksawery_Cherry_Pick,
	Ksawery_Cherry_Pick_Continue,
	Ksawery_Cherry_Pick_Skip,
	Ksawery_Cherry_Pick_Abort,
	Ksawery_Revert,
	Ksawery_Revert_Continue,
	Ksawery_Revert_Skip,
	Ksawery_Revert_Abort,
	Ksawery_Bisect_Good,
	Ksawery_Bisect_Bad,
	Ksawery_Bisect_Start,
	Ksawery_Bisect_Skip,
	Ksawery_Bisect_Reset,
	Ksawery_Conflict_Mark,
	Ksawery_Conflict_Assist,
	Ksawery_Conflict_Use_Base,
	Ksawery_Conflict_Use_Current,
	Ksawery_Conflict_Use_Applied,
	Ksawery_Conflict_Delete,
	Ksawery_Raw_Command,
}

/* Racket_Dispatch_Class selects a generic admitted programmable route shape. */
Racket_Dispatch_Class :: enum u8 {
	Invalid,
	Keymap_Inspection,
	Transaction,
	Personal,
	Ksawery_Extension,
}

/* native_route constructs one checked native provider identity. */
native_route :: proc(operation: Native_Route) -> interaction.Command_Route {
	return {provider = NATIVE_ROUTE_PROVIDER, operation = u16(operation)}
}

/* contextual_route constructs one checked contextual provider identity. */
contextual_route :: proc(operation: Contextual_Route) -> interaction.Command_Route {
	return {provider = CONTEXTUAL_ROUTE_PROVIDER, operation = u16(operation)}
}

/* racket_route constructs one catalog-indexed programmable provider identity. */
racket_route :: proc(
	dispatch_class: Racket_Dispatch_Class,
	operation: u16,
) -> interaction.Command_Route {
	provider := interaction.Command_Provider_ID(0)
	switch dispatch_class {
	case .Keymap_Inspection:
		provider = RACKET_INSPECTION_ROUTE_PROVIDER
	case .Transaction:
		provider = RACKET_RUNTIME_ROUTE_PROVIDER
	case .Personal:
		provider = RACKET_PERSONAL_ROUTE_PROVIDER
	case .Ksawery_Extension:
		provider = RACKET_KSAWERY_ROUTE_PROVIDER
	case .Invalid:
	}
	return {provider = provider, operation = operation}
}

/* native_route_decode returns the provider-owned operation for one native route. */
native_route_decode :: proc(route: interaction.Command_Route) -> (Native_Route, bool) {
	if route.provider != NATIVE_ROUTE_PROVIDER || route.operation == 0 ||
	   route.operation > u16(Native_Route.Goto_Char) {
		return .Invalid, false
	}
	return Native_Route(route.operation), true
}

/* contextual_route_decode returns the provider-owned operation for one contextual route. */
contextual_route_decode :: proc(route: interaction.Command_Route) -> (Contextual_Route, bool) {
	if route.provider != CONTEXTUAL_ROUTE_PROVIDER || route.operation == 0 ||
	   route.operation > u16(Contextual_Route.Ksawery_Raw_Command) {
		return .Invalid, false
	}
	return Contextual_Route(route.operation), true
}

/* racket_route_decode returns the generic class and catalog operation identity. */
racket_route_decode :: proc(
	route: interaction.Command_Route,
) -> (dispatch_class: Racket_Dispatch_Class, operation: u16, ok: bool) {
	if route.operation == 0 {
		return .Invalid, 0, false
	}
	switch route.provider {
	case RACKET_INSPECTION_ROUTE_PROVIDER:
		return .Keymap_Inspection, route.operation, true
	case RACKET_RUNTIME_ROUTE_PROVIDER:
		return .Transaction, route.operation, true
	case RACKET_PERSONAL_ROUTE_PROVIDER:
		return .Personal, route.operation, true
	case RACKET_KSAWERY_ROUTE_PROVIDER:
		return .Ksawery_Extension, route.operation, true
	case:
		return .Invalid, 0, false
	}
}

/* built_in_command_registry_init validates provider routes before registry activation. */
built_in_command_registry_init :: proc(
	registry: ^interaction.Command_Registry,
	generation: interaction.Registry_Generation,
	allocator: runtime.Allocator,
	racket_definitions: []interaction.Command_Definition = nil,
	provided_definitions: []interaction.Command_Definition = nil,
) -> (ok: bool, failure: interaction.Failure_Context) {
	base := built_in_base_command_definitions()
	combined, allocation_error := make(
		[]interaction.Command_Definition,
		interaction.MAX_COMMANDS,
		allocator,
	)
	if allocation_error != nil {
		return false, {code = .Persistent_Memory_Limit, registry_generation = generation}
	}
	defer delete(combined, allocator)
	count := 0
	for definition in base {
		combined[count] = definition
		count += 1
	}
	if len(racket_definitions) > interaction.MAX_COMMANDS - count {
		return false, {
			code = .Command_Limit,
			registry_generation = generation,
			limit = interaction.MAX_COMMANDS,
			actual = u64(count + len(racket_definitions)),
		}
	}
	for definition in racket_definitions {
		combined[count] = definition
		count += 1
	}
	admitted := combined[:count]
	if provided_definitions != nil {
		admitted = provided_definitions
	}
	for definition in admitted {
		failure = built_in_route_validate(definition, generation)
		if failure.code != .None {
			return false, failure
		}
	}
	return interaction.command_registry_init(registry, generation, admitted, allocator)
}

@(private)
built_in_route_validate :: proc(
	definition: interaction.Command_Definition,
	generation: interaction.Registry_Generation,
) -> interaction.Failure_Context {
	if definition.route.provider == RACKET_INSPECTION_ROUTE_PROVIDER ||
	   definition.route.provider == RACKET_RUNTIME_ROUTE_PROVIDER ||
	   definition.route.provider == RACKET_PERSONAL_ROUTE_PROVIDER ||
	   definition.route.provider == RACKET_KSAWERY_ROUTE_PROVIDER {
		_, _, decoded := racket_route_decode(definition.route)
		if !decoded {
			return {code = .Invalid_Route, registry_generation = generation}
		}
		if definition.implementation != .Racket {
			return {code = .Invalid_Implementation, registry_generation = generation}
		}
		return {}
	}
	implementation, invocation, text_requirement, effects, found :=
		built_in_route_contract(definition.route)
	if !found {
		return {code = .Invalid_Route, registry_generation = generation}
	}
	if definition.implementation != implementation {
		return {code = .Invalid_Implementation, registry_generation = generation}
	}
	if definition.invocation != invocation {
		return {code = .Invalid_Command, registry_generation = generation}
	}
	if definition.text_requirement != text_requirement {
		return {code = .Invalid_Text_Requirement, registry_generation = generation}
	}
	if definition.effects != effects {
		return {code = .Invalid_Effects, registry_generation = generation}
	}
	return {}
}

@(private)
built_in_route_contract :: proc(
	route: interaction.Command_Route,
) -> (
	implementation: interaction.Implementation_Class,
	invocation: interaction.Invocation_Class,
	text_requirement: interaction.Text_Requirement,
	effects: interaction.Command_Effects,
	found: bool,
) {
	switch route.provider {
	case NATIVE_ROUTE_PROVIDER:
		return native_route_contract(Native_Route(route.operation))
	case CONTEXTUAL_ROUTE_PROVIDER:
		return contextual_route_contract(Contextual_Route(route.operation))
	case:
		return {}, {}, {}, {}, false
	}
}

@(private)
native_route_contract :: proc(
	route: Native_Route,
) -> (
	interaction.Implementation_Class,
	interaction.Invocation_Class,
	interaction.Text_Requirement,
	interaction.Command_Effects,
	bool,
) {
	invocation := interaction.Invocation_Class.Ordinary
	text_requirement := interaction.Text_Requirement.Prohibited
	effects: interaction.Command_Effects
	if native_route_is_jan_structured(route) || native_route_is_jan_planning(route) ||
	   native_route_is_jan_computation(route) || native_route_is_jan_output(route) {
		effects = {.View, .Lifecycle}
		if jan_route_changes_source(route) {
			effects = {.Buffer, .View, .Lifecycle, .Text_Mutation}
		}
		return .Native, invocation, text_requirement, effects, true
	}
	#partial switch route {
	case .Cursor_Previous_Grapheme, .Cursor_Next_Grapheme,
	     .Cursor_Previous_Line, .Cursor_Next_Line, .Cursor_Line_Start, .Cursor_Line_End,
	     .Cursor_Previous_Word, .Cursor_Next_Word,
	     .Cursor_Next_Word_Start, .Cursor_Word_End,
	     .Cursor_Line_First_Non_Whitespace, .Cursor_Buffer_Start, .Cursor_Buffer_End,
	     .Toggle_Overwrite_Mode,
	     .Scroll_Previous_Page, .Scroll_Next_Page, .Recenter,
	     .Select_Word, .Select_Paragraph, .Select_Buffer, .Select_Definition,
	     .Narrow_To_Region, .Narrow_To_Definition, .Widen,
	     .Pop_Selection_Location,
	     .ISearch_Forward, .ISearch_Backward, .ISearch_Forward_Regexp, .ISearch_Backward_Regexp,
	     .Search_Symbol_At_Point, .Search_Word,
	     .Highlight_Symbol_At_Point, .Highlight_Phrase, .Highlight_Regexp,
	     .Highlight_Lines, .Highlight_Remove,
	     .Search_Next_Occurrence, .Search_Previous_Occurrence,
	     .Set_Mark, .Deactivate_Mark, .Exchange_Point_And_Mark,
	     .Goto_Line, .Goto_Char:
		effects = {.View}
	case .Cursor_Find_Next_Character, .Cursor_Find_Previous_Character,
	     .Cursor_Till_Next_Character, .Cursor_Till_Previous_Character:
		text_requirement = .Required
		effects = {.View}
	case .Query_Replace, .Query_Replace_Regexp, .Replace_String, .Replace_Regexp,
	     .Delete_Previous_Grapheme, .Delete_Next_Grapheme, .Insert_Line_Break,
	     .Undo, .Redo, .Kill_Region, .Kill_Line, .Backward_Kill_Word, .Kill_Word,
	     .Delete_Region, .Delete_Blank_Lines, .Fill_Paragraph, .Transpose_Words,
	     .Upcase_Word, .Downcase_Word, .Capitalize_Word, .Comment_Dwim,
	     .Dynamic_Abbrev_Expand, .Yank, .Yank_After_Point, .Yank_Pop,
	     .Structural_Indent, .Insert_Indentation, .Indent_Lines, .Outdent_Lines,
	     .Rigid_Indent_Right, .Rigid_Indent_Left,
	     .Rigid_Indent_Right_Fast, .Rigid_Indent_Left_Fast,
	     .Normalize_Indentation_To_Tabs, .Normalize_Indentation_To_Spaces:
		effects = {.Buffer, .View, .Text_Mutation}
	case .Indent_Rigidly:
		effects = {.View, .Lifecycle}
	case .Occur:
		effects = {.View, .Lifecycle}
	case .Insert_File:
		text_requirement = .Optional
		effects = {.Buffer, .View, .Lifecycle, .Text_Mutation}
	case .Modal_Repeat_Last_Change:
		text_requirement = .Optional
		effects = {.Buffer, .View, .Text_Mutation}
	case .Replace_Region_Text, .Replace_Rectangle_Text:
		text_requirement = .Required
		effects = {.Buffer, .View, .Text_Mutation}
	case .Select_Rectangle:
		effects = {.View}
	case .Copy_Rectangle:
		effects = {.Buffer}
	case .Kill_Rectangle:
		effects = {.Buffer, .View, .Text_Mutation}
	case .Structural_Forward, .Structural_Backward, .Structural_Up, .Structural_Down,
	     .Structural_Select:
		effects = {.View}
	case .Insert_Text:
		invocation = .Text_Input
		text_requirement = .Required
		effects = {.Buffer, .View, .Text_Mutation}
	case .Insert_Text_After_Point:
		text_requirement = .Required
		effects = {.Buffer, .View, .Text_Mutation}
	case .Save_Associated_Document, .Find_File, .Find_Alternate_File, .Write_File,
	     .Save_Some_Buffers, .Toggle_Read_Only, .Next_Buffer, .Previous_Buffer,
	     .Switch_To_Buffer,
	     .Find_File_Other_Pane, .Switch_To_Buffer_Other_Pane, .Display_Buffer_Other_Pane,
	     .Kill_Buffer,
	     .List_Buffers, .Reload_Interaction_Profile, .Reload_Personal_Commands,
	     .Execute_Extended_Command, .Select_Interaction_Profile,
	     .Help_About_Help, .Apropos_Command, .Info,
	     .Describe_Function, .Describe_Variable,
	     .Describe_Syntax_Table, .Open_Tutorial,
	     .Modal_Enter_Insert, .Modal_Enter_Replace, .Modal_Enter_Normal,
	     .Describe_Modal_Repeat,
	     .Start_Keyboard_Macro, .End_Keyboard_Macro,
	     .Name_Last_Keyboard_Macro, .Call_Named_Keyboard_Macro,
	     .Select_Theme,
	     .Describe_Theme,
	     .Dir_Open, .Project_Promote, .Project_Unregister,
	     .Project_Inspect_Active, .Project_Find_File,
	     .Project_Switch_Buffer, .Project_Save_Buffers,
	     .Project_Close_Buffers, .Project_Refresh, .Project_Command_Menu,
	     .Describe_Project_Bindings, .Recover_Unsaved_Work,
	     .Describe_Language_State, .Describe_Structural_State,
	     .Jan_Inspect_Syntax, .Jan_Lint, .Jan_Lint_Refresh, .Jan_Language_Status,
	     .Split_Pane_Below, .Split_Pane_Right, .Close_Pane, .Keep_Only_Pane,
	     .Focus_Pane_Left, .Focus_Pane_Down, .Focus_Pane_Up, .Focus_Pane_Right,
	     .Focus_Next_Pane, .Enlarge_Pane_Vertically, .Enlarge_Pane_Horizontally,
	     .Shrink_Pane_Horizontally, .Balance_Panes, .Balance_Pane_Areas,
	     .Request_Editor_Exit, .Workspace_Add_Project, .Workspace_Remove_Project,
	     .Workspace_Unregister, .Save_Location, .List_Locations, .Visit_Location:
		effects = {.Lifecycle}
	case .Modal_Enter_Visual_Character, .Modal_Enter_Visual_Line, .Modal_Enter_Visual_Block:
		effects = {.View, .Lifecycle}
	case .Call_Last_Keyboard_Macro, .Finish_Or_Call_Keyboard_Macro:
		effects = {.Buffer, .View, .Lifecycle, .Text_Mutation}
	case .Modal_Enter_Insert_Line_First, .Modal_Enter_Insert_Line_End:
		effects = {.View, .Lifecycle}
	case .Modal_Open_Line_Below, .Modal_Open_Line_Above:
		effects = {.Buffer, .View, .Lifecycle, .Text_Mutation}
	case .Store_Number, .Increment_Number, .Store_Text, .Store_Position:
		effects = {.Lifecycle}
	case .Store_Region_Text:
		effects = {.Buffer, .Lifecycle}
	case .Insert_Slot:
		effects = {.Buffer, .View, .Text_Mutation}
	case .Store_Layout, .Visit_Slot, .Restore_Layout:
		effects = {.Lifecycle}
	case .Modal_Enter_Insert_After,
	     .List_Language_Diagnostics, .Next_Language_Diagnostic,
	     .Previous_Language_Diagnostic, .Next_Location, .Previous_Location,
	     .Symbol_Navigator, .Project_Search_Text, .Project_Search_Text_Regexp,
	     .Project_Search_Repeat:
		effects = {.View, .Lifecycle}
	case .Status_Bar_Inspect, .Status_Bar_Actions, .Status_Bar_Activate_Segment:
		effects = {.View, .Lifecycle}
	case .Gutter_Toggle_Line_Numbers, .Gutter_Cycle_Line_Number_Mode,
	     .Gutter_Set_Line_Numbers_None, .Gutter_Set_Line_Numbers_Absolute,
	     .Gutter_Set_Line_Numbers_Relative, .Gutter_Set_Line_Numbers_Hybrid,
	     .Gutter_Set_Numbering_Logical, .Gutter_Set_Numbering_Visual,
	     .Gutter_Toggle_Line_Number_Side, .Gutter_Inspect_Numbering,
	     .Gutter_Inspect_Markers, .Gutter_Refresh_Markers,
	     .Gutter_Invoke_Primary_Marker_Action:
		effects = {.View}
	case .Complete_At_Point, .Completion_Inspect, .Completion_Show_Documentation:
		effects = {.View, .Lifecycle}
	case .Completion_Next, .Completion_Previous, .Completion_First,
	     .Completion_Last, .Completion_Cancel:
		effects = {.View}
	case .Completion_Accept:
		effects = {.Buffer, .View, .Text_Mutation}
	case .Describe_Completion_State:
		effects = {.Lifecycle}
	case .Ksawery_Status:
		effects = {.Lifecycle}
	case .Terminal_Send_Next_Key, .Terminal_Copy_Mode, .Terminal_Copy_Mode_Done,
	     .Terminal_Beginning_Of_Line, .Terminal_End_Of_Line,
	     .Terminal_Reset_Cursor_Point, .Terminal_Next_Prompt,
	     .Terminal_Previous_Prompt, .Terminal_Open_Link:
		effects = {.View}
	case .Terminal_Send_Return, .Terminal_Send_Tab, .Terminal_Send_Escape,
	     .Terminal_Send_Backspace, .Terminal_Send_Delete, .Terminal_Send_Up,
	     .Terminal_Send_Down, .Terminal_Send_Left, .Terminal_Send_Right,
	     .Terminal_Send_Prior, .Terminal_Send_Next, .Terminal_Send_Space,
	     .Terminal_Undo:
		effects = {.Lifecycle}
	case .Terminal_Open, .Terminal_New, .Terminal_Open_Here,
	     .Terminal_Open_Project, .Terminal_Open_Other_Pane, .Terminal_Toggle,
	     .Terminal_List, .Terminal_Rename, .Terminal_Yank, .Terminal_Yank_Pop,
	     .Terminal_Clear, .Terminal_Next_Error,
	     .Terminal_Clear_Scrollback, .Terminal_Terminate,
	     .Shell_Command, .Async_Shell_Command, .Compile, .Recompile:
		effects = {.View, .Lifecycle}
	case .Maksym_Open_Directory, .Maksym_Open_Directory_Other_Pane,
	     .Maksym_Open_Directory_Below, .Maksym_Open_Directory_Right,
	     .Maksym_Open_Containing_Directory, .Maksym_Open_Containing_Directory_Other_Pane,
	     .Maksym_Parent_Directory, .Maksym_Jump_To_Entry, .Maksym_Open_Entry,
	     .Maksym_Open_Entry_Other_Pane, .Maksym_Display_Entry_Other_Pane, .Maksym_Refresh,
	     .Maksym_Toggle_Details, .Maksym_Cycle_Sort:
		effects = {.View, .Lifecycle}
	case .Maksym_Next_Entry, .Maksym_Previous_Entry:
		effects = {.View}
	case .Maksym_Toggle_Editable_Listing, .Maksym_Apply_Editable_Listing,
	     .Maksym_Cancel_Editable_Listing:
		effects = {.View, .Lifecycle}
	case .Maksym_Editable_Next_Line, .Maksym_Editable_Previous_Line:
		effects = {.View}
	case .Darek_Toggle, .Darek_Select, .Darek_Focus_Toggle, .Darek_Show_Directory,
	     .Darek_Find_Current_File, .Darek_Show_Current_Project, .Darek_Visit_Action,
	     .Darek_Open, .Darek_Open_Split_Below, .Darek_Open_Split_Right,
	     .Darek_Open_And_Hide, .Darek_Open_Mru_Pane, .Darek_Open_External,
	     .Darek_Create_File, .Darek_Create_Directory, .Darek_Rename_Node,
	     .Darek_Move_Node, .Darek_Copy_Node, .Darek_Delete_Node,
	     .Darek_Copy_Absolute_Path, .Darek_Copy_Project_Relative_Path,
	     .Darek_Copy_Project_Root, .Darek_Copy_Name,
	     .Darek_Move_Project_Up, .Darek_Move_Project_Down, .Darek_Project_Add,
	     .Darek_Project_Remove, .Darek_Project_Rename,
	     .Darek_Workspace_Switch, .Darek_Workspace_Next,
	     .Darek_Root_Parent, .Darek_Root_Current_Directory,
	     .Darek_Toggle_Peek, .Darek_Toggle_File_Follow,
	     .Darek_Toggle_Hidden_Files, .Darek_Toggle_VCS_Ignored,
	     .Darek_Toggle_File_Watch, .Darek_Toggle_VCS_Decorations,
	     .Darek_Toggle_Diagnostics, .Darek_Select_Sort, .Darek_Filter,
	     .Darek_Panel_Left, .Darek_Panel_Right, .Darek_Decrease_Width,
	     .Darek_Increase_Width, .Darek_Fit_Width, .Darek_Toggle_Extra_Width,
	     .Darek_Toggle_Width_Lock, .Darek_Toggle_Directory_Compression,
	     .Darek_Narrow_Current_Project, .Darek_Show_All_Projects,
	     .Darek_Shell_Command, .Darek_Shell_Command_Project,
	     .Darek_Bulk_Actions, .Darek_Context_Actions,
	     .Darek_Help, .Darek_Help_Advanced, .Darek_Hide, .Darek_Close:
		effects = {.View, .Lifecycle}
	case .Darek_Next_Node, .Darek_Previous_Node, .Darek_Next_Sibling,
	     .Darek_Previous_Sibling, .Darek_Next_Project, .Darek_Previous_Project,
	     .Darek_Project_Collapse, .Darek_Project_Collapse_Others,
	     .Darek_Parent_Node, .Darek_Structure_Action,
	     .Darek_Collapse_Or_Parent, .Darek_Collapse_Parent,
	     .Darek_Collapse_All_Projects, .Darek_Refresh,
	     .Darek_Other_Pane_Next_Line, .Darek_Other_Pane_Previous_Line,
	     .Darek_Other_Pane_Next_Page, .Darek_Other_Pane_Previous_Page:
		effects = {.View}
	case .Describe_Language_Support, .Describe_Language_Service, .Restart_Language_Service:
		effects = {.Lifecycle}
	case .Language_Show_Hover, .Language_Go_To_Definition,
	     .Language_Find_References, .Language_Document_Symbols,
	     .Language_Workspace_Symbols, .Language_Signature_Help:
		effects = {.View, .Lifecycle}
	case .Language_Rename, .Language_Format_Buffer, .Language_Format_Region,
	     .Language_Code_Actions:
		effects = {.Buffer, .View, .Lifecycle, .Text_Mutation}
	case .Describe_Language_Bundle, .Language_Support_Doctor,
	     .Language_Bundle_List, .Language_Bundle_Search,
	     .Language_Bundle_Install, .Language_Bundle_Enable,
	     .Language_Bundle_Disable, .Language_Bundle_Update,
	     .Language_Bundle_Rollback, .Language_Bundle_Remove,
	     .Language_Bundle_Refresh_Catalogs:
		effects = {.Lifecycle}
	case .Package_Catalog_List, .Package_Catalog_Add,
	     .Package_Catalog_Disable, .Package_Catalog_Remove,
	     .Package_Catalog_Refresh, .Package_Catalog_Search,
	     .Package_Catalog_Describe, .Package_Manual_Acquire,
	     .Package_Advisory_List, .Package_Curator_Validate,
	     .Package_Catalog_Doctor, .Package_List, .Package_Discover,
	     .Package_Describe, .Package_Install, .Package_Enable,
	     .Package_Disable, .Package_Update, .Package_Rollback,
	     .Package_Remove, .Package_Cleanup, .Package_Doctor:
		effects = {.Lifecycle}
	case .Copy_Region:
		effects = {.Buffer}
	case .Keyboard_Quit:
		invocation = .Cancellation
		effects = {.View}
	case .Invalid:
		return {}, {}, {}, {}, false
	}
	return .Native, invocation, text_requirement, effects, true
}

/* jan_route_changes_source identifies public Jan transaction routes. */
jan_route_changes_source :: proc(route: Native_Route) -> bool {
	#partial switch route {
	case .Jan_Insert_Heading_Before, .Jan_Insert_Heading_After, .Jan_Insert_Heading_Below,
	     .Jan_Split_Heading, .Jan_Promote_Heading, .Jan_Demote_Heading,
	     .Jan_Move_Subtree_Up, .Jan_Move_Subtree_Down, .Jan_Clone_Subtree,
	     .Jan_Kill_Subtree, .Jan_Sort_Child_Headings, .Jan_Heading_To_List_Item,
	     .Jan_List_Item_To_Heading, .Jan_Insert_List_Item_Before,
	     .Jan_Insert_List_Item_After, .Jan_Delete_List_Item, .Jan_Promote_List_Item,
	     .Jan_Demote_List_Item, .Jan_Move_List_Item_Up, .Jan_Move_List_Item_Down,
	     .Jan_Duplicate_List_Item, .Jan_Sort_List_Items, .Jan_Cycle_List_Bullet,
	     .Jan_Repair_List_Indentation, .Jan_Insert_Drawer, .Jan_Insert_Block,
	     .Jan_Move_Structure_Up, .Jan_Move_Structure_Down, .Jan_Delete_Structure,
	     .Jan_Create_Table, .Jan_Align_Table, .Jan_Insert_Table_Row,
	     .Jan_Delete_Table_Row, .Jan_Move_Table_Row_Up, .Jan_Move_Table_Row_Down,
	     .Jan_Duplicate_Table_Row, .Jan_Insert_Table_Column, .Jan_Delete_Table_Column,
	     .Jan_Move_Table_Column_Left, .Jan_Move_Table_Column_Right,
	     .Jan_Duplicate_Table_Column, .Jan_Insert_Table_Separator,
	     .Jan_Delete_Table_Separator, .Jan_Edit_Table_Cell, .Jan_Create_Footnote,
	     .Jan_Normalize_Footnote, .Jan_Renumber_Footnotes, .Jan_Move_Footnote_Up,
	     .Jan_Move_Footnote_Down, .Jan_Expand_Template, .Jan_Indent:
		return true
	case .Jan_Context_Action, .Jan_Todo, .Jan_Set_Priority, .Jan_Toggle_Checkbox, .Jan_Update_Statistics,
	     .Jan_Set_Tags, .Jan_Set_Property, .Jan_Timestamp, .Jan_Schedule,
	     .Jan_Deadline, .Jan_Clock_In, .Jan_Clock_Out, .Jan_Clock_Cancel,
	     .Jan_Clock_Switch, .Jan_Clock_Resume, .Jan_Set_Effort,
	     .Jan_Refile, .Jan_Copy_Subtree, .Jan_Archive_Subtree,
	     .Jan_Toggle_Archive, .Jan_Restore_Archive, .Jan_Capture_Finalize,
	     .Jan_Attach, .Jan_Attachment_Rename,
	     .Jan_Attachment_Delete, .Jan_Attachment_Synchronize,
	     .Jan_Agenda_Todo, .Jan_Agenda_Set_Priority, .Jan_Agenda_Set_Tags,
	     .Jan_Agenda_Set_Property, .Jan_Agenda_Schedule, .Jan_Agenda_Deadline,
	     .Jan_Agenda_Set_Effort, .Jan_Agenda_Clock_In, .Jan_Agenda_Clock_Out,
	     .Jan_Agenda_Refile, .Jan_Agenda_Archive, .Jan_Agenda_Capture,
	     .Jan_Agenda_Delete, .Jan_Agenda_Apply_Selection,
	     .Jan_Table_Recalculate, .Jan_Table_Recalculate_All,
	     .Jan_Execute, .Jan_Execute_Subtree, .Jan_Execute_Buffer, .Jan_Call,
	     .Jan_Result_Remove, .Jan_Return_From_Source, .Jan_Execute_Batch:
		return true
	case .Jan_Demarcate_Source, .Jan_Insert_Header_Argument,
	     .Jan_Context_Meta_Up, .Jan_Context_Meta_Down:
		return true
	case .Jan_Citation_Insert, .Jan_Bibliography_Insert,
	     .Jan_Encrypt_Subtree, .Jan_Decrypt_Subtree,
	     .Jan_Mobile_Pull, .Jan_Mobile_Reconcile, .Jan_Dynamic_Block_Update:
		return true
	case:
		return false
	}
}

@(private)
contextual_route_contract :: proc(
	route: Contextual_Route,
) -> (
	interaction.Implementation_Class,
	interaction.Invocation_Class,
	interaction.Text_Requirement,
	interaction.Command_Effects,
	bool,
) {
	invocation := interaction.Invocation_Class.Ordinary
	text_requirement := interaction.Text_Requirement.Prohibited
	switch route {
	case .Prompt_Insert_Text, .Component_Query_Text:
		invocation = .Text_Input
		text_requirement = .Required
	case .Cancel:
		invocation = .Cancellation
	case .Prompt_Delete_Previous, .Prompt_Accept,
	     .Prompt_Choice_1, .Prompt_Choice_2, .Prompt_Choice_3, .Prompt_Choice_4,
	     .Search_History_Newer, .Search_History_Older, .Search_History_Complete,
	     .Search_Extend_Textual, .Search_Extend_Structural, .Search_Extend_Transferred,
	     .Search_Toggle_Case, .Search_Toggle_Pattern, .Search_Toggle_Word,
	     .Search_Toggle_Symbol, .Search_Toggle_Whitespace, .Search_Materialize,
	     .Query_Replace_And_Exit, .Query_Quit,
	     .Component_Previous_Row, .Component_Next_Row, .Component_Activate_Current,
	     .Component_Mark_Save, .Component_Mark_Kill, .Component_Unmark,
	     .Component_Execute, .Component_Close, .Component_Query_Delete_Previous,
	     .Component_Complete_Current, .Result_First, .Result_Last,
	     .Result_Refresh, .Result_Edit, .Result_Apply,
	     .Ksawery_Mark, .Ksawery_Unmark, .Ksawery_Clear_Marks,
	     .Ksawery_Stage, .Ksawery_Unstage, .Ksawery_Discard,
	     .Ksawery_Commit, .Ksawery_Amend, .Ksawery_Fixup, .Ksawery_Sequence,
	     .Ksawery_History, .Ksawery_History_Next, .Ksawery_Refs,
	     .Ksawery_Stashes, .Ksawery_Worktrees, .Ksawery_Blame, .Ksawery_Reflog,
	     .Ksawery_Processes,
	     .Ksawery_Providers,
	     .Ksawery_Provider_Reload, .Ksawery_Provider_Disable,
	     .Ksawery_Raw_Command,
	     .Ksawery_Fetch, .Ksawery_Push,
	     .Ksawery_Branch_Create, .Ksawery_Branch_Switch, .Ksawery_Branch_Rename, .Ksawery_Branch_Delete,
	     .Ksawery_Tag_Create, .Ksawery_Tag_Delete,
	     .Ksawery_Merge_Fast_Forward, .Ksawery_Merge, .Ksawery_Merge_No_Fast_Forward,
	     .Ksawery_Merge_Continue, .Ksawery_Merge_Abort,
	     .Ksawery_Rebase, .Ksawery_Rebase_Autosquash, .Ksawery_Rebase_Continue,
	     .Ksawery_Rebase_Skip, .Ksawery_Rebase_Abort,
	     .Ksawery_Sequence_Mark, .Ksawery_Sequence_Unmark,
	     .Ksawery_Cherry_Pick, .Ksawery_Cherry_Pick_Continue,
	     .Ksawery_Cherry_Pick_Skip, .Ksawery_Cherry_Pick_Abort,
	     .Ksawery_Revert, .Ksawery_Revert_Continue, .Ksawery_Revert_Skip, .Ksawery_Revert_Abort,
	     .Ksawery_Bisect_Good, .Ksawery_Bisect_Bad, .Ksawery_Bisect_Start,
	     .Ksawery_Bisect_Skip, .Ksawery_Bisect_Reset,
	     .Ksawery_Conflict_Mark, .Ksawery_Conflict_Assist, .Ksawery_Conflict_Use_Base,
	     .Ksawery_Conflict_Use_Current, .Ksawery_Conflict_Use_Applied,
	     .Ksawery_Conflict_Delete:
	case .Invalid:
		return {}, {}, {}, {}, false
	}
	return .Native, invocation, text_requirement, {.View}, true
}
