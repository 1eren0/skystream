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
(4..32 according to logical core count) to lower peak pressure on
low-core machines without slowing high-core machines by default. The 32-slot
burst had higher *throughput* in the controlled simulation, so blindly
capping all desktops at 16 would be unjustified.

## Baseline measurements — GitHub Linux CI

Measured in the unchanged search code on commit d2475d5, run
https://github.com/1eren0/skystream/actions/runs/38016042656.
Values are medians in microseconds. Filtering includes test assertion and
result verification overhead and must not be interpreted as isolated pure
function time:

| Items | Direct filter | One-shot compute() |
|---:|---:|---:|
| 30 | 137 | 669 |
| 100 | 517 | 891 |
| 300 | 792 | 1,219 |
| 1,000 | 1,982 | 2,078 |

The 48-provider synthetic burst returned 68,229 us at 8 slots, 39,026 us at
16 slots and 31,952 us at 32 slots (peak active providers equalled the chosen
limit). This is **not** an actual scraper/network benchmark. We retain 32
slots when a machine reports >=16 logical processors and budget smaller
machines proportionally. The new 512-item offload threshold avoids the
measured compute() overhead for 30/100/300-item batches; batches >=512 keep
the UI offload safeguard.

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
