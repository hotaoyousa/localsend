import 'package:localsend_app/util/qr_connection_info.dart';
import 'package:test/test.dart';

void main() {
  group('parseQrConnectionInfo', () {
    test('reads released LocalSend web-share links with and without a PIN', () {
      expect(parseQrConnectionInfo('http://192.168.1.20:53317')?.ip, '192.168.1.20');
      expect(parseQrConnectionInfo('https://10.0.0.2:53317/?pin=12%2034')?.ip, '10.0.0.2');
      expect(parseQrConnectionInfo('https://172.16.0.3:8080/')?.ip, '172.16.0.3');
    });

    test('extracts only the host, ignoring paths and query parameters', () {
      expect(parseQrConnectionInfo('http://192.168.1.20:53317/?pin=10.0.0.1#192.168.0.1')?.ip, '192.168.1.20');
      expect(parseQrConnectionInfo('  https://192.168.1.20:53317  ')?.ip, '192.168.1.20');
    });

    test('preserves the peer protocol and port instead of local settings', () {
      final peer = parseQrConnectionInfo('http://192.168.1.20:54321/?pin=1234')!;
      expect(peer.port, 54321);
      expect(peer.https, isFalse);
      expect(peer.uri.toString(), 'http://192.168.1.20:54321');
      expect(parseQrConnectionInfo('https://10.0.0.2')!.port, 443);
      expect(parseQrConnectionInfo('http://10.0.0.2')!.port, 80);
    });

    test('supports bracketed IPv6 literals', () {
      expect(parseQrConnectionInfo('https://[2001:db8::1]:53317/?pin=1234')?.ip, '2001:db8::1');
      expect(parseQrConnectionInfo('http://[::1]:8080')?.ip, '::1');
    });

    test('rejects text, unsupported schemes, hostnames and malformed addresses', () {
      for (final value in [
        '',
        'not a link',
        '192.168.1.20',
        'ftp://192.168.1.20:53317',
        'localsend://192.168.1.20:53317',
        'https://example.com/?ip=192.168.1.20',
        'http://256.1.2.3:53317',
        'http://192.168.1.20:bad',
        'http://192.168.1.20:65536',
        'http://192.168.1.20:0',
        'http://[invalid]:53317',
        'http://user@192.168.1.20:53317',
        'http://192.168.1.20 :53317',
      ]) {
        expect(parseQrConnectionInfo(value), isNull, reason: value);
      }
    });
  });
}
