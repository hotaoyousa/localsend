import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/provider/desktop_pairing_provider.dart';
import 'package:localsend_app/util/desktop_pairing_invitation.dart';
import 'package:localsend_app/util/qr_connection_info.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/rust/api/cancel.dart';
import 'package:localsend_isolates/rust/api/http.dart';
import 'package:localsend_isolates/rust/api/model.dart' as rust;
import 'package:mockito/mockito.dart';

class _Token extends Mock implements RsCancellationToken {}

class _Client extends Mock implements RsHttpClient {
  rust.PrepareUploadRequestDto? invitation;
  rust.RegisterDto? registration;
  String? address;
  String? pin;
  int status = 204;
  int cancels = 0;
  String fingerprint = 'B' * 64;
  @override
  Future<PrepareUploadResult> prepareUpload({
    required rust.ProtocolType protocol,
    required String ip,
    required int port,
    required rust.PrepareUploadRequestDto payload,
    String? publicKey,
    String? pin,
    required RsCancellationToken cancelToken,
  }) async {
    invitation = payload;
    address = '$ip:$port';
    this.pin = pin;
    return PrepareUploadResult(
      statusCode: status,
      response: status == 200 ? const rust.PrepareUploadResponseDto(sessionId: 'old-client', files: {'peer': 'token'}) : null,
    );
  }

  @override
  Future<void> cancel({required rust.ProtocolType protocol, required String ip, required int port, required String sessionId}) async {
    cancels++;
  }

  @override
  Future<ResultWithPublicKeyRegisterResponseDto> register({
    required rust.ProtocolType protocol,
    required String ip,
    required int port,
    required rust.RegisterDto payload,
  }) async {
    address = '$ip:$port';
    registration = payload;
    return ResultWithPublicKeyRegisterResponseDto(
      body: rust.RegisterResponseDto(
        alias: 'Computer B',
        version: '2.2',
        token: fingerprint,
        hasWebInterface: true,
        deviceType: rust.DeviceType.desktop,
      ),
    );
  }
}

Device _device(String letter, String ip) => Device(
  signalingId: null,
  ip: ip,
  version: '2.2',
  port: 54321,
  https: true,
  fingerprint: letter * 64,
  alias: 'Computer $letter',
  deviceModel: null,
  deviceType: DeviceType.desktop,
  download: true,
  channels: [HttpChannel(host: ip, port: 54321, https: true)],
);

void main() {
  final a = _device('A', '192.168.1.10');
  final b = _device('B', '192.168.1.20');
  late _Client client;
  late DesktopPairingService service;
  final pinned = <String>[];
  setUp(() {
    client = _Client();
    pinned.clear();
    service = DesktopPairingService(
      ownDevice: () => a,
      discovery: () => client,
      pinned: (fingerprint, timeout) {
        pinned.add(fingerprint);
        return client;
      },
      createToken: _Token.new,
    );
  });
  test('invitation round trip preserves endpoint, identity and Unicode alias', () {
    final value = DesktopPairingInvitation.fromDevice(b.copyWith(alias: '电脑 B'));
    final result = DesktopPairingInvitation.decode(value.encode())!;
    expect(result.alias, '电脑 B');
    expect(result.ip, b.ip);
    expect(result.port, 54321);
    expect(result.https, true);
    expect(result.fingerprint, b.fingerprint);
  });
  test('invalid, local-only and non-IP invitations are rejected', () {
    final valid = jsonDecode(DesktopPairingInvitation.fromDevice(b).encode()) as Map<String, dynamic>;
    for (final mutation in [
      {'version': 2},
      {'port': 0},
      {'port': 65536},
      {'port': '53317'},
      {'fingerprint': 'spoof'},
      {'https': 'true'},
      {'ip': 'localhost'},
      {'ip': '127.0.0.1'},
      {'ip': '::'},
      {'ip': '::1'},
      {'ip': '224.0.0.1'},
      {'ip': 'fe80::1%3'},
      {'alias': ''},
    ]) {
      expect(DesktopPairingInvitation.decode(jsonEncode({...valid, ...mutation})), isNull, reason: mutation.toString());
    }
    expect(DesktopPairingInvitation.decode('x' * 5000), isNull);
    expect(DesktopPairingInvitation.decode('invalid'), isNull);
  });
  test('phone introduces the other computer, authenticating as itself; no upload', () async {
    await service.introduce(recipient: b, peer: a, token: _Token(), pin: '1234');
    expect(pinned, [b.fingerprint]);
    expect(client.address, '192.168.1.20:54321');
    expect(client.pin, '1234');
    expect(client.invitation!.info.token, a.fingerprint);
    final file = client.invitation!.files.values.single;
    expect(file.fileType, DesktopPairingInvitation.mimeType);
    expect(DesktopPairingInvitation.decode(file.preview)!.fingerprint, a.fingerprint);
    expect(file.size.toInt(), utf8.encode(file.preview!).length);
  });
  test('same computer is refused before any request', () async {
    await expectLater(service.introduce(recipient: b, peer: b, token: _Token()), throwsStateError);
    expect(client.invitation, isNull);
  });
  test('old peer creating a normal upload session is cancelled, never treated as paired', () async {
    client.status = 200;
    await expectLater(service.introduce(recipient: b, peer: a, token: _Token()), throwsStateError);
    expect(client.cancels, 1);
  });
  test('rejection is not reported as success', () async {
    client.status = 403;
    await expectLater(service.introduce(recipient: b, peer: a, token: _Token()), throwsStateError);
  });
  test('computer directly registers with pinned peer using its own identity', () async {
    final connected = await service.connect(DesktopPairingInvitation.fromDevice(b));
    expect(connected.fingerprint, b.fingerprint);
    expect(pinned, [b.fingerprint]);
    expect(client.address, '192.168.1.20:54321');
    expect(client.registration!.token, a.fingerprint);
  });
  test('changed identity is rejected, including on unencrypted endpoints', () async {
    client.fingerprint = 'C' * 64;
    await expectLater(service.connect(DesktopPairingInvitation.fromDevice(b)), throwsStateError);
  });
  test('discovery retains scanned port and protocol and refuses own device', () async {
    final connected = await service.discover(const QrConnectionInfo(ip: '192.168.1.20', port: 54321, https: false));
    expect(connected.port, 54321);
    expect(connected.https, false);
    client.fingerprint = a.fingerprint;
    await expectLater(service.discover(const QrConnectionInfo(ip: '192.168.1.10', port: 54321, https: true)), throwsStateError);
  });
  test('QR PIN retained for invitation without including it in shareable endpoint', () {
    final endpoint = parseQrConnectionInfo('http://192.168.1.10:54321/?pin=1234')!;
    expect(endpoint.pin, '1234');
    expect(endpoint.uri.toString(), 'http://192.168.1.10:54321');
  });
}
