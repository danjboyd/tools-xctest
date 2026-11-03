# Swift test bundle example

`CalculatorTests.swift` is an ordinary XCTest test case in Swift. The
`GNUmakefile` builds it into `CalculatorTests.xctest` without SwiftPM, and
`make check` runs it with `xctest`.

```sh
make SWIFTC=/path/to/interop/swiftc SWIFTFLAGS="-gnustep-objc-interop ..."
make check
make check XCTEST_FLAGS=-only-testing:CalculatorTests/CalculatorTests/testParse
```

It needs a `swiftc` with GNUstep's Objective-C interop, and tools-xctest
installed with its Swift overlay (`make XCTEST_SWIFTC=... install` at the
top level). See "Swift tests" in the top-level README. `XCTEST_HEADERS` and
`XCTEST_LIBDIR` default to the Local domain from `gnustep-config`.
