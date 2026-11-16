# Testing an app before gnustep-packager packages it

Greeter is a small GNUstep app with an XCTest bundle. Its GitHub Actions
workflow uses [gnustep-packager](https://github.com/danjboyd/gnustep-packager)'s
reusable workflow to build it for Windows, run its tests, and make an MSI. The
MSI is made only if the tests pass.

| File | What it is |
| --- | --- |
| `Greeter.m`, `AppDelegate.m`, `main.m`, `GNUmakefile` | The app. `Greeter` is the part the tests cover. |
| `Tests/` | The test bundle, `GreeterTests.xctest`, built with `xctest.make`. |
| `packaging/package.manifest.json` | gnustep-packager's manifest: build, stage, and the MSI. |
| `packaging/build.sh` | The build step: tools-xctest, the app, then `make check` on the tests. |
| `packaging/stage.sh` | The stage step: the app and its GNUstep runtime, nothing from the tests. |
| `../../.github/workflows/packaged-app-example.yml` | The workflow that calls gnustep-packager. |

## How it works

gnustep-packager's MSI job sets up the gnustep-cli-new toolchain, then runs
the manifest's build and stage commands in that toolchain's CLANG64 shell
(`"kind": "msys2-bash"`), then builds and checks the MSI.

The build step (`packaging/build.sh`):

1. Downloads the tools-xctest 0.8.0 release archive, checks its SHA-256 and
   builds it in `build/`. The toolchain doesn't include tools-xctest yet, so
   it's used from there, uninstalled. Nothing is installed into the
   toolchain, which the later steps still use, or into the stage.
2. Builds `Greeter.app`.
3. Runs `make check` in `Tests/`, pointing `xctest.make` at the uninstalled
   tools-xctest. A failing test fails the step, so the job stops before
   staging and no MSI is made. The JUnit report is written to
   `build/GreeterTests.junit.xml`.

The stage step copies the app, the GNUstep runtime and the DLLs they import.
The app doesn't link XCTest, so nothing from tools-xctest is packaged, and
gnustep-packager's runtime closure check confirms that.

## Using it in your app

- Copy `packaging/` and the workflow. In the manifest, change the `package`
  section, `launch.entryRelativePath`, and the MSI `upgradeCode` (make a new
  one; it identifies your app to Windows Installer). In the workflow, change
  `manifest-path` and `artifact-name`.
- Test the app's code from a bundle, as `Tests/GNUmakefile` does: compile the
  sources under test into the bundle (`GreeterTests_OBJC_FILES` lists
  `../Greeter.m`), or put them in a library that both link.
- In `packaging/build.sh`, change the app and test directories, and the
  stage script's app name.
- Keep the include line in `Tests/GNUmakefile`
  (`XCTEST_MAKE ?= $(GNUSTEP_MAKEFILES)/Auxiliary/xctest.make`). The build
  script overrides it with the uninstalled `xctest.make`. Where tools-xctest
  is installed, the default is used and the `XCTEST_*` overrides in
  `build.sh` can go.

## Limits

- These are unit tests. Hosted tests (`xctest -host`) run inside the app and
  need a display; they're Linux only.
- The workflow pins gnustep-cli-new v0.1.5, the default of gnustep-packager
  v0.1.10. To use a newer toolchain, set gnustep-packager's four
  `gnustep-cli-*` inputs together (see its `docs/github-actions.md`).
- `build.sh` builds against a fixed copy of gnustep-base's
  `NSBackgroundActivityScheduler.h` if the toolchain's still has the
  `__block` instance variable that clang 23 rejects (gnustep/libs-base#809).

## When gnustep-cli ships tools-xctest

When the toolchain includes tools-xctest, `build.sh` doesn't need step 1. It
can run `make -C Tests check` with the installed `xctest.make` and `xctest`.
