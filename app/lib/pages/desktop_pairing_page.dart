import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/pages/qr_scan_page.dart';
import 'package:localsend_app/provider/desktop_pairing_provider.dart';
import 'package:localsend_app/util/qr_connection_info.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/rust/api/cancel.dart';
import 'package:refena_flutter/refena_flutter.dart';

class DesktopPairingPage extends StatefulWidget {
  const DesktopPairingPage();
  @override
  State<DesktopPairingPage> createState() => _DesktopPairingPageState();
}

class _DesktopPairingPageState extends State<DesktopPairingPage> with Refena {
  final _computers = <Device?>[null, null];
  final _endpoints = <QrConnectionInfo?>[null, null];
  final _connected = [false, false];
  final _tokens = <RsCancellationToken>[];
  bool _busy = false;
  bool _failed = false;

  @override
  void dispose() {
    for (final token in _tokens) {
      token.cancel();
    }
    super.dispose();
  }

  Future<void> _scan(int index) async {
    final endpoint = await Navigator.of(context).push<QrConnectionInfo>(MaterialPageRoute(builder: (_) => const QrScanPage(selectComputer: true)));
    if (endpoint == null || !mounted) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final computer = await ref.read(desktopPairingProvider).discover(endpoint);
      if (!mounted) return;
      if (computer.fingerprint.toUpperCase() == _computers[1 - index]?.fingerprint.toUpperCase()) throw StateError('Same computer');
      setState(() {
        _computers[index] = computer;
        _endpoints[index] = endpoint;
        _connected.fillRange(0, 2, false);
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    final service = ref.read(desktopPairingProvider);
    try {
      for (var i = 0; i < 2; i++) {
        if (_connected[i]) continue;
        final token = service.createToken();
        _tokens.add(token);
        try {
          await service.introduce(recipient: _computers[i]!, peer: _computers[1 - i]!, token: token, pin: _endpoints[i]?.pin);
          if (!mounted) return;
          setState(() => _connected[i] = true);
        } catch (_) {
          if (!mounted) return;
          setState(() => _failed = true);
        } finally {
          _tokens.remove(token);
        }
        if (!mounted) return;
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(t.desktopPairing.title)),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(t.desktopPairing.instructions),
        const SizedBox(height: 16),
        for (var i = 0; i < 2; i++)
          Card(
            child: ListTile(
              leading: Icon(_connected[i] ? Icons.check_circle : Icons.computer),
              title: Text(i == 0 ? t.desktopPairing.computerA : t.desktopPairing.computerB),
              subtitle: Text(
                _computers[i] == null
                    ? t.desktopPairing.notScanned
                    : '${_computers[i]!.alias}\n${_computers[i]!.ip}:${_computers[i]!.port}${_connected[i] ? '\n${t.desktopPairing.connected}' : ''}',
              ),
              isThreeLine: _computers[i] != null,
              trailing: IconButton(tooltip: t.qrScanPage.title, onPressed: _busy ? null : () => _scan(i), icon: const Icon(Icons.qr_code_scanner)),
            ),
          ),
        const SizedBox(height: 16),
        Text(t.desktopPairing.directTransfer),
        const SizedBox(height: 16),
        if (_busy) ...[const LinearProgressIndicator(), const SizedBox(height: 12), Text(t.desktopPairing.confirmOnComputers)],
        if (_failed) Padding(padding: const EdgeInsets.only(top: 12), child: Text(t.desktopPairing.failed)),
        if (_connected.every((value) => value))
          Padding(padding: const EdgeInsets.only(top: 12), child: Text(t.desktopPairing.done))
        else
          FilledButton.icon(
            onPressed: _busy || _computers.any((value) => value == null) ? null : _connect,
            icon: const Icon(Icons.link),
            label: Text(_failed ? t.qrScanPage.retryConnection : t.desktopPairing.connect),
          ),
      ],
    ),
  );
}
