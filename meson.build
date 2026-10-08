project('xctest', 'objc', version : '0.5.0', default_options : ['warning_level=3'])

pkg = import('pkgconfig')

# Ensure clang is used for Objective-C
objc_compiler = meson.get_compiler('objc')
if objc_compiler.get_id() != 'clang'
  error('Clang is required for this project. Please set CC=clang, and OBJC=clang before running Meson.')
endif

dependencies_to_link = []
# Common Objective-C flags
objc_flags = ['-fblocks', '-fobjc-exceptions']
gnustep_runtime_lib_dirs = []
gnustep_makefiles = ''

# Use GNUstep on non-Darwin platforms
if host_machine.system() != 'darwin'
    # Objective-C (GNUstep) support from gnustep-config
    gnustep_config = find_program('gnustep-config', required: true)
    if not gnustep_config.found()
        error('GNUstep is required for this project. Please install GNUstep and ensure gnustep-config is in your PATH. You might want to source GNUstep.sh before running Meson.')
    endif

    gnustep_flags = run_command(gnustep_config, '--objc-flags', check: true).stdout().strip().split()
    gnustep_base_libs = run_command(gnustep_config, '--base-libs', check: true).stdout().strip().split()
    gnustep_makefiles = run_command(gnustep_config, '--variable=GNUSTEP_MAKEFILES', check: true).stdout().strip()

    # Filter out flags that are handled by Meson's built-in options
    foreach flag : gnustep_flags
    if flag != '-Wall' and flag != '-g' and flag != '-O2' and flag != '-MMD'
        objc_flags += flag
    endif
    endforeach

    foreach flag : gnustep_base_libs
    if flag.startswith('-L')
        gnustep_runtime_lib_dirs += flag.substring(2)
    endif
    endforeach

    add_project_link_arguments(gnustep_base_libs, language: 'objc')
else
  # Properly link against the Foundation framework
  foundation_dep = dependency('appleframeworks', modules: ['Foundation'])
  dependencies_to_link += foundation_dep

  add_project_link_arguments('-lobjc', language: 'objc')
endif

# Add Objective-C flags
add_project_arguments(objc_flags, language: 'objc')

source = [
	'XCTest/XCTestAssertions.m',
	'XCTest/XCTestCase.m',
	'XCTest/XCTestExpectation.m',
	'XCTest/GSXCTestRunner.m',
	'XCTest/XCTWaiter.m',
	'XCTest/XCTestCase+AsynchronousTesting.m',
	'XCTest/GSXCTestReporting.m',
	'XCTest/XCAbstractTest.m',
	'XCTest/XCTestSuite.m',
	'XCTest/XCTestRun.m',
	'XCTest/XCTestObservationCenter.m',
	'XCTest/XCTIssue.m',
	'XCTest/XCTExpectedFailure.m',
	'XCTest/XCTestCase+Performance.m',
	'XCTest/GSXCTestWatchdog.m',
	'XCTest/XCTContext.m',
	'XCTest/XCTAttachment.m',
	'XCTest/XCTMetric.m',
	'XCTest/GSXCTestParallel.m',
]

headers = [
	'XCTest/XCTest.h',
	'XCTest/XCTestAssertions.h',
	'XCTest/XCTestAssertionsImpl.h',
	'XCTest/XCTestCase.h',
	'XCTest/XCTestExpectation.h',
	'XCTest/GSXCTestRunner.h',
	'XCTest/XCTWaiter.h',
	'XCTest/XCTestErrors.h',
	'XCTest/XCTestCase+AsynchronousTesting.h',
	'XCTest/XCAbstractTest.h',
	'XCTest/XCTestSuite.h',
	'XCTest/XCTestRun.h',
	'XCTest/XCTestObservation.h',
	'XCTest/XCTestObservationCenter.h',
	'XCTest/XCTIssue.h',
	'XCTest/XCTExpectedFailure.h',
	'XCTest/XCTActivity.h',
	'XCTest/XCTContext.h',
	'XCTest/XCTAttachment.h',
	'XCTest/XCTMetric.h',
]

include_dirs = include_directories(
    '.',
    'XCTest',
)

# Build XCTest library
xctest_lib = library(
  'XCTest',
  source,
  dependencies: dependencies_to_link,
  include_directories: include_dirs,
  install: true,
)

install_headers(
  headers,
  install_dir: join_paths(get_option('prefix'), get_option('includedir'), 'XCTest'),
)

