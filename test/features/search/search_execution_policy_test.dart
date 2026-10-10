import 'package:flutter_test/flutter_test.dart';
import 'package:skystream/core/domain/entity/multimedia_item.dart';
import 'package:skystream/features/search/domain/search_execution_policy.dart';
import 'package:skystream/features/search/domain/search_result_filter.dart';

MultimediaItem _item(String title, int index) =>
    MultimediaItem(title: title, url: '/item/$index', posterUrl: '');

void main() {
  group('search concurrency budget', () {
    test('never schedules more work than providers available', () {
      expect(searchConcurrencyLimit(
        logicalProcessors: 32, desktop: true, providerCount: 3,
      ), 3);
      expect(searchConcurrencyLimit(
        logicalProcessors: 8, desktop: true, providerCount: 0,
      ), 0);
    });

    test('desktop budget scales with cores but caps the peak', () {
      expect(searchConcurrencyLimit(
        logicalProcessors: 2, desktop: true, providerCount: 70,
      ), 4);
      expect(searchConcurrencyLimit(
        logicalProcessors: 4, desktop: true, providerCount: 70,
      ), 8);
      expect(searchConcurrencyLimit(
        logicalProcessors: 8, desktop: true, providerCount: 70,
      ), 16);
      expect(searchConcurrencyLimit(
        logicalProcessors: 16, desktop: true, providerCount: 70,
      ), 32);
      expect(searchConcurrencyLimit(
        logicalProcessors: 32, desktop: true, providerCount: 70,
      ), 32);
    });

    test('mobile budget preserves four to eight concurrent providers', () {
      expect(searchConcurrencyLimit(
        logicalProcessors: 2, desktop: false, providerCount: 70,
      ), 4);
      expect(searchConcurrencyLimit(
        logicalProcessors: 6, desktop: false, providerCount: 70,
      ), 6);
      expect(searchConcurrencyLimit(
        logicalProcessors: 16, desktop: false, providerCount: 70,
      ), 8);
    });

    test('zero reported CPUs still chooses a safe budget', () {
      expect(searchConcurrencyLimit(
        logicalProcessors: 0, desktop: true, providerCount: 70,
      ), 4);
    });
  });

  group('filter execution boundary', () {
    test('small provider result sets stay on caller without spawning isolate',
        () async {
      for (final count in [0, 1, 29, 30, 100]) {
        final items = List.generate(
          count,
          (i) => _item(i.isEven ? 'İstanbul' : 'Ankara', i),
        );
        var workerCalls = 0;
        final result = await filterSearchItems(
          items,
          'istanbul',
          runInBackground: (input, query) async {
            workerCalls++;
            return filterProviderSearchResults(input, query);
          },
        );

        expect(workerCalls, 0);
        expect(result.map((item) => item.url).toList(),
            filterProviderSearchResults(items, 'istanbul')
                .map((item) => item.url).toList());
      }
    });

    test('large provider result sets delegate exactly once', () async {
      final items = List.generate(
        3000,
        (i) => _item(i.isEven ? 'Dune' : 'Other', i),
      );
      var calls = 0;
      final result = await filterSearchItems(
        items,
        'dune',
        runInBackground: (input, query) async {
          calls++;
          expect(identical(input, items), isTrue);
          expect(query, 'dune');
          return filterProviderSearchResults(input, query);
        },
      );
      expect(calls, 1);
      expect(result.length, 1500);
      expect(result.first.title, 'Dune');
    });

    test('real isolate result preserves multilingual matching and order',
        () async {
      final items = List.generate(
        3000,
        (i) => _item(i.isEven ? 'رِحْلَةُ البَحْرِ $i' : 'Other $i', i),
      );
      final result = await filterSearchItems(items, 'بحر');
      expect(result.length, 1500);
      expect(result.first.url, '/item/0');
      expect(result.last.url, '/item/2998');
    });
  });
}
