import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/pages/desktop_pairing_page.dart';
import 'package:localsend_app/pages/qr_scan_page.dart';
import 'package:localsend_app/provider/local_ip_provider.dart';
import 'package:localsend_app/provider/network/server/server_provider.dart';
import 'package:localsend_app/provider/qr_share_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/util/desktop_pairing_invitation.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/util/ui/snackbar.dart';
import 'package:localsend_app/widget/dialogs/qr_dialog.dart';
import 'package:localsend_app/widget/dialogs/qr_send_request_prompt.dart';
import 'package:localsend_app/widget/dialogs/zoom_dialog.dart';
import 'package:localsend_app/widget/responsive_list_view.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Native LocalSend connection codes use the existing server and its settings.
/// Opening this tab never changes encryption or starts a separate web share.
class QrConnectionTab extends StatelessWidget {
  const QrConnectionTab();

  Future<void> _send(BuildContext context) async {
    final device = await Navigator.of(context).push<Device>(QrScanPage.sendRoute());
    if (device == null || !context.mounted) return;
    await sendFilesToDevice(context, device, chooseFiles: true);
  }

  @override
  Widget build(BuildContext context) {
    final server = context.watch(serverProvider);
    final ips = context.watch(localIpProvider).localIps;
    final settings = context.watch(settingsProvider);
    final connection = context.watch(qrShareProvider);
    final mobile = !checkPlatformIsDesktop();
    return Scaffold(
      appBar: AppBar(title: Text(t.qrConnection.title), automaticallyImplyLeading: false),
      body: ResponsiveListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (mobile) ...[
            _ScanAction(
              icon: Icons.upload_rounded,
              label: t.qrConnection.scanSend,
              detail: t.qrConnection.sendHint,
              onTap: () async => _send(context),
            ),
            _ScanAction(
              icon: Icons.download_rounded,
              label: t.qrConnection.scanReceive,
              detail: t.qrConnection.receiveHint,
              onTap: () async {
                await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => const QrScanPage(mode: QrScanMode.receive)));
              },
            ),
            _ScanAction(
              icon: Icons.devices_rounded,
              label: t.qrConnection.linkComputers,
              detail: t.qrConnection.pairHint,
              onTap: () async {
                await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => const DesktopPairingPage()));
              },
            ),
            const SizedBox(height: 20),
          ],
          if (connection.connecting) ...[const LinearProgressIndicator(), const SizedBox(height: 12), Text(t.qrConnection.connecting)],
          if (connection.connectedPeer != null || connection.failed) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      connection.failed
                          ? t.desktopPairing.failed
                          : connection.role == PairingRole.receive
                          ? t.qrConnection.waiting(peer: connection.connectedPeer!.alias)
                          : t.qrConnection.readySend(peer: connection.connectedPeer!.alias),
                    ),
                    if (connection.role == PairingRole.receive && !connection.failed)
                      Text(settings.qrConnectionAutoSave ? t.qrConnection.autoReceive : t.qrConnection.confirmReceive),
                    TextButton(onPressed: () => context.ref.notifier(qrShareProvider).resetConnection(), child: Text(t.general.cancel)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Text(t.qrConnection.myCode, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(t.qrConnection.chooseNetwork),
          const SizedBox(height: 12),
          if (server == null) ...[
            Text(t.general.offline),
            FilledButton(
              onPressed: () async {
                await context.ref.notifier(serverProvider).startServerFromSettings();
              },
              child: Text(t.qrConnection.startServer),
            ),
          ] else if (ips.isEmpty)
            Text(t.qrConnection.noNetwork)
          else
            Card(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    for (final ip in ips)
                      Builder(
                        builder: (context) {
                          final endpoint = Uri(scheme: server.https ? 'https' : 'http', host: ip, port: server.port);
                          final url = endpoint.toString();
                          final code = settings.receivePin == null
                              ? url
                              : endpoint.replace(queryParameters: {'pin': settings.receivePin!}).toString();
                          return _QrAddress(url: url, code: code, pin: settings.receivePin);
                        },
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ScanAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final String detail;
  final VoidCallback onTap;
  const _ScanAction({required this.icon, required this.label, required this.detail, required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Card.filled(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          child: Row(
            children: [
              Icon(icon, size: 32, color: Theme.of(context).colorScheme.onPrimaryContainer),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(detail),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    ),
  );
}

class _QrAddress extends StatelessWidget {
  final String url;
  final String code;
  final String? pin;
  const _QrAddress({required this.url, required this.code, this.pin});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final address = SelectableText(url, style: Theme.of(context).textTheme.bodyLarge);
        final actions = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: t.general.copy,
              icon: const Icon(Icons.content_copy),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: code));
                if (context.mounted) context.showSnackBar(t.general.copiedToClipboard);
              },
            ),
            IconButton.filledTonal(
              tooltip: t.qrConnection.showCode,
              icon: const Icon(Icons.qr_code_2),
              onPressed: () async {
                await showDialog<void>(
                  context: context,
                  routeSettings: const RouteSettings(name: 'qr-connection-code'),
                  builder: (_) => QrDialog(data: code, label: url, pin: pin, showSendRequest: false),
                );
              },
            ),
            IconButton(
              tooltip: t.dialogs.zoom.title,
              icon: const Icon(Icons.tv),
              onPressed: () async {
                await showDialog<void>(
                  context: context,
                  routeSettings: const RouteSettings(name: 'qr-connection-code'),
                  builder: (_) => ZoomDialog(label: url, pin: pin, showSendRequest: false),
                );
              },
            ),
          ],
        );
        return constraints.maxWidth >= 460
            ? Row(
                children: [
                  Expanded(child: address),
                  const SizedBox(width: 8),
                  actions,
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  address,
                  Align(alignment: Alignment.centerRight, child: actions),
                ],
              );
      },
    ),
  );
}
