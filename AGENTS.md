# Repository guidance

## Project and layout

This repository provides an Objective-C XCTest compatibility library and the
`xctest` command-line runner for GNUstep. It implements a subset of XCTest;
do not assume that Apple XCTest APIs are available here.

- `XCTest/`: public headers, assertion macros and helpers, test case lifecycle,
  discovery of test methods, and asynchronous expectations.
- `XCTest/GSXCTestRunner.h` / `XCTest/GSXCTestRunner.m`: class discovery,
  test selection, class lifecycle, execution, and aggregate results.
  `XCTestPrivate.h` and `GSXCTestReporting.h` are private headers; they are
  not installed.
- `main.m`: CLI argument handling and test bundle loading.
- `GNUmakefile` and `XCTest/GNUmakefile`: runner and library build definitions.
- `Tests/Regression.m`: standalone regression checks, including checks of
  expected assertion failures.
- `Tests/Fixture.m`: loadable bundle fixtures for CLI checks.
- `Tests/run.sh`: build and regression entry point.
- `Tests/run-*-tests.sh`, with fixture bundles in `Tests/*Fixture/` and shared
  helpers in `Tests/test-helpers.sh`: regression scripts for one area each
  (CLI filters, output formats, reports, hosted and parallel runs, ...).
- `xctest.make` and `xctest-bundle`: installed helpers for building test
  bundles with gnustep-make and other build systems.
- `README.md`: user-facing build instructions and supported behavior.

## Build and validation

Use a configured GNUstep development environment with `GNUSTEP_MAKEFILES` set
and Objective-C exceptions and blocks support enabled. Run from the repo root:

```sh
make
sh Tests/run.sh
```

`make check` runs `Tests/run.sh` and every `Tests/run-*-tests.sh` script;
`meson test -C build` runs them from a Meson build. The test script builds both
the project and the tests, sets `LD_LIBRARY_PATH`
to use the local library, and checks the regression program and CLI exit codes.
Some fixtures deliberately fail: judge the suite by the script's exit status
and final `All regression and CLI checks passed.` message, not isolated failure
logs. For direct runs on Linux, include `XCTest/obj` in `LD_LIBRARY_PATH`.
The local runner is `obj/xctest`; installation is unnecessary for validation.

Run the regression script after implementation or build changes. Extend the
existing regression checks for behavioral fixes and new functionality; add CLI
fixtures/checks when changing argument parsing, filtering, or exit statuses.
Documentation-only edits do not require compiling. Report which checks ran and
any environment limitations; do not describe unrun checks as passing.

## Implementation conventions

- Match the surrounding Objective-C style and keep changes focused. Preserve
  existing file line endings and copyright/license headers.
- Use manual reference counting consistently (`retain`, `release`,
  `autorelease`, and `[super dealloc]`). Copy stored blocks and release them
  appropriately; do not introduce ARC as an incidental change.
- Keep library functionality usable by standalone test cases without linking
  the runner. Avoid introducing Apple-only framework dependencies.
- Register new source files and exported headers in the relevant `GNUmakefile`;
  expose new public APIs through `XCTest/XCTest.h` where appropriate.
- Preserve single evaluation of assertion operands, useful file/line
  diagnostics, optional formatted messages, and interruption semantics for
  `continueAfterFailure`. Cover numeric edge cases when changing comparisons.
- Preserve deterministic alphabetical discovery, inherited test methods,
  subclass overrides, fresh instances per test, and teardown after failures.
- Keep expectation fulfillment thread-safe. Expectation creation and waits
  occur on the test thread; waits pump its default run loop. Exercise timeout
  and violation paths when changing asynchronous behavior.
- CLI test runs succeed only when at least one test executes and all selected
  tests succeed. Invalid input, unmatched filters, and empty runs must fail.
- Update `README.md` when supported APIs or behavior change. Check declarations,
  implementation, and regression coverage before relying on its feature list.

## Workspace hygiene

Inspect `git status` before editing and preserve unrelated work, including
untracked source files. Do not commit generated `obj/` directories or test
bundles built under `Tests/` (`*.bundle`, `*.xctest`, `*.app`). Files with explicit licenses retain those terms;
otherwise consult `COPYING.LIB` for the LGPL license.
