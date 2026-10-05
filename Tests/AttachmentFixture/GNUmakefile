ifeq ($(GNUSTEP_MAKEFILES),)
 GNUSTEP_MAKEFILES := $(shell gnustep-config --variable=GNUSTEP_MAKEFILES 2>/dev/null)
endif
ifeq ($(GNUSTEP_MAKEFILES),)
 $(error You need to set GNUSTEP_MAKEFILES before compiling!)
endif

include $(GNUSTEP_MAKEFILES)/common.make

BUNDLE_NAME = AttachmentFixture
NEEDS_GUI = no

XCTEST_SOURCE_ROOT ?= ../..
XCTEST_LIBRARY_DIR ?= ../../XCTest/obj

AttachmentFixture_OBJC_FILES = AttachmentFixture.m
AttachmentFixture_INCLUDE_DIRS = -I$(XCTEST_SOURCE_ROOT)
AttachmentFixture_BUNDLE_LIBS = -lXCTest
AttachmentFixture_LIB_DIRS = -L$(XCTEST_LIBRARY_DIR)

include $(GNUSTEP_MAKEFILES)/bundle.make
