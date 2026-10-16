# 0.6.0 performance features: design decisions

Why 0.6.0's performance features work the way they do, where the choice
wasn't obvious. Where nothing else decided it, the conservative option was
taken: match Apple's XCTest, make new behaviour opt-in, and keep existing
baseline files working. The sections follow the four parts of the work:
statistics, hardware counters, baselines per machine, and the report.

## perf-statistics

- **Apple's warm-up run.** Apple doesn't document it. The evidence is a
  developer-forums report (thread 675561) of a `measure(metrics:)` block
  that "ran 6 times" with the default `iterationCount` of 5 and reported 5
  values. `measureBlock:` reports all 10 runs in Apple's output, so it gets
  no warm-up. The metric's hooks run during the warm-up and it is asked for
  its measurements, which are then dropped, so a metric sees the same
  sequence for every run.
- **Significance level** is fixed at p < 0.05, one-sided (only "worse"
  counts). It isn't configurable; nobody asked, and it can be added later
  without breaking anything.
- **Welch's t-test from summary statistics** (mean, stddev, count) rather
  than raw samples, as decided, so baseline files stay small and readable.
- **Baseline keys** are `stddev` and `count`, as decided. Apple's
  `maxPercentRelativeStandardDeviation` (its "Max STDDEV" baseline setting)
  is honoured if present, but makes a noisy result *inconclusive* rather than
  failing it as Apple would, following decision 6; it is never written
  automatically.
- **Verdict rules**: past `maxPercentRegression` and significant (or no
  statistics to test) → regressed; past it but not significant →
  inconclusive; noisier than `maxPercentRelativeStandardDeviation` →
  inconclusive unless significantly regressed; otherwise passed. Entries
  without `stddev`/`count` behave as in 0.5.x, with one exception: an entry
  that sets Apple's `maxPercentRelativeStandardDeviation` (which 0.5.x
  ignored) and is both noisier than that and past `maxPercentRegression`
  is inconclusive rather than a failure, since without the statistics a
  noisy result can't be told from a regression.
- **`"version": 2`** is written at the top of the baselines file when
  recording. Older xctest versions ignore it (they skip non-object
  entries), so the file stays readable by 0.5.x.
- **Inconclusive output**: the classic console prints
  `testX: warning: ...`; Apple-format output prints a line shaped like
  Apple's warnings (`<unknown>:0: warning: -[Class test] : ...`), since
  Apple has no inconclusive result; the JUnit report adds a `warning:` line
  to the test's `system-out`. With `-performance-inconclusive-fails YES` the
  same text is also recorded as a performance-regression failure.
- **Classic and JUnit measurement lines** gain `median` and `min`. The
  Apple-format line is unchanged, so tools that parse Apple's format still
  work.

## perf-counters

