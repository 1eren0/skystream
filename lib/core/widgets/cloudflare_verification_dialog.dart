import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'package:skystream/l10n/generated/app_localizations.dart';

import '../logger/app_logger.dart';
import '../network/cloudflare_bypass.dart';

/// A real, visible browser: the user can complete an interactive challenge.
/// Cookies stay in the same WebView2 environment the HTTP engine reads.
Future<CfResult?> showCloudflareVerification({
  required BuildContext context,
  required String url,
  required WebViewEnvironment? environment,
  String? referer,
}) => showDialog<CfResult>(
  context: context,
  useRootNavigator: true,
  barrierDismissible: false,
  builder: (_) => CloudflareVerificationDialog(
    url: url,
    environment: environment,
    referer: referer,
  ),
);

class CloudflareVerificationDialog extends StatefulWidget {
  final String url;
  final WebViewEnvironment? environment;
  final String? referer;

  bool get seedReferrer {
    final source = Uri.tryParse(referer ?? '');
    final target = Uri.parse(url);
    return source != null &&
        source.scheme == target.scheme &&
        source.host == target.host &&
        referer != url;
  }

  const CloudflareVerificationDialog({
    super.key,
    required this.url,
    required this.environment,
    this.referer,
  });

  @override
  State<CloudflareVerificationDialog> createState() =>
      _CloudflareVerificationDialogState();
}

enum _VerificationProblem { unreadable, notOpened }

/// How long a challenge-free page may keep showing content while 'loading'
/// before it is treated as ready.
const _loadingGrace = Duration(seconds: 3);

