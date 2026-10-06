ifeq ($(GNUSTEP_MAKEFILES),)
 GNUSTEP_MAKEFILES := $(shell gnustep-config --variable=GNUSTEP_MAKEFILES 2>/dev/null)
endif
ifeq ($(GNUSTEP_MAKEFILES),)
 $(error You need to set GNUSTEP_MAKEFILES before compiling!)
endif

include $(GNUSTEP_MAKEFILES)/common.make

PACKAGE_NAME = xctest
TOOL_NAME = xctest
SUBPROJECTS = XCTest

xctest_OBJC_FILES = main.m
ADDITIONAL_TOOL_LIBS = -lXCTest
ADDITIONAL_LIB_DIRS = -L./XCTest/obj

-include GNUmakefile.preamble
include $(GNUSTEP_MAKEFILES)/aggregate.make
include $(GNUSTEP_MAKEFILES)/tool.make

-include GNUmakefile.postamble

# Regression scripts, in order; each takes the same four arguments.
XCTEST_TEST_SCRIPTS = cli-filter \
	lifecycle \
	assertion \
	async \
	output \
	junit \
	list \
	object-model \
	hosted \
	expected-failure \
	performance \
	repetition \
	out-of-test \
	issue \
	timeout \
	activity \
	attachment \
	order \
	metric \
	parallel \
	make-helper
# There is no -host on Windows (it needs LD_PRELOAD).
ifneq (,$(findstring mingw,$(GNUSTEP_HOST_OS))$(findstring windows,$(GNUSTEP_HOST_OS)))
XCTEST_TEST_SCRIPTS := $(filter-out hosted,$(XCTEST_TEST_SCRIPTS))
endif

after-check:: all
	@set -e; for name in $(XCTEST_TEST_SCRIPTS); do \
	  echo "./Tests/run-$$name-tests.sh"; \
	  ./Tests/run-$$name-tests.sh "$(CURDIR)/obj/xctest" "$(CURDIR)/XCTest/obj" "$(CURDIR)" "$(dir $(GNUSTEP_MAKEFILES))Libraries"; \
	done

# xctest.make, for projects' test bundles, and xctest-bundle, for other
# build systems. (GNUSTEP_TOOLS already includes DESTDIR; GNUSTEP_MAKEFILES
# doesn't.)
after-install::
	$(MKDIRS) "$(DESTDIR)$(GNUSTEP_MAKEFILES)/Auxiliary" "$(GNUSTEP_TOOLS)"
	$(INSTALL_DATA) xctest.make "$(DESTDIR)$(GNUSTEP_MAKEFILES)/Auxiliary/xctest.make"
	$(INSTALL_PROGRAM) xctest-bundle "$(GNUSTEP_TOOLS)/xctest-bundle"

after-uninstall::
	rm -f "$(DESTDIR)$(GNUSTEP_MAKEFILES)/Auxiliary/xctest.make" "$(GNUSTEP_TOOLS)/xctest-bundle"
