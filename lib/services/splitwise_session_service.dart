import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class SplitwiseSessionService {
  SplitwiseSessionService._();

  static final instance = SplitwiseSessionService._();
  static const _cookieKey = 'splitwise_cookie';
  static const _csrfKey = 'splitwise_csrf_token';
  static const _baseUrl = 'https://secure.splitwise.com';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<bool> hasSession() async {
    final values = await _storage.readAll();
    return (values[_cookieKey] ?? '').isNotEmpty &&
        (values[_csrfKey] ?? '').isNotEmpty;
  }

  Future<void> ensureAuthenticated(BuildContext context, {bool force = false}) async {
    if (!force && await hasSession()) return;
    if (force) await clear();
    if (!context.mounted) {
      throw StateError('Splitwise sign-in cannot be opened after the screen closes.');
    }

    final authenticated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const _SplitwiseLoginPage()),
    );
    if (authenticated != true || !await hasSession()) {
      throw StateError('Splitwise sign-in was not completed.');
    }
  }

  Future<void> clear() => _storage.deleteAll();

  Future<http.Response> post(
    Uri url, {
    Object? body,
    Map<String, String>? headers,
    required Future<void> Function() reauthenticate,
  }) {
    return _send(
      (sessionHeaders) => http.post(
        url,
        headers: {...sessionHeaders, ...?headers},
        body: body,
      ),
      reauthenticate: reauthenticate,
    );
  }

  Future<http.Response> get(
    Uri url, {
    Map<String, String>? headers,
    required Future<void> Function() reauthenticate,
  }) {
    return _send(
      (sessionHeaders) => http.get(url, headers: {...sessionHeaders, ...?headers}),
      reauthenticate: reauthenticate,
    );
  }

  Future<http.Response> _send(
    Future<http.Response> Function(Map<String, String>) send, {
    required Future<void> Function() reauthenticate,
  }) async {
    var response = await send(await _headers());
    if (response.statusCode != 403) return response;

    await clear();
    await reauthenticate();
    response = await send(await _headers());
    if (response.statusCode == 403) await clear();
    return response;
  }

  Future<Map<String, String>> _headers() async {
    final cookie = await _storage.read(key: _cookieKey);
    final csrf = await _storage.read(key: _csrfKey);
    if (cookie == null || cookie.isEmpty || csrf == null || csrf.isEmpty) {
      throw StateError('No Splitwise session is available.');
    }
    return {
      'Cookie': cookie,
      'X-CSRF-Token': csrf,
      'Origin': _baseUrl,
      'Referer': '$_baseUrl/',
    };
  }
}

class _SplitwiseLoginPage extends StatefulWidget {
  const _SplitwiseLoginPage();

  @override
  State<_SplitwiseLoginPage> createState() => _SplitwiseLoginPageState();
}

class _SplitwiseLoginPageState extends State<_SplitwiseLoginPage> {
  bool _saving = false;

  Future<void> _captureSession(
    InAppWebViewController controller,
    WebUri? url,
  ) async {
    if (_saving) return;
    if (url == null || url.path == '/login') return;
    final cookies = await CookieManager.instance().getCookies(
      url: WebUri('https://secure.splitwise.com/'),
    );
    final cookieHeader = cookies.map((cookie) => '${cookie.name}=${cookie.value}').join('; ');
    if (cookieHeader.isEmpty) return;

    final javascriptResult = await controller.evaluateJavascript(source: '''
      document.querySelector('meta[name="csrf-token"]')?.content ||
      document.querySelector('meta[name="csrf_token"]')?.content || ''
    ''');
    final csrf = javascriptResult?.toString().replaceAll('"', '').trim() ?? '';
    if (csrf.isEmpty) return;

    _saving = true;
    await SplitwiseSessionService.instance._storage.write(
      key: SplitwiseSessionService._cookieKey,
      value: cookieHeader,
    );
    await SplitwiseSessionService.instance._storage.write(
      key: SplitwiseSessionService._csrfKey,
      value: csrf,
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in to Splitwise')),
      body: InAppWebView(
        initialUrlRequest: URLRequest(url: WebUri('https://secure.splitwise.com/login')),
        initialSettings: InAppWebViewSettings(javaScriptEnabled: true),
        onLoadStop: _captureSession,
      ),
    );
  }
}