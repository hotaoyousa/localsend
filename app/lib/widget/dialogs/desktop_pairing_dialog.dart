import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/provider/desktop_pairing_provider.dart';
import 'package:localsend_app/util/desktop_pairing_invitation.dart';
import 'package:refena_flutter/refena_flutter.dart';

class DesktopPairingDialog extends StatefulWidget {
  final String phoneAlias;
  final DesktopPairingInvitation peer;
  const DesktopPairingDialog({required this.phoneAlias, required this.peer});

  @override
  State<DesktopPairingDialog> createState() => _DesktopPairingDialogState();
}

class _DesktopPairingDialogState extends State<DesktopPairingDialog> with Refena {
  bool _busy = false;
  bool _failed = false;

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final device = await ref.read(desktopPairingProvider).connect(widget.peer);
      if (mounted) Navigator.of(context).pop(device);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: Text(t.desktopPairing.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(t.desktopPairing.invitation(phone: widget.phoneAlias, peer: widget.peer.alias)),
            const SizedBox(height: 12),
            Text('${widget.peer.https ? 'https' : 'http'}://${widget.peer.ip}:${widget.peer.port}'),
            const SizedBox(height: 12),
            Text(t.desktopPairing.directTransfer),
            if (_busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
            if (_failed) Padding(padding: const EdgeInsets.only(top: 12), child: Text(t.desktopPairing.failed)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: Text(t.general.cancel)),
        FilledButton(onPressed: _busy ? null : _connect, child: Text(_failed ? t.qrScanPage.retryConnection : t.desktopPairing.connect)),
      ],
    ),
  );
}
