/// A CloudStream provider's pure parts: how episode data travels through SkyStream, how links are
/// labelled, how CloudStream's types map to SkyStream's, and the provider ids.
library;

import 'package:cs3_engine/cs3_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skystream/core/cloudstream/cloudstream_engine.dart';
import 'package:skystream/core/cloudstream/cloudstream_models.dart';
import 'package:skystream/core/cloudstream/cloudstream_provider.dart';
import 'package:skystream/core/domain/entity/multimedia_item.dart';
import 'package:skystream/core/extensions/base_provider.dart';

void main() {
  group('episode tokens', () {
    test('carry any data there and back', () {
      for (final data in ['/watch/1', '{"id": 1, "ep": "ü 🎬"}', 'https://x.test/a?b=c&d=e', '']) {
        final token = CloudStreamProvider.token(data);
        expect(token, startsWith('cs3data:'));
        expect(CloudStreamProvider.decodeToken(token), (data: data, torrent: false));
      }
    });

    test('mark torrents', () {
      final token = CloudStreamProvider.token('magnet:?xt=urn:btih:abc', torrent: true);
      expect(token, startsWith('cs3torrent:'));
      expect(CloudStreamProvider.decodeToken(token), (data: 'magnet:?xt=urn:btih:abc', torrent: true));
    });

    test('leave anything else as it is', () {
      expect(CloudStreamProvider.decodeToken('https://x.test/1'), (data: 'https://x.test/1', torrent: false));
    });
  });

  group('link labels', () {
    test('add a known quality', () {
      expect(CloudStreamProvider.label({'name': 'Server', 'quality': 1080}), 'Server · 1080p');
    });

    test('leave out unknown qualities and ones already named', () {
      expect(CloudStreamProvider.label({'name': 'Server', 'quality': 400}), 'Server');
      expect(CloudStreamProvider.label({'name': 'Server', 'quality': 0}), 'Server');
      expect(CloudStreamProvider.label({'name': 'Server 720p', 'quality': 720}), 'Server 720p');
    });

    test('fall back to the source when there is no name', () {
      expect(CloudStreamProvider.label({'name': '  ', 'source': 'Mirror'}), 'Mirror');
      expect(CloudStreamProvider.label({}), 'Link');
    });
  });

  test('CloudStream types map to SkyStream content types', () {
    expect(CloudStreamProvider.contentType('TvSeries'), MultimediaContentType.series);
    expect(CloudStreamProvider.contentType('AsianDrama'), MultimediaContentType.series);
    expect(CloudStreamProvider.contentType('Anime'), MultimediaContentType.anime);
    expect(CloudStreamProvider.contentType('Live'), MultimediaContentType.livestream);
    expect(CloudStreamProvider.contentType('AnimeMovie'), MultimediaContentType.movie);
    expect(CloudStreamProvider.contentType('Others'), MultimediaContentType.other);
    expect(CloudStreamProvider.contentType(null), MultimediaContentType.other);
  });

  test('provider ids name the plugin, repository included, and are recognised', () {
    final id = CloudStreamProvider.idFor('0a1b2c3d4e/Megakino', 'Megakino');
    expect(id, 'cs3:0a1b2c3d4e/Megakino/Megakino');
    expect(CloudStreamProvider.isCloudStreamId(id), isTrue);
    expect(CloudStreamProvider.isCloudStreamId('com.example.plugin'), isFalse);
    expect(CloudStreamProvider.isCloudStreamId(null), isFalse);
  });

  group("a Play an extension's full-screen window took", () {
    CloudStreamProvider provider(Map<String, dynamic> answer) => CloudStreamProvider(
      plugin: const CsInstalledPlugin(
        info: CsPluginInfo(internalName: 'Pokemon', name: 'Pokemon', url: '', repositoryUrl: ''),
        filePath: '/plugins/Pokemon.cs3',
      ),
      pluginKey: 'ayu/Pokemon',
      info: const CsProviderInfo(name: 'Pokemon'),
      host: _AnsweringHost(answer),
    );

    test('ends quietly when it left no links', () {
      expect(
        provider({'links': <Object?>[], 'subtitles': <Object?>[], 'completed': true, 'fullScreen': true})
            .loadStreams(CloudStreamProvider.token('pokemon')),
        throwsA(isA<ExtensionScreenEnded>()),
      );
    });

    test('plays what it left otherwise, and an empty answer of no full-screen window stays empty', () async {
      final links = await provider({
        'links': [
          {'url': 'https://cdn.test/a.m3u8', 'name': 'A'},
        ],
        'fullScreen': true,
      }).loadStreams(CloudStreamProvider.token('x'));
      expect(links.single.url, 'https://cdn.test/a.m3u8');
      expect(await provider({'links': <Object?>[]}).loadStreams(CloudStreamProvider.token('x')), isEmpty);
    });
  });
}

/// An engine host whose every call answers [answer].
class _AnsweringHost extends CloudStreamEngineHost {
  _AnsweringHost(this.answer);

  final Map<String, dynamic> answer;

  @override
  Future<T> run<T>(
    String path,
    Future<T> Function(Cs3Engine engine) call, {
    String kind = 'call',
    String? provider,
    String mainUrl = '',
    String? pluginUrl,
  }) async => answer as T;
}
