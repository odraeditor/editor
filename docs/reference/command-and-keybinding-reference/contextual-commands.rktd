; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.
;
; Projection of user-invokable module-local commands that do not enter the
; editor-wide command registry. Keep names aligned with src/command/maksym.rkt
; and bindings aligned with src/maksym_module/module.odin.

(
 ("Maksym" "maksym-copy-absolute-paths" "Copy absolute paths for the active Maksym target set." (("Contextual" "C-0 w")))
 ("Maksym" "maksym-copy-names" "Copy names for the active Maksym target set." (("Contextual" "w")))
 ("Maksym" "maksym-copy-targets" "Copy the active Maksym target set to a selected directory." (("Contextual" "C")))
 ("Maksym" "maksym-create-directory" "Create a directory below the active Maksym directory." (("Contextual" "+")))
 ("Maksym" "maksym-delete-targets" "Delete the active Maksym target set after review." (("Contextual" "D")))
 ("Maksym" "maksym-describe-entry-type" "Report the type of the selected Maksym entry." (("Contextual" "y")))
 ("Maksym" "maksym-find-file-relative" "Find a path relative to the active Maksym directory." (("Contextual" "C-x C-f")))
 ("Maksym" "maksym-invert-marks" "Invert marks in the active Maksym listing." (("Contextual" "t")))
 ("Maksym" "maksym-mark-entry" "Add the selected Maksym entry to the target set." (("Contextual" "m")))
 ("Maksym" "maksym-move-targets" "Move or rename the active Maksym target set." (("Contextual" "R")))
 ("Maksym" "maksym-next-marked-entry" "Move to the next marked Maksym entry." (("Contextual" "M-}")))
 ("Maksym" "maksym-previous-marked-entry" "Move to the previous marked Maksym entry." (("Contextual" "M-{")))
 ("Maksym" "maksym-rename-pattern" "Prepare a bounded pattern rename for marked Maksym entries." (("Contextual" "% R")))
 ("Maksym" "maksym-shell-command" "Run a shell command on the active Maksym target set." (("Contextual" "!") ("Contextual" "X")))
 ("Maksym" "maksym-shell-command-async" "Run an asynchronous shell command on the active Maksym target set." (("Contextual" "&")))
 ("Maksym" "maksym-shell-command-current-directory" "Run a shell command from the active Maksym directory." (("Contextual" "M-!")))
 ("Maksym" "maksym-unmark-all" "Clear every mark in the active Maksym listing." (("Contextual" "U")))
 ("Maksym" "maksym-unmark-entry" "Remove the selected Maksym entry from the target set." (("Contextual" "u")))
)
