import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';

/// Gets the device's local IP on the current network (e.g. when connected to client's hotspot).
/// Prioritizes NetworkInterface.list so it works without internet (e.g. hotspot with no data).
Future<String?> getLocalIpAddress() async {
  // 1) NetworkInterface.list FIRST – works without internet; getWifiIP() often fails on hotspot-with-no-internet
  try {
    final fromInterfaces = _getLocalIpFromInterfaces();
    if (fromInterfaces != null) return fromInterfaces;
  } catch (e, st) {
    debugPrint('getLocalIpAddress NetworkInterface (first): $e $st');
  }

  // 2) network_info_plus WiFi IP (can be null when no internet or on desktop hotspot)
  try {
    final info = NetworkInfo();
    String? ip = await info.getWifiIP();
    if (ip != null && ip.isNotEmpty && !_isLoopback(ip) && _isPrivateOrLinkLocal(ip)) {
      return ip;
    }
  } catch (e, st) {
    debugPrint('getLocalIpAddress getWifiIP: $e $st');
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

/// Uses NetworkInterface.list only (no internet required). Prefers WiFi-like interfaces and 192.168.x.x.
Future<String?> _getLocalIpFromInterfaces() async {
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
  if (wifiCandidates.isNotEmpty) return wifiCandidates.first;
  final preferred = candidates.where((s) => s.startsWith('192.168.')).toList();
  if (preferred.isNotEmpty) return preferred.first;
  if (candidates.isNotEmpty) return candidates.first;
  return null;
}

/// Gateway IP for ping (client hotspot). Tries network_info_plus first; if null (e.g. no internet), derives from [localIp].
Future<String?> getGatewayIpAddress(String? localIp) async {
  try {
    final info = NetworkInfo();
    String? gw = await info.getWifiGatewayIP();
    if (gw != null && gw.isNotEmpty && !_isLoopback(gw)) return gw;
  } catch (_) {}
  if (localIp == null || localIp.isEmpty) return null;
  return _gatewayFromLocalIp(localIp);
}

String? _gatewayFromLocalIp(String ip) {
  final parts = ip.split('.');
  if (parts.length != 4) return null;
  if (ip.startsWith('192.168.')) return '${parts[0]}.${parts[1]}.${parts[2]}.1';
  if (ip.startsWith('10.')) return '${parts[0]}.${parts[1]}.${parts[2]}.1';
  if (ip.startsWith('172.')) return '${parts[0]}.${parts[1]}.${parts[2]}.1';
  if (ip.startsWith('169.254.')) return null;
  return '${parts[0]}.${parts[1]}.${parts[2]}.1';
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
