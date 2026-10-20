import 'dart:async';
import 'dart:convert';

import 'package:localsend_app/provider/device_info_provider.dart';
import 'package:localsend_app/provider/http_provider.dart';
import 'package:localsend_app/util/desktop_pairing_invitation.dart';
import 'package:localsend_app/util/qr_connection_info.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/rust/api/cancel.dart';
import 'package:localsend_isolates/rust/api/http.dart';
import 'package:localsend_isolates/rust/api/model.dart' as rust;
import 'package:localsend_isolates/util/rust.dart';
import 'package:refena_flutter/refena_flutter.dart';

final desktopPairingProvider = Provider(
  (ref) => DesktopPairingService(
    ownDevice: () => ref.read(deviceFullInfoProvider),
    discovery: () => ref.read(qrDiscoveryClientProvider),
    pinned: (fingerprint, timeoutMs) => ref.read(httpProvider).pinnedTo(fingerprint, timeoutMs: timeoutMs),
    createToken: createCancellationToken,
  ),
);

class DesktopPairingService {
  final Device Function() ownDevice;
  final RsHttpClient Function() discovery;
  final RsHttpClient Function(String, int) pinned;
  final RsCancellationToken Function() createToken;

  DesktopPairingService({required this.ownDevice, required this.discovery, required this.pinned, required this.createToken});

  Future<Device> discover(QrConnectionInfo endpoint, {bool computerOnly = true}) async {
    final result = await discovery().register(
      protocol: endpoint.https ? rust.ProtocolType.https : rust.ProtocolType.http,
      ip: endpoint.ip,
      port: endpoint.port,
      payload: ownDevice().toRegisterDto(),
    );
    final device = result.body.toDevice(endpoint.ip, endpoint.port, endpoint.https);
    if ((computerOnly && device.deviceType != DeviceType.desktop) ||
        device.fingerprint.toUpperCase() == ownDevice().fingerprint.toUpperCase() ||
        DesktopPairingInvitation.decode(DesktopPairingInvitation.fromDevice(device).encode()) == null) {
      throw StateError('Not a supported remote computer');
    }
    return device;
  }

  /// Returns only after the recipient accepts the selected role and reaches its peer.
  Future<void> introduce({
    required Device recipient,
    required Device peer,
    required RsCancellationToken token,
    String? pin,
    PairingRole? role,
  }) async {
    if (recipient.fingerprint.toUpperCase() == peer.fingerprint.toUpperCase()) throw StateError('Same computer');
    final invitation = DesktopPairingInvitation.fromDevice(peer, role: role).encode();
    final timer = Timer(const Duration(minutes: 2), token.cancel);
    try {
      final result = await pinned(recipient.fingerprint, 120000).prepareUpload(
        protocol: recipient.getProtocolType(),
        ip: recipient.ip!,
        port: recipient.port,
        payload: rust.PrepareUploadRequestDto(
          info: ownDevice().toRegisterDto(),
          files: {
            'peer': rust.FileDto(
              id: 'peer',
              fileName: 'connection.localsend-pair',
              size: BigInt.from(utf8.encode(invitation).length),
              fileType: DesktopPairingInvitation.mimeType,
              preview: invitation,
            ),
          },
        ),
        pin: pin,
        cancelToken: token,
      );
      // Empty acceptance is 204: this request exchanges metadata, never bytes.
      if (result.statusCode != 204) {
        if (result.response != null) {
          await pinned(
            recipient.fingerprint,
            8000,
          ).cancel(protocol: recipient.getProtocolType(), ip: recipient.ip!, port: recipient.port, sessionId: result.response!.sessionId);
        }
        throw StateError('Invitation was not accepted by a compatible computer');
      }
    } finally {
      timer.cancel();
    }
  }

  /// The computer contacts the introduced peer itself, using the learned pin.
  Future<Device> connect(DesktopPairingInvitation peer) async {
    if (peer.fingerprint == ownDevice().fingerprint.toUpperCase()) throw StateError('Same computer');
    final response = await pinned(peer.fingerprint, 8000).register(
      protocol: peer.https ? rust.ProtocolType.https : rust.ProtocolType.http,
      ip: peer.ip,
      port: peer.port,
      payload: ownDevice().toRegisterDto(),
    );
    if (response.body.token.toUpperCase() != peer.fingerprint) throw StateError('Peer identity changed');
    return response.body.toDevice(peer.ip, peer.port, peer.https);
  }
}
