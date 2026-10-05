# Two test bundles built with xctest.make, as a project would:
#   include $(GNUSTEP_MAKEFILES)/Auxiliary/xctest.make
# The regressions point XCTEST_MAKE at this tree's copy, and build against
# its uninstalled library.

ifeq ($(GNUSTEP_MAKEFILES),)
 GNUSTEP_MAKEFILES := $(shell gnustep-config --variable=GNUSTEP_MAKEFILES 2>/dev/null)
endif

include $(GNUSTEP_MAKEFILES)/common.make

XCTEST_BUNDLE_NAME = HelperTests OtherTests
HelperTests_OBJC_FILES = HelperTests.m
OtherTests_OBJC_FILES = OtherTests.m

XCTEST_MAKE ?= $(GNUSTEP_MAKEFILES)/Auxiliary/xctest.make
include $(XCTEST_MAKE)
