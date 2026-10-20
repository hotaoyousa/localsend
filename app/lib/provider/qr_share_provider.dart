import 'package:localsend_isolates/model/device.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Tracks the QR codes this device currently shows and the peers that
/// registered while a QR code was open.
///
/// A registration is how a peer announces its own address, so a peer that
/// registers while this device advertises its address has scanned that QR code.
/// The QR dialogs offer to send files back to such a peer, which is the reverse
/// of the regular transfer (where the peer sends files here).
final qrShareProvider = NotifierProvider<QrShareService, QrShareState>((ref) {
  return QrShareService();
});

class QrShareState {
  /// The number of QR dialogs that are currently open.
  final int openDialogs;

  /// A peer that registered while a QR code was open and that the user has
  /// neither answered nor dismissed yet.
  final Device? pendingRequest;

  const QrShareState({
    required this.openDialogs,
    this.pendingRequest,
  });

  bool get isSharing => openDialogs > 0;
}

class QrShareService extends Notifier<QrShareState> {
  /// Fingerprints that already got a prompt in the current QR session, so the
  /// repeated registrations of the same peer do not ask again.
  final _prompted = <String>{};

  @override
  QrShareState init() => const QrShareState(openDialogs: 0);

  /// A QR dialog became visible.
  void dialogOpened() {
    state = QrShareState(openDialogs: state.openDialogs + 1, pendingRequest: state.pendingRequest);
  }

  /// A QR dialog was closed. The last one ends the QR session.
  void dialogClosed() {
    final openDialogs = state.openDialogs - 1;
    if (openDialogs > 0) {
      state = QrShareState(openDialogs: openDialogs, pendingRequest: state.pendingRequest);
      return;
    }

    _prompted.clear();
    state = const QrShareState(openDialogs: 0);
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
    if (!state.isSharing) {
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

    state = QrShareState(openDialogs: state.openDialogs);
  }
}
