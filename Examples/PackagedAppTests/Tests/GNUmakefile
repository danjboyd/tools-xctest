# The app's unit tests, as an XCTest bundle. `make check` runs them with
# xctest and fails if any test fails.
#
# XCTEST_MAKE defaults to the xctest.make that an installed tools-xctest puts
# in gnustep-make's Auxiliary directory. packaging/build.sh points it, and
# XCTEST_INCLUDE_DIR, XCTEST_LIBRARY_DIR and XCTEST, at an uninstalled build
# instead.

include $(GNUSTEP_MAKEFILES)/common.make

XCTEST_BUNDLE_NAME = GreeterTests
GreeterTests_OBJC_FILES = GreeterTests.m ../Greeter.m
GreeterTests_INCLUDE_DIRS = -I..

XCTEST_MAKE ?= $(GNUSTEP_MAKEFILES)/Auxiliary/xctest.make
include $(XCTEST_MAKE)
