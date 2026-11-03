# Swift test bundle example

`CalculatorTests.swift` is an ordinary XCTest test case in Swift. The
`GNUmakefile` builds it into `CalculatorTests.xctest` with gnustep-make and
`xctest.make`, and `make check` runs it with `xctest`.

```sh
source <GNUstep>/System/Library/Makefiles/GNUstep.sh   # gnustep-swift's tools-make
source <gnustep-swift>/…/gnustep-interop.sh            # its GNUSTEP_SWIFT_* profile
make
make check
make check XCTEST_FLAGS=-only-testing:CalculatorTests/CalculatorTests/testParse
```

It needs gnustep-swift's tools-make, which compiles `_SWIFT_FILES` and
links `swiftrt.o`, and tools-xctest installed with its Swift overlay
(`make XCTEST_SWIFTC=... install` at the top level). To build against an
uninstalled tools-xctest, add `XCTEST_INCLUDE_DIR=<source root>` and
`XCTEST_LIBRARY_DIR=<source root>/XCTest/obj`. See "Swift tests" in the
top-level README.
