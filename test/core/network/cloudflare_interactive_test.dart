import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skystream/core/network/cloudflare_bypass.dart';
import 'package:skystream/core/network/cloudflare_http_overrides.dart';

const MethodChannel _pathProvider = MethodChannel(
  'plugins.flutter.io/path_provider',
);

class _ProbeEnvironment implements WebViewEnvironment {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory directory;
  late WebViewEnvironment environment;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('skystream-cf-test-');
    messenger.setMockMethodCallHandler(
      _pathProvider,
      (call) async => directory.path,
    );
    environment = _ProbeEnvironment();
    CloudflareBypass.platformHasWebView = () => true;
    CloudflareBypass.needsWebViewEnvironment = () => true;
    CloudflareBypass.createEnvironment = (_) async => environment;
  });

  tearDown(() {
    CloudflareBypass.interactiveSolver = null;
    CloudflareBypass.debugResetEnvironment();
    CloudflareBypass.debugResetPlatformProbe();
    messenger.setMockMethodCallHandler(_pathProvider, null);
    directory.deleteSync(recursive: true);
  });

  test(
    'same-site requests share one visible verification and its result',
    () async {
      final entered = Completer<void>();
      final verified = Completer<CfResult?>();
      var dialogs = 0;
      var cookieWrites = 0;
      CloudflareBypass.interactiveSolver = (url, receivedEnvironment, referer) {
        dialogs++;
        expect(url, 'https://interactive.test/catalog');
        expect(identical(receivedEnvironment, environment), isTrue);
        expect(referer, 'https://interactive.test/episode');
        entered.complete();
        return verified.future;
      };
      final first = CloudflareBypass.instance.solveAndFetch(
        'https://interactive.test/catalog',
        callerId: 'test-plugin',
        referer: 'https://interactive.test/episode',
        onSolved: (_) async => cookieWrites++,
      );
      final second = CloudflareBypass.instance.solveAndFetch(
        'https://interactive.test/catalog',
        callerId: 'test-plugin',
      );
      await entered.future.timeout(const Duration(seconds: 5));
      expect(dialogs, 1);
      expect(cookieWrites, 0);
      const page = CfResult(
        body: '<html><body>Catalog</body></html>',
        statusCode: 200,
        finalUrl: 'https://interactive.test/catalog',
      );
      verified.complete(page);
      expect(await first, same(page));
      expect(await second, same(page));
      expect(cookieWrites, 1);
    },
  );

  test(
    'verified browser identity and Cloudflare cookies are kept for the host',
    () async {
      const agent = 'Mozilla/5.0 (Windows NT 10.0) Edg/154.0.0.0';
      CloudflareBypass.interactiveSolver = (url, _, _) async => CfResult(
        body: '<html><body>Catalog</body></html>',
        statusCode: 200,
        finalUrl: url,
        cookies: const [
          {'name': 'cf_clearance', 'value': 'x', 'domain': '.agent.test'},
        ],
        userAgent: agent,
      );
      expect(CloudflareBypass.instance.userAgentFor('agent.test'), isNull);
      final result = await CloudflareBypass.instance.solveAndFetch(
        'https://agent.test/catalog',
      );
      expect(result?.cookies.single['name'], 'cf_clearance');
      expect(CloudflareBypass.instance.userAgentFor('agent.test'), agent);
      expect(CloudflareBypass.instance.userAgentFor('other.test'), isNull);
      expect(
        CloudflareBypass.instance.cookieHeaderFor('agent.test'),
        'cf_clearance=x',
      );
      expect(
        CloudflareBypass.instance.cookieHeaderFor('img.agent.test'),
        'cf_clearance=x',
      );
      expect(CloudflareBypass.instance.cookieHeaderFor('other.test'), isNull);
      expect(isCloudflareCookieName('_cfuvid'), isTrue);
      expect(isCloudflareCookieName('__cf_bm'), isTrue);
      expect(isCloudflareCookieName('PHPSESSID'), isFalse);
    },
  );

  test('host-only clearance never reaches a sibling or subdomain', () async {
    CloudflareBypass.interactiveSolver = (url, _, _) async => CfResult(
      body: '<html>ok</html>',
      statusCode: 200,
      finalUrl: url,
      userAgent: 'ScopedAgent/1',
      cookies: const [
        {'name': 'cf_clearance', 'value': 'only-this-host'},
      ],
    );
    await CloudflareBypass.instance.solveAndFetch(
      'https://scoped.test/',
      callerId: 'plugin-a',
    );
    expect(
      CloudflareBypass.instance.cookieHeaderFor(
        'scoped.test', callerId: 'plugin-a',
      ),
      'cf_clearance=only-this-host',
    );
    expect(
      CloudflareBypass.instance.cookieHeaderFor(
        'img.scoped.test', callerId: 'plugin-a',
      ),
      isNull,
    );
    expect(
      CloudflareBypass.instance.userAgentFor(
        'scoped.test', callerId: 'plugin-b',
      ),
      isNull,
    );
    expect(
      CloudflareBypass.instance.cookieHeaderFor(
        'scoped.test', callerId: 'plugin-b',
      ),
      isNull,
    );
  });

  test('a domain clearance also supplies its verified UA to subdomains', () async {
    CloudflareBypass.interactiveSolver = (url, _, _) async => CfResult(
      body: '<html>ok</html>',
      statusCode: 200,
      finalUrl: url,
      userAgent: 'SharedSiteAgent/2',
      cookies: const [
        {
          'name': 'cf_clearance',
          'value': 'domain-cookie',
          'domain': '.shared-site.test',
          'secure': true,
        },
      ],
    );
    await CloudflareBypass.instance.solveAndFetch(
      'https://shared-site.test/', callerId: 'plugin-a',
    );
    expect(
      CloudflareBypass.instance.userAgentFor(
        'images.shared-site.test', callerId: 'plugin-a',
      ),
      'SharedSiteAgent/2',
    );
    expect(
      CloudflareBypass.instance.cookieHeaderFor(
        'images.shared-site.test', callerId: 'plugin-a',
      ),
      'cf_clearance=domain-cookie',
    );
    expect(
      CloudflareBypass.instance.cookieHeaderFor(
        'unrelated.test', callerId: 'plugin-a',
      ),
      isNull,
    );
  });

  test('an HTTP error or a challenge page cannot count as verified', () {
    const clearance = <Map<String, dynamic>>[
      {'name': 'cf_clearance', 'value': 'token'},
    ];
    expect(
      isVerifiedCloudflarePage(
        host: 'site.test', expectedHost: 'site.test',
        httpStatus: 403, challenge: false, hasBody: true,
        cookies: clearance,
      ),
      isFalse,
    );
    expect(
      isVerifiedCloudflarePage(
        host: 'site.test', expectedHost: 'site.test',
        httpStatus: 200, challenge: true, hasBody: true,
        cookies: clearance,
      ),
      isFalse,
    );
    expect(
      isVerifiedCloudflarePage(
        host: 'other.test', expectedHost: 'site.test',
        httpStatus: 200, challenge: false, hasBody: true,
        cookies: clearance,
      ),
      isFalse,
    );
    expect(
      isVerifiedCloudflarePage(
        host: 'site.test', expectedHost: 'site.test',
        httpStatus: 200, challenge: false, hasBody: true,
        cookies: const [],
      ),
      isFalse,
    );
    expect(
      isVerifiedCloudflarePage(
        host: 'site.test', expectedHost: 'site.test',
        httpStatus: 200, challenge: false, hasBody: true,
        cookies: clearance,
      ),
      isTrue,
    );
  });

  test(
    'cancelling verification releases the queue for a later request',
    () async {
      var dialogs = 0;
      CloudflareBypass.interactiveSolver = (_, _, _) async {
        dialogs++;
        return null;
      };
      expect(
        await CloudflareBypass.instance.solveAndFetch('https://cancel.test/'),
        isNull,
      );
      expect(
        await CloudflareBypass.instance.solveAndFetch('https://later.test/'),
        isNull,
      );
      expect(dialogs, 2);
    },
  );

  test(
    'failed browser environment never opens a misleading verification UI',
    () async {
      CloudflareBypass.createEnvironment = (_) async => null;
      var dialogs = 0;
      CloudflareBypass.interactiveSolver = (_, _, _) async {
        dialogs++;
        return null;
      };
      expect(
        await CloudflareBypass.instance.solveAndFetch('https://failed.test/'),
        isNull,
      );
      expect(dialogs, 0);
    },
  );

  test('plain HTTP requests to a verified host carry its clearance', () async {
    CloudflareBypass.interactiveSolver = (url, _, _) async => CfResult(
      body: '<html><body>ok</body></html>',
      statusCode: 200,
      finalUrl: url,
      cookies: const [
        {'name': 'cf_clearance', 'value': 'img'},
      ],
      userAgent: 'VerifiedAgent/1.0',
    );
    await CloudflareBypass.instance.solveAndFetch('https://localhost/');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final seen = <String?>[];
    server.listen((request) {
      seen
        ..add(request.headers.value(HttpHeaders.cookieHeader))
        ..add(request.headers.value(HttpHeaders.userAgentHeader));
      request.response.close();
    });
    try {
      await HttpOverrides.runWithHttpOverrides(() async {
        final client = HttpClient();
        final request = await client.getUrl(
          Uri.parse('http://localhost:${server.port}/poster.webp'),
        );
        await (await request.close()).drain<void>();
        client.close();
      }, CloudflareHttpOverrides());
    } finally {
      await server.close(force: true);
    }
    expect(seen.first, isNull, reason: 'secure clearance must not leak over plaintext HTTP');
    expect(seen.last, isNot('VerifiedAgent/1.0'));
    expect(shouldAttachCloudflareClearance(Uri.parse('https://localhost/poster.webp')), isTrue);
    expect(shouldAttachCloudflareClearance(Uri.parse('http://localhost/poster.webp')), isFalse);
  });
}
