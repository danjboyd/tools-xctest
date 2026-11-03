# A Swift test bundle, built with gnustep-make and xctest.make and run by
# `make check`. It needs gnustep-swift's tools-make (with its GNUSTEP_SWIFT_*
# profile) and tools-xctest installed with its Swift overlay; see "Swift
# tests" in the top-level README.

include $(GNUSTEP_MAKEFILES)/common.make

XCTEST_BUNDLE_NAME = CalculatorTests
CalculatorTests_SWIFT_FILES = CalculatorTests.swift

include $(GNUSTEP_MAKEFILES)/Auxiliary/xctest.make
