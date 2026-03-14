import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';

/// Gets the device's local IP on the current network (e.g. when connected to client's hotspot).
/// Tries [NetworkInfo.getWifiIP] first, then falls back to non-loopback IPv4 from [NetworkInterface].
Future<String?> getLocalIpAddress() async {
  try {
    final info = NetworkInfo();
    String? ip = await info.getWifiIP();
    if (ip != null && ip.isNotEmpty && !_isLoopback(ip)) {
      return ip;
    }
    // Fallback: get from network interfaces (works when getWifiIP is null on desktop/hotspot)
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLinkLocal: false,
    );
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        final s = addr.address;
        if (_isLoopback(s)) continue;
        if (s.startsWith('192.168.') || s.startsWith('10.') || s.startsWith('172.')) {
          return s;
        }
      }
    }
    // Any non-loopback IPv4
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        final s = addr.address;
        if (!_isLoopback(s)) return s;
      }
    }
  } catch (e, st) {
    debugPrint('getLocalIpAddress: $e $st');
  }
  return null;
}

bool _isLoopback(String ip) {
  return ip == '127.0.0.1' || ip == '::1' || ip.startsWith('127.');
}
