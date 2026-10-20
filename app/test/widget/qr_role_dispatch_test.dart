import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/state/server/server_state.dart';
import 'package:localsend_app/pages/home_page.dart';
import 'package:localsend_app/pages/home_page_controller.dart';
import 'package:localsend_app/provider/desktop_pairing_provider.dart';
import 'package:localsend_app/provider/device_info_provider.dart';
import 'package:localsend_app/provider/network/server/controller/receive_controller.dart';
import 'package:localsend_app/provider/network/server/server_utils.dart';
import 'package:localsend_app/provider/qr_share_provider.dart';
import 'package:localsend_app/util/desktop_pairing_invitation.dart';
import 'package:localsend_app/widget/dialogs/add_file_dialog.dart';
import 'package:localsend_app/widget/dialogs/desktop_pairing_dialog.dart';
import 'package:localsend_isolates/isolate.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/rust/api/model.dart' as rust;
import 'package:localsend_isolates/rust/api/server.dart' as native;
import 'package:mockito/mockito.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

class _ParentState extends Mock implements ParentIsolateState {}

class _Pairing extends Mock implements DesktopPairingService {
  final peers = <DesktopPairingInvitation>[];
  bool fail = false;
  Completer<void>? gate;
  @override
  Future<Device> connect(DesktopPairingInvitation peer) async {
    peers.add(peer);
    await gate?.future;
    if (fail) throw StateError('Unreachable');
    return Device.empty.copyWith(ip: peer.ip, fingerprint: peer.fingerprint, alias: peer.alias);
  }
}

class _Actions extends RefenaObserver {
  final decisions = <IsolateHttpServerPrepareUploadDecisionAction>[];
  @override
  void handleEvent(RefenaEvent event) {
    if (event is ActionDispatchedEvent && event.action is IsolateHttpServerPrepareUploadDecisionAction) {
      decisions.add(event.action as IsolateHttpServerPrepareUploadDecisionAction);
    }
  }
}

HttpServerPrepareUploadEvent _invitation(PairingRole role, {bool phone = false}) {
  final peer = DesktopPairingInvitation(
    ip: '192.168.1.20',
    port: 54321,
    https: true,
    fingerprint: (phone ? 'C' : 'B') * 64,
    alias: 'Peer',
    role: role,
  );
  return HttpServerPrepareUploadEvent(
    sessionId: 'pairing',
    ip: '192.168.1.30',
    certFingerprint: 'C' * 64,
    info: native.RegisterDtoV2(
      alias: 'Phone',
      version: '2.2',
      fingerprint: 'C' * 64,
      port: 53317,
      protocol: rust.ProtocolType.https,
      download: false,
    ),
    files: {
      'peer': rust.FileDto(
        id: 'peer',
        fileName: 'connection.localsend-pair',
        size: BigInt.from(300),
        fileType: DesktopPairingInvitation.mimeType,
        preview: peer.encode(),
      ),
    },
  );
}

void main() {
  setUp(() {
    LocaleSettings.setLocaleSync(AppLocale.en);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      (call) async => call.method.startsWith('is') ? false : null,
    );
  });
  for (final scenario in ['send', 'receive', 'unreachable', 'closed', 'aborted', 'phone']) {
    testWidgets('explicit QR role $scenario is dispatched without role dialog', (tester) async {
      final pairing = _Pairing()..fail = scenario == 'unreachable';
      if (scenario == 'aborted') pairing.gate = Completer<void>();
      final observer = _Actions();
      final parent = _ParentState();
      final scope = RefenaScope(
        observers: [observer],
        overrides: [
          desktopPairingProvider.overrideWithValue(pairing),
          deviceFullInfoProvider.overrideWithBuilder((_) => Device.empty.copyWith(fingerprint: 'A' * 64)),
          parentIsolateProvider.overrideWithReducer(
            notifier: (_) => IsolateController(initialState: parent),
            reducer: {
              IsolateDiscoveryAddDeviceAction: (state) => state,
              IsolateHttpServerPrepareUploadDecisionAction: (state) => state,
            },
          ),
        ],
        child: Builder(
          builder: (context) {
            final key = context.read(navigationProvider).key;
            Routerino.navigatorKey = key;
            return MaterialApp(
              navigatorKey: key,
              home: PageView(
                controller: context.watch(homePageControllerProvider).controller,
                children: const [SizedBox(), SizedBox(), SizedBox(), SizedBox()],
              ),
            );
          },
        ),
      );
      await tester.pumpWidget(scope);
      await tester.pumpAndSettle();
      if (scenario != 'closed') scope.redux(homePageControllerProvider).dispatch(ChangeTabAction(HomeTab.qrConnection));
      final controller = ReceiveController(
        ServerUtils(
          refFunc: () => scope,
          getState: () => const ServerState(alias: 'A', port: 53317, https: true, session: null, web: null),
          getStateOrNull: () => null,
          setState: (_) => throw StateError('Must not create a file transfer session'),
        ),
      );
      final role = scenario == 'send' ? PairingRole.send : PairingRole.receive;
      final request = controller.onPrepareUpload(_invitation(role, phone: scenario == 'phone'));
      await tester.pumpAndSettle();
      if (scenario == 'aborted') {
        controller.onPrepareUploadAborted(HttpServerPrepareUploadAbortedEvent(sessionId: 'pairing'));
        pairing.gate!.complete();
      }
      await request;
      await tester.pumpAndSettle();
      expect(find.byType(DesktopPairingDialog), findsNothing);
      if (scenario == 'closed') {
        expect(pairing.peers, isEmpty);
        expect(observer.decisions.single.config, isNull);
      } else if (scenario == 'aborted') {
        expect(observer.decisions, isEmpty);
        expect(scope.read(qrShareProvider).connecting, false);
      } else if (scenario == 'unreachable') {
        expect(observer.decisions.single.config, isNull);
        expect(scope.read(qrShareProvider).failed, true);
      } else {
        expect(observer.decisions.single.config!.fileNameMap, isEmpty);
        if (scenario == 'send') {
          expect(find.byType(AddFileDialog), findsOneWidget);
          expect(scope.read(homePageControllerProvider).currentTab, HomeTab.send);
        } else {
          expect(find.byType(AddFileDialog), findsNothing);
          expect(scope.read(qrShareProvider).role, PairingRole.receive);
          expect(scope.read(qrShareProvider).connectedPeer, isNotNull);
        }
        if (scenario == 'phone') expect(pairing.peers.single.ip, '192.168.1.30');
      }
      expect(tester.takeException(), isNull);
    }, variant: const TargetPlatformVariant({TargetPlatform.macOS, TargetPlatform.windows}));
  }
}
