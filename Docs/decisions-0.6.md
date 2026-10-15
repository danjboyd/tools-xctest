# 0.6.0 performance work: decisions log

Dan approved the plan on 2026-10-15 ("all recommended"). The work was done
overnight; when a question came up that the plan didn't settle, the
conservative option was taken (match Apple, opt-in, backwards-compatible)
and recorded here for review.

## Branches

The features touch the same baseline and reporting code, so their branches
are stacked rather than each taken from master: `perf-statistics` →
`perf-machines` → `perf-report`. `perf-counters` is independent and starts
from master. Each is merged into `next-0.6`. Only those branches are pushed
(for CI); master, tags and upstream are untouched.

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
  expected 10ms+ of CPU time, which failed under heavy load (load average
  26 here tonight); it now spins for 20ms of CPU time (`clock()`), except on
  Windows, where `clock()` is elapsed time. Worth taking to master as well.
