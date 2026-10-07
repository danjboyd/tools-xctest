include $(GNUSTEP_MAKEFILES)/common.make
TOOL_NAME = regression
regression_OBJC_FILES = Regression.m
regression_INCLUDE_DIRS = -I..
regression_TOOL_LIBS = -lXCTest
BUNDLE_NAME = Fixture
Fixture_OBJC_FILES = Fixture.m
Fixture_INCLUDE_DIRS = -I..
Fixture_BUNDLE_LIBS = -lXCTest
ADDITIONAL_LIB_DIRS = -L../XCTest/obj
include $(GNUSTEP_MAKEFILES)/tool.make
include $(GNUSTEP_MAKEFILES)/bundle.make
