// SPDX-FileCopyrightText: 2026 Adrian PK
// SPDX-License-Identifier: GPL-3.0-only
//
// This file is part of Odra. See COPYING for license terms.

// Package terminal_session composes PTY processes with terminal emulator state.
package terminal_session

import "../interactive_session"
import "../terminal_emulator"

/* MAX_SESSIONS matches the immutable process and emulator capacity. */
MAX_SESSIONS :: 32
/* OPERATING_SCROLLBACK_BYTES is the ordinary retained-text target. */
OPERATING_SCROLLBACK_BYTES :: 32 * 1_024 * 1_024
/* OPERATING_SCROLLBACK_ROWS is the ordinary retained physical-line target. */
OPERATING_SCROLLBACK_ROWS :: 100_000
/* MAX_SCROLLBACK_ROWS is the immutable retained physical-line ceiling. */
MAX_SCROLLBACK_ROWS :: 250_000
/* MAX_SCROLLBACK_BYTES is the immutable retained-text byte ceiling. */
MAX_SCROLLBACK_BYTES :: 64 * 1_024 * 1_024
/* OPERATING_STATE_BYTES is the ordinary aggregate state target per session. */
OPERATING_STATE_BYTES :: 64 * 1_024 * 1_024
/* MAX_STATE_BYTES is the immutable aggregate state ceiling per session. */
MAX_STATE_BYTES :: 128 * 1_024 * 1_024
/* OPERATING_OUTPUT_TURN_BYTES bounds output parsed in one session turn. */
OPERATING_OUTPUT_TURN_BYTES :: 256 * 1_024
/* MAX_OUTPUT_TURN_BYTES is the immutable parser-turn ceiling. */
MAX_OUTPUT_TURN_BYTES :: 1 * 1_024 * 1_024
/* OPERATING_OUTPUT_TURN_NANOSECONDS bounds one parser turn. */
OPERATING_OUTPUT_TURN_NANOSECONDS :: i64(4_000_000)
/* MAX_OUTPUT_TURN_NANOSECONDS is the immutable parser-turn time ceiling. */
MAX_OUTPUT_TURN_NANOSECONDS :: i64(8_000_000)
/* MAX_PROJECTED_CELLS matches the existing display cell-product ceiling. */
MAX_PROJECTED_CELLS :: 1_048_576
/* MAX_TERMINAL_COLUMNS is the immutable terminal width ceiling. */
MAX_TERMINAL_COLUMNS :: 2_048
/* MAX_TERMINAL_ROWS is the immutable terminal height ceiling. */
MAX_TERMINAL_ROWS :: 1_024
/* OPERATING_COPIED_TEXT_BYTES bounds one ordinary copied text snapshot. */
OPERATING_COPIED_TEXT_BYTES :: 1 * 1_024 * 1_024
/* MAX_COPIED_TEXT_BYTES is the immutable copied text snapshot ceiling. */
MAX_COPIED_TEXT_BYTES :: 4 * 1_024 * 1_024
/* OUTPUT_CHUNK_BYTES bounds each copied PTY-to-emulator transfer. */
OUTPUT_CHUNK_BYTES :: 16 * 1_024
/* MAX_INPUT_TEXT_BYTES bounds one normalized text input event. */
MAX_INPUT_TEXT_BYTES :: 4 * 1_024
/* MAX_INPUT_REPEAT_COUNT bounds one repeated normalized input request. */
MAX_INPUT_REPEAT_COUNT :: 1_024
/* MAX_ENCODED_KEY_BYTES bounds one normalized text or emulator key sequence. */
MAX_ENCODED_KEY_BYTES :: MAX_INPUT_TEXT_BYTES
/* MAX_PASTE_FRAMING_BYTES bounds bracketed-paste prefix and suffix bytes. */
MAX_PASTE_FRAMING_BYTES :: 12
/* MAX_SEMANTIC_RECORDS bounds retained prompt and command-result records. */
MAX_SEMANTIC_RECORDS :: terminal_emulator.SEMANTIC_ANCHOR_CAPACITY
/* MAX_OSC_133_BYTES bounds one sidecar shell-integration sequence. */
MAX_OSC_133_BYTES :: 128
/* MAX_ENCODED_MOUSE_BYTES bounds one negotiated child mouse report. */
MAX_ENCODED_MOUSE_BYTES :: 128
/* MAX_HYPERLINK_BYTES bounds one copied terminal link target. */
MAX_HYPERLINK_BYTES :: 4 * 1_024
/* OPERATING_EVENT_ENTRIES bounds one ordinary session observation queue. */
OPERATING_EVENT_ENTRIES :: 1_024
/* MAX_EVENT_ENTRIES is the immutable per-session observation ceiling. */
MAX_EVENT_ENTRIES :: 4_096
/* OPERATING_EVENT_BYTES bounds one ordinary session observation queue payload. */
OPERATING_EVENT_BYTES :: 1 * 1_024 * 1_024
/* MAX_EVENT_BYTES is the immutable per-session observation payload ceiling. */
MAX_EVENT_BYTES :: 4 * 1_024 * 1_024
/* OPERATING_AGGREGATE_EVENT_ENTRIES bounds ordinary instance-wide observations. */
OPERATING_AGGREGATE_EVENT_ENTRIES :: 8_192
/* MAX_AGGREGATE_EVENT_ENTRIES is the immutable instance-wide observation ceiling. */
MAX_AGGREGATE_EVENT_ENTRIES :: 32_768
/* OPERATING_AGGREGATE_EVENT_BYTES bounds ordinary instance-wide event payload. */
OPERATING_AGGREGATE_EVENT_BYTES :: 8 * 1_024 * 1_024
/* MAX_AGGREGATE_EVENT_BYTES is the immutable instance-wide event payload ceiling. */
MAX_AGGREGATE_EVENT_BYTES :: 32 * 1_024 * 1_024
/* OPERATING_SUBSCRIBERS_PER_SESSION is the ordinary fanout bound. */
OPERATING_SUBSCRIBERS_PER_SESSION :: 8
/* MAX_SUBSCRIBERS_PER_SESSION is the immutable per-session fanout ceiling. */
MAX_SUBSCRIBERS_PER_SESSION :: 16
/* OPERATING_SUBSCRIBERS is the ordinary aggregate subscriber bound. */
OPERATING_SUBSCRIBERS :: 32
/* MAX_SUBSCRIBERS is the immutable aggregate subscriber ceiling. */
MAX_SUBSCRIBERS :: 64
/* MAX_EVENT_BATCH_ENTRIES bounds one owner-thread delivery snapshot. */
MAX_EVENT_BATCH_ENTRIES :: 256
/* MAX_EVENT_BATCH_BYTES bounds one owner-thread delivery snapshot payload. */
MAX_EVENT_BATCH_BYTES :: 1 * 1_024 * 1_024
/* MAX_SUBSCRIBER_TURN_MILLISECONDS bounds one Racket subscriber invocation. */
MAX_SUBSCRIBER_TURN_MILLISECONDS :: 25
/* MAX_SUBSCRIBER_TEMPORARY_BYTES bounds one Racket subscriber invocation. */
MAX_SUBSCRIBER_TEMPORARY_BYTES :: 8 * 1_024 * 1_024
/* MAX_EVENT_PROVIDER_BYTES bounds copied adapter provenance. */
MAX_EVENT_PROVIDER_BYTES :: 96
/* MAX_METADATA_BYTES is the immutable copied title and working-context ceiling. */
MAX_METADATA_BYTES :: terminal_emulator.METADATA_BYTES
/* MAX_IMAGE_PLACEMENTS is the immutable retained image-placement ceiling. */
MAX_IMAGE_PLACEMENTS :: terminal_emulator.IMAGE_PLACEMENTS
/* DEFAULT_BELL_INTERVAL_NANOSECONDS rate-limits admitted child attention. */
DEFAULT_BELL_INTERVAL_NANOSECONDS :: i64(1_000_000_000)

