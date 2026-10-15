# 0.6.0 performance work: decisions log

Dan approved the plan on 2026-10-15 ("all recommended"). The work was done
overnight; when a question came up that the plan didn't settle, the
conservative option was taken (match Apple, opt-in, backwards-compatible)
and recorded here for review.

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
  (`PERF_PMU_TYPE_SHIFT`, Linux 6.0 and later), summed, so work on either
  kind is counted; on older kernels, a single generic counter.
- **Multiplexing.** Counts are scaled by time enabled ÷ time running, as
  `perf stat` does.
- **GSXCTHardwareCounterMetric** reports raw counts ("misses") rather than
  thousands, with `org.gnustep.XCTMetric_HardwareCounter.*` identifiers, as
  it isn't Apple's.
- **Unavailable counters** are logged once per process and left out;
  `XCTEST_PERF_COUNTERS=0` turns them off (also how the tests exercise that
  path). `+[GSXCTHardwareCounterMetric isAvailable]` is public so a test can
  skip itself.
- **Untested here: the working path.** Debian (this machine) and Ubuntu
  (CI) set `perf_event_paranoid` to 3+, which refuses all unprivileged
  counters, so only the unavailable path ran. To check the rest:
  `sudo sysctl kernel.perf_event_paranoid=2`, then run `make check` (the
  metric script checks the counts when they're available).
