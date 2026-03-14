import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';

/// Gets the device's local IP on the current network (e.g. when connected to client's hotspot).
/// Tries multiple methods so it works on Windows/macOS when laptop is on phone hotspot.
Future<String?> getLocalIpAddress() async {
  // 1) network_info_plus WiFi IP (often null on desktop when on hotspot)
  try {
    final info = NetworkInfo();
    String? ip = await info.getWifiIP();
    if (ip != null && ip.isNotEmpty && !_isLoopback(ip) && _isPrivateOrLinkLocal(ip)) {
      return ip;
    }
  } catch (e, st) {
    debugPrint('getLocalIpAddress getWifiIP: $e $st');
  }

  // 2) NetworkInterface.list – all IPv4, include link-local; prefer WiFi-like interface names
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLinkLocal: true,
    );
    final candidates = <String>[];
    final wifiCandidates = <String>[];
    final nameLower = (String n) => n.toLowerCase();
    for (final iface in interfaces) {
      final name = nameLower(iface.name);
      final isWifiLike = name.contains('wi') || name.contains('wlan') || name.contains('wireless') || name.contains('wifi');
      for (final addr in iface.addresses) {
        final s = addr.address;
        if (_isLoopback(s)) continue;
        if (!_isPrivateOrLinkLocal(s)) continue;
        if (isWifiLike) {
          wifiCandidates.add(s);
        } else {
          candidates.add(s);
        }
      }
    }
    // Prefer IP from WiFi-like interface, then 192.168.x.x (phone hotspots), then any
    if (wifiCandidates.isNotEmpty) return wifiCandidates.first;
    final preferred = candidates.where((s) => s.startsWith('192.168.')).toList();
    if (preferred.isNotEmpty) return preferred.first;
    if (candidates.isNotEmpty) return candidates.first;
  } catch (e, st) {
    debugPrint('getLocalIpAddress NetworkInterface: $e $st');
  }

  // 3) Any non-loopback IPv4 from interfaces (no private filter)
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLinkLocal: true,
    );
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        final s = addr.address;
        if (_isLoopback(s)) continue;
        return s;
      }
    }
  } catch (e, st) {
    debugPrint('getLocalIpAddress fallback: $e $st');
  }

  // 4) List without type filter (some platforms report interfaces differently)
  try {
    final interfaces = await NetworkInterface.list(includeLinkLocal: true);
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        final s = addr.address;
        if (s.contains(':')) continue; // skip IPv6
        if (_isLoopback(s)) continue;
        if (_isPrivateOrLinkLocal(s)) return s;
      }
    }
  } catch (e, st) {
    debugPrint('getLocalIpAddress list all: $e $st');
  }

  return null;
}

bool _isLoopback(String ip) {
  return ip == '127.0.0.1' || ip == '::1' || ip.startsWith('127.');
}

bool _isPrivateOrLinkLocal(String ip) {
  return ip.startsWith('192.168.') ||
      ip.startsWith('10.') ||
      ip.startsWith('172.') ||
      ip.startsWith('169.254.');
}
