import 'package:flutter_test/flutter_test.dart';
import 'package:skystream/core/addons/models/addon_stream_source.dart';
import 'package:skystream/core/utils/source_text.dart';

void main() {
  group('sourceAudioLanguageTag', () {
    test('keeps a concise explicit language as an uppercase badge', () {
      expect(sourceAudioLanguageTag('  hi  '), 'HI');
      expect(sourceAudioLanguageTag('Turkish'), 'TURKISH');
    });

    test('does not invent a language for absent or unknown metadata', () {
      for (final value in <String?>[null, '', '  ', 'und', 'UNKNOWN', 'n/a']) {
        expect(sourceAudioLanguageTag(value), isNull);
      }
    });

    test('does not turn arbitrary long source text into a badge', () {
      expect(sourceAudioLanguageTag('Unknown language or auto-detected value'), isNull);
    });
  });

  group('Stremio stream audio language', () {
    AddonStreamSource source(Map<String, dynamic> fields) =>
        AddonStreamSource.fromJson({
          'url': 'https://cdn.test/movie.mkv',
          ...fields,
        }, addonId: 'example', addonName: 'Example');

    test('uses explicit top-level stream language', () {
      expect(source({'audioLanguage': 'tr'}).audioLanguage, 'tr');
      expect(source({'language': 'ja'}).audioLanguage, 'ja');
      expect(source({'lang': 'hi'}).audioLanguage, 'hi');
    });

    test('uses explicit behavior hints when top-level value is absent', () {
      expect(source({
        'behaviorHints': {'audioLanguage': 'en'},
      }).audioLanguage, 'en');
    });

    test('does not guess audio language from a movie title', () {
      expect(source({'name': 'English Patient 1080p'}).audioLanguage, isNull);
    });

    test('ignores malformed metadata instead of throwing', () {
      expect(source({'audioLanguage': 42}).audioLanguage, isNull);
    });
  });
}
