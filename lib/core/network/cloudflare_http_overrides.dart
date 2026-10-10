import 'dart:io';

import 'cloudflare_bypass.dart';

/// Sends a visibly verified host's Cloudflare clearance with every plain
/// `dart:io` request the app makes to that host.
///
/// Images are the reason: artwork is fetched by the image cache's own HTTP
/// client (dozens of call sites, none passing headers), and a site behind
/// Cloudflare answers those requests with the challenge page instead of the
/// picture. Requests that already carry a clearance cookie are left alone, so
/// the extension engine's own cookie handling is unaffected.
/// Cloudflare clearance is a secure browser credential. Never put it on
/// plaintext HTTP, even for localhost or an image URL that looks harmless.
bool shouldAttachCloudflareClearance(Uri uri) => uri.scheme == 'https';

class CloudflareHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _ClearanceHttpClient(super.createHttpClient(context));
}

class _ClearanceHttpClient implements HttpClient {
  final HttpClient _inner;
  _ClearanceHttpClient(this._inner);

  HttpClientRequest _withClearance(HttpClientRequest request) {
    if (!shouldAttachCloudflareClearance(request.uri)) return request;
    final host = request.uri.host;
    final agent = CloudflareBypass.instance.userAgentFor(host);
    final cookie = CloudflareBypass.instance.cookieHeaderFor(
      host, path: request.uri.path,
    );
    if (agent == null || cookie == null) return request;
    final existing = request.headers.value(HttpHeaders.cookieHeader) ?? '';
    if (existing.contains('cf_clearance=')) return request;
    request.headers.set(HttpHeaders.userAgentHeader, agent);
    request.headers.set(
      HttpHeaders.cookieHeader,
      existing.isEmpty ? cookie : '$existing; $cookie',
    );
    return request;
  }

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      _inner.openUrl(method, url).then(_withClearance);

  @override
  Future<HttpClientRequest> open(
    String method,
    String host,
    int port,
    String path,
  ) => _inner.open(method, host, port, path).then(_withClearance);

  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);
  @override
  Future<HttpClientRequest> postUrl(Uri url) => openUrl('POST', url);
  @override
  Future<HttpClientRequest> putUrl(Uri url) => openUrl('PUT', url);
  @override
  Future<HttpClientRequest> deleteUrl(Uri url) => openUrl('DELETE', url);
  @override
  Future<HttpClientRequest> patchUrl(Uri url) => openUrl('PATCH', url);
  @override
  Future<HttpClientRequest> headUrl(Uri url) => openUrl('HEAD', url);

  @override
  Future<HttpClientRequest> get(String host, int port, String path) =>
      open('GET', host, port, path);
  @override
  Future<HttpClientRequest> post(String host, int port, String path) =>
      open('POST', host, port, path);
  @override
  Future<HttpClientRequest> put(String host, int port, String path) =>
      open('PUT', host, port, path);
  @override
  Future<HttpClientRequest> delete(String host, int port, String path) =>
      open('DELETE', host, port, path);
  @override
  Future<HttpClientRequest> patch(String host, int port, String path) =>
      open('PATCH', host, port, path);
  @override
  Future<HttpClientRequest> head(String host, int port, String path) =>
      open('HEAD', host, port, path);

  @override
  Duration get idleTimeout => _inner.idleTimeout;
  @override
  set idleTimeout(Duration value) => _inner.idleTimeout = value;
  @override
  Duration? get connectionTimeout => _inner.connectionTimeout;
  @override
  set connectionTimeout(Duration? value) => _inner.connectionTimeout = value;
  @override
  int? get maxConnectionsPerHost => _inner.maxConnectionsPerHost;
  @override
  set maxConnectionsPerHost(int? value) =>
      _inner.maxConnectionsPerHost = value;
  @override
  bool get autoUncompress => _inner.autoUncompress;
  @override
  set autoUncompress(bool value) => _inner.autoUncompress = value;
  @override
  String? get userAgent => _inner.userAgent;
  @override
  set userAgent(String? value) => _inner.userAgent = value;

  @override
  set authenticate(
    Future<bool> Function(Uri url, String scheme, String? realm)? f,
  ) => _inner.authenticate = f;
  @override
  void addCredentials(
    Uri url,
    String realm,
    HttpClientCredentials credentials,
  ) => _inner.addCredentials(url, realm, credentials);
  @override
  set connectionFactory(
    Future<ConnectionTask<Socket>> Function(
      Uri url,
      String? proxyHost,
      int? proxyPort,
    )?
    f,
  ) => _inner.connectionFactory = f;
  @override
  set findProxy(String Function(Uri url)? f) => _inner.findProxy = f;
  @override
  set authenticateProxy(
    Future<bool> Function(String host, int port, String scheme, String? realm)?
    f,
  ) => _inner.authenticateProxy = f;
  @override
  void addProxyCredentials(
    String host,
    int port,
    String realm,
    HttpClientCredentials credentials,
  ) => _inner.addProxyCredentials(host, port, realm, credentials);
  @override
  set badCertificateCallback(
    bool Function(X509Certificate cert, String host, int port)? callback,
  ) => _inner.badCertificateCallback = callback;
  @override
  set keyLog(Function(String line)? callback) => _inner.keyLog = callback;
  @override
  void close({bool force = false}) => _inner.close(force: force);
}
