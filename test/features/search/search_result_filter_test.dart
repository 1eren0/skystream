import 'package:flutter_test/flutter_test.dart';
import 'package:skystream/core/domain/entity/multimedia_item.dart';
import 'package:skystream/features/search/domain/search_result_filter.dart';

MultimediaItem _item(String title) =>
    MultimediaItem(title: title, url: '/title', posterUrl: '');

List<String> _titles(List<MultimediaItem> items) =>
    items.map((item) => item.title).toList();

void main() {
  group('filterProviderSearchResults', () {
    test('matches Arabic substrings even with vowel marks', () {
      final items = [
        _item('رِحْلَةُ البَحْرِ'),
        _item('الطريق إلى المدرسة'),
      ];

      expect(_titles(filterProviderSearchResults(items, 'بحر')), [
        'رِحْلَةُ البَحْرِ',
      ]);
    });

    test('matches within unspaced CJK titles', () {
      final items = [_item('君の名は'), _item('千と千尋の神隠し')];

      expect(_titles(filterProviderSearchResults(items, 'の名')), ['君の名は']);
    });

    test('handles Turkish dotted I without losing a matching title', () {
      final items = [_item('İstanbul Hatırası'), _item('Ankara')];

      expect(_titles(filterProviderSearchResults(items, 'istanbul')), [
        'İstanbul Hatırası',
      ]);
    });

    test('matches punctuation-separated words and repeated whitespace', () {
      final items = [_item('Spider-Man: Homecoming'), _item('Batman')];

      expect(_titles(filterProviderSearchResults(items, '  SPIDER   man ')), [
        'Spider-Man: Homecoming',
      ]);
    });

    test('preserves localized provider results when titles do not match', () {
      // The provider already searched in Arabic, but displays English titles.
      final items = [_item('The Sea Will Overflow')];

      expect(
        _titles(filterProviderSearchResults(items, 'هذا البحر سوف يفيض')),
        ['The Sea Will Overflow'],
      );
    });

    test('keeps provider order and filters noise when titles do match', () {
      final items = [
        _item('بحر الرمال'),
        _item('An unrelated recommendation'),
        _item('أسرار البحر'),
      ];

      expect(_titles(filterProviderSearchResults(items, 'بحر')), [
        'بحر الرمال',
        'أسرار البحر',
      ]);
    });

    test('does not turn an empty provider response into results', () {
      expect(filterProviderSearchResults([], 'بحر'), isEmpty);
    });

    test('does not search for whitespace-only input', () {
      expect(filterProviderSearchResults([_item('Dune')], '  \t  '), isEmpty);
    });
  });
}