/* Event_Limits configures ordinary queues within immutable safety ceilings. */
Event_Limits :: struct {
	event_entries:           u16,
	event_bytes:             u64,
	aggregate_event_entries: u64,
	aggregate_event_bytes:   u64,
	subscribers_per_session: u16,
	subscribers:             u16,
}

/* DEFAULT_EVENT_LIMITS preserves the admitted factory event policy. */
DEFAULT_EVENT_LIMITS :: Event_Limits {
	event_entries = OPERATING_EVENT_ENTRIES,
	event_bytes = OPERATING_EVENT_BYTES,
	aggregate_event_entries = OPERATING_AGGREGATE_EVENT_ENTRIES,
	aggregate_event_bytes = OPERATING_AGGREGATE_EVENT_BYTES,
	subscribers_per_session = OPERATING_SUBSCRIBERS_PER_SESSION,
	subscribers = OPERATING_SUBSCRIBERS,
}

/* Session_ID identifies one fixed terminal-session registry slot. */
Session_ID :: distinct u32
/* Session_Generation invalidates stale terminal-session references. */
Session_Generation :: distinct u32

/* Session_Ref identifies one exact composed terminal-session generation. */
Session_Ref :: struct {
	id:         Session_ID,
	generation: Session_Generation,
}

/* Lifecycle records ownership of both process and emulator resources. */
Lifecycle :: enum u8 {
	Invalid = 0,
	Running,
	Exited,
	Failed,
	Closed,
}

