ifeq ($(GNUSTEP_MAKEFILES),)
 GNUSTEP_MAKEFILES := $(shell gnustep-config --variable=GNUSTEP_MAKEFILES 2>/dev/null)
endif
ifeq ($(GNUSTEP_MAKEFILES),)
 $(error You need to set GNUSTEP_MAKEFILES before compiling!)
endif

include $(GNUSTEP_MAKEFILES)/common.make

BUNDLE_NAME = ObjectModelFixture
NEEDS_GUI = no

XCTEST_SOURCE_ROOT ?= ../..
XCTEST_LIBRARY_DIR ?= ../../XCTest/obj

ObjectModelFixture_OBJC_FILES = ObjectModelFixture.m
ObjectModelFixture_PRINCIPAL_CLASS = FixtureObserverRegistrar
ObjectModelFixture_INCLUDE_DIRS = -I$(XCTEST_SOURCE_ROOT)
ObjectModelFixture_BUNDLE_LIBS = -lXCTest
ObjectModelFixture_LIB_DIRS = -L$(XCTEST_LIBRARY_DIR)

include $(GNUSTEP_MAKEFILES)/bundle.make
