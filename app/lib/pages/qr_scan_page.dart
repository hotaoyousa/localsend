import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localsend_app/config/theme.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/provider/desktop_pairing_provider.dart';
import 'package:localsend_app/provider/device_info_provider.dart';
import 'package:localsend_app/provider/http_provider.dart';
import 'package:localsend_app/provider/last_devices.provider.dart';
import 'package:localsend_app/provider/network/server/server_provider.dart';
import 'package:localsend_app/provider/qr_share_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/util/desktop_pairing_invitation.dart';
import 'package:localsend_app/util/qr_connection_info.dart';
import 'package:localsend_app/util/ui/snackbar.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/rust/api/cancel.dart';
import 'package:localsend_isolates/rust/api/model.dart';
import 'package:localsend_isolates/util/rust.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// The state of the "receive files from the scanned device" request.
enum _ReceiveState {
  idle,

  /// The address of this device is being announced to the scanned device.
  requesting,

  /// The scanned device knows where to send files; waiting for its request.
  waiting,

  /// The scanned device could not be reached.
  failed,
}

enum QrScanMode { choose, send, receive }

class QrScanPage extends StatefulWidget {
  final bool selectComputer;
  final QrScanMode mode;
  const QrScanPage({this.selectComputer = false, this.mode = QrScanMode.choose});

  /// Close the scanner without overlapping its exit with the file picker entry.
  static Route<Device> sendRoute() => PageRouteBuilder<Device>(
    pageBuilder: (_, _, _) => const QrScanPage(mode: QrScanMode.send),
    transitionDuration: const Duration(milliseconds: 200),
    reverseTransitionDuration: Duration.zero,
    transitionsBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
  );

