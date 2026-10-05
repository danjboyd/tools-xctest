#
# xctest.make: build XCTest bundles with gnustep-make and run them with
# `make check`. Installed in $(GNUSTEP_MAKEFILES)/Auxiliary by tools-xctest.
#
#   include $(GNUSTEP_MAKEFILES)/common.make
#
#   XCTEST_BUNDLE_NAME = MyTests
#   MyTests_OBJC_FILES = FooTests.m BarTests.m
#
#   include $(GNUSTEP_MAKEFILES)/Auxiliary/xctest.make
#
# `make` builds MyTests.xctest, linked with libXCTest; `make check` runs
# it with xctest and fails if any test fails. Test bundles are never
# installed. Use the usual bundle variables (MyTests_OBJC_FILES,
# MyTests_INCLUDE_DIRS, MyTests_BUNDLE_LIBS, ...) for the rest.
#
# Optional variables:
#   XCTEST_BUNDLE_NAME         One or more test bundles (required).
#   XCTEST_FLAGS               Options for every xctest run, e.g.
#                              -junit-report results.xml.
#   <Bundle>_XCTEST_FLAGS      Options for one bundle's run.
#   XCTEST_HOST                An application to run the tests in (xctest -host);
#                              also makes the bundles link the GUI.
#   XCTEST_LAUNCHER            A command to run xctest under, e.g. "xvfb-run -a".
#   XCTEST                     The xctest program (default: xctest, from PATH).
#   XCTEST_BUNDLE_EXTENSION    Default .xctest. Note that it applies to every
#                              bundle in this makefile.
#   XCTEST_LIBRARY_DIR, XCTEST_INCLUDE_DIR
#                              An uninstalled tools-xctest to build against
#                              and run with (its XCTest/obj and source root).
#

ifeq ($(strip $(XCTEST_BUNDLE_NAME)),)
  $(error xctest.make: set XCTEST_BUNDLE_NAME to the test bundles to build)
endif

XCTEST ?= xctest
XCTEST_BUNDLE_EXTENSION ?= .xctest
BUNDLE_EXTENSION = $(XCTEST_BUNDLE_EXTENSION)
BUNDLE_NAME += $(XCTEST_BUNDLE_NAME)
NEEDS_GUI ?= $(if $(XCTEST_HOST),yes,no)

$(foreach bundle,$(XCTEST_BUNDLE_NAME),\
  $(eval $(bundle)_BUNDLE_LIBS += -lXCTest)\
  $(eval $(bundle)_STANDARD_INSTALL = no)\
  $(if $(XCTEST_LIBRARY_DIR),$(eval $(bundle)_LIB_DIRS += -L$(XCTEST_LIBRARY_DIR)))\
  $(if $(XCTEST_INCLUDE_DIR),$(eval $(bundle)_INCLUDE_DIRS += -I$(XCTEST_INCLUDE_DIR))))

include $(GNUSTEP_MAKEFILES)/bundle.make

# Runs every bundle, then fails if any of them failed.
_XCTEST_ENV = $(if $(XCTEST_LIBRARY_DIR),LD_LIBRARY_PATH="$(XCTEST_LIBRARY_DIR)$${LD_LIBRARY_PATH:+:$$LD_LIBRARY_PATH}")
_XCTEST_RUN = $(_XCTEST_ENV) $(XCTEST_LAUNCHER) $(XCTEST) "$(GNUSTEP_BUILD_DIR)/$(1)$(BUNDLE_EXTENSION)" \
  $(if $(XCTEST_HOST),-host "$(XCTEST_HOST)") $(XCTEST_FLAGS) $($(1)_XCTEST_FLAGS)

after-check:: all
	@status=0; \
	$(foreach bundle,$(XCTEST_BUNDLE_NAME),\
	  echo "Running $(bundle)$(BUNDLE_EXTENSION)..."; \
	  $(call _XCTEST_RUN,$(bundle)) || status=1;) \
	exit $$status
