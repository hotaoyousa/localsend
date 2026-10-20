import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/pages/home_page_controller.dart';
import 'package:localsend_app/provider/network/send_provider.dart';
import 'package:localsend_app/provider/qr_share_provider.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/util/native/file_picker.dart';
import 'package:localsend_app/widget/dialogs/add_file_dialog.dart';
import 'package:localsend_app/widget/dialogs/qr_dialog.dart';
import 'package:localsend_app/widget/dialogs/qr_send_request_prompt.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

class _RecordingSender extends SendNotifier {
  Device? target;
  List<CrossFile>? files;
  int sessions = 0;

  @override
  Future<void> startSession({required Device target, required List<CrossFile> files, required bool background}) async {
    this.target = target;
    this.files = files;
    sessions++;
  }
}

Device _peer({String fingerprint = 'phone-fingerprint'}) {
  return Device(
    signalingId: null,
    ip: '10.0.0.2',
    version: '2.2',
    port: 53317,
    https: false,
    fingerprint: fingerprint,
    alias: 'Phone',
    deviceModel: null,
    deviceType: DeviceType.mobile,
    download: false,
    channels: const [],
  );
}

void main() {
  setUp(() {
    LocaleSettings.setLocaleSync(AppLocale.en);
  });

  group('QrShareService', () {
    test('only offers peers that register while a QR code is open', () {
      final container = RefenaContainer();

      container.notifier(qrShareProvider).offer(_peer());
      expect(container.read(qrShareProvider).pendingRequest, isNull);

      container.notifier(qrShareProvider).dialogOpened();
      container.notifier(qrShareProvider).offer(_peer());
      expect(container.read(qrShareProvider).pendingRequest, _peer());
    });

    test('asks every peer at most once per QR session and forgets it afterwards', () {
      final container = RefenaContainer();
      container.notifier(qrShareProvider).dialogOpened();

      container.notifier(qrShareProvider).offer(_peer());
      container.notifier(qrShareProvider).dismiss();
      expect(container.read(qrShareProvider).pendingRequest, isNull);

      // The same peer registering again (e.g. a periodic scan) does not ask again.
      container.notifier(qrShareProvider).offer(_peer());
      expect(container.read(qrShareProvider).pendingRequest, isNull);

      // The next QR session starts over.
      container.notifier(qrShareProvider).dialogClosed();
      container.notifier(qrShareProvider).dialogOpened();
      container.notifier(qrShareProvider).offer(_peer());
      expect(container.read(qrShareProvider).pendingRequest, _peer());
    });

    test('ignores requests without an open QR code and drops them when it closes', () {
      final container = RefenaContainer();
      container.notifier(qrShareProvider).dialogOpened();
      container.notifier(qrShareProvider).offer(_peer());
      expect(container.read(qrShareProvider).pendingRequest, isNotNull);

      container.notifier(qrShareProvider).dialogClosed();
      expect(container.read(qrShareProvider).pendingRequest, isNull);
    });
  });

  testWidgets('QR dialog offers to send files to a peer that scanned the QR code', (tester) async {
    final sender = _RecordingSender();
    final scope = RefenaScope(
      overrides: [
        sendProvider.overrideWithNotifier((ref) => sender),
        globalReduxProvider.overrideWithGlobalReducer(
          reducer: {
            PickFileAction: null,
          },
        ),
      ],
      child: Builder(
        builder: (context) {
          final navigatorKey = context.read(navigationProvider).key;
          Routerino.navigatorKey = navigatorKey;
          return MaterialApp(
            navigatorKey: navigatorKey,
            home: RouterinoHome(
              builder: () => Builder(
                builder: (context) => Scaffold(
                  body: Column(
                    children: [
                      Expanded(
                        // Attaches the home page controller so switching the tab works.
                        child: PageView(
                          controller: context.watch(homePageControllerProvider).controller,
                          children: const [SizedBox(), SizedBox(), SizedBox()],
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          await showDialog(
                            context: context,
                            builder: (_) => const QrDialog(data: 'http://10.0.0.1:53317'),
                          );
                        },
                        child: const Text('show'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
    await tester.pumpWidget(scope);
    await tester.pumpAndSettle();

    // Showing the QR code opens the QR session.
    scope.notifier(qrShareProvider).dialogOpened();
    await tester.tap(find.text('show'));
    await tester.pumpAndSettle();
    expect(find.byType(QrDialog), findsOneWidget);
    expect(find.byType(QrSendRequestPrompt), findsNothing);

    // The peer registered itself, which is how it announces its address.
    scope.notifier(qrShareProvider).offer(_peer());
    await tester.pumpAndSettle();
    expect(find.text(t.dialogs.qr.sendRequest(alias: 'Phone')), findsOneWidget);
    expect(sender.sessions, 0);

    // Cancelling keeps the QR dialog and does not send anything.
    await tester.tap(find.text(t.general.cancel));
    await tester.pumpAndSettle();
    expect(find.byType(QrSendRequestPrompt), findsNothing);
    expect(find.byType(QrDialog), findsOneWidget);
    expect(sender.sessions, 0);

    // A second request of the same peer is not asked again in this QR session.
    scope.notifier(qrShareProvider).offer(_peer());
    await tester.pumpAndSettle();
    expect(find.byType(QrSendRequestPrompt), findsNothing);

    // A new peer gets its own prompt; sending uses the regular sending flow.
    scope.notifier(qrShareProvider).offer(_peer(fingerprint: 'other-fingerprint'));
    await tester.pumpAndSettle();
    expect(find.text(t.dialogs.qr.sendRequest(alias: 'Phone')), findsOneWidget);

    await tester.tap(find.text(t.dialogs.qr.sendFiles));
    await tester.pumpAndSettle();

    expect(find.byType(QrDialog), findsNothing);
    expect(find.byType(AddFileDialog), findsOneWidget);
    expect(sender.sessions, 0);

    scope.redux(selectedSendingFilesProvider).dispatch(AddMessageAction(message: 'phone receive test'));
    await tester.tap(find.descendant(of: find.byType(AddFileDialog), matching: find.text(t.sendTab.picker.file)));
    await tester.pumpAndSettle();

    expect(sender.sessions, 1);
    expect(sender.target!.ip, '10.0.0.2');
    expect(sender.target!.port, 53317);
    expect(sender.target!.fingerprint, 'other-fingerprint');
    expect(sender.files!.single.bytes, 'phone receive test'.codeUnits);
    expect(tester.takeException(), isNull);
  }, variant: const TargetPlatformVariant({TargetPlatform.android, TargetPlatform.windows}));

  testWidgets('a register that arrives while the QR code is shown offers the peer', (tester) async {
    late Ref ref;
    await tester.pumpWidget(
      RefenaScope(
        child: Builder(
          builder: (context) {
            ref = context.ref;
            return const SizedBox();
          },
        ),
      ),
    );

    final service = ref.notifier(qrShareProvider);

    // Without a QR code on screen, a registration is just discovery.
    service.onRegister(device: _peer(), ownFingerprint: 'own-fingerprint');
    expect(ref.read(qrShareProvider).pendingRequest, isNull);

    // While the QR code is shown, the registering peer is offered.
    service.dialogOpened();
    service.onRegister(device: _peer(), ownFingerprint: 'own-fingerprint');
    final pending = ref.read(qrShareProvider).pendingRequest;
    expect(pending, isNotNull);
    expect(pending!.ip, '10.0.0.2');
    expect(pending.alias, 'Phone');
    expect(pending.port, 53317);

    // A device that registers with this device's own fingerprint is ignored.
    service.dialogClosed();
    service.dialogOpened();
    service.onRegister(
      device: _peer(fingerprint: 'own-fingerprint'),
      ownFingerprint: 'own-fingerprint',
    );
    expect(ref.read(qrShareProvider).pendingRequest, isNull);

    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