class _CloudflareVerificationDialogState
    extends State<CloudflareVerificationDialog> {
  InAppWebViewController? _controller;
  Timer? _poll;
  Timer? _deadline;
  bool _checking = false;
  bool _finished = false;
  bool _mainHttpFailure = false;
  int _mainHttpStatus = 200;
  late bool _targetNavigated;
  String? _lastPageState;
  // When a page without a challenge first showed content while still
  // loading. Ads and images can keep a page loading for a long time.
  DateTime? _contentWhileLoadingSince;
  _VerificationProblem? _problem;

  @override
  void initState() {
    super.initState();
    _targetNavigated = !widget.seedReferrer;
    // Below the plugin's 75-second and engine's 90-second invocation limits.
    _deadline = Timer(const Duration(seconds: 45), () {
      talker.warning(
        '[CF UI] Verification expired for ${Uri.parse(widget.url).host}',
      );
      _finish(null);
    });
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _inspect());
  }

  void _finish(CfResult? result) {
    if (_finished || !mounted) return;
    _finished = true;
    _poll?.cancel();
    _deadline?.cancel();
    Navigator.of(context).pop(result);
  }

  Future<void> _inspect() async {
    final controller = _controller;
    if (_checking || _finished || controller == null || !mounted) return;
    _checking = true;
    try {
      final location = await controller.getUrl();
      final expected = Uri.parse(widget.url);
      if (location == null || location.scheme != expected.scheme) {
        return;
      }
      final inspected = await controller.evaluateJavascript(
        source: r'''
        (function() {
          var title = (document.title || '').toLowerCase();
          var challenge = !!document.getElementById('challenge-form') ||
            !!document.querySelector('.cf-mitigated-content') ||
            // Cloudflare's own challenge titles, English and Turkish.
            title.indexOf('just a moment') !== -1 ||
            title.indexOf('bir dakika lütfen') !== -1 ||
            title.indexOf('güvenlik doğrulaması') !== -1;
          return JSON.stringify({title: title, state: document.readyState,
            path: location.pathname, challenge: challenge,
            body: !!document.body && document.body.innerText.trim().length > 0});
        })()
      ''',
      );
      if (inspected is! String || !mounted || _finished) return;
      final page = jsonDecode(inspected) as Map<String, dynamic>;
      final state =
          '$inspected host=${location.host} httpFailure=$_mainHttpFailure';
      if (state != _lastPageState) {
        _lastPageState = state;
        talker.debug('[CF UI] Page state ${redactSecrets(state)}');
      }
      if (page['challenge'] == true || page['body'] != true) {
        _contentWhileLoadingSince = null;
        return;
      }
      // Content is usable at DOMContentLoaded ('interactive'). A page that
      // shows content but never leaves 'loading' (slow ads or images) is
      // accepted after a short grace period instead of waiting for them.
      if (page['state'] == 'loading') {
        final since = _contentWhileLoadingSince ??= DateTime.now();
        if (DateTime.now().difference(since) < _loadingGrace) return;
      }
      if (!_targetNavigated) {
        if (location.host != expected.host) return;
        // Navigate from the real referring document so the browser preserves
        // its own Referer and same-site fetch context, including redirects.
        _targetNavigated = true;
        _mainHttpFailure = false;
        await controller.evaluateJavascript(
          source: 'location.assign(${jsonEncode(widget.url)});',
        );
        return;
      }
      // A readable 403 or redirect to another site must not be treated as
      // solved just because its page has text and no recognized challenge.
      if (location.host != expected.host || _mainHttpFailure) return;
      final html = await controller.evaluateJavascript(
        source: 'document.documentElement.outerHTML',
      );
      if (html is! String || html.isEmpty || _finished || !mounted) return;
      // Read the clearance from this live page before it closes. Reading it
      // afterwards through the environment's cookie manager came back with no
      // Cloudflare cookies, so every later request opened this dialog again.
      final cookies = await _pageCookies(controller, expected);
      final agent = await controller.evaluateJavascript(
        source: 'navigator.userAgent',
      );
      if (_finished || !mounted) return;
      if (!isVerifiedCloudflarePage(
            host: location.host,
            expectedHost: expected.host,
            httpStatus: _mainHttpStatus,
            challenge: page['challenge'] == true,
            hasBody: page['body'] == true,
            cookies: cookies,
          ) ||
          agent is! String ||
          agent.isEmpty) {
        // Stay on the page so the viewer can finish the challenge, rather
        // than caching a block page or a session with no reusable identity.
        return;
      }
      talker.info(
        '[CF UI] Verified cookies: '
        '${cookies.map((cookie) => cookie['name']).join(',')} '
        'userAgent=${agent.isNotEmpty}',
      );
      _finish(
        CfResult(
          body: html,
          statusCode: 200,
          finalUrl: location.toString(),
          cookies: cookies,
          userAgent: agent,
        ),
      );
    } catch (error, stack) {
      talker.error('[CF UI] Could not inspect verification page', error, stack);
      if (mounted && !_finished) {
        setState(() => _problem = _VerificationProblem.unreadable);
      }
    } finally {
      _checking = false;
    }
  }

  /// Cloudflare cookies of [target]'s site, HttpOnly ones included, read
  /// through DevTools on this page. Empty (and logged) when that fails.
  Future<List<Map<String, dynamic>>> _pageCookies(
    InAppWebViewController controller,
    Uri target,
  ) async {
    try {
      final reply = await controller.callDevToolsProtocolMethod(
        methodName: 'Network.getCookies',
        parameters: {
          'urls': ['${target.scheme}://${target.host}/', target.toString()],
        },
      );
      final list = reply is Map ? reply['cookies'] : null;
      if (list is! List) return const [];
      return [
        for (final cookie in list)
          if (cookie is Map && isCloudflareCookieName('${cookie['name']}'))
            Map<String, dynamic>.from(cookie),
      ];
    } catch (error, stack) {
      talker.error('[CF UI] Could not read verified cookies', error, stack);
      return const [];
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _deadline?.cancel();
    super.dispose();
  }

  String _messageFor(AppLocalizations l10n) => switch (_problem) {
    null => l10n.cloudflareVerificationPrompt,
    _VerificationProblem.unreadable => l10n.cloudflareVerificationUnreadable,
    _VerificationProblem.notOpened => l10n.cloudflareVerificationNotOpened,
  };

  @override
  Widget build(BuildContext context) => Dialog(
    child: SizedBox(
      width: 1000,
      height: 680,
      child: Column(
        children: [
          ListTile(
            title: Text(AppLocalizations.of(context)!.cloudflareVerificationTitle),
            subtitle: Text(
              '${Uri.parse(widget.url).host}\n'
              '${_messageFor(AppLocalizations.of(context)!)}',
            ),
            trailing: TextButton(
              onPressed: () => _finish(null),
              child: Text(AppLocalizations.of(context)!.cancel),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: InAppWebView(
              webViewEnvironment: widget.environment,
              initialUrlRequest: URLRequest(
                url: WebUri(widget.seedReferrer ? widget.referer! : widget.url),
                headers:
                    widget.seedReferrer ||
                        widget.referer == null ||
                        widget.referer == widget.url
                    ? null
                    : {'Referer': widget.referer!},
              ),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                domStorageEnabled: true,
              ),
              onWebViewCreated: (controller) => _controller = controller,
              onLoadStart: (_, _) {
                _mainHttpFailure = false;
                _mainHttpStatus = 200;
              },
              onLoadStop: (_, _) => _inspect(),
              onTitleChanged: (_, _) => _inspect(),
              onReceivedHttpError: (_, request, response) {
                if (request.isForMainFrame == true &&
                    (response.statusCode ?? 0) >= 400) {
                  _mainHttpFailure = true;
                  _mainHttpStatus = response.statusCode!;
                }
              },
              onReceivedError: (_, request, error) {
                if (request.isForMainFrame != true) return;
                talker.error(
                  '[CF UI] Main page failed: ${error.type} ${error.description}',
                );
                if (mounted && !_finished) {
                  setState(() => _problem = _VerificationProblem.notOpened);
                }
              },
            ),
          ),
        ],
      ),
    ),
  );
}