- **Apple's identifiers aren't documented.** The measurements use Apple's
  display names and units as they appear in Xcode output ("CPU Instructions
  Retired, kI", "CPU Cycles, kC") and the identifiers
  `com.apple.dt.XCTMetric_CPU.instructions_retired` and
  `com.apple.dt.XCTMetric_CPU.cycles`, by analogy with
  `com.apple.dt.XCTMetric_CPU.time`. They couldn't be confirmed from public
  sources; if Apple's differ, baselines keyed by them won't carry over.
- **What is counted.** Only user-mode work (`exclude_kernel`), by the
  measuring thread and threads it starts while measuring (`inherit`), or
  only the measuring thread with `initLimitingToCurrentThread:YES`. Linux
  can't count a process's already-running other threads without opening a
  counter per thread, so "the process" means the measuring thread and its
  new threads. CPU time still covers the whole process, as before.
- **Hybrid CPUs** (Intel cpu_core/cpu_atom): one counter per kind of core
  (`PERF_PMU_TYPE_SHIFT`, Linux 6.0 and later), so work on either kind is
  counted; on older kernels, a single generic counter.
- **Scaling** (fixed after review). Each run reads the counters at its
  start and end and uses the differences: `PERF_EVENT_IOC_RESET` doesn't
  reset the enabled/running times, so totals since opening would scale a
  run by earlier runs' ratios. A hybrid CPU's counters for one event run in
  turn as the thread moves between kinds of core, so their counts are
  summed and scaled once, by the largest time enabled over the sum of the
  times running (1 unless they had to share the hardware). Scaling each
  separately counted time on the other kind of core as multiplexing and
  inflated the counts (about 2× for a thread split evenly).
- **A counter that never ran** (every hardware counter taken by another
  user, or a failed read) is left out of that run's measurements rather
  than reported as 0, which a recorded baseline would never flag.
- **Only permanent failures turn the counters off.** EACCES/EPERM (not
  allowed) and ENOSYS (no perf events) do, for the rest of the process.
  Others (EMFILE, an event this CPU lacks, ...) leave out just those
  counters, logged once per reason, so one metric's failure doesn't change
  what another reports.
- **Files.** Counters are opened with close-on-exec, and closed when a
  measure method finishes (a private `_gsDidFinishMeasuring` hook), not
  when the test case is released at the end of the run: each suite keeps
  its tests' first instances, so hundreds of performance tests would
  otherwise hold thousands of descriptors.
- **GSXCTHardwareCounterMetric** reports raw counts ("misses") rather than
  thousands, with `org.gnustep.XCTMetric_HardwareCounter.*` identifiers, as
  it isn't Apple's.
- **Unavailable counters** are logged once per process and left out;
  `XCTEST_PERF_COUNTERS=0` turns them off (also how the tests exercise that
  path). `+[GSXCTHardwareCounterMetric isAvailable]` is public so a test can
  skip itself.
- **The working path, tested 2026-10-16** with
  `kernel.perf_event_paranoid=2` (Intel Core Ultra 7 255U, hybrid; Linux
  6.12): the metric script's counter checks ran and passed, and make check
  and meson test passed. A 2M-iteration loop measured 7,203.7 kI
  instructions retired with a 0.001% relative standard deviation over three
  runs (CPU time: 2.7%), and 3.63M cycles in 1.39 ms of CPU time (about
  2.6 GHz, so not inflated). CI (Ubuntu, paranoid 4) still only exercises
  the unavailable path.

## perf-machines

- **Lookup merges key by key.** This machine's entry overrides the test's
  entry one key at a time, for each metric, so settings such as
  `maxPercentRegression` (and even `stddev`/`count`) can be given once for
  all machines. A machine without an entry gets the test's entry.
- **Recording stays where it was unless asked.** `-update-performance-baselines`
  writes under `"machines"` only when a machine is named (option or
  `XCTEST_MACHINE_ID`; `auto` names it by its CPU), or when the test already
  has machines. Otherwise it updates the entry itself, as in 0.5.x, so
  existing baseline files don't change shape.
- **Default identifier**: "<CPU model>, <n> cores, <architecture>", from
  `/proc/cpuinfo` (`model name`, else ARM's `Hardware`/`Model`) or, on
  Windows, the registry's `ProcessorNameString`; runs of spaces collapsed.
  The core count is `NSProcessInfo`'s `processorCount` (all configured
  CPUs, so a container's CPU quota doesn't change it, though its CPU set
  might). Naming the machine avoids any doubt.
- **The machine is logged** ("Performance baselines for machine ...") once
  per run whenever baselines are read, including by the parallel
  coordinator; workers don't log it again.
- The option wins over `XCTEST_MACHINE_ID`. Parallel workers get the
  option and inherit the environment.
- **Malformed entries** (from review): a machine's entry, or a metric's,
  that isn't a JSON object is replaced when recording instead of crashing
  the test (`-mutableCopy` on a number threw). The metric case was there in
  0.5.x too.
- **The default machine identifier is worked out once** per process, and
  only when baselines are in use (it reads `/proc/cpuinfo`).

## perf-report

- **Schema** (`"version": 1`): run-level `bundle`, `machine`, `date`, and a
  flat `measurements` list, one entry per test and metric (and repetition,
  as `iteration`, when tests are repeated). Fields that don't apply are
  `null` rather than missing, so consumers can rely on the keys; NaN
  p-values are `null` too, as JSON has no NaN.
- **Always written** when asked for, even with no measurements (an empty
  list), so CI can always collect the file; a failure to write fails the
  run, as an unwritable JUnit report does.
- **Parallel runs**: the coordinator writes it from the workers' merged
  results; workers don't.
- **JUnit properties** go per `<testcase>`, first in the element, named
  `performance.<metric identifier>.<field>`. Ant's JUnit schema has no
  test-case properties, but Jenkins' and GitLab's parsers accept them; the
  existing `system-out` lines stay for tools that ignore them.
- **Fixture fix**: `testAllMetrics` spun for 20ms of *elapsed* time and
  expected 10ms+ of CPU time, which failed under heavy load (a load
  average of 26 on a 14-core machine); it now spins for 20ms of CPU time
  (`clock()`), except on Windows, where `clock()` is elapsed time.
