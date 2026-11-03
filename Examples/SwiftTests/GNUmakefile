# A Swift test bundle, built without SwiftPM, run with xctest.
#
#   make SWIFTC=/path/to/swiftc SWIFTFLAGS="..." XCTEST_HEADERS=... XCTEST_LIBDIR=...
#   make check
#
# SWIFTC must be a swiftc with GNUstep's Objective-C interop, and SWIFTFLAGS
# that toolchain's own flags (-gnustep-objc-interop, its resource
# directory, libs-base's module map, ...). XCTEST_HEADERS is the directory
# holding XCTest/ (and XCTest.swiftmodule, the Swift overlay), and
# XCTEST_LIBDIR the one holding libXCTest and libXCTestSwift. By default
# both come from gnustep-config.
#
# This is plain make, not gnustep-make: gnustep-make has no Swift rules
# yet. A bundle is a directory holding the shared library and
# Resources/Info-gnustep.plist naming it as NSExecutable.

BUNDLE = CalculatorTests
SOURCES = CalculatorTests.swift

SWIFTC ?= swiftc
SWIFTFLAGS ?=
XCTEST ?= xctest
XCTEST_HEADERS ?= $(shell gnustep-config --variable=GNUSTEP_LOCAL_HEADERS 2>/dev/null)
XCTEST_LIBDIR ?= $(shell gnustep-config --variable=GNUSTEP_LOCAL_LIBRARIES 2>/dev/null)

all: $(BUNDLE).xctest/$(BUNDLE)

$(BUNDLE).xctest/$(BUNDLE): $(SOURCES)
	mkdir -p $(BUNDLE).xctest/Resources
	printf '{\n  NSExecutable = "%s";\n}\n' $(BUNDLE) > $(BUNDLE).xctest/Resources/Info-gnustep.plist
	$(SWIFTC) $(SWIFTFLAGS) -parse-as-library -emit-library -module-name $(BUNDLE) \
	  -I $(XCTEST_HEADERS) -Xcc -I$(XCTEST_HEADERS) \
	  -L $(XCTEST_LIBDIR) -Xlinker -rpath -Xlinker $(XCTEST_LIBDIR) \
	  -lXCTestSwift -lXCTest \
	  $(SOURCES) -o $@

check: all
	$(XCTEST) $(BUNDLE).xctest $(XCTEST_FLAGS)

clean:
	rm -rf $(BUNDLE).xctest

.PHONY: all check clean
