import 'dart:convert';

import 'package:cs3_engine/cs3_engine.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../domain/entity/multimedia_item.dart';
import '../extensions/base_provider.dart';
import '../logger/app_logger.dart';
import '../services/local_proxy_service.dart';
import 'cloudstream_engine.dart';
import 'cloudstream_models.dart';

/// One CloudStream provider (a plugin's `MainAPI`) as a SkyStream provider, so home, search,
/// details, the player and downloads use it like any other.
///
/// Built from what the plugin registered at install time; the engine only starts, and the
/// plugin only loads, when the provider is first used.
class CloudStreamProvider extends SkyStreamProvider {
  CloudStreamProvider({
    required this.plugin,
    required this.pluginKey,
    required this.info,
    required CloudStreamEngineHost host,
    Future<void> Function()? prepareLinks,
  }) : _host = host,
       _prepareLinks = prepareLinks;

  /// Every CloudStream provider id starts with this, which is how the UI tells them apart.
  static const String idPrefix = 'cs3:';

  /// `cs3:<plugin key>/<provider name>`. The key (see [CloudStreamRepository.keyOf]) includes the
  /// repository: two repositories can offer plugins with the same internal name (forks).
  static String idFor(String pluginKey, String providerName) => '$idPrefix$pluginKey/$providerName';

  static bool isCloudStreamId(String? id) => id != null && id.startsWith(idPrefix);

  final CsInstalledPlugin plugin;
  final String pluginKey;
  final CsProviderInfo info;
  final CloudStreamEngineHost _host;

  /// Run before links are fetched: loads the plugins whose link extractors they may need.
  final Future<void> Function()? _prepareLinks;

  /// Home page sections fetched at once; each is a network call in the plugin.
  static const int _homeConcurrency = 4;

  @override
  String get packageName => idFor(pluginKey, info.name);

  @override
  String get name => info.name;

  @override
  String get mainUrl => info.mainUrl;

  @override
  String get checkSource => packageName;

  @override
  String get version => '${plugin.info.version}';

  @override
  List<String> get languages => [if (info.lang != null && info.lang!.isNotEmpty) info.lang!];

  @override
  Set<ProviderType> get supportedTypes {
    final types = {for (final t in info.types) _providerType(t)};
    return types.isEmpty ? {ProviderType.other} : types;
  }

  /// The plugin's display name, for the CloudStream badge.
  String get pluginName => plugin.info.name;

  String get _pluginPath => plugin.filePath;

  /// Runs [call] with the plugin loaded; see [CloudStreamEngineHost.run]. [kind] is the provider
  /// call it makes.
  Future<Map<String, dynamic>> _call(
    Future<Map<String, dynamic>> Function(Cs3Engine engine) call, {
    String kind = 'call',
  }) => _host.run(_pluginPath, call, kind: kind, provider: packageName, mainUrl: mainUrl, pluginUrl: plugin.info.url);

  @override
  Future<List<MultimediaItem>> search(String query, {CancelToken? cancelToken}) async {
    try {
      final result = await _call((e) => e.search(name, query, plugin: _pluginPath), kind: 'search');
      return [for (final item in _list(result['items'])) _item(item)];
    } catch (error) {
      talker.warning('[CloudStream] $name search failed: $error');
      return const [];
    }
  }

  @override
  Future<Map<String, List<MultimediaItem>>> getHome() async {
    if (!info.hasMainPage) return const {};
    // One call per section, a few at a time: the engine walks a provider's sections one after
    // another when asked for all of them.
    final names = info.sections.isEmpty ? const <String?>[null] : info.sections.cast<String?>();
    final pages = List<Map<String, List<MultimediaItem>>>.filled(names.length, const {});
    Object? failure;
    var next = 0;
    Future<void> worker() async {
      while (next < names.length) {
        final index = next++;
        try {
          final result = await _call(
            (e) => e.mainPage(name, section: names[index], plugin: _pluginPath),
            kind: 'mainPage',
          );
          pages[index] = {
            for (final section in _list(result['sections']))
              if (section['error'] == null && _list(section['items']).isNotEmpty)
                // Home items carry no provider, like SkyStream plugins' (the carousel would print the
                // id); details falls back to the active provider, whose home this is.
                (section['name'] as String? ?? name): [
                  for (final item in _list(section['items'])) _item(item, stampProvider: false),
                ],
          };
        } catch (error) {
          failure = error;
          talker.warning('[CloudStream] $name home section ${names[index]} failed: $error');
        }
      }
    }

    await Future.wait([for (var i = 0; i < _homeConcurrency; i++) worker()]);
    final home = {for (final page in pages) ...page};
    // Nothing at all, and a failure: the home screen's error state (with retry), not a blank page.
    if (home.isEmpty && failure != null) throw failure!;
    return home;
  }

