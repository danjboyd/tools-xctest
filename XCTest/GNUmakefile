include $(GNUSTEP_MAKEFILES)/common.make

PACKAGE_NAME = XCTest

LIBRARY_NAME = XCTest
XCTest_HEADER_FILES = XCTest.h XCTestAssertions.h XCTestAssertionsImpl.h XCTestCase.h XCTestExpectation.h GSXCTestRunner.h
XCTest_OBJC_FILES = XCTestAssertions.m XCTestCase.m XCTestExpectation.m GSXCTestRunner.m
XCTest_INCLUDE_DIRS = -I../

-include GNUmakefile.preamble
include $(GNUSTEP_MAKEFILES)/library.make
-include GNUmakefile.postamble
