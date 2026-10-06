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
	XCTAttachment.h XCTMetric.h
XCTest_OBJC_FILES = XCTestAssertions.m XCTestCase.m GSXCTestRunner.m \
	XCTestExpectation.m XCTWaiter.m XCTestCase+AsynchronousTesting.m GSXCTestReporting.m \
	XCAbstractTest.m XCTestSuite.m XCTestRun.m XCTestObservationCenter.m \
	XCTIssue.m XCTExpectedFailure.m XCTestCase+Performance.m GSXCTestWatchdog.m \
	XCTContext.m XCTAttachment.m XCTMetric.m \
	GSXCTestParallel.m
XCTest_INCLUDE_DIRS = -I../

# Preloaded into host applications by `xctest -host`.
XCTestHost_OBJC_FILES = GSXCTestHostLoader.m
XCTestHost_INCLUDE_DIRS = -I../
XCTestHost_LIBRARIES_DEPEND_UPON = -L./obj -lXCTest $(FND_LIBS) $(OBJC_LIBS) $(SYSTEM_LIBS)

-include GNUmakefile.preamble
include $(GNUSTEP_MAKEFILES)/library.make
-include GNUmakefile.postamble
