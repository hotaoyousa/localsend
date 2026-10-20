import 'dart:io';

/// The endpoint encoded by LocalSend's existing web-share QR codes.
class QrConnectionInfo {
  final String ip;
  final int port;
  final bool https;
  final String? pin;

  const QrConnectionInfo({required this.ip, required this.port, required this.https, this.pin});

  Uri get uri => Uri(scheme: https ? 'https' : 'http', host: ip, port: port);
}

/// Reads the endpoint without contacting it or resolving hostnames.
/// Released versions generate http(s)://IP:port, optionally with /?pin=... .
QrConnectionInfo? parseQrConnectionInfo(String value) {
  final text = value.trim();
  if (text.isEmpty || RegExp(r'\s').hasMatch(text)) {
    return null;
  }

  final uri = Uri.tryParse(text);
  if (uri == null || !uri.hasAuthority || (uri.scheme != 'http' && uri.scheme != 'https') || uri.userInfo.isNotEmpty) {
    return null;
  }

  if (uri.port < 1 || uri.port > 65535) {
    return null;
  }

  var host = uri.host;
  if (host.startsWith('[') && host.endsWith(']')) {
    host = host.substring(1, host.length - 1);
  }
  final ip = InternetAddress.tryParse(host)?.address;
  return ip == null ? null : QrConnectionInfo(ip: ip, port: uri.port, https: uri.scheme == 'https', pin: uri.queryParameters['pin']);
}