  @override
  Future<MultimediaItem> getDetails(String url) async {
    final result = await _call((e) => e.load(name, url, plugin: _pluginPath), kind: 'load');
    final type = _contentType(result['type'] as String?);
    final title = result['name'] as String? ?? '';
    final episodes = <Episode>[];

    final dataUrl = result['dataUrl'] as String?;
    final magnet = result['magnet'] as String? ?? result['torrent'] as String?;
    if (dataUrl != null) {
      episodes.add(Episode(name: title, url: _token(dataUrl), season: 1, episode: 1));
    } else if (magnet != null) {
      episodes.add(Episode(name: title, url: _token(magnet, torrent: true), season: 1, episode: 1));
    } else {
      final raw = _list(result['episodes']);
      for (var i = 0; i < raw.length; i++) {
        final ep = raw[i];
        final number = (ep['episode'] as num?)?.toInt() ?? i + 1;
        episodes.add(
          Episode(
            name: (ep['name'] as String?)?.trim().isNotEmpty == true ? ep['name'] as String : 'Episode $number',
            url: _token(ep['data'] as String),
            season: (ep['season'] as num?)?.toInt() ?? 1,
            episode: number,
            description: ep['description'] as String?,
            posterUrl: ep['posterUrl'] as String?,
            dubStatus: switch ((ep['dub'] as String?)?.toLowerCase()) {
              'dubbed' => DubStatus.dubbed,
              'subbed' => DubStatus.subbed,
              _ => DubStatus.none,
            },
          ),
        );
      }
    }

    return MultimediaItem(
      title: title,
      // The URL we were asked for, not the one the plugin echoes: history and the details
      // screen are keyed by it.
      url: url,
      posterUrl: result['posterUrl'] as String? ?? '',
      bannerUrl: result['backgroundPosterUrl'] as String?,
      description: result['plot'] as String?,
      contentType: type,
      provider: packageName,
      year: (result['year'] as num?)?.toInt(),
      duration: (result['duration'] as num?)?.toInt(),
      tags: [...?(result['tags'] as List?)?.whereType<String>()],
      episodes: episodes,
    );
  }

  @override
  Future<List<StreamResult>> loadStreams(String url) async {
    final (:data, :torrent) = _decodeToken(url);
    if (torrent) return [StreamResult(url: data, source: 'Torrent', providerName: name)];

    await _prepareLinks?.call();
    final result = await _call((e) => e.loadLinks(name, data, plugin: _pluginPath), kind: 'loadLinks');
    // Its full-screen window (a game) took the Play, and left no links: nothing to play, and nothing went wrong.
    if (_list(result['links']).isEmpty && result['fullScreen'] == true) throw const ExtensionScreenEnded();
    final subtitles = await _subtitles(_list(result['subtitles']));
    return [
      for (final link in _list(result['links']))
        StreamResult(
          url: link['url'] as String,
          source: _label(link),
          providerName: name,
          headers: _headers(link),
          subtitles: subtitles,
          drmKid: (link['drm'] as Map?)?['kid'] as String?,
          drmKey: (link['drm'] as Map?)?['key'] as String?,
          licenseUrl: (link['drm'] as Map?)?['licenseUrl'] as String?,
        ),
    ];
  }

  MultimediaItem _item(Map<String, dynamic> item, {bool stampProvider = true}) => MultimediaItem(
    title: item['name'] as String? ?? '',
    url: item['url'] as String,
    posterUrl: item['posterUrl'] as String? ?? '',
    contentType: _contentType(item['type'] as String?),
    provider: stampProvider ? packageName : null,
    year: (item['year'] as num?)?.toInt(),
    headers: (item['posterHeaders'] as Map?)?.cast<String, String>(),
  );

