import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skystream/core/domain/entity/multimedia_item.dart';
import 'package:skystream/features/search/domain/search_result_filter.dart';

/// Controlled workloads with the real MultimediaItem model and filtering
/// function. No HTTP, JS engine or WebView. These timings are not proof of
/// faster real searches; CI is a noisy, shared environment.
List<MultimediaItem> _sample(int count) => List.generate(
  count,
  (i) => MultimediaItem(
    title: i.isEven ? 'Dune: Chapter $i' : 'Other Movie $i',
    url: '/movie/$i',
    posterUrl: '',
  ),
);

class _FilterInput {
  final List<MultimediaItem> items;
  final String query;
  const _FilterInput(this.items, this.query);
}

List<MultimediaItem> _isolateFilter(_FilterInput input) =>
    filterProviderSearchResults(input.items, input.query);

int _median(List<int> values) {
  final sorted = List<int>.from(values)..sort();
  return sorted[sorted.length ~/ 2];
}

Future<int> _timeAsync(Future<void> Function() operation) async {
  final watch = Stopwatch()..start();
  await operation();
  watch.stop();
  return watch.elapsedMicroseconds;
}

int _timeSync(void Function() operation) {
  final watch = Stopwatch()..start();
  operation();
  watch.stop();
  return watch.elapsedMicroseconds;
}

Future<({int micros, int peak})> _simulatedBurst({
  required int limit,
  required List<MultimediaItem> items,
}) async {
  const providers = 48;
  var next = 0;
  var active = 0;
  var peak = 0;
  final watch = Stopwatch()..start();

  Future<void> worker() async {
    while (next < providers) {
      final index = next++;
      active++;
      if (active > peak) peak = active;
      try {
        await Future<void>.delayed(Duration(milliseconds: 6 + index % 7));
        final result = await compute(_isolateFilter, _FilterInput(items, 'dune'));
        if (result.length != items.length ~/ 2) {
          throw StateError('Search results changed during benchmark');
        }
      } finally {
        active--;
      }
    }
  }

  await Future.wait(List.generate(limit, (_) => worker()));
  watch.stop();
  return (micros: watch.elapsedMicroseconds, peak: peak);
}

void main() {
  test('benchmark: direct filtering versus per-result compute isolation', () async {
    final warm = _FilterInput(_sample(100), 'dune');
    for (var i = 0; i < 4; i++) {
      _isolateFilter(warm);
      await compute(_isolateFilter, warm);
    }

    for (final count in [30, 100, 300, 1000]) {
      final input = _FilterInput(_sample(count), 'dune');
      final expected = _isolateFilter(input);
      final direct = <int>[];
      final isolated = <int>[];

      for (var i = 0; i < 15; i++) {
        direct.add(_timeSync(() {
          final filtered = _isolateFilter(input);
          expect(filtered.length, expected.length);
        }));
      }
      for (var i = 0; i < 7; i++) {
        isolated.add(await _timeAsync(() async {
          final filtered = await compute(_isolateFilter, input);
          expect(
            filtered.map((item) => item.url).toList(),
            expected.map((item) => item.url).toList(),
          );
        }));
      }
      // ignore: avoid_print
      print('SEARCH_FILTER_BENCH count=$count '
          'sync_median_us=${_median(direct)} '
          'compute_median_us=${_median(isolated)}');
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('benchmark: synthetic provider burst at 8/16/32 slots', () async {
    final items = _sample(100);
    for (final limit in [8, 16, 32]) {
      final first = await _simulatedBurst(limit: limit, items: items);
      final second = await _simulatedBurst(limit: limit, items: items);
      expect(first.peak, lessThanOrEqualTo(limit));
      expect(second.peak, lessThanOrEqualTo(limit));
      // ignore: avoid_print
      print('SEARCH_BURST_BENCH slots=$limit '
          'median_us=${_median([first.micros, second.micros])} '
          'peak=${first.peak}');
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
