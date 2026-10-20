import 'package:localsend_app/util/desktop_pairing_invitation.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Tracks the QR codes this device currently shows and the peers that
/// registered while a QR code was open.
///
/// The connection tab handles explicit send/receive invitations. Legacy web QR
/// dialogs retain their register-based send prompt; the hub does not infer a
/// transfer direction from ordinary network discovery registrations.
final qrShareProvider = NotifierProvider<QrShareService, QrShareState>((ref) {
  return QrShareService();
});

class QrShareState {
  /// The number of QR dialogs that are currently open.
  final int openDialogs;

  /// A peer that registered while a QR code was open and that the user has
  /// neither answered nor dismissed yet.
  final Device? pendingRequest;
  final bool hubActive;
  final Device? connectedPeer;
  final PairingRole? role;
  final bool connecting;
  final bool failed;

  const QrShareState({
    required this.openDialogs,
    this.pendingRequest,
    this.hubActive = false,
    this.connectedPeer,
    this.role,
    this.connecting = false,
    this.failed = false,
  });

  bool get isSharing => hubActive || openDialogs > 0;
}

class QrShareService extends Notifier<QrShareState> {
  /// Fingerprints that already got a prompt in the current QR session, so the
  /// repeated registrations of the same peer do not ask again.
  final _prompted = <String>{};

  @override
  QrShareState init() => const QrShareState(openDialogs: 0);

  void setHubActive(bool active) {
    state = QrShareState(
      openDialogs: state.openDialogs,
      hubActive: active,
      connectedPeer: active ? state.connectedPeer : null,
      role: active ? state.role : null,
    );
  }

  void connectionStarted(PairingRole role) {
    state = QrShareState(openDialogs: state.openDialogs, hubActive: state.hubActive, role: role, connecting: true);
  }

  void connectionFinished({Device? peer, required PairingRole role, bool failed = false}) {
    state = QrShareState(openDialogs: state.openDialogs, hubActive: state.hubActive, connectedPeer: peer, role: role, failed: failed);
  }

  void resetConnection() {
    state = QrShareState(openDialogs: state.openDialogs, hubActive: state.hubActive);
  }

  /// A QR dialog became visible.
  void dialogOpened() {
    state = QrShareState(
      openDialogs: state.openDialogs + 1,
      hubActive: state.hubActive,
      connectedPeer: state.connectedPeer,
      role: state.role,
      pendingRequest: state.pendingRequest,
    );
  }

  /// A QR dialog was closed. The last one ends the QR session.
  void dialogClosed() {
    final openDialogs = state.openDialogs - 1;
    if (openDialogs > 0) {
      state = QrShareState(
        openDialogs: openDialogs,
        hubActive: state.hubActive,
        connectedPeer: state.connectedPeer,
        role: state.role,
        pendingRequest: state.pendingRequest,
      );
      return;
    }

    _prompted.clear();
    state = QrShareState(openDialogs: 0, hubActive: state.hubActive, connectedPeer: state.connectedPeer, role: state.role);
  }

  /// A peer registered itself on this device's server.
  ///
  /// This only counts while a QR code is open, and every peer is asked at most
  /// once per QR session. A device that registers with the fingerprint of this
  /// device is itself and is ignored.
  void onRegister({
    required Device device,
    required String ownFingerprint,
  }) {
    if (device.fingerprint == ownFingerprint) {
      // "I talked to myself lol"
      return;
    }

    offer(device);
  }

  /// A peer registered itself, without checking whether it is this device.
  ///
  /// This only counts while a QR code is open, and every peer is asked at most
  /// once per QR session.
  void offer(Device device) {
    if (!state.isSharing || state.hubActive) {
      return;
    }

    if (!_prompted.add(device.fingerprint)) {
      return;
    }

    state = QrShareState(openDialogs: state.openDialogs, pendingRequest: device);
  }

  /// The user declined the request or sent files to the peer.
  void dismiss() {
    if (state.pendingRequest == null) {
      return;
    }

    state = QrShareState(openDialogs: state.openDialogs, hubActive: state.hubActive, connectedPeer: state.connectedPeer, role: state.role);
  }
}
