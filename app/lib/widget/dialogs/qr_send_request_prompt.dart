import 'package:flutter/material.dart';
import 'package:localsend_app/config/theme.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/pages/home_page.dart';
import 'package:localsend_app/pages/home_page_controller.dart';
import 'package:localsend_app/provider/network/send_provider.dart';
import 'package:localsend_app/provider/qr_share_provider.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/util/native/file_picker.dart';
import 'package:localsend_app/widget/dialogs/add_file_dialog.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

/// Shown inside the QR dialogs.
///
/// A peer registered itself while this device was advertising its address, so
/// it scanned the QR code and is able to receive files. The user may pick the
/// files to send back with the regular sending flow.
class QrSendRequestPrompt extends StatelessWidget {
  final Device device;

  const QrSendRequestPrompt({
    required this.device,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 15),
        Text(
          t.dialogs.qr.sendRequest(alias: device.alias),
          textAlign: TextAlign.center,
          style: TextStyle(color: Theme.of(context).colorScheme.warning),
        ),
        const SizedBox(height: 5),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              onPressed: () => context.ref.notifier(qrShareProvider).dismiss(),
              child: Text(t.general.cancel),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: () async => _sendFilesTo(context, device),
              icon: const Icon(Icons.send),
              label: Text(t.dialogs.qr.sendFiles),
            ),
          ],
        ),
      ],
    );
  }
}

/// Closes the QR dialog and lets the user select the files to send to [device].
///
/// The files are sent with the regular sending flow, so the transfer is
/// identical to picking the device from the device list.
Future<void> _sendFilesTo(BuildContext context, Device device) async {
  final ref = context.ref;
  ref.notifier(qrShareProvider).dismiss();

  // The QR code has been used; the user continues on the send page.
  context.pop();
  ref.redux(homePageControllerProvider).dispatch(ChangeTabAction(HomeTab.send));

  var files = ref.read(selectedSendingFilesProvider);
  if (files.isEmpty) {
    await AddFileDialog.open(context: Routerino.context, options: FilePickerOption.getOptionsForPlatform());
    files = ref.read(selectedSendingFilesProvider);
  }

  if (files.isEmpty) {
    return;
  }

  await ref.notifier(sendProvider).startSession(target: device, files: files, background: false);
}
