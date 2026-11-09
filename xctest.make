#
# This file is part of the GNUstep XCTEST Library.
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2 of the License, or (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.     See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; see the file COPYING.LIB.
# If not, see <http://www.gnu.org/licenses/> or write to the
# Free Software Foundation, 51 Franklin Street, Fifth Floor,
# Boston, MA 02110-1301, USA.
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
#   XCTEST_SWIFT_VERSION_CHECK no: don't check a Swift bundle's compiler
#                              against the one that built the XCTest module.
#
# Code coverage: `make coverage` builds the bundles again with clang's
# -fprofile-instr-generate -fcoverage-mapping, in obj/xctest-coverage so
# the ordinary build is left alone, runs them with xctest -coverage-output,
# and writes, for each bundle, a summary (also printed), lcov and HTML:
#   coverage/<Bundle>.profdata, <Bundle>.txt, <Bundle>.lcov, <Bundle>-html/
# It fails if any test fails. Code outside the bundles is measured only if
# it's built with $(XCTEST_COVERAGE_FLAGS) too; name its binaries in
# XCTEST_COVERAGE_OBJECTS to include them in the reports.
#   XCTEST_COVERAGE_DIR        Where the reports go (default: coverage).
#   XCTEST_COVERAGE_OBJECTS    More instrumented binaries to report on, e.g.
#                              the library the tests exercise.
#   XCTEST_COVERAGE_REPORT_FLAGS  Options for llvm-cov report, export and
#                              show (default: leave out the GNUstep and
#                              XCTest headers), e.g. -ignore-filename-regex=Tests/.
#   XCTEST_LLVM_COV            The llvm-cov program (default: llvm-cov on
#                              PATH, or the highest-numbered llvm-cov-<n>).
#   XCTEST_LLVM_PROFDATA       The llvm-profdata xctest merges with (see
#                              xctest(1)).
#
# Swift test bundles: list the sources in <Bundle>_SWIFT_FILES, as for any
# Swift target. That needs a gnustep-make with Swift support (gnustep-swift's
# tools-make, with its GNUSTEP_SWIFT_* profile), which compiles them and
# links swiftrt.o. xctest.make adds what a bundle loaded into xctest also
# needs: the libraries the Swift objects ask for (libXCTestSwift, the Swift
# runtime, ...), which bundle.make doesn't link, and, with
# XCTEST_INCLUDE_DIR/XCTEST_LIBRARY_DIR, the uninstalled XCTest module map
# and Swift overlay. Without Swift support, a Swift test bundle is an error.
#

ifeq ($(strip $(XCTEST_BUNDLE_NAME)),)
  $(error xctest.make: set XCTEST_BUNDLE_NAME to the test bundles to build)
endif

XCTEST ?= xctest
XCTEST_BUNDLE_EXTENSION ?= .xctest
BUNDLE_EXTENSION = $(XCTEST_BUNDLE_EXTENSION)
BUNDLE_NAME += $(XCTEST_BUNDLE_NAME)
NEEDS_GUI ?= $(if $(XCTEST_HOST),yes,no)

XCTEST_COVERAGE_DIR ?= coverage
XCTEST_COVERAGE_FLAGS = -fprofile-instr-generate -fcoverage-mapping
# By default the reports leave out the inline functions of GNUstep's and
# XCTest's headers. llvm-cov reports normalized paths, so these are too
# (a prefix such as .../src/../gnustep would never match).
XCTEST_COVERAGE_REPORT_FLAGS ?= \
  $(foreach domain,SYSTEM LOCAL NETWORK USER,$(if $(GNUSTEP_$(domain)_HEADERS),\
    -ignore-filename-regex='$(abspath $(GNUSTEP_$(domain)_HEADERS))/')) \
  $(if $(XCTEST_INCLUDE_DIR),-ignore-filename-regex='$(abspath $(XCTEST_INCLUDE_DIR))/XCTest/')

# In `make coverage`'s own build (below), every bundle is instrumented.
ifeq ($(_XCTEST_COVERAGE_BUILD),yes)
  $(foreach bundle,$(XCTEST_BUNDLE_NAME),\
    $(eval $(bundle)_OBJCFLAGS += $(XCTEST_COVERAGE_FLAGS))\
    $(eval $(bundle)_CFLAGS += $(XCTEST_COVERAGE_FLAGS))\
    $(eval $(bundle)_BUNDLE_LIBS += -fprofile-instr-generate))
endif

$(foreach bundle,$(XCTEST_BUNDLE_NAME),\
  $(eval $(bundle)_BUNDLE_LIBS += -lXCTest)\
  $(eval $(bundle)_STANDARD_INSTALL = no)\
  $(if $(XCTEST_LIBRARY_DIR),$(eval $(bundle)_LIB_DIRS += -L$(XCTEST_LIBRARY_DIR)))\
  $(if $(XCTEST_INCLUDE_DIR),$(eval $(bundle)_INCLUDE_DIRS += -I$(XCTEST_INCLUDE_DIR))))

# Swift test bundles. SWIFT_AUTOLINK_ARGS is gnustep-make's, per instance:
# the @-files listing the libraries each Swift object asks for.
_XCTEST_SWIFT_BUNDLES = $(strip $(foreach bundle,$(XCTEST_BUNDLE_NAME),$(if $(strip $($(bundle)_SWIFT_FILES)),$(bundle))))
$(foreach bundle,$(_XCTEST_SWIFT_BUNDLES),\
  $(eval $(bundle)_BUNDLE_LIBS += $$(SWIFT_AUTOLINK_ARGS))\
  $(if $(XCTEST_INCLUDE_DIR),$(eval $(bundle)_SWIFT_INCLUDE_DIRS += $(XCTEST_INCLUDE_DIR))\
    $(eval $(bundle)_SWIFT_CLANG_MODULEMAPS += $(XCTEST_INCLUDE_DIR)/XCTest/module.modulemap))\
  $(if $(XCTEST_LIBRARY_DIR),$(eval $(bundle)_SWIFT_INCLUDE_DIRS += $(XCTEST_LIBRARY_DIR))))
# gnustep-swift's tools-make fixes a Swift instance's library directories
# before adding <Bundle>_LIB_DIRS, so the uninstalled library's directory
# goes in AUXILIARY_LIB_DIRS too (ahead of the installed libraries).
ifneq ($(and $(_XCTEST_SWIFT_BUNDLES),$(XCTEST_LIBRARY_DIR)),)
  AUXILIARY_LIB_DIRS += -L$(XCTEST_LIBRARY_DIR)
endif

include $(GNUSTEP_MAKEFILES)/bundle.make

ifneq ($(_XCTEST_SWIFT_BUNDLES),)
  ifeq ($(origin SWIFT_RUNTIME_OBJ_FILE),undefined)
    $(error xctest.make: $(_XCTEST_SWIFT_BUNDLES) has Swift sources, but this gnustep-make ($(GNUSTEP_MAKEFILES)) can't build Swift; use gnustep-swift's tools-make)
  endif
  # The Swift overlay's module loads only in the compiler that built it,
  # recorded beside it in XCTest.swiftversion: the uninstalled one in
  # XCTEST_LIBRARY_DIR, or the first installed one on the header path. A
  # different compiler is an error here, rather than an unreadable module
  # in the build (but not for make clean). XCTEST_SWIFT_VERSION_CHECK=no
  # skips the check; without the file (an older tools-xctest), there's
  # nothing to check.
  ifneq ($(XCTEST_SWIFT_VERSION_CHECK)$(if $(MAKECMDGOALS),$(if $(filter-out clean distclean,$(MAKECMDGOALS)),,no)),no)
    _XCTEST_SWIFT_VERSION_FILE := $(firstword $(wildcard \
      $(if $(XCTEST_LIBRARY_DIR),$(XCTEST_LIBRARY_DIR)/XCTest.swiftversion) \
      $(foreach domain,USER LOCAL NETWORK SYSTEM,$(GNUSTEP_$(domain)_HEADERS)/XCTest.swiftversion)))
    ifneq ($(_XCTEST_SWIFT_VERSION_FILE),)
      _XCTEST_SWIFT_VERSION_BUILT := $(shell cat '$(_XCTEST_SWIFT_VERSION_FILE)')
      _XCTEST_SWIFT_VERSION_USED := $(shell $(SWIFT_FRONTEND) --version 2>/dev/null \
        | sed -n -e 's/.*Swift version /Swift version /p' -e '/^Target: /p')
      ifneq ($(_XCTEST_SWIFT_VERSION_BUILT),$(_XCTEST_SWIFT_VERSION_USED))
        $(error xctest.make: $(_XCTEST_SWIFT_BUNDLES): the XCTest Swift module was built with "$(_XCTEST_SWIFT_VERSION_BUILT)" ($(_XCTEST_SWIFT_VERSION_FILE)), but this build's compiler ($(SWIFT_FRONTEND)) is "$(_XCTEST_SWIFT_VERSION_USED)"; rebuild tools-xctest's Swift overlay with this compiler, or set XCTEST_SWIFT_VERSION_CHECK=no)
      endif
    endif
  endif
  # bundle.make links the Swift objects but not the libraries they list.
  ifneq ($(filter $(GNUSTEP_INSTANCE),$(_XCTEST_SWIFT_BUNDLES)),)
$(BUNDLE_FILE): $(SWIFT_AUTOLINK_FILES)
  endif
endif

# Runs every bundle, then fails if any of them failed.
_XCTEST_ENV = $(if $(XCTEST_LIBRARY_DIR),LD_LIBRARY_PATH="$(XCTEST_LIBRARY_DIR)$${LD_LIBRARY_PATH:+:$$LD_LIBRARY_PATH}")
# _XCTEST_RUN(bundle[, build directory])
_XCTEST_RUN = $(_XCTEST_ENV) $(XCTEST_LAUNCHER) $(XCTEST) "$(or $(2),$(GNUSTEP_BUILD_DIR))/$(1)$(BUNDLE_EXTENSION)" \
  $(if $(XCTEST_HOST),-host "$(XCTEST_HOST)") $(XCTEST_FLAGS) $($(1)_XCTEST_FLAGS)

after-check:: all
	@status=0; \
	$(foreach bundle,$(XCTEST_BUNDLE_NAME),\
	  echo "Running $(bundle)$(BUNDLE_EXTENSION)..."; \
	  $(call _XCTEST_RUN,$(bundle)) || status=1;) \
	exit $$status

# make coverage. The instrumented build goes under obj, which make clean
# removes; the reports in XCTEST_COVERAGE_DIR are left for you.
_XCTEST_COVERAGE_BUILD_DIR = $(CURDIR)/obj/xctest-coverage

# Sets llvm_cov: XCTEST_LLVM_COV, llvm-cov, or the highest llvm-cov-<n>.
_XCTEST_FIND_LLVM_COV = llvm_cov="$(XCTEST_LLVM_COV)"; \
	if [ -z "$$llvm_cov" ]; then llvm_cov=$$(command -v llvm-cov 2>/dev/null || true); fi; \
	if [ -z "$$llvm_cov" ]; then \
	  llvm_cov=$$(IFS=:; for d in $$PATH; do ls "$$d"/llvm-cov-[0-9]* 2>/dev/null || true; done \
	    | sed 's/.*-\([0-9]*\)\(\.exe\)\{0,1\}$$/\1 &/' | sort -n | tail -n 1 | cut -d' ' -f2-); \
	fi; \
	if [ -z "$$llvm_cov" ]; then echo "xctest.make: llvm-cov not found (set XCTEST_LLVM_COV)" >&2; exit 1; fi

# The instrumented bundle's binary: Name, or Name.dll on Windows.
_XCTEST_COVERAGE_BINARY = $(_XCTEST_COVERAGE_BUILD_DIR)/$(1)$(BUNDLE_EXTENSION)/$(1)

coverage::
	@$(MAKE) --no-print-directory all _XCTEST_COVERAGE_BUILD=yes \
	  GNUSTEP_BUILD_DIR="$(_XCTEST_COVERAGE_BUILD_DIR)"
	@$(_XCTEST_FIND_LLVM_COV); \
	status=0; \
	$(foreach bundle,$(XCTEST_BUNDLE_NAME),\
	  echo "Running $(bundle)$(BUNDLE_EXTENSION) for coverage..."; \
	  $(call _XCTEST_RUN,$(bundle),$(_XCTEST_COVERAGE_BUILD_DIR)) \
	    -coverage-output "$(XCTEST_COVERAGE_DIR)" || status=1; \
	  profile="$(XCTEST_COVERAGE_DIR)/$(bundle).profdata"; \
	  binary="$(call _XCTEST_COVERAGE_BINARY,$(bundle))"; \
	  if [ -f "$$binary.dll" ]; then binary="$$binary.dll"; fi; \
	  if [ -f "$$profile" ]; then \
	    set -- "$$binary" $(foreach object,$(XCTEST_COVERAGE_OBJECTS),-object "$(object)") \
	      -instr-profile "$$profile" $(XCTEST_COVERAGE_REPORT_FLAGS); \
	    "$$llvm_cov" report "$$@" > "$(XCTEST_COVERAGE_DIR)/$(bundle).txt" || status=1; \
	    cat "$(XCTEST_COVERAGE_DIR)/$(bundle).txt"; \
	    "$$llvm_cov" export -format=lcov "$$@" > "$(XCTEST_COVERAGE_DIR)/$(bundle).lcov" || status=1; \
	    "$$llvm_cov" show -format=html -output-dir="$(XCTEST_COVERAGE_DIR)/$(bundle)-html" "$$@" || status=1; \
	    echo "Coverage of $(bundle): $(XCTEST_COVERAGE_DIR)/$(bundle).txt, $(bundle).lcov and $(bundle)-html/"; \
	  else \
	    status=1; \
	  fi;) \
	exit $$status
