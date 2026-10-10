import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skystream/core/extensions/services/repository_service.dart';

/// Replaces only the external shortener. The resolved manifest is still
/// fetched and parsed by the real RepositoryService over local HTTP.
class _LocalShortcodeService extends RepositoryService {
  final String manifestUrl;

  _LocalShortcodeService(this.manifestUrl) : super(Dio());

  @override
  Future<String?> resolveShortLink(String shortUrl) async =>
      shortUrl == 'https://cutt.ly/sky-universe' ? manifestUrl : null;
}

/// Adding an extension repository by URL or by shortcode.
///
/// The old resolver understood exactly two things: a full `https://…` URL, or
/// a bare code looked up at `cutt.ly/sky-CODE` that answered with a redirect
/// header. Everything else — a host without a scheme, a code that lives at
/// `cutt.ly/CODE`, a shortener that answers 200 with a meta refresh — failed
/// with "Invalid URL format" or silently resolved to nothing.
void main() {
  late HttpServer server;
  late String base;
  late RepositoryService service;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    service = RepositoryService(Dio());
    server.listen((request) async {
      switch (request.uri.path) {
        case '/redirect':
          request.response
            ..statusCode = 302
            ..headers.set('location', 'https://example.com/repo.json');
        case '/meta':
          request.response
            ..statusCode = 200
            ..headers.contentType = ContentType.html
            ..write(
              '<html><head><meta http-equiv="refresh" '
              'content="0;url=https://example.com/meta.json"></head></html>',
            );
        case '/js':
          request.response
            ..statusCode = 200
            ..headers.contentType = ContentType.html
            ..write(
              "<html><script>window.location = "
              "'https://example.com/js.json';</script></html>",
            );
        case '/dead':
          request.response
            ..statusCode = 302
            ..headers.set('location', 'https://cutt.ly/404');
        case '/relative':
          request.response
            ..statusCode = 302
            ..headers.set('location', '/inline');
        case '/inline':
          request.response
            ..statusCode = 200
            ..headers.contentType = ContentType.json
            ..write(
              '{"name":"Inline Repository","id":"inline.repo",'
              '"plugins":[{"packageName":"example.plugin",'
              '"name":"Example","url":"https://example.test/plugin.js",'
              '"version":1}]}',
            );
        case '/hybrid':
          request.response
            ..statusCode = 200
            ..headers.contentType = ContentType.json
            ..write(
              '{"name":"Hybrid Repository","id":"hybrid.repo",'
              '"repos":["https://example.test/child.json"],'
              '"plugins":[{"packageName":"example.hybrid",'
              '"name":"Hybrid Plugin","url":"https://example.test/plugin.js",'
              '"version":1}]}',
            );
        case '/missing':
          request.response.statusCode = 404;
        default:
          request.response.statusCode = 404;
      }
      await request.response.close();
    });
  });

  tearDown(() async => server.close(force: true));

  group('repository url parsing', () {
    test('keeps a full url as-is', () async {
      expect(
        await service.parseRepoUrl(' https://example.com/repo.json '),
        'https://example.com/repo.json',
      );
    });

    test('adds the scheme to a bare host or path', () async {
      expect(
        await service.parseRepoUrl('raw.githubusercontent.com/u/r/main/x.json'),
        'https://raw.githubusercontent.com/u/r/main/x.json',
      );
      expect(await service.parseRepoUrl('example.com'), 'https://example.com');
    });

    test('accepts a custom scheme share link', () async {
      expect(
        await service.parseRepoUrl('skystream://example.com/repo.json'),
        'https://example.com/repo.json',
      );
    });

    test('an empty value asks for input instead of crashing', () {
      expect(() => service.parseRepoUrl('   '), throwsA(isA<Exception>()));
    });
  });

  group('shortcode resolution', () {
    test('follows a redirect header', () async {
      expect(
        await service.resolveShortLink('$base/redirect'),
        'https://example.com/repo.json',
      );
    });

    test('follows a meta refresh page', () async {
      expect(
        await service.resolveShortLink('$base/meta'),
        'https://example.com/meta.json',
      );
    });

    test('follows a javascript redirect page', () async {
      expect(
        await service.resolveShortLink('$base/js'),
        'https://example.com/js.json',
      );
    });

    test('treats the shortener 404 page as "no such code"', () async {
      expect(await service.resolveShortLink('$base/dead'), isNull);
      expect(await service.resolveShortLink('$base/missing'), isNull);
    });

    test('recognises the shortener dead ends', () {
      expect(service.isDeadEnd('https://cutt.ly/404'), isTrue);
      expect(service.isDeadEnd('https://cutt.ly/'), isTrue);
      expect(service.isDeadEnd(''), isTrue);
      expect(service.isDeadEnd('https://example.com/x.json'), isFalse);
    });

    test('unescapes html entities in a redirect target', () {
      expect(
        service.unescapeHtml('https://e.com/a.json?x=1&amp;y=2'),
        'https://e.com/a.json?x=1&y=2',
      );
    });
  });

  group('repository manifests', () {
    test('accepts a direct URL with embedded plugins and no pluginLists', () async {
      final repo = await service.fetchRepository('$base/inline');

      expect(repo, isNotNull);
      final repository = repo!;
      expect(repository.name, 'Inline Repository');
      expect(repository.plugins.single.packageName, 'example.plugin');
      expect((await service.getRepoPlugins(repository)).single.name, 'Example');
    });

    test('keeps embedded plugins in a collection that also lists repositories', () async {
      final repo = await service.fetchRepository('$base/hybrid');

      expect(repo, isNotNull);
      final repository = repo!;
      expect(repository.includedRepos, <String>[
        'https://example.test/child.json',
      ]);
      expect(repository.plugins.single.name, 'Hybrid Plugin');
    });

    test('Universe shortcode resolves through the normal manifest parser', () async {
      final shortcodeService = _LocalShortcodeService('$base/hybrid');
      final repo = await shortcodeService.fetchRepository('universe');

      expect(repo, isNotNull);
      final repository = repo!;
      expect(repository.includedRepos, <String>[
        'https://example.test/child.json',
      ]);
      expect(repository.plugins.single.name, 'Hybrid Plugin');
    });

    test('a shortlink redirect with a relative Location resolves to an absolute URL', () async {
      expect(await service.resolveShortLink('$base/relative'), '$base/inline');
    });
  });
}