/* Failure_Code is the stable terminal-session failure vocabulary. */
Failure_Code :: enum u16 {
	None = 0,
	Invalid_Argument,
	Stale_Reference,
	Capacity,
	Allocation,
	Process,
	Emulator,
	Input_Limit,
	Output_Limit,
	Projection_Limit,
	Cleanup,
	Paste_Rejected,
	Navigation_Unavailable,
	Hyperlink_Rejected,
	Event_Limit,
	Subscriber_Limit,
}

/* Failure_Stage identifies the composed operation that failed. */
Failure_Stage :: enum u8 {
	None = 0,
	Initialize,
	Open,
	Process,
	Parse,
	Input,
	Project,
	Scrollback,
	Resize,
	Close,
	Copy_Mode,
	Paste,
	Navigation,
	Mouse,
	Hyperlink,
}

/* Input_Kind identifies one normalized terminal input family. */
Input_Kind :: enum u8 {
	Invalid,
	Text,
	Key,
	Focus,
}

/* Input_Key is the terminal-session semantic key vocabulary. */
Input_Key :: enum u8 {
	Invalid,
	Character,
	Enter,
	Tab,
	Backspace,
	Delete,
	Escape,
	Up,
	Down,
	Left,
	Right,
	Home,
	End,
	Prior,
	Next,
	Space,
}

/* Input_Action distinguishes an initial key press from a repeated event. */
Input_Action :: enum u8 {
	Invalid,
	Press,
	Repeat,
}

/* Input_Modifier is copied frontend-independent modifier state. */
Input_Modifier :: enum u8 {
	Shift,
	Control,
	Alt,
	Super,
}

/* Input_Modifiers combines copied frontend-independent modifier states. */
Input_Modifiers :: bit_set[Input_Modifier; u8]

/* Focus_Event identifies a normalized terminal presentation focus transition. */
Focus_Event :: enum u8 {
	Invalid,
	Gained,
	Lost,
}

/* Input_Source records whether contextual routing admitted ordinary or literal input. */
Input_Source :: enum u8 {
	Invalid,
	Ordinary,
	Literal_Next,
}

/* Input_Request borrows one bounded normalized input event. */
Input_Request :: struct {
	kind:         Input_Kind,
	key:          Input_Key,
	action:       Input_Action,
	modifiers:    Input_Modifiers,
	text:         string,
	focus:        Focus_Event,
	source:       Input_Source,
	repeat_count: u16,
}

/* Input_Observation reports exactly what one admitted input request queued. */
Input_Observation :: struct {
	ref:             Session_Ref,
	kind:            Input_Kind,
	source:          Input_Source,
	repeat_count:    u16,
	encoded_bytes:   u64,
	queued_bytes:    u64,
	queue_bytes:     u64,
	focus_reporting: bool,
}