  @override
  State<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<QrScanPage> with Refena {
  QrConnectionInfo? _connection;
  bool _invalidCode = false;
  Timer? _sendProgressTimer;
  bool _showSendProgress = false;
  bool _sendFailed = false;
  RsCancellationToken? _receiveToken;

  @override
  void dispose() {
    _receiveToken?.cancel();
    _sendProgressTimer?.cancel();
    if (widget.mode == QrScanMode.receive) ref.notifier(qrShareProvider).resetConnection();
    super.dispose();
  }

  int _scannerGeneration = 0;
  _ReceiveState _receiveState = _ReceiveState.idle;

  /// The alias of the scanned device, shown while waiting for its files.
  String? _receiveAlias;

  void _onDetect(BarcodeCapture capture) {
    if (!mounted || _connection != null) {
      return;
    }

    var sawQrCode = false;
    for (final barcode in capture.barcodes) {
      if (barcode.format != BarcodeFormat.qrCode || barcode.rawValue == null) {
        continue;
      }
      sawQrCode = true;
      final connection = parseQrConnectionInfo(barcode.rawValue!);
      if (connection != null) {
        // Removing MobileScanner also stops and disposes its camera controller.
        setState(() {
          _connection = connection;
          _receiveState = _ReceiveState.idle;
          _receiveAlias = null;
        });
        if (!widget.selectComputer && widget.mode != QrScanMode.choose) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (widget.mode == QrScanMode.send) {
              unawaited(_connectForSending(connection));
            } else {
              unawaited(_requestReceive(connection));
            }
          });
        }
        return;
      }
    }

    if (sawQrCode && !_invalidCode) {
      setState(() => _invalidCode = true);
    }
  }

  Future<void> _connectForSending(QrConnectionInfo connection) async {
    final generation = _scannerGeneration;
    _sendProgressTimer?.cancel();
    setState(() {
      _sendFailed = false;
      _showSendProgress = false;
    });
    _sendProgressTimer = Timer(const Duration(milliseconds: 250), () {
      if (mounted && generation == _scannerGeneration) setState(() => _showSendProgress = true);
    });
    try {
      final response = await ref
          .read(qrDiscoveryClientProvider)
          .register(
            protocol: connection.https ? ProtocolType.https : ProtocolType.http,
            ip: connection.ip,
            port: connection.port,
            payload: ref.read(deviceFullInfoProvider).toRegisterDto(),
          );
      if (!mounted || generation != _scannerGeneration) return;
      final target = response.body.toDevice(connection.ip, connection.port, connection.https);
      final service = ref.read(desktopPairingProvider);
      final token = service.createToken();
      _receiveToken = token;
      try {
        // Explicitly identify this QR sender so the recipient can apply its QR setting.
        await service.introduce(
          recipient: target,
          peer: ref.read(deviceFullInfoProvider),
          token: token,
          pin: connection.pin,
          role: PairingRole.receive,
        );
      } finally {
        _receiveToken = null;
      }
      if (!mounted || generation != _scannerGeneration) return;
      ref.redux(lastDevicesProvider).dispatch(AddLastDeviceAction(target));
      Navigator.of(context).pop(target);
    } catch (_) {
      if (mounted && generation == _scannerGeneration) setState(() => _sendFailed = true);
    } finally {
      _sendProgressTimer?.cancel();
    }
  }

  Widget _sendConnectionView(QrConnectionInfo connection) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_sendFailed ? Icons.error_outline : Icons.check_circle_outline, size: 64),
          const SizedBox(height: 16),
          Text(_sendFailed ? t.qrScanPage.connectionFailed : t.qrConnection.scanSend, textAlign: TextAlign.center),
          if (!_sendFailed && _showSendProgress) ...[
            const SizedBox(height: 20),
            const LinearProgressIndicator(),
            const SizedBox(height: 12),
            Text(t.qrConnection.connecting),
          ],
          if (_sendFailed) ...[
            const SizedBox(height: 12),
            SelectableText(connection.uri.toString()),
            const SizedBox(height: 20),
            FilledButton(onPressed: () async => _connectForSending(connection), child: Text(t.qrScanPage.retryConnection)),
            TextButton(onPressed: _scanAgain, child: Text(t.qrScanPage.scanAgain)),
          ],
        ],
      ),
    ),
  );

  void _scanAgain() {
    _receiveToken?.cancel();
    _receiveToken = null;
    _sendProgressTimer?.cancel();
    _showSendProgress = false;
    _sendFailed = false;
    if (widget.mode == QrScanMode.receive) ref.notifier(qrShareProvider).resetConnection();
    setState(() {
      _connection = null;
      _invalidCode = false;
      _receiveState = _ReceiveState.idle;
      _receiveAlias = null;
      _scannerGeneration++;
    });
  }

  /// In receive mode, asks the scanned peer to send using an explicit role.
  /// The legacy chooser keeps the register-based request for older entry points.
  Future<void> _requestReceive(QrConnectionInfo connection) async {
    final generation = _scannerGeneration;
    setState(() => _receiveState = _ReceiveState.requesting);

    try {
      // Only a running server can accept the files that are about to be sent here.
      var device = ref.read(deviceFullInfoProvider);
      if (device.port < 1) {
        await ref.notifier(serverProvider).startServerFromSettings();
        device = ref.read(deviceFullInfoProvider);
      }
      if (device.port < 1) {
        throw StateError('The local server is not running');
      }

      if (widget.mode == QrScanMode.receive) {
        final service = ref.read(desktopPairingProvider);
        final target = await service.discover(connection, computerOnly: false);
        if (!mounted || generation != _scannerGeneration) return;
        final token = service.createToken();
        _receiveToken = token;
        ref.notifier(qrShareProvider).connectionFinished(peer: target, role: PairingRole.receive);
        try {
          await service.introduce(
            recipient: target,
            peer: ref.read(deviceFullInfoProvider),
            token: token,
            pin: connection.pin,
            role: PairingRole.send,
          );
        } catch (_) {
          if (mounted && generation == _scannerGeneration) ref.notifier(qrShareProvider).resetConnection();
          rethrow;
        } finally {
          _receiveToken = null;
        }
        if (mounted && generation == _scannerGeneration) {
          setState(() {
            _receiveState = _ReceiveState.waiting;
            _receiveAlias = target.alias;
          });
        }
        return;
      }

      final response = await ref
          .read(qrDiscoveryClientProvider)
          .register(
            protocol: connection.https ? ProtocolType.https : ProtocolType.http,
            ip: connection.ip,
            port: connection.port,
            payload: device.toRegisterDto(),
          );

      if (!mounted || generation != _scannerGeneration) {
        return;
      }
      setState(() {
        _receiveState = _ReceiveState.waiting;
        _receiveAlias = response.body.alias;
      });
    } catch (e) {
      if (!mounted || generation != _scannerGeneration) {
        return;
      }
      setState(() => _receiveState = _ReceiveState.failed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final connection = _connection;
    final ip = connection?.ip;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.mode == QrScanMode.send
              ? t.qrConnection.scanSend
              : widget.mode == QrScanMode.receive
              ? t.qrConnection.scanReceive
              : t.qrScanPage.title,
        ),
      ),
      body: SafeArea(
        child: ip == null
            ? Column(
                children: [
                  Expanded(
                    // The internal controller handles app pause/resume and disposal.
                    child: MobileScanner(
                      key: ValueKey(_scannerGeneration),
                      onDetect: _onDetect,
                      errorBuilder: (context, error) => Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                error.errorCode == MobileScannerErrorCode.permissionDenied ? t.qrScanPage.permissionDenied : t.qrScanPage.cameraError,
                                textAlign: TextAlign.center,
                              ),
                              if (error.errorCode == MobileScannerErrorCode.permissionDenied)
                                TextButton(
                                  onPressed: () async {
                                    await openAppSettings();
                                  },
                                  child: Text(t.general.settings),
                                ),
                              TextButton(onPressed: _scanAgain, child: Text(t.qrScanPage.scanAgain)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      _invalidCode ? t.qrScanPage.invalidCode : t.qrScanPage.instruction,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              )
            : widget.mode == QrScanMode.send && !widget.selectComputer
            ? _sendConnectionView(connection!)
            : Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle_outline, size: 64),
                      const SizedBox(height: 16),
                      Text(t.qrScanPage.deviceIp, style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 12),
                      SelectableText(ip, style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                      Text(connection!.uri.toString(), textAlign: TextAlign.center),
                      const SizedBox(height: 20),
                      if (widget.mode != QrScanMode.receive)
                        FilledButton.icon(
                          onPressed: () => Navigator.of(context).pop(connection),
                          icon: const Icon(Icons.send),
                          label: Text(widget.selectComputer ? t.desktopPairing.useComputer : t.sendTab.title),
                        ),
                      const SizedBox(height: 12),
                      if (!widget.selectComputer)
                        if (_receiveState == _ReceiveState.waiting)
                          Card(
                            margin: EdgeInsets.zero,
                            color: Theme.of(context).colorScheme.secondaryContainer,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.download_done),
                                  const SizedBox(height: 8),
                                  Text(
                                    t.qrScanPage.receiveWaiting(alias: _receiveAlias ?? ip),
                                    textAlign: TextAlign.center,
                                  ),
                                  if (widget.mode == QrScanMode.receive) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      ref.watch(settingsProvider).qrConnectionAutoSave ? t.qrConnection.autoReceive : t.qrConnection.confirmReceive,
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          )
                        else ...[
                          OutlinedButton.icon(
                            onPressed: _receiveState == _ReceiveState.requesting ? null : () async => _requestReceive(connection),
                            icon: const Icon(Icons.download),
                            label: Text(t.qrScanPage.receive),
                          ),
                          if (_receiveState == _ReceiveState.requesting)
                            const Padding(
                              padding: EdgeInsets.only(top: 12),
                              child: LinearProgressIndicator(),
                            ),
                          if (_receiveState == _ReceiveState.failed)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(
                                t.qrScanPage.connectionFailed,
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Theme.of(context).colorScheme.warning),
                              ),
                            ),
                          if (_receiveState == _ReceiveState.failed)
                            TextButton(
                              onPressed: () async => _requestReceive(connection),
                              child: Text(t.qrScanPage.retryConnection),
                            ),
                        ],
                      const SizedBox(height: 12),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 12,
                        children: [
                          TextButton.icon(
                            onPressed: () async {
                              await Clipboard.setData(ClipboardData(text: ip));
                              if (context.mounted) {
                                context.showSnackBar(t.general.copiedToClipboard);
                              }
                            },
                            icon: const Icon(Icons.copy),
                            label: Text(t.general.copy),
                          ),
                          OutlinedButton(onPressed: _scanAgain, child: Text(t.qrScanPage.scanAgain)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
