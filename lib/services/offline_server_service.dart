import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/server_config.dart';

class MerchantOfflineServerService {
  static String get _base => ServerConfig.localOfflineBaseUrl;

  static Future<bool> health() async {
    try {
      final res = await http
          .get(Uri.parse("$_base/health"))
          .timeout(const Duration(seconds: 4));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, dynamic>?> getOfflineWallet(String userId) async {
    try {
      final res = await http
          .get(Uri.parse("$_base/offline-wallet/$userId"))
          .timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return data["wallet"] as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>> getOfflineTransactions({
    String? merchantId,
  }) async {
    try {
      final uri = merchantId == null
          ? Uri.parse("$_base/offline-transactions")
          : Uri.parse("$_base/offline-transactions?merchantId=$merchantId");
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return const [];
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final list = (data["transactions"] as List?) ?? const [];
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<Map<String, dynamic>?> syncNow() async {
    try {
      final res = await http
          .post(Uri.parse("$_base/sync-offline-transactions"))
          .timeout(const Duration(seconds: 15));
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return data;
    } catch (_) {
      return null;
    }
  }
}