/* Mouse_Action identifies one normalized physical pointer transition. */
Mouse_Action :: enum u8 {
	Invalid = 0,
	Press,
	Release,
	Motion,
}

/* Mouse_Button identifies pointer buttons and normalized wheel steps. */
Mouse_Button :: enum u8 {
	None = 0,
	Left,
	Right,
	Middle,
	Wheel_Up,
	Wheel_Down,
}

/* Mouse_Route records which authority owns one normalized mouse event. */
Mouse_Route :: enum u8 {
	Invalid = 0,
	Local,
	Child,
	Hyperlink,
}

/* Mouse_Request borrows one normalized surface-space mouse event. */
Mouse_Request :: struct {
	action:    Mouse_Action,
	button:    Mouse_Button,
	modifiers: Input_Modifiers,
	x, y:      f32,
}

/* Mouse_Observation reports routing without simulating frontend input. */
Mouse_Observation :: struct {
	ref:             Session_Ref,
	route:           Mouse_Route,
	mouse_tracking:  bool,
	encoded_bytes:   u64,
	queued_bytes:    u64,
	queue_bytes:     u64,
	hyperlink_bytes: u32,
}

/* Hyperlink_Target_Kind is the initial explicit external-resource allowlist. */
Hyperlink_Target_Kind :: enum u8 {
	Invalid = 0,
	HTTP,
	HTTPS,
	Mailto,
	File,
}

/* Hyperlink_Observation reports one copied and validated inert target. */
Hyperlink_Observation :: struct {
	ref:    Session_Ref,
	kind:   Hyperlink_Target_Kind,
	column: u16,
	row:    u32,
	bytes:  u32,
}

/* Failure_Record retains the first bounded terminal-session failure. */
Failure_Record :: struct {
	stage:          Failure_Stage,
	code:           Failure_Code,
	process_code:   interactive_session.Failure_Code,
	emulator_result: terminal_emulator.Result,
	limit:          u64,
	actual:         u64,
}

/* Limits defines operating bounds below immutable terminal-session ceilings. */
Limits :: struct {
	output_turn_bytes:       u64,
	output_turn_nanoseconds: i64,
	scrollback_bytes:        u64,
	scrollback_rows:         u64,
	state_bytes:             u64,
	copied_text_bytes:       u64,
}

/* DEFAULT_LIMITS defines the ordinary terminal-session policy. */
DEFAULT_LIMITS :: Limits {
	output_turn_bytes = OPERATING_OUTPUT_TURN_BYTES,
	output_turn_nanoseconds = OPERATING_OUTPUT_TURN_NANOSECONDS,
	scrollback_bytes = OPERATING_SCROLLBACK_BYTES,
	scrollback_rows = OPERATING_SCROLLBACK_ROWS,
	state_bytes = OPERATING_STATE_BYTES,
	copied_text_bytes = OPERATING_COPIED_TEXT_BYTES,
}

/* Session_Record is copied inspection without direct resource ownership. */
Session_Record :: struct {
	ref:               Session_Ref,
	lifecycle:         Lifecycle,
	process:           interactive_session.Session_Record,
	emulator:          terminal_emulator.Ref,
	render_revision:   u64,
	output_bytes:      u64,
	writeback_bytes:   u64,
	retained_bytes:    u64,
	projection_bytes:  u64,
	effects:           Effect_Record,
	failure:           Failure_Record,
}

/* Attention_Channel selects admitted host attention without changing session semantics. */
Attention_Channel :: enum u8 {
	None = 0,
	Audible,
	Visual,
	Both,
}

/* Progress_State is copied non-executable child progress metadata. */
Progress_State :: enum u8 {
	Unreported = 0,
	Removed,
	Set,
	Error,
	Indeterminate,
	Paused,
}

/* Effect_Policy fixes one session's bounded attention authority. */
Effect_Policy :: struct {
	attention:                 Attention_Channel,
	bell_interval_nanoseconds: i64,
}

