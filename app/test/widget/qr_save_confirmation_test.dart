import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/config/theme.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/persistence/color_mode.dart';
import 'package:localsend_app/model/persistence/quick_save_mode.dart';
import 'package:localsend_app/model/state/server/server_state.dart';
import 'package:localsend_app/pages/receive_page.dart';
import 'package:localsend_app/provider/network/server/controller/receive_controller.dart';
import 'package:localsend_app/provider/network/server/server_provider.dart';
import 'package:localsend_app/provider/network/server/server_utils.dart';
import 'package:localsend_app/provider/persistence_provider.dart';
import 'package:localsend_app/provider/qr_share_provider.dart';
import 'package:localsend_app/util/desktop_pairing_invitation.dart';
import 'package:localsend_isolates/isolate.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/model/dto/multicast_dto.dart';
import 'package:localsend_isolates/rust/api/model.dart' as rust;
import 'package:localsend_isolates/rust/api/server.dart' as native;
import 'package:mockito/mockito.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

import '../mocks.mocks.dart';

class _Sync extends Mock implements SyncState {
  @override
  String get alias => 'Receiver';
  @override
  int get port => 53317;
  @override
  ProtocolType get protocol => ProtocolType.https;
  @override
  bool get serverRunning => true;
  @override
  bool get download => false;
}

class _Parent extends Mock implements ParentIsolateState {
  @override
  SyncState get syncState => _Sync();
}

class _Server extends ServerService {
  final ServerState Function() current;
  int declined = 0;
  int accepted = 0;
  _Server(this.current);
  @override
  ServerState init() => current();
  void update(ServerState next) => state = next;
  @override
  void declineFileRequest() => declined++;
  @override
  Future<void> acceptFileRequest(Map<String, String> names) async => accepted++;
}

class _Receiver extends ReceiveController {
  int accepted = 0;
  _Receiver(super.server);
  @override
  Future<void> acceptFileRequest(Map<String, String> names) async => accepted++;
}

void main() {
  setUp(() {
    LocaleSettings.setLocaleSync(AppLocale.en);
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in ['plugins.flutter.io/path_provider', 'main-delegate-channel', 'windows_taskbar', 'wakelock_plus']) {
      messenger.setMockMethodCallHandler(MethodChannel(channel), (call) async => channel.contains('path_provider') ? '/tmp' : null);
    }
    messenger.setMockMethodCallHandler(const MethodChannel('window_manager'), (call) async => call.method == 'isMinimized' ? false : true);
  });
  for (final scenario in ['confirm', 'accept', 'decline', 'auto save', 'global auto save', 'unrelated sender', 'normal transfer']) {
    testWidgets('QR receive policy: $scenario', (tester) async {
      final persistence = MockPersistenceService();
      when(persistence.getDestination()).thenReturn('/tmp');
      when(persistence.getQrConnectionAutoSave()).thenReturn(scenario == 'auto save' || scenario == 'unrelated sender');
      when(
        persistence.getQuickSave(),
      ).thenReturn(scenario == 'global auto save' || scenario == 'normal transfer' ? QuickSaveMode.on : QuickSaveMode.off);
      var state = const ServerState(alias: 'Receiver', port: 53317, https: true, session: null, web: null);
      final server = _Server(() => state);
      final parent = _Parent();
      final scope = RefenaScope(
        overrides: [
          persistenceProvider.overrideWithValue(persistence),
          parentIsolateProvider.overrideWithNotifier((_) => IsolateController(initialState: parent)),
          serverProvider.overrideWithNotifier((_) => server),
        ],
        child: Builder(
          builder: (context) {
            final key = context.read(navigationProvider).key;
            Routerino.navigatorKey = key;
            return MaterialApp(navigatorKey: key, theme: getTheme(ColorMode.localsend, Colors.teal, Brightness.light, null), home: const Scaffold());
          },
        ),
      );
      await tester.pumpWidget(scope);
      if (scenario != 'normal transfer') {
        scope
            .notifier(qrShareProvider)
            .connectionFinished(
              peer: Device.empty.copyWith(fingerprint: (scenario == 'unrelated sender' ? 'C' : 'B') * 64),
              role: PairingRole.receive,
            );
      }
      final receiver = _Receiver(
        ServerUtils(
          refFunc: () => scope,
          getState: () => state,
          getStateOrNull: () => state,
          setState: (builder) {
            state = builder(state)!;
            server.update(state);
          },
        ),
      );
      final event = HttpServerPrepareUploadEvent(
        sessionId: 'files',
        ip: '192.168.1.20',
        certFingerprint: 'B' * 64,
        info: native.RegisterDtoV2(
          alias: 'Sender',
          version: '2.2',
          fingerprint: 'B' * 64,
          port: 53317,
          protocol: rust.ProtocolType.https,
          download: false,
        ),
        files: {'file': rust.FileDto(id: 'file', fileName: 'test.txt', size: BigInt.from(12), fileType: 'application/octet-stream')},
      );
      await tester.runAsync(() => receiver.onPrepareUpload(event));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump(const Duration(milliseconds: 100));
      final autoSave = scenario == 'auto save' || scenario == 'normal transfer';
      expect(receiver.accepted, autoSave ? 1 : 0);
      expect(find.byType(ReceivePage), autoSave ? findsNothing : findsOneWidget);
      expect(state.session!.isQrConnection, scenario != 'unrelated sender' && scenario != 'normal transfer');
      if (!autoSave) {
        expect(find.text(t.general.accept), findsOneWidget);
        expect(find.text(t.general.decline), findsOneWidget);
        if (scenario == 'accept') {
          await tester.tap(find.text(t.general.accept));
          await tester.pump(const Duration(milliseconds: 100));
          expect(server.accepted, 1);
        }
        if (scenario == 'decline') {
          await tester.tap(find.text(t.general.decline));
          await tester.pump();
          expect(server.declined, greaterThanOrEqualTo(1));
          expect(receiver.accepted, 0);
        }
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }, variant: const TargetPlatformVariant({TargetPlatform.android, TargetPlatform.macOS, TargetPlatform.windows}));
  }
}
