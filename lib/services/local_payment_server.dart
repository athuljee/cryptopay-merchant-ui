import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'local_storage.dart';

/// Runs a local HTTP server so the client can POST offline payments.
/// Use on mobile/desktop only (dart:io); not supported on web.
class LocalPaymentServer {
  static HttpServer? _server;
  static const int defaultPort = 8765;

  /// Called when an offline payment is received (for UI to show PaymentReceivedScreen).
  static void Function(Map<String, dynamic> tx)? onPaymentReceived;

  static int? get port => _server?.port;
  static bool get isRunning => _server != null;

  static Future<String?> start({int port = defaultPort}) async {
    if (_server != null) return null;
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      _server!.listen(_handleRequest);
      return null;
    } on SocketException catch (e) {
      debugPrint("LocalPaymentServer: bind failed $e");
      return e.message;
    }
  }

  static void stop() {
    _server?.close();
    _server = null;
  }

  static void _handleRequest(HttpRequest request) {
    if (request.method == "GET" && (request.uri.path == "/ping" || request.uri.path == "/ping/")) {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({"ok": true, "service": "merchant-local-payment"}))
        ..close();
    } else if (request.method == "POST" && request.uri.path == "/receive-payment") {
      _handleReceivePayment(request);
    } else {
      request.response
        ..statusCode = HttpStatus.notFound
        ..write("Not found")
        ..close();
    }
  }

  static void _handleReceivePayment(HttpRequest request) async {
    try {
      final chunks = <int>[];
      await for (final chunk in request) {
        chunks.addAll(chunk);
      }
      final raw = utf8.decode(chunks);
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final txId = data[OfflineTxKeys.txId] as String?;
      final from = data[OfflineTxKeys.from] as String?;
      final to = data[OfflineTxKeys.to] as String?;
      final amount = data[OfflineTxKeys.amount];
      final token = data[OfflineTxKeys.token] as String?;
      final timestamp = data[OfflineTxKeys.timestamp] as String?;
      if (txId == null || from == null || to == null || amount == null || token == null) {
        request.response
          ..statusCode = HttpStatus.badRequest
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({"ok": false, "error": "Missing fields"}))
          ..close();
        return;
      }
      final tx = {
        OfflineTxKeys.txId: txId,
        OfflineTxKeys.from: from,
        OfflineTxKeys.to: to,
        OfflineTxKeys.amount: amount is num ? amount.toDouble() : double.tryParse(amount.toString()) ?? 0.0,
        OfflineTxKeys.token: token,
        OfflineTxKeys.timestamp: timestamp ?? DateTime.now().toIso8601String(),
        OfflineTxKeys.status: "pending",
      };
      await LocalStorage.addPendingOfflineTx(tx);
      onPaymentReceived?.call(tx);
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({"ok": true, "txId": txId}))
        ..close();
    } catch (e, st) {
      debugPrint("LocalPaymentServer error: $e $st");
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({"ok": false, "error": e.toString()}))
        ..close();
    }
  }
}
