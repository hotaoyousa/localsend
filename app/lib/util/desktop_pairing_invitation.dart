import 'dart:convert';
import 'dart:io';

import 'package:localsend_isolates/model/device.dart';

/// A metadata-only invitation carried by the existing prepare-upload protocol.
/// No user files or transfer session are relayed through the phone.
enum PairingRole { send, receive }

class DesktopPairingInvitation {
  static const mimeType = 'application/vnd.localsend.peer-introduction+json';
  final String ip;
  final int port;
  final bool https;
  final String fingerprint;
  final String alias;
  final PairingRole? role;

  const DesktopPairingInvitation({
    required this.ip,
    required this.port,
    required this.https,
    required this.fingerprint,
    required this.alias,
    this.role,
  });

  factory DesktopPairingInvitation.fromDevice(Device device, {PairingRole? role}) => DesktopPairingInvitation(
    ip: device.ip!,
    port: device.port,
    https: device.https,
    fingerprint: device.fingerprint,
    alias: device.alias,
    role: role,
  );

  String encode() => jsonEncode({
    'version': 1,
    'ip': ip,
    'port': port,
    'https': https,
    'fingerprint': fingerprint,
    'alias': alias,
    if (role != null) 'role': role!.name,
  });

  static DesktopPairingInvitation? decode(String? text) {
    if (text == null || text.length > 4096) return null;
    try {
      final json = jsonDecode(text);
      if (json is! Map<String, dynamic> || json['version'] != 1) return null;
      final ip = json['ip'];
      final port = json['port'];
      final https = json['https'];
      final fingerprint = json['fingerprint'];
      final alias = json['alias'];
      final roleName = json['role'];
      if (roleName != null && roleName != 'send' && roleName != 'receive') return null;
      final role = roleName == null ? null : PairingRole.values.byName(roleName as String);
      if (ip is! String ||
          port is! int ||
          port < 1 ||
          port > 65535 ||
          https is! bool ||
          fingerprint is! String ||
          !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(fingerprint) ||
          alias is! String ||
          alias.isEmpty ||
          alias.length > 256) {
        return null;
      }
      final address = InternetAddress.tryParse(ip);
      // A scope ID belongs to the scanning phone, so it is not portable to a PC.
      if (address == null ||
          address.isLoopback ||
          address.isMulticast ||
          address.isLinkLocal ||
          address.rawAddress.every((b) => b == 0) ||
          ip.contains('%') ||
          ip == '255.255.255.255') {
        return null;
      }
      return DesktopPairingInvitation(
        ip: address.address,
        port: port,
        https: https,
        fingerprint: fingerprint.toUpperCase(),
        alias: alias,
        role: role,
      );
    } catch (_) {
      return null;
    }
  }
}
