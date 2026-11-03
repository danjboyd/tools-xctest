# A Swift test bundle built with xctest.make, as a project would:
#   include $(GNUSTEP_MAKEFILES)/Auxiliary/xctest.make
# run-make-swift-tests.sh builds it with this tree's xctest.make, with
# gnustep-swift's tools-make and a stand-in Swift toolchain (see the
# script), and with a gnustep-make that has no Swift support.

ifeq ($(GNUSTEP_MAKEFILES),)
 GNUSTEP_MAKEFILES := $(shell gnustep-config --variable=GNUSTEP_MAKEFILES 2>/dev/null)
endif

include $(GNUSTEP_MAKEFILES)/common.make

XCTEST_BUNDLE_NAME = SwiftMakeTests
SwiftMakeTests_SWIFT_FILES = FirstTests.swift SecondTests.swift

XCTEST_MAKE ?= $(GNUSTEP_MAKEFILES)/Auxiliary/xctest.make
include $(XCTEST_MAKE)
