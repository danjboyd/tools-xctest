# Testing your app with tools-xctest

This guide is for people who installed GNUstep with
[gnustep-cli](https://github.com/danjboyd/gnustep-cli-new) and want to unit
test their code with XCTest. It goes from a fresh install to a passing test,
then shows how to make CI refuse to package an app whose tests fail.

The [Testing guide workflow](../.github/workflows/testing-guide.yml) runs these
steps on clean Ubuntu 24.04 and Windows Server 2022 runners for every change
to this guide or its example.

## 1. Install gnustep-cli

Follow gnustep-cli's [install
instructions](https://github.com/danjboyd/gnustep-cli-new#install). With
its default `setup --user`, the toolchain lands in
`~/.local/share/gnustep-cli`. Put its tools on `PATH` as setup tells you,
then load its GNUstep environment in every shell you build in:

```sh
. ~/.local/share/gnustep-cli/System/Library/Makefiles/GNUstep.sh
```

### On Windows

gnustep-cli's PowerShell installer puts an MSYS2 `clang64` toolchain, with its
own `bash` and `make`, in `%LOCALAPPDATA%\gnustep-cli`. In PowerShell, check
the installer against its published digest before running it:

```powershell
Invoke-WebRequest -Uri https://github.com/danjboyd/gnustep-cli-new/releases/download/v0.1.9/gnustep-bootstrap.ps1 -OutFile gnustep-bootstrap.ps1
(Get-FileHash -Algorithm SHA256 gnustep-bootstrap.ps1).Hash   # 4D39C0E45C618DD38DAD533BDC6DECD9A4B4CBD92B913084B1D75043298E7BF7
.\gnustep-bootstrap.ps1 setup --user
```

Do the rest of this guide in the toolchain's `bash`, with its environment
loaded:

```powershell
& "$env:LOCALAPPDATA\gnustep-cli\usr\bin\bash.exe" --noprofile --norc
```

```sh
export MSYSTEM=CLANG64 PATH="/clang64/bin:/usr/bin:$PATH"
. /clang64/share/GNUstep/Makefiles/GNUstep.sh
```

That's the shell the CI job uses. `gnustep shell` opens gnustep-cli's own
shell on the same toolchain. Steps 2 to 4 are then the same as on Linux.

## 2. Install tools-xctest

```sh
gnustep install tools-xctest
```

This installs the XCTest library and headers, the `xctest` runner, and
`xctest.make`, which builds test bundles with gnustep-make. The runner goes
on the `PATH` that setup printed, and `xctest.make` is available as
`$(GNUSTEP_MAKEFILES)/Auxiliary/xctest.make`.

If you followed an earlier version of this guide and installed tools-xctest
with `make install` from its source, `gnustep install` refuses to replace
that `xctest.make`. Run `make uninstall` in the source tree first, with
`GNUstep.sh` loaded, then install the package.

### Without gnustep-cli's package

On a toolchain gnustep-cli doesn't manage, build tools-xctest from its
release archive and install it into the toolchain:

```sh
curl -fsSLO https://github.com/danjboyd/tools-xctest/releases/download/v0.8.1/tools-xctest-0.8.1.tar.gz
echo "f02333c61c02533ea1d96c5072608bdbde345f9d0167305100832b6f1b12e189  tools-xctest-0.8.1.tar.gz" | sha256sum -c -
tar -xzf tools-xctest-0.8.1.tar.gz
cd tools-xctest-0.8.1
make
make install
```

`make install` puts the runner in the toolchain's `Local/Tools` (on Windows,
`/clang64/bin`); loading `GNUstep.sh` puts it on `PATH`.

## 3. Write a test

[Examples/FirstTest](../Examples/FirstTest) has a small class, `Counter`, and
its tests. The tests are a bundle in their own directory:

```
FirstTest/
  Counter.h
  Counter.m
  Tests/
    GNUmakefile
    CounterTests.m
```

`Tests/GNUmakefile` names the bundle and compiles the code under test into it:

```make
include $(GNUSTEP_MAKEFILES)/common.make

XCTEST_BUNDLE_NAME = CounterTests
CounterTests_OBJC_FILES = CounterTests.m ../Counter.m
CounterTests_INCLUDE_DIRS = -I..

include $(GNUSTEP_MAKEFILES)/Auxiliary/xctest.make
```

`Tests/CounterTests.m` is an `XCTestCase` subclass. Every method whose name
starts with `test` is a test:

```objc
#import <XCTest/XCTest.h>
#import "Counter.h"

@interface CounterTests : XCTestCase
@end

@implementation CounterTests

- (void) testIncrementAddsOne
{
  Counter *counter = [[Counter alloc] init];
  [counter increment];
  [counter increment];
  XCTAssertEqual([counter value], 2);
}

@end
```

The example has two more tests. The [README](../README.md#supported-behavior)
lists the assertions and the rest of what's supported.

## 4. Run it

```sh
make -C Tests check
```

`make check` builds `CounterTests.xctest` and runs it with `xctest`. Its
output, with the log's timestamps removed:

```
XCTest: Running Unit Tests
XCTest:   Running CounterTests
XCTest:     testIncrementAddsOne...
XCTest:     testResetGoesBackToZero...
XCTest:     testStartsAtZero...
XCTest:   CounterTests: 3 tests PASSED
XCTest: 1 tests PASSED
```

If a test fails, the output says where and why, and `make check` exits
nonzero, so a script or CI job stops there:

```
XCTest:     testIncrementAddsOne...
XCTest:     Assertion FAILED at CounterTests.m:20, (([counter value]) equal to (3)) failed: ("2") is not equal to ("3")
XCTest:     testIncrementAddsOne FAILED
...
XCTest:   CounterTests: 1/3 tests FAILED
```

Some useful options:

- **One test:** `make -C Tests check XCTEST_FLAGS="-XCTest CounterTests.testIncrementAddsOne"`
- **JUnit XML for CI:** `XCTEST_FLAGS="-junit-report results.xml"`
- **Xcode-style output:** `XCTEST_FLAGS="-output-format apple"`

`man xctest` lists every option. The comments at the top of `xctest.make`
list the make variables, such as `XCTEST_HOST` for tests that run inside your
app and `XCTEST_LAUNCHER` for running under `xvfb-run`.

## 5. Gate packaging on your tests

[gnustep-packager](https://github.com/danjboyd/gnustep-packager) builds a
Windows MSI or a Linux AppImage from a GNUstep app in GitHub Actions. Its
manifest's build step can run your tests first, so a failing test means no
package.

[Examples/PackagedAppTests](../Examples/PackagedAppTests) does this for a small
GUI app, with a workflow that builds both an MSI and an AppImage. Its
[README](../Examples/PackagedAppTests/README.md) explains the parts to copy. It
builds tools-xctest in the CI job without installing it, so the package never
contains it.

## Limits

- **Checked on Ubuntu 24.04 and Windows Server 2022,** with gnustep-cli 0.1.9.
  On Windows, gnustep-cli's installer is in preview. With MSYS2's own
  packages instead of gnustep-cli's toolchain, building tools-xctest needs
  `-DHAVE_MODE_T`, as the Windows build in
  [Examples/PackagedAppTests](../Examples/PackagedAppTests) shows.
