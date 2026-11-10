ifeq ($(GNUSTEP_MAKEFILES),)
 GNUSTEP_MAKEFILES := $(shell gnustep-config --variable=GNUSTEP_MAKEFILES 2>/dev/null)
endif
ifeq ($(GNUSTEP_MAKEFILES),)
 $(error You need to set GNUSTEP_MAKEFILES before compiling!)
endif

include $(GNUSTEP_MAKEFILES)/common.make

BUNDLE_NAME = UIThreadSpikeFixture
NEEDS_GUI = yes

XCTEST_SOURCE_ROOT ?= ../..
XCTEST_LIBRARY_DIR ?= ../../XCTest/obj

UIThreadSpikeFixture_OBJC_FILES = UIThreadSpikeTests.m
UIThreadSpikeFixture_INCLUDE_DIRS = -I$(XCTEST_SOURCE_ROOT)
UIThreadSpikeFixture_BUNDLE_LIBS = -lXCTest -lgnustep-gui
UIThreadSpikeFixture_LIB_DIRS = -L$(XCTEST_LIBRARY_DIR)

include $(GNUSTEP_MAKEFILES)/bundle.make