  /// CloudStream episode data can be anything (a path, JSON...), and the player treats some
  /// strings (`/...`, `magnet:`) as playable already, so it travels wrapped.
  @visibleForTesting
  static String token(String data, {bool torrent = false}) => _token(data, torrent: torrent);

  @visibleForTesting
  static ({String data, bool torrent}) decodeToken(String token) => _decodeToken(token);

  @visibleForTesting
  static String label(Map<String, dynamic> link) => _label(link);

  @visibleForTesting
  static MultimediaContentType contentType(String? type) => _contentType(type);

  static String _token(String data, {bool torrent = false}) =>
      '${torrent ? 'cs3torrent' : 'cs3data'}:${base64Url.encode(utf8.encode(data))}';

  static ({String data, bool torrent}) _decodeToken(String token) {
    final colon = token.indexOf(':');
    final scheme = colon < 0 ? '' : token.substring(0, colon);
    if (scheme != 'cs3data' && scheme != 'cs3torrent') return (data: token, torrent: false);
    return (data: utf8.decode(base64Url.decode(token.substring(colon + 1))), torrent: scheme == 'cs3torrent');
  }

  /// "Server · 1080p". SkyStream reads the quality back from this label.
  static String _label(Map<String, dynamic> link) {
    final name = (link['name'] as String?)?.trim().isNotEmpty == true ? link['name'] as String : link['source'] as String? ?? 'Link';
    final quality = (link['quality'] as num?)?.toInt() ?? 0;
    // CloudStream's Qualities.Unknown is 400, and 0 or less means none.
    final known = quality > 0 && quality != 400 && !name.contains('${quality}p');
    return known ? '$name · ${quality}p' : name;
  }

  static Map<String, String>? _headers(Map<String, dynamic> link) {
    final headers = <String, String>{...?(link['headers'] as Map?)?.map((k, v) => MapEntry('$k', '$v'))};
    final referer = link['referer'] as String?;
    if (referer != null && referer.isNotEmpty && !headers.keys.any((k) => k.toLowerCase() == 'referer')) {
      headers['Referer'] = referer;
    }
    return headers.isEmpty ? null : headers;
  }

  /// SkyStream's subtitles carry no headers, so ones that need them go through the local proxy.
  static Future<List<SubtitleFile>> _subtitles(List<Map<String, dynamic>> raw) async {
    final files = <SubtitleFile>[];
    for (final sub in raw) {
      var url = sub['url'] as String;
      final headers = (sub['headers'] as Map?)?.map((k, v) => MapEntry('$k', '$v'));
      if (headers != null && headers.isNotEmpty) {
        await LocalProxyService.instance.startServer();
        url = LocalProxyService.instance.getProxyUrl(url, headers: headers);
      }
      final lang = sub['lang'] as String? ?? 'Unknown';
      files.add(SubtitleFile(url: url, label: lang, lang: lang));
    }
    return files;
  }

  static List<Map<String, dynamic>> _list(Object? value) => [
    for (final entry in (value as List?) ?? const []) if (entry is Map) Map<String, dynamic>.from(entry),
  ];

  /// CloudStream `TvType` to SkyStream's content type.
  static MultimediaContentType _contentType(String? type) => switch (type) {
    'TvSeries' || 'Cartoon' || 'AsianDrama' || 'Documentary' => MultimediaContentType.series,
    'Anime' || 'OVA' => MultimediaContentType.anime,
    'Live' => MultimediaContentType.livestream,
    'Movie' || 'AnimeMovie' || 'Torrent' || 'NSFW' => MultimediaContentType.movie,
    _ => MultimediaContentType.other,
  };

  static ProviderType _providerType(String type) => switch (_contentType(type)) {
    MultimediaContentType.movie => ProviderType.movie,
    MultimediaContentType.series => ProviderType.series,
    MultimediaContentType.anime => ProviderType.anime,
    MultimediaContentType.livestream => ProviderType.livestream,
    MultimediaContentType.other => ProviderType.other,
  };
}
