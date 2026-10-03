<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Use Factory Go Language Support

This chapter opens a trusted Go Project, observes maintained local syntax,
diagnostics, and completion, and confirms that Factory Go support remains
editable when `gopls` is unavailable.

## Before You Begin

If you enter this chapter directly, first complete [Prepare the User Guide
Exercises](../getting-started/prepare-exercises.md).

Complete
[Use Language Services and Diagnostics](language-services-and-diagnostics.md).
Confirm that Go and `gopls` are available in the environment used to start
Odra:

```sh
command -v go
command -v gopls
gopls version
```

Odra's interoperability acceptance uses `gopls v0.23.0`. A different compatible
version may work, but it is not the recorded acceptance version.

## Create a Go Project

Create one disposable module inside the User Guide work area:

```sh
mkdir -p ~/odra-guide/work/projects/go-language-service
printf 'module example.com/odra-guide\n\ngo 1.22\n' \
  > ~/odra-guide/work/projects/go-language-service/go.mod
printf 'package main\n\nimport "fmt"\n\nfunc main() { fmt.Println("Odra") }\n' \
  > ~/odra-guide/work/projects/go-language-service/main.go
```

Open the directory with `Open Dir`, promote it to a Project, and grant trust to
that exact local Project. External language-service processes do not start for
an ordinary Dir or an untrusted Project.

## Use the Factory Definition

Do not add a Go definition to `init.rkt`. Odra ships `.go` recognition, a
pinned local Tree-sitter syntax provider, the `gopls serve` service profile,
nearest `go.work` or `go.mod` root discovery, and language-service formatting
as one Factory bundle.

Personal language configuration remains available for deliberate overrides or
additional languages. It is not required for this chapter.

## Inspect the Catalog and Session

Open `main.go`, then run `M-x describe-language-support`. Confirm these facts:

1. The document language is `go` because `.go` is a confirmed suffix.
2. The selected service is `gopls` from Factory configuration.
3. The resolved root contains `go.mod`.
4. The executable is available through controlled lookup.

Run `M-x describe-language-service`. Wait until the selected session is active
and diagnostics and completion are negotiated. The service command is a direct
argument vector; Odra does not pass it through a shell.

## Exercise Diagnostics and Completion

Replace the function body with:

```go
func main() {
    fmt.Prin
    _ = missingName
}
```

The undefined identifier produces a diagnostic. Run
`M-x list-language-diagnostics` to inspect it.

Place point after `fmt.Prin` and press `C-M-i`. Select one of the `Print`
completion candidates, then undo the accepted edit. The diagnostic and
completion use Odra's existing language-independent adapters.

Restore the valid function before continuing.

## Observe Unavailable Recovery

Exit Odra, launch it from an environment that cannot resolve `gopls`, and open
the same trusted Project. `M-x describe-language-support` reports the selected
definition as unavailable while `main.go` remains editable with local syntax.

Restore the normal launch environment and restart Odra. The same Factory
configuration resolves `gopls` again; no `init.rkt` change is required.

## Verify the Result

You have completed this chapter when the Factory bundle recognizes `.go`,
provides local syntax, selects `gopls`, resolves the module root, exposes one
diagnostic and completion candidates, and preserves syntax-aware editing when
the executable is unavailable.

For Rust installation and recovery, see the
[Rust Language Support Reference](../../../reference/language-support/rust/index.md).
For TypeScript, JavaScript, HTML, and CSS configuration recipes, see
[Set Up and Diagnose Language Services](../../../how-to/use-language-services/index.md).
For exact constructors, precedence, bounds, package facets, and feature
behavior, see the
[Language Support Configuration Reference](../../../reference/language-support-configuration/index.md).

---

[Previous: Use Language Services and Diagnostics](language-services-and-diagnostics.md) ·
[User Guide](../index.md) ·
[Next: Use the Basic Language Pack](use-the-basic-language-pack.md)
