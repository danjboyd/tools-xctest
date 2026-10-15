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
  without `stddev`/`count` behave exactly as in 0.5.x.
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
