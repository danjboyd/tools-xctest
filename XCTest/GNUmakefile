include $(GNUSTEP_MAKEFILES)/common.make

PACKAGE_NAME = XCTest

LIBRARY_NAME = XCTest
# libXCTestHost works through LD_PRELOAD, so there is no -host on Windows.
ifeq (,$(findstring mingw,$(GNUSTEP_HOST_OS))$(findstring windows,$(GNUSTEP_HOST_OS)))
LIBRARY_NAME += XCTestHost
endif
XCTest_HEADER_FILES = XCTest.h XCTestAssertions.h XCTestAssertionsImpl.h XCTestCase.h \
	XCTestExpectation.h XCTWaiter.h XCTestErrors.h XCTestCase+AsynchronousTesting.h \
	XCAbstractTest.h XCTestSuite.h XCTestRun.h XCTestObservation.h XCTestObservationCenter.h \
	XCTIssue.h XCTExpectedFailure.h GSXCTestRunner.h XCTActivity.h XCTContext.h \
	XCTAttachment.h XCTMetric.h GSXCTestSwift.h GSXCTestSwiftOverlay.h \
	module.modulemap
XCTest_OBJC_FILES = XCTestAssertions.m XCTestCase.m GSXCTestRunner.m \
	XCTestExpectation.m XCTWaiter.m XCTestCase+AsynchronousTesting.m GSXCTestReporting.m \
	XCAbstractTest.m XCTestSuite.m XCTestRun.m XCTestObservationCenter.m \
	XCTIssue.m XCTExpectedFailure.m XCTestCase+Performance.m GSXCTestWatchdog.m \
	XCTContext.m XCTAttachment.m XCTMetric.m \
	GSXCTestParallel.m GSXCTStatistics.m
XCTest_INCLUDE_DIRS = -I../

# Preloaded into host applications by `xctest -host`.
XCTestHost_OBJC_FILES = GSXCTestHostLoader.m
XCTestHost_INCLUDE_DIRS = -I../
XCTestHost_LIBRARIES_DEPEND_UPON = -L./obj -lXCTest $(FND_LIBS) $(OBJC_LIBS) $(SYSTEM_LIBS)

-include GNUmakefile.preamble
include $(GNUSTEP_MAKEFILES)/library.make
-include GNUmakefile.postamble

# The Swift overlay (Swift/*.swift): XCTAssert* and friends for Swift tests.
# Built only when XCTEST_SWIFTC names a swiftc with GNUstep's Objective-C
# interop; XCTEST_SWIFTFLAGS carries that toolchain's own flags (resource
# directory, -gnustep-objc-interop, libs-base's module map, ...). They're
# swiftc driver flags: pass frontend-only ones as -Xfrontend <flag> (e.g.
# -Xfrontend -disable-objc-attr-requires-foundation-module). It is a
# Swift module named XCTest over the Clang module of the same name, so
# `import XCTest` gives both, and importing it links libXCTestSwift.
# The source tree comes first, and its module map is named explicitly:
# with an older tools-xctest installed where XCTEST_SWIFTFLAGS points,
# there are two maps defining XCTest, which clang otherwise rejects, and
# the headers must be this tree's.
ifneq ($(XCTEST_SWIFTC),)
XCTEST_SWIFT_SOURCES = Swift/Bridge.swift Swift/Assertions.swift Swift/Errors.swift Swift/Expectations.swift Swift/Helpers.swift
# The overlay's -lobjc (autolinked) must be the libobjc libXCTest uses, from
# the gnustep-swift profile or GNUstep's library directories: left to the
# Swift driver, it can find GCC's libobjc.so.4, and loading a test bundle
# then crashes in the runtime's class loader.
_XCTEST_SWIFT_OBJC_LIB_DIRS = $(if $(GNUSTEP_SWIFT_LIBOBJC2_LIBDIR),-L$(GNUSTEP_SWIFT_LIBOBJC2_LIBDIR)) \
  $(GNUSTEP_LIBRARIES_FLAGS)

after-all:: obj/libXCTestSwift$(SHARED_LIBEXT)

obj/libXCTestSwift$(SHARED_LIBEXT): $(XCTEST_SWIFT_SOURCES) obj/libXCTest$(SHARED_LIBEXT) $(XCTest_HEADER_FILES)
	$(ECHO_NOTHING)echo " Compiling the Swift overlay ..."; \
	$(XCTEST_SWIFTC) -I.. -Xcc -I.. -Xcc -fmodule-map-file=$(CURDIR)/module.modulemap \
	  $(_XCTEST_SWIFT_OBJC_LIB_DIRS) $(XCTEST_SWIFTFLAGS) -parse-as-library \
	  -module-name XCTest -module-link-name XCTestSwift \
	  -emit-library -emit-module -emit-module-path obj/XCTest.swiftmodule \
	  $(XCTEST_SWIFT_SOURCES) -L./obj -lXCTest -o $@$(END_ECHO)

# (GNUSTEP_HEADERS and GNUSTEP_LIBRARIES already include DESTDIR.)
after-install::
	$(MKDIRS) $(GNUSTEP_HEADERS) $(GNUSTEP_LIBRARIES)
	$(INSTALL_DATA) obj/XCTest.swiftmodule $(GNUSTEP_HEADERS)/XCTest.swiftmodule
	$(INSTALL_DATA) obj/XCTest.swiftdoc $(GNUSTEP_HEADERS)/XCTest.swiftdoc
	$(INSTALL_PROGRAM) obj/libXCTestSwift$(SHARED_LIBEXT) $(GNUSTEP_LIBRARIES)/libXCTestSwift$(SHARED_LIBEXT)

after-uninstall::
	rm -f $(GNUSTEP_HEADERS)/XCTest.swiftmodule $(GNUSTEP_HEADERS)/XCTest.swiftdoc \
	  $(GNUSTEP_LIBRARIES)/libXCTestSwift$(SHARED_LIBEXT)

after-clean::
	rm -f obj/libXCTestSwift$(SHARED_LIBEXT) obj/XCTest.swiftmodule obj/XCTest.swiftdoc
endif
