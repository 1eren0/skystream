# Search performance probe

This PR has a repeatable **microbenchmark**, not a claim of end-user FPS or
network throughput improvement. The existing production search fans out to up to
32 desktop providers and sent *every* 30+ item result batch through
`compute()`, starting a transient isolate with a copy of each item list.

## Reproduce

```sh
flutter test --reporter expanded test/features/search/search_performance_benchmark_test.dart
flutter test test/features/search/search_execution_policy_test.dart
flutter test test/features/search/search_result_filter_test.dart
```

The first command logs `SEARCH_FILTER_BENCH` median microseconds for direct
filtering and a one-shot `compute()` on lists of 30, 100, 300 and 1000
MultimediaItem instances. It also logs `SEARCH_BURST_BENCH` with measured
elapsed microseconds and peak concurrent simulated providers for 8, 16 and 32
slots. The workload is deterministic, but the timings **are not**: warmup,
runner load and isolate startup affect the outcome. Do not write unit-test
pass/fail conditions on wall-clock timings.

An isolate is primarily a tool for keeping the UI responsive, not making each
individual job complete faster. Avoiding one-off isolates for short batches
can lower per-provider time-to-result without sacrificing large-batch
responsiveness. Desktop concurrency is scaled to reported logical processors
(max 16) to lower peak pressure; a 32-slot burst can have higher *throughput*
in IO-only simulations, so that cap needs real-device validation.

## Required on-device follow-up

In Flutter profile mode on Android TV, low-end Windows and a high-core PC,
compare 8/16/32 active providers and the new CPU-scaled policy using an actual
30–70-provider search. Record time to first provider result, time to finish,
p95/p99 UI and raster frame times, maximum RSS, peak in-flight HTTP, and
cancellation time when editing the query. Benchmark on the same plugin set and
network. Revert the desktop limit if the real search completion slowdown is
material and the peak resource benefit is negligible.

The regression tests cover worker routing, language matching, result order,
and never queuing more tasks than available providers. The project-wide
existing tests cover search UI and cancellation behavior.
