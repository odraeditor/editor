<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Use the Basic Language Pack

This chapter uses the language support included with Odra, completes one local
syntax and language-service workflow, and shows how the same commands apply to
every maintained programming language.

## Before You Begin

If you enter this chapter directly, first complete
[Prepare the User Guide Exercises](../getting-started/prepare-exercises.md).
Then complete
[Use Language Services and Diagnostics](language-services-and-diagnostics.md).
Use a trusted disposable Project under `~/odra-guide/work/projects/`. Local
syntax does not require Project trust, but external language servers do.

The basic pack recognizes Jan, Odin, Racket, Go, Rust, TypeScript, JavaScript,
HTML, and CSS without personal configuration. Install only the external server
needed for the language you choose. This walkthrough uses Go and `gopls`:

```sh
go install golang.org/x/tools/gopls@v0.23.0
command -v gopls
gopls version
```

## Create the Exercise Project

```sh
mkdir -p ~/odra-guide/work/projects/basic-language-pack
cd ~/odra-guide/work/projects/basic-language-pack
go mod init example.com/basic-language-pack
printf 'package main\n\nimport "fmt"\n\nfunc main() { fmt.Println("Odra") }\n' > main.go
```

Open the directory with `Open Dir`, promote it to a Project, grant trust to
that exact root, and open `main.go`.

## Confirm Recognition and Local Syntax

The `.go` suffix selects the `go` language from `org.odra.go`. Keywords,
strings, functions, and punctuation should receive distinct syntax roles as
soon as the file opens; this does not wait for `gopls`.

Run `M-x describe-language-support`. Confirm the language, Factory bundle,
`go.syntax` provider, `gopls` service, and the root containing `go.mod`.

## Complete a Language Workflow

Change the function body to:

```go
func main() {
    fmt.Prin
    _ = missingName
}
```

Then perform these actions:

1. Place point after `fmt.Prin`, press `C-M-i`, and accept a `Print` completion.
2. Run `M-x language-show-hover` over `fmt`.
3. Run `M-x language-go-to-definition` on a local declaration and return with
   the normal location-history command.
4. Run `M-x list-language-diagnostics` and inspect the undefined identifier.
5. Remove the invalid line and run `M-x language-format-buffer`.
6. Save the file and confirm that the buffer remains valid Go source.

Direct editing also exposes common language actions under `C-c C-l`. Modal
Normal state uses `g d`, `g r`, `K`, and the `g l` prefix. These bindings invoke
the same semantic commands; the interaction profile does not change provider
behavior.

## Observe Service-Independent Editing

Exit Odra and start it from an environment where `gopls` is not on `PATH`.
Open the same file. Recognition, local syntax, movement, selection, editing,
save, and undo remain available. Service-backed commands report the missing
executable instead of disabling the document.

Restore the normal environment. Restart Odra, or run
`M-x restart-language-service` after inspecting a failed session. No personal
language definition is required.

## Try Another Pack Language

Create a file with one of the following selectors and open it in a suitable
trusted Project: `.rkt`, `.rs`, `.ts`, `.js`, `.html`, or `.css`. Install its
documented server only when service-backed intelligence is needed. Use
`M-x describe-language-support` as the common entry point.

Jan (`.org`, `.jan`) and Odin (`.odin`) are also members of the pack. Jan adds
native outline and structured-document commands. Odin uses OLS for diagnostics
and completion. Their setup and capabilities appear beside the other languages
in the [Language Support Reference](../../../reference/language-support/index.md).

## Verify the Result

You have completed the chapter when a Factory language is recognized, local
syntax works before the server starts, completion and diagnostics work with an
available server, navigation and formatting use semantic commands, and the
document remains editable when the server is absent.

---

[Previous: Use Factory Go Language Support](configure-language-support.md) ·
[User Guide](../index.md) ·
[Next: Use Language Completion](language-completion.md)
