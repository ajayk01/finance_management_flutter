import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:finance_app/services/direct_sql_service.dart';
import 'package:flutter/material.dart';

class LocalServerScreen extends StatefulWidget {
  const LocalServerScreen({super.key});

  @override
  State<LocalServerScreen> createState() => _LocalServerScreenState();
}

class _LocalServerScreenState extends State<LocalServerScreen> {
  HttpServer? _server;
  bool _starting = false;
  String? _address;
  String? _deviceIp;  String? _publicIp;
  int? _port;

  bool get _isRunning => _server != null;

  Future<void> _startServer() async {
    if (_isRunning || _starting) return;

    setState(() => _starting = true);

    try {
      final server = await HttpServer.bind(InternetAddress.anyIPv4, 8080);
      _server = server;
      _address = 'localhost';
      final ipResults = await Future.wait<String?>([
        _getDeviceIp(),
        _getPublicIp(),
      ]);
      _deviceIp = ipResults[0];
      _publicIp = ipResults[1];
      _port = server.port;

      unawaited(_serveRequests(server));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _deviceIp == null
                ? 'Server started on http://${_address ?? 'localhost'}:${server.port}'
                : 'Server started on http://${_deviceIp!}:${server.port}',
          ),
        ),
      );
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start server: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _starting = false);
      }
    }
  }

  Future<void> _stopServer() async {
    final server = _server;
    if (server == null) return;

    await server.close(force: true);

    if (!mounted) return;
    setState(() {
      _server = null;
      _address = null;
      _deviceIp = null;
      _publicIp = null;
      _port = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Server stopped')),
    );
  }

  Future<void> _serveRequests(HttpServer server) async {
    await for (final request in server) {
      final path = request.uri.path;

      if (path == '/health') {
        _writeJson(request.response, {
          'ok': true,
          'message': 'Server is running',
          'timestamp': DateTime.now().toIso8601String(),
        });
        continue;
      }

      if (request.method != 'GET') {
        _writeJson(
          request.response,
          {
            'ok': false,
            'error': 'Only GET is supported for this endpoint',
          },
          statusCode: HttpStatus.methodNotAllowed,
        );
        continue;
      }

      await _serveActiveAccounts(request.response);
    }
  }

  Future<void> _serveActiveAccounts(HttpResponse response) async {
    try {
      final accounts = await DirectSqlService.getAllActiveAccounts();
      _writeJson(
        response,
        {
          'ok': true,
          'bankAccounts': accounts.bankAccounts.map(_bankAccountToJson).toList(),
          'creditCardAccounts': accounts.creditCardAccounts.map(_creditCardAccountToJson).toList(),
          'investmentAccounts': accounts.investmentAccounts.map(_investmentAccountToJson).toList(),
        },
      );
    } catch (e) {
      _writeJson(
        response,
        {
          'ok': false,
          'error': e.toString(),
        },
        statusCode: HttpStatus.internalServerError,
      );
    }
  }

  Map<String, dynamic> _bankAccountToJson(dynamic account) {
    return {
      'id': account.id,
      'name': account.name,
      'balance': account.balance,
      'initialBalance': account.initialBalance,
      'isActive': account.isActive,
      'logo': account.logo,
    };
  }

  Map<String, dynamic> _creditCardAccountToJson(dynamic account) {
    return {
      'id': account.id,
      'name': account.name,
      'usedAmount': account.usedAmount,
      'totalLimit': account.totalLimit,
      'availableCredit': account.availableCredit,
      'rewardPoints': account.rewardPoints,
      'isActive': account.isActive,
      'logo': account.logo,
    };
  }

  Map<String, dynamic> _investmentAccountToJson(dynamic account) {
    return {
      'id': account.id,
      'name': account.name,
      'totalInvested': account.totalInvested,
      'totalWithdraw': account.totalWithdraw,
      'currentValue': account.currentValue,
      'xirr': account.xirr,
      'isActive': account.isActive,
    };
  }

  void _writeJson(
    HttpResponse response,
    Map<String, dynamic> data, {
    int statusCode = HttpStatus.ok,
  }) {
    response.statusCode = statusCode;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(data));
    unawaited(response.close());
  }

  Future<String?> _getDeviceIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );

      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          final ip = address.address;
          if (!ip.startsWith('127.')) {
            return ip;
          }
        }
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  Future<String?> _getPublicIp() async {
    HttpClient? client;
    try {
      client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);
      final request = await client.getUrl(Uri.parse('https://api.ipify.org?format=json'));
      final response = await request.close().timeout(const Duration(seconds: 5));

      if (response.statusCode != HttpStatus.ok) {
        return null;
      }

      final body = await utf8.decoder.bind(response).join();
      final data = jsonDecode(body);
      if (data is Map<String, dynamic>) {
        final ip = data['ip']?.toString();
        if (ip != null && ip.isNotEmpty) {
          return ip;
        }
      }
    } catch (_) {
      return null;
    } finally {
      client?.close(force: true);
    }

    return null;
  }

  @override
  void dispose() {
    final server = _server;
    _server = null;
    if (server != null) {
      unawaited(server.close(force: true));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localhostUrl = 'http://${_address ?? 'localhost'}:${_port ?? 8080}';
    final deviceUrl = _deviceIp == null ? null : 'http://${_deviceIp!}:${_port ?? 8080}';
    final publicUrl = _publicIp == null ? null : 'http://${_publicIp!}:${_port ?? 8080}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Local Server'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isRunning ? 'Server is running' : 'Server is stopped',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            if (_isRunning) ...[
              const SizedBox(height: 8),
              Text('Local: $localhostUrl', style: const TextStyle(fontSize: 14)),
              if (deviceUrl != null)
                Text('Network: $deviceUrl', style: const TextStyle(fontSize: 14)),
              if (publicUrl != null)
                Text('Public: $publicUrl', style: const TextStyle(fontSize: 14)),
              if (publicUrl == null)
                const Text(
                  'Public IP not available (internet lookup failed).',
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                ),
            ],
            const SizedBox(height: 12),
            const Text(
              'Endpoints:\nGET /health\nGET / (returns getAllActiveAccounts JSON)',
              style: TextStyle(fontSize: 14, color: Colors.black87),
            ),
            const SizedBox(height: 8),
            const Text(
              'Note: Public URL works only if router/firewall allows inbound port forwarding to this device.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _starting
                    ? null
                    : _isRunning
                        ? _stopServer
                        : _startServer,
                child: Text(_isRunning ? 'Stop Server' : 'Start Server'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