/* DEFAULT_EFFECT_POLICY denies host attention while retaining semantic observations. */
DEFAULT_EFFECT_POLICY :: Effect_Policy {
	attention = .None,
	bell_interval_nanoseconds = DEFAULT_BELL_INTERVAL_NANOSECONDS,
}

/* Effect_Record reports bounded terminal-originated effects and explicit dispositions. */
Effect_Record :: struct {
	policy:                       Effect_Policy,
	bell_requests:                u64,
	bell_admitted:                u64,
	bell_suppressed:              u64,
	device_responses:             u64,
	title_changes:                u64,
	working_context_changes:      u64,
	clipboard_read_denials:       u64,
	clipboard_write_denials:      u64,
	notification_denials:         u64,
	progress_reports:             u64,
	unknown_sequences:            u64,
	unknown_sequence_bytes:       u64,
	metadata_revision:            u64,
	metadata_truncations:         u64,
	diagnostics:                  u64,
	progress_state:               Progress_State,
	progress_percent:             i16,
}

/* Effect_Observation reports one parser turn without publishing host effects itself. */
Effect_Observation :: struct {
	bell_requests:           u64,
	bell_admitted:           bool,
	audible_attention:       bool,
	visual_attention:        bool,
	title_changed:           bool,
	working_context_changed: bool,
	progress_changed:        bool,
	denied_effects:          u64,
	diagnostics:             u64,
}

/* Metadata_Kind selects one copied non-executable terminal metadata value. */
Metadata_Kind :: enum u8 {
	Invalid = 0,
	Title,
	Working_Context,
}

/* Metadata_Copy reports bounded caller-owned metadata transfer. */
Metadata_Copy :: struct {
	ref:            Session_Ref,
	kind:           Metadata_Kind,
	revision:       u64,
	required_bytes: u64,
	copied_bytes:   u64,
	truncated:      bool,
}

/* Event_Kind is the closed native terminal observation vocabulary. */
Event_Kind :: enum u8 {
	Invalid = 0,
	Prompt_Boundary,
	Command_Boundary,
	Working_Context,
	Title,
	Bell,
	Result_Location,
	Process_Exit,
	Normalized_Text,
	Terminal_Revision,
	Raw_Output,
	Overflow,
}

/* Event_Kind_Set selects terminal observations for one subscription. */
Event_Kind_Set :: bit_set[Event_Kind; u16]

/* Event_Provider owns bounded adapter provenance. */
Event_Provider :: struct {
	bytes:  [MAX_EVENT_PROVIDER_BYTES]u8,
	length: u8,
}

/* Event_Record owns one bounded native observation payload while queued. */
Event_Record :: struct {
	ref:          Session_Ref,
	sequence:     u64,
	kind:         Event_Kind,
	provider:     Event_Provider,
	values:       [4]u64,
	signed_value: i32,
	flags:        u8,
	payload:      []u8,
}

/* Subscription_ID identifies one fixed event-subscriber slot. */
Subscription_ID :: distinct u32
/* Subscription_Generation invalidates stale subscriber references. */
Subscription_Generation :: distinct u32

/* Subscription_Ref identifies one exact terminal subscriber generation. */
Subscription_Ref :: struct {
	id:         Subscription_ID,
	generation: Subscription_Generation,
}

/* Subscription_Definition borrows one explicit bounded observation policy. */
Subscription_Definition :: struct {
	sessions:               []Session_Ref,
	kinds:                  Event_Kind_Set,
	raw_output:             bool,
	handler:                string,
	batch_events:           u16,
	batch_bytes:            u64,
	turn_milliseconds:      u16,
	temporary_memory_bytes: u64,
}

/* Subscription_Record is copied generation-scoped delivery metadata. */
Subscription_Record :: struct {
	ref:                    Subscription_Ref,
	session_count:          u8,
	handler:                Event_Provider,
	batch_events:           u16,
	batch_bytes:            u64,
	turn_milliseconds:      u16,
	temporary_memory_bytes: u64,
	active:                 bool,
	failure:                Failure_Record,
}

