import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localsend_app/config/theme.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/pages/desktop_pairing_page.dart';
import 'package:localsend_app/provider/device_info_provider.dart';
import 'package:localsend_app/provider/http_provider.dart';
import 'package:localsend_app/provider/network/server/server_provider.dart';
import 'package:localsend_app/util/qr_connection_info.dart';
import 'package:localsend_app/util/ui/snackbar.dart';
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

class QrScanPage extends StatefulWidget {
  final bool selectComputer;
  const QrScanPage({this.selectComputer = false});

  @override
  State<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<QrScanPage> with Refena {
  QrConnectionInfo? _connection;
  bool _invalidCode = false;
  bool _pairingOpen = false;
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
        return;
      }
    }

    if (sawQrCode && !_invalidCode) {
      setState(() => _invalidCode = true);
    }
  }

  void _scanAgain() {
    setState(() {
      _connection = null;
      _invalidCode = false;
      _receiveState = _ReceiveState.idle;
      _receiveAlias = null;
      _scannerGeneration++;
    });
  }

  /// Announces the address of this device to the scanned device, so that it can
  /// send files here without the user entering an IP address.
  ///
  /// The announcement is the regular `register` request of the LocalSend
  /// protocol, which carries the alias, port, protocol and fingerprint of this
  /// device; the scanned device learns the IP from the connection itself.
  Future<void> _requestReceive(QrConnectionInfo connection) async {
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

      final response = await ref
          .read(qrDiscoveryClientProvider)
          .register(
            protocol: connection.https ? ProtocolType.https : ProtocolType.http,
            ip: connection.ip,
            port: connection.port,
            payload: device.toRegisterDto(),
          );

      if (!mounted) {
        return;
      }
      setState(() {
        _receiveState = _ReceiveState.waiting;
        _receiveAlias = response.body.alias;
      });
    } catch (e) {
      if (!mounted) {
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
        title: Text(t.qrScanPage.title),
        actions: [
          if (!widget.selectComputer)
            IconButton(
              tooltip: t.desktopPairing.title,
              icon: const Icon(Icons.devices),
              onPressed: () async {
                setState(() => _pairingOpen = true);
                await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => const DesktopPairingPage()));
                if (mounted) {
                  setState(() {
                    _pairingOpen = false;
                    _scannerGeneration++;
                  });
                }
              },
            ),
        ],
      ),
      body: SafeArea(
        child: _pairingOpen
            ? const SizedBox.shrink()
            : ip == null
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