pkg.generate(libraries : xctest_lib,
             version : meson.project_version(),
             name : 'XCTest',
             filebase : 'XCTest',
             description : 'Reimplementation of XCTest for GNUstep',
)

# Preloaded into host applications by `xctest -host`. It works through
# LD_PRELOAD, so there is no -host on Windows.
xctest_test_depends = [xctest_lib]
if host_machine.system() != 'windows'
  xctest_host_lib = library(
    'XCTestHost',
    'XCTest/GSXCTestHostLoader.m',
    dependencies: dependencies_to_link,
    include_directories: include_dirs,
    link_with: xctest_lib,
    install: true,
  )
  xctest_test_depends += xctest_host_lib
endif

# Build XCTest tool
xctest_tool = executable('xctest', 'main.m', link_with: xctest_lib, install: true)

# xctest-bundle wraps a shared library of tests as a bundle xctest can load
# (see the README for using it from Meson).
xctest_bundle_script = files('xctest-bundle')
install_data('xctest-bundle', install_dir: get_option('bindir'), install_mode: 'rwxr-xr-x')

if host_machine.system() != 'darwin'
  # For gnustep-make projects: include $(GNUSTEP_MAKEFILES)/Auxiliary/xctest.make
  install_data('xctest.make', install_dir: join_paths(gnustep_makefiles, 'Auxiliary'))

  # A test bundle built the way the README shows for Meson projects.
  meson_fixture_lib = shared_module('FilterFixture', 'Tests/FilterFixture/FilterFixture.m',
                                    include_directories: include_directories('.'),
                                    link_with: xctest_lib,
                                    name_prefix: '')
  meson_fixture_bundle = custom_target('FilterFixture.xctest',
                                       input: meson_fixture_lib,
                                       output: 'FilterFixture.xctest',
                                       command: [xctest_bundle_script, '@OUTPUT@', '@INPUT@'],
                                       build_by_default: true)

  xctest_test_env = environment()
  xctest_test_env.set('GNUSTEP_MAKEFILES', gnustep_makefiles)

  # Regression scripts: [test name, script]. Each takes the same arguments.
  xctest_tests = [
    ['cli-filters', 'run-cli-filter-tests.sh'],
    ['lifecycle', 'run-lifecycle-tests.sh'],
    ['assertions', 'run-assertion-tests.sh'],
    ['async', 'run-async-tests.sh'],
    ['output', 'run-output-tests.sh'],
    ['junit', 'run-junit-tests.sh'],
    ['list-tests', 'run-list-tests.sh'],
    ['object-model', 'run-object-model-tests.sh'],
    ['expected-failures', 'run-expected-failure-tests.sh'],
    ['performance', 'run-performance-tests.sh'],
    ['repetition', 'run-repetition-tests.sh'],
    ['out-of-test', 'run-out-of-test-tests.sh'],
    ['issues', 'run-issue-tests.sh'],
    ['timeouts', 'run-timeout-tests.sh'],
    ['activities', 'run-activity-tests.sh'],
    ['attachments', 'run-attachment-tests.sh'],
    ['order', 'run-order-tests.sh'],
    ['metrics', 'run-metric-tests.sh'],
    ['parallel', 'run-parallel-tests.sh'],
    ['make-helper', 'run-make-helper-tests.sh'],
  ]
  if host_machine.system() != 'windows'
    xctest_tests += [['hosted', 'run-hosted-tests.sh']]
  endif

  # The standalone regression program (Tests/Regression.m).
  regression = executable('regression', 'Tests/Regression.m',
                          include_directories: include_directories('.'),
                          dependencies: dependencies_to_link,
                          link_with: xctest_lib)
  test('regression', regression, is_parallel: false)

  test('meson-bundle', xctest_tool,
       args: [meson_fixture_bundle.full_path(), '-only-testing:FilterFixture/AlphaTests'],
       depends: [meson_fixture_bundle],
       is_parallel: false)

  foreach t : xctest_tests
    test(t[0],
         find_program('Tests/' + t[1]),
         args: [
           join_paths(meson.current_build_dir(), 'xctest'),
           meson.current_build_dir(),
           meson.current_source_dir(),
           ':'.join(gnustep_runtime_lib_dirs),
         ],
         env: xctest_test_env,
         depends: [xctest_tool] + xctest_test_depends,
         # The scripts rebuild shared fixture bundles in the source tree.
         is_parallel: false)
  endforeach
endif
