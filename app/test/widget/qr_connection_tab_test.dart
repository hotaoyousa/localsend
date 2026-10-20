import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/state/network_state.dart';
import 'package:localsend_app/model/state/server/server_state.dart';
import 'package:localsend_app/pages/home_page.dart';
import 'package:localsend_app/pages/home_page_controller.dart';
import 'package:localsend_app/pages/tabs/qr_connection_tab.dart';
import 'package:localsend_app/provider/local_ip_provider.dart';
import 'package:localsend_app/provider/network/server/server_provider.dart';
import 'package:localsend_app/provider/persistence_provider.dart';
import 'package:localsend_app/provider/qr_share_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/util/desktop_pairing_invitation.dart';
import 'package:localsend_app/widget/dialogs/qr_dialog.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:mockito/mockito.dart';
import 'package:refena_flutter/refena_flutter.dart';

import '../mocks.mocks.dart';

class _Ips extends LocalIpService {
  _Ips(super.settingsService);
  @override
  NetworkState init() => const NetworkState(localIps: ['10.29.252.119', '192.168.1.100'], initialized: true);
  @override
  get initialAction => null;
}

class _Server extends ServerService {
  @override
  ServerState? init() => const ServerState(alias: 'This device', port: 53317, https: true, session: null, web: null);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (Platform.environment['QR_HUB_PREVIEW_DIR'] != null) {
      for (final entry in {
        'Roboto': '/System/Library/Fonts/Supplemental/Arial Unicode.ttf',
        'MaterialIcons':
            '/Users/hutao/Desktop/localsend/.tooling/fvm-cache/versions/3.41.9/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      }.entries) {
        final loader = FontLoader(entry.key)..addFont(File(entry.value).readAsBytes().then((bytes) => ByteData.sublistView(bytes)));
        await loader.load();
      }
    }
  });
  setUp(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
  });
  test('QR connection is a top-level tab between Send and Settings', () {
    expect(HomeTab.values, [HomeTab.receive, HomeTab.send, HomeTab.qrConnection, HomeTab.settings]);
    expect(HomeTab.qrConnection.label, t.qrConnection.title);
  });
  for (final platform in [TargetPlatform.android, TargetPlatform.macOS, TargetPlatform.windows]) {
    testWidgets('QR hub mobile actions and LAN codes fit on $platform', (tester) async {
      final mobile = platform == TargetPlatform.android;
      await tester.binding.setSurfaceSize(mobile ? const Size(320, 850) : const Size(1100, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final persistence = MockPersistenceService();
      when(persistence.getReceivePin()).thenReturn('4321');
      final boundaryKey = GlobalKey();
      final scope = RefenaScope(
        overrides: [
          persistenceProvider.overrideWithValue(persistence),
          localIpProvider.overrideWithNotifier((ref) => _Ips(ref.notifier(settingsProvider))),
          serverProvider.overrideWithNotifier((_) => _Server()),
        ],
        child: MaterialApp(
          theme: ThemeData(fontFamily: 'Roboto', colorSchemeSeed: Colors.teal),
          home: RepaintBoundary(key: boundaryKey, child: const QrConnectionTab()),
        ),
      );
      await tester.pumpWidget(scope);
      scope.notifier(qrShareProvider).setHubActive(true);
      await tester.pumpAndSettle();
      expect(find.text(t.qrConnection.scanSend), mobile ? findsOneWidget : findsNothing);
      expect(find.text(t.qrConnection.scanReceive), mobile ? findsOneWidget : findsNothing);
      expect(find.text(t.qrConnection.linkComputers), mobile ? findsOneWidget : findsNothing);
      expect(find.text(t.qrConnection.chooseNetwork), findsOneWidget);
      expect(find.text('https://10.29.252.119:53317'), findsOneWidget);
      expect(find.text('https://192.168.1.100:53317'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final preview = Platform.environment['QR_HUB_PREVIEW_DIR'];
      if (preview != null) {
        await tester.runAsync(() async {
          final boundary = boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1.5);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(preview).create(recursive: true);
          await File('$preview/${platform.name}.png').writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        await tester.pump();
      }
      await tester.ensureVisible(find.byTooltip(t.qrConnection.showCode).first);
      await tester.tap(find.byTooltip(t.qrConnection.showCode).first);
      await tester.pumpAndSettle();
      final dialog = tester.widget<QrDialog>(find.byType(QrDialog));
      expect(dialog.data, 'https://10.29.252.119:53317?pin=4321');
      expect(dialog.showSendRequest, false);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(platform));
  }
  test('hub registration never guesses a send request; leaving clears auto receive', () {
    final scope = RefenaContainer();
    final service = scope.notifier(qrShareProvider);
    final peer = Device.empty.copyWith(fingerprint: 'B' * 64, alias: 'Sender');
    service.setHubActive(true);
    service.offer(peer);
    expect(scope.read(qrShareProvider).pendingRequest, isNull);
    service.connectionFinished(peer: peer, role: PairingRole.receive);
    expect(scope.read(qrShareProvider).connectedPeer, peer);
    service.setHubActive(false);
    expect(scope.read(qrShareProvider).connectedPeer, isNull);
    expect(scope.read(qrShareProvider).role, isNull);
  });
  testWidgets('navigation activates QR listening only on its own tab', (tester) async {
    final scope = RefenaScope(
      child: Builder(
        builder: (context) => MaterialApp(
          home: PageView(
            controller: context.watch(homePageControllerProvider).controller,
            children: const [SizedBox(), SizedBox(), SizedBox(), SizedBox()],
          ),
        ),
      ),
    );
    await tester.pumpWidget(scope);
    await tester.pumpAndSettle();
    scope.redux(homePageControllerProvider).dispatch(ChangeTabAction(HomeTab.qrConnection));
    await tester.pumpAndSettle();
    expect(scope.read(qrShareProvider).hubActive, true);
    scope.redux(homePageControllerProvider).dispatch(ChangeTabAction(HomeTab.settings));
    await tester.pumpAndSettle();
    expect(scope.read(qrShareProvider).hubActive, false);
  });
}
