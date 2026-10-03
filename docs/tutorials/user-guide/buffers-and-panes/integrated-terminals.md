<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Use Integrated Terminals

This chapter teaches one complete terminal workflow without leaving the editor.
At the end, you will have an independent shell session in a lower pane, run a
full-screen program, copy retained output, and return to the previous buffer.

## Open a Terminal

Run `M-x terminal-open`. Odra selects or creates the default terminal for the
active Workspace, opens a pane below the editing pane, and moves focus to
it. Your document remains visible above. Type `pwd` and press Return. Terminal
input goes to the child process; it does not edit a document buffer.

Press `C-x o` to move between the editing and terminal panes. Run
`M-x terminal-open` again to focus the same terminal, without adding a pane.

Run `M-x terminal-toggle` to hide the lower pane and return to editing. The
process and its retained output continue to exist. Running the command again
restores the session and its remembered pane height. You can also use
`terminal-toggle` to create the initial terminal.

## Keep More Than One Session

Run `M-x terminal-new` to create another independent shell in the same lower
pane. The previous shell stays retained. Use
`M-x terminal-list` to select a retained session. A split pane may show the
same terminal session twice; both views then display the same process. Use
`terminal-new` when you need a separate process and history.

`M-x terminal-open-here` starts in the active resource directory.
`M-x terminal-open-project` uses the active or recent Project. Both open in
the lower pane. `M-x terminal-open-other-pane` uses the ordinary other-pane
display policy instead.

## Run One Command

Press `M-!`, enter a shell command, and press Return. Odra starts a bounded
task in the active resource, Project, or home directory and replaces the
active pane with its terminal-backed output. The editor remains responsive
while the process runs.

Press `M-&` for the same one-shot execution without replacing the active
view. The task and its output remain available through `M-x terminal-list`.

Run `M-x compile` to execute a retained compilation command. The prompt starts
with the previous command, or `make` before the first run. After the process
finishes, press `g` in its result buffer or run `M-x recompile` to execute the
same command again.

## Run a Full-Screen Program

Start `vim` in the terminal. Arrow keys, Return, Tab, Escape, Backspace, Page
Up, and Page Down are encoded for the child terminal mode. Use `C-q` followed
by a key when you need to forward the next normalized key literally.

Exit Vim normally. Odra retains the shell session and its scrollback.

## Copy Retained Output

Run `M-x terminal-copy-mode`. Movement and selection operate on retained
terminal text without pausing the child. Copy with the ordinary copy command,
then finish with Return. Press `C-g` to cancel the current copy operation or
leave copy mode according to the current state.

Child-requested clipboard reads and writes remain denied. Explicit copy and
paste continue through Odra's ordinary kill-ring and clipboard authority.

## Use the Pointer in a Terminal

With pointer reporting available, the primary button focuses a visible
terminal pane. The first press on an unfocused terminal changes focus only, so
it cannot also activate something in the child program.

When the child is not using mouse reporting, press and drag the primary button
to select retained terminal text locally. Odra enters terminal copy mode for
the gesture; copy with `M-w` and finish with Return. `M-x terminal-copy-mode`,
`C-SPC`, movement, and `M-w` provide the complete keyboard equivalent.

When a full-screen child requests mouse reporting, subsequent pointer events
belong to that child. Hold Shift while pressing and dragging to keep the
gesture local and select retained text instead. Ordinary terminal wheel events
also follow the child's negotiated mouse mode; wheel scrolling of editor
buffers is not part of the first pointer delivery.

## Finish a Session

Type `exit` in the shell to finish it. Odra closes the default lower terminal
pane and returns to the editor. If no text buffer remains, it opens a scratch
buffer. A later `terminal-open` creates a fresh shell.

Run `M-x terminal-terminate` to request coordinated process termination. A
completed one-shot command remains inspectable in its result buffer.
Closing one view does not terminate a session that is still retained elsewhere.

For exact commands, limits, and exit behavior, read the
[Integrated Terminal Reference](../../../reference/integrated-terminal/index.md).
For configuration, use
[Configure Integrated Terminals](../../../how-to/configure-integrated-terminal/index.md).

---

[Previous: Restore Layouts](restore-layouts.md) ·
[User Guide](../index.md) ·
[Next: Search and Navigation](../search-and-navigation/index.md)