/* Event_Batch is caller-owned copied delivery storage and acknowledgment identity. */
Event_Batch :: struct {
	subscription: Subscription_Ref,
	events:       []Event_Record,
	payload:      []u8,
	event_count:  u16,
	payload_bytes: u64,
	sessions:     [MAX_SESSIONS]Session_Ref,
	cursors:      [MAX_SESSIONS]u64,
	session_count: u8,
}

/* Prompt_Movement selects one confirmed retained OSC 133 prompt boundary. */
Prompt_Movement :: enum u8 {
	Invalid = 0,
	Previous,
	Next,
}

/* Prompt_Record is one copied, generation-local confirmed prompt boundary. */
Prompt_Record :: struct {
	ref:      Session_Ref,
	sequence: u64,
	row:      u64,
	column:   u16,
}

/* Command_Result_Record is one bounded OSC 133 command completion. */
Command_Result_Record :: struct {
	ref:                 Session_Ref,
	sequence:            u64,
	prompt_sequence:     u64,
	output_start_bytes:  u64,
	output_end_bytes:    u64,
	exit_status:         i32,
	exit_status_present: bool,
}

/* Semantic_Stats reports bounded shell-integration ownership. */
Semantic_Stats :: struct {
	ref:             Session_Ref,
	prompt_records:  u16,
	result_records:  u16,
	next_sequence:   u64,
	alternate_screen: bool,
}

/* Open_Request borrows all data needed for atomic process and emulator startup. */
Open_Request :: struct {
	process:  interactive_session.Session_Prepare_Request,
	start:    interactive_session.Process_Start_Request,
	emulator: terminal_emulator.Options,
	limits:   Limits,
}

/* Registry owns composed terminal sessions and their subordinate registries. */
Registry :: struct {
	state:  rawptr,
	closed: bool,
}

/* Registry_Stats is one immutable aggregate ownership snapshot. */
Registry_Stats :: struct {
	session_count:      u16,
	running_count:      u16,
	exited_count:       u16,
	failed_count:       u16,
	output_bytes:       u64,
	writeback_bytes:    u64,
	retained_bytes:     u64,
	projection_bytes:   u64,
}

/* Render_Cell is one copied frontend-independent terminal cell. */
Render_Cell :: terminal_emulator.Projected_Cell
/* Render_Row is one copied frontend-independent terminal row. */
Render_Row :: terminal_emulator.Projected_Row
/* Image_Placement is copied bounded terminal image metadata. */
Image_Placement :: terminal_emulator.Image_Placement

/* Viewport_Action changes one session's shared terminal viewport. */
Viewport_Action :: enum u8 {
	Top = 0,
	Bottom,
	Delta,
	Row,
}

/* Text_Scope identifies the copied terminal content requested by a caller. */
Text_Scope :: enum u8 {
	Screen = 0,
	Viewport,
	Screen_Range,
	History_Range,
}

/* Text_Range is one inclusive coordinate range in its requested row space. */
Text_Range :: struct {
	start_column: u16,
	start_row:    u32,
	end_column:   u16,
	end_row:      u32,
	rectangle:    bool,
}

/* Text_Request borrows one bounded plain-text projection request. */
Text_Request :: struct {
	scope:      Text_Scope,
	range:      Text_Range,
	normalized: bool,
}

/* Scrollback_Record is copied retained-range and viewport-follow state. */
Scrollback_Record :: struct {
	ref:                  Session_Ref,
	total_rows:           u64,
	scrollback_rows:      u64,
	retained_start_row:   u64,
	retained_end_row:     u64,
	viewport_offset:      u64,
	viewport_rows:        u64,
	scrollback_max_bytes: u64,
	scrollback_max_rows:  u64,
	compression_activity: u64,
	following:            bool,
}

/* Compression_Observation reports one bounded incremental compression step. */
Compression_Observation :: struct {
	ref:             Session_Ref,
	activity_before: u64,
	activity_after:  u64,
	pending:         bool,
	supported:       bool,
	progress:        bool,
}

/* Text_Copy reports copied bytes and explicit snapshot truncation. */
Text_Copy :: struct {
	ref:            Session_Ref,
	scope:          Text_Scope,
	range:          Text_Range,
	required_bytes: u64,
	copied_bytes:   u64,
	limit_bytes:    u64,
	truncated:      bool,
	normalized:     bool,
}

/* Copy_Movement identifies one retained-text point transition. */
Copy_Movement :: enum u8 {
	Invalid = 0,
	Previous_Column,
	Next_Column,
	Previous_Row,
	Next_Row,
	Line_Start,
	Line_End,
	Previous_Page,
	Next_Page,
	Retained_Start,
	Retained_End,
}

/* Copy_Pointer_Action identifies one local retained-text pointer transition. */
Copy_Pointer_Action :: enum u8 {
	Invalid = 0,
	Begin,
	Extend,
}

/* Copy_Pointer_Request maps one signed viewport cell into retained copy state. */
Copy_Pointer_Request :: struct {
	action:       Copy_Pointer_Action,
	viewport_row: i64,
	column:       i64,
}

/* Copy_Search_Direction identifies one bounded literal search direction. */
Copy_Search_Direction :: enum u8 {
	Invalid = 0,
	Forward,
	Backward,
}

/* Copy_Mode_State is caller-owned state for one terminal view. */
Copy_Mode_State :: struct {
	active:               bool,
	point_row:            u64,
	point_column:         u32,
	desired_column:       u32,
	mark_present:         bool,
	selection_active:     bool,
	mark_row:             u64,
	mark_column:          u32,
	viewport_top_row:     u64,
	viewport_rows:        u64,
	follow_tail_on_entry: bool,
}

/* Copy_Mode_Transition reports one local transition without terminal input. */
Copy_Mode_Transition :: struct {
	state:                 Copy_Mode_State,
	changed:               bool,
	selection_deactivated: bool,
	completed:             bool,
	resume_follow_tail:    bool,
}

/* Copy_Search_Observation reports one bounded retained-text search. */
Copy_Search_Observation :: struct {
	state:         Copy_Mode_State,
	found:         bool,
	wrapped:       bool,
	searched_bytes: u64,
}

/* Paste_Request borrows one bounded UTF-8 text transfer for terminal input. */
Paste_Request :: struct {
	text:               string,
	allow_unsafe:       bool,
	replace_codepoints: u32,
}

/* Paste_Observation reports validated terminal-aware framing and PTY queueing. */
Paste_Observation :: struct {
	ref:             Session_Ref,
	text_bytes:      u64,
	encoded_bytes:   u64,
	queued_bytes:    u64,
	queue_bytes:     u64,
	bracketed:       bool,
	unsafe_accepted: bool,
	replaced_codepoints: u32,
}

/* Render_Revision is copied metadata for one stable frontend-independent frame. */
Render_Revision :: struct {
	ref:              Session_Ref,
	revision:         u64,
	projection:       terminal_emulator.Projection,
	row_count:        u64,
	cell_count:       u64,
	projection_bytes: u64,
	image_generation: u64,
	image_count:      u64,
	image_bytes:      u64,
	images_truncated: bool,
}

/* Output_Observation reports one typed, bounded PTY-to-terminal turn. */
Output_Observation :: struct {
	ref:                   Session_Ref,
	process_read_bytes:    u64,
	parsed_bytes:          u64,
	writeback_bytes:       u64,
	bell_count:            u64,
	writeback_count:       u64,
	effects:               Effect_Observation,
	process_exited:        bool,
	output_pending:        bool,
	input_pending:         bool,
	byte_budget_exhausted: bool,
	time_budget_exhausted: bool,
	progress:              bool,
	failure:               Failure_Record,
}

/* Output_Batch reports one fair aggregate terminal-output turn. */
Output_Batch :: struct {
	sessions_visited:    u16,
	sessions_progressed: u16,
	process_read_bytes:  u64,
	parsed_bytes:        u64,
	writeback_bytes:     u64,
	work_remaining:      bool,
	failure:             Failure_Record,
}
