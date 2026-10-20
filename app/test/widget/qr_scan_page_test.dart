import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/config/theme.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/model/persistence/color_mode.dart';
import 'package:localsend_app/model/send_mode.dart';
import 'package:localsend_app/pages/desktop_pairing_page.dart';
import 'package:localsend_app/pages/qr_scan_page.dart';
import 'package:localsend_app/pages/tabs/send_tab.dart';
import 'package:localsend_app/pages/tabs/send_tab_vm.dart';
import 'package:localsend_app/provider/animation_provider.dart';
import 'package:localsend_app/provider/desktop_pairing_provider.dart';
import 'package:localsend_app/provider/device_info_provider.dart';
import 'package:localsend_app/provider/favorites_provider.dart';
import 'package:localsend_app/provider/http_provider.dart';
import 'package:localsend_app/provider/last_devices.provider.dart';
import 'package:localsend_app/provider/local_ip_provider.dart';
import 'package:localsend_app/provider/logging/discovery_logs_provider.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_app/provider/network/send_provider.dart';
import 'package:localsend_app/provider/persistence_provider.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/util/native/file_picker.dart';
import 'package:localsend_app/util/qr_connection_info.dart';
import 'package:localsend_app/widget/dialogs/add_file_dialog.dart';
import 'package:localsend_app/widget/dialogs/address_input_dialog.dart';
import 'package:localsend_isolates/isolate.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/rust/api/cancel.dart';
import 'package:localsend_isolates/rust/api/http.dart' as rust_http;
import 'package:localsend_isolates/rust/api/model.dart' as rust_model;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:mockito/mockito.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

import '../mocks.mocks.dart';

class _ScannerPlatform extends MobileScannerPlatform {
  final captures = StreamController<BarcodeCapture?>.broadcast();
  MobileScannerException? error;
  int starts = 0;
  int stops = 0;
  int disposals = 0;

  @override
  Stream<BarcodeCapture?> get barcodesStream => captures.stream;

  @override
  Stream<TorchState> get torchStateStream => const Stream.empty();

  @override
  Stream<double> get zoomScaleStateStream => const Stream.empty();

  @override
  Future<MobileScannerViewAttributes> start(StartOptions options) async {
    if (error != null) {
      throw error!;
    }
    starts++;
    return const MobileScannerViewAttributes(
      cameraDirection: CameraFacing.back,
      currentTorchMode: TorchState.unavailable,
      size: Size(640, 480),
    );
  }

  @override
  Widget buildCameraView() => const ColoredBox(color: Colors.black);

  @override
  Future<void> stop() async => stops++;

  @override
  Future<void> dispose() async => disposals++;

  void detect(String value) {
    captures.add(
      BarcodeCapture(
        barcodes: [Barcode(format: BarcodeFormat.qrCode, rawValue: value)],
      ),
    );
  }
}

class _IsolateController extends Mock implements IsolateController {}

class _FavoritesService extends Mock implements FavoritesService {}

class _DiscoveryLogger extends Mock implements DiscoveryLogger {}

class _TestLocalIpService extends LocalIpService {
  _TestLocalIpService(super.settingsService);
  @override
  get initialAction => null;
}

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

class _RegisterClient extends Mock implements rust_http.RsHttpClient {
  String? ip;
  int? port;
  rust_model.ProtocolType? protocol;
  rust_model.RegisterDto? payload;
  bool fail = false;
  @override
  Future<rust_http.ResultWithPublicKeyRegisterResponseDto> register({
    required rust_model.ProtocolType protocol,
    required String ip,
    required int port,
    required rust_model.RegisterDto payload,
  }) async {
    this.ip = ip;
    this.port = port;
    this.protocol = protocol;
    this.payload = payload;
    if (fail) throw Exception('Receiver unavailable');
    return const rust_http.ResultWithPublicKeyRegisterResponseDto(
      body: rust_model.RegisterResponseDto(
        alias: 'QR receiver',
        version: '2.2',
        token: 'receiver-fingerprint',
        hasWebInterface: true,
      ),
    );
  }
}

class _PairToken extends Mock implements RsCancellationToken {}

class _PairingService extends Mock implements DesktopPairingService {
  final attempts = <String>[];
  bool failB = true;
  @override
  RsCancellationToken Function() get createToken => _PairToken.new;
  @override
  Future<Device> discover(QrConnectionInfo endpoint) async => _localDevice.copyWith(
    ip: endpoint.ip,
    port: endpoint.port,
    https: endpoint.https,
    fingerprint: (endpoint.ip.endsWith('.10') ? 'A' : 'B') * 64,
    alias: endpoint.ip.endsWith('.10') ? 'First PC' : 'Second PC',
    deviceType: DeviceType.desktop,
  );
  @override
  Future<void> introduce({required Device recipient, required Device peer, required RsCancellationToken token, String? pin}) async {
    attempts.add(recipient.alias);
    if (recipient.alias == 'Second PC' && failB) {
      failB = false;
      throw StateError('Connection failed');
    }
  }
}

final _localDevice = Device(
  signalingId: null,
  ip: '10.0.0.1',
  version: '2.2',
  port: 53317,
  https: true,
  fingerprint: 'sender-fingerprint',
  alias: 'Sender',
  deviceModel: null,
  deviceType: DeviceType.mobile,
  download: false,
  channels: [],
);

void main() {
  late _ScannerPlatform scanner;
  late MobileScannerPlatform previousPlatform;

  setUp(() {
    previousPlatform = MobileScannerPlatform.instance;
    MobileScannerController.resetPlatformSessionOwner();
    scanner = _ScannerPlatform();
    MobileScannerPlatform.instance = scanner;
    LocaleSettings.setLocaleSync(AppLocale.en);
  });

  tearDown(() async {
    await scanner.captures.close();
    MobileScannerPlatform.instance = previousPlatform;
  });

  testWidgets('Android phone scans two computers, refuses duplicates and retries only failed side', (tester) async {
    final pairing = _PairingService();
    await tester.pumpWidget(
      RefenaScope(
        overrides: [desktopPairingProvider.overrideWithValue(pairing)],
        child: const MaterialApp(home: DesktopPairingPage()),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> scan(int index, String address) async {
      await tester.tap(find.byIcon(Icons.qr_code_scanner).at(index));
      await tester.pumpAndSettle();
      scanner.detect(address);
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.desktopPairing.useComputer));
      await tester.pumpAndSettle();
    }

    await scan(0, 'https://192.168.1.10:54321');
    await scan(1, 'https://192.168.1.10:54321');
    expect(find.text(t.desktopPairing.failed), findsOneWidget);
    expect(pairing.attempts, isEmpty);
    await scan(1, 'http://192.168.1.20:54322');
    await tester.tap(find.text(t.desktopPairing.connect));
    await tester.pumpAndSettle();
    expect(pairing.attempts, ['First PC', 'Second PC']);
    expect(find.text(t.desktopPairing.done), findsNothing);
    await tester.tap(find.text(t.qrScanPage.retryConnection));
    await tester.pumpAndSettle();
    expect(pairing.attempts, ['First PC', 'Second PC', 'Second PC']);
    expect(find.text(t.desktopPairing.done), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('scanner provides an entry to connect two computers', (tester) async {
    await tester.pumpWidget(RefenaScope(child: const MaterialApp(home: QrScanPage())));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(t.desktopPairing.title));
    await tester.pumpAndSettle();
    expect(find.byType(DesktopPairingPage), findsOneWidget);
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS, TargetPlatform.macOS]) {
    testWidgets('send page scanner entry on $platform', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        RefenaScope(
          overrides: [
            sendTabVmProvider.overrideWithBuilder(
              (ref) => SendTabVm(
                sendMode: SendMode.single,
                selectedFiles: [],
                localIps: [],
                nearbyDevices: [],
                favoriteDevices: [],
                onTapQr: (context) async {
                  await context.push(() => const QrScanPage());
                },
                onTapAddress: (_) async {},
                onTapFavorite: (_) async {},
                onTapSendMode: (_, _) async {},
                onTapDevice: (_, _) async {},
                onTapDeviceMultiSend: (_, _) async {},
              ),
            ),
            animationProvider.overrideWithBuilder((ref) => false),
            nearbyDevicesProvider.overrideWithNotifier(
              (ref) => NearbyDevicesService(
                isolateController: _IsolateController(),
                favoriteService: _FavoritesService(),
                discoveryLogs: _DiscoveryLogger(),
              ),
            ),
            globalReduxProvider.overrideWithGlobalReducer(reducer: {SendTabInitAction: null}),
          ],
          child: const MaterialApp(home: Scaffold(body: SendTab())),
        ),
      );
      await tester.pumpAndSettle();
      final entry = find.byIcon(Icons.qr_code_scanner);
      if (platform == TargetPlatform.macOS) {
        expect(entry, findsNothing);
      } else {
        expect(entry, findsOneWidget);
        expect(tester.getCenter(entry).dy, tester.getCenter(find.byIcon(Icons.ads_click)).dy);
        await tester.tap(entry);
        await tester.pumpAndSettle();
        expect(find.byType(QrScanPage), findsOneWidget);
        expect(find.byType(MobileScanner), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 50));
    }, variant: TargetPlatformVariant({platform}));
  }

  for (final scenario in ['choose file', 'already selected', 'cancel file picker', 'unreachable receiver', 'cancel scan']) {
    testWidgets('QR sending workflow: $scenario', (tester) async {
      final persistence = MockPersistenceService();
      when(persistence.getPort()).thenReturn(53317);
      when(persistence.isHttps()).thenReturn(true);
      final client = _RegisterClient()..fail = scenario == 'unreachable receiver';
      final sender = _RecordingSender();
      final scope = RefenaScope(
        overrides: [
          persistenceProvider.overrideWithValue(persistence),
          deviceFullInfoProvider.overrideWithBuilder((ref) => _localDevice),
          localIpProvider.overrideWithNotifier((ref) => _TestLocalIpService(ref.notifier(settingsProvider))),
          httpProvider.overrideWithBuilder((ref) => HttpClientCollection(privateKey: '', certificate: '', discovery: client)),
          qrDiscoveryClientProvider.overrideWithBuilder((ref) => client),
          sendProvider.overrideWithNotifier((ref) => sender),
          nearbyDevicesProvider.overrideWithNotifier(
            (ref) => NearbyDevicesService(
              isolateController: _IsolateController(),
              favoriteService: _FavoritesService(),
              discoveryLogs: _DiscoveryLogger(),
            ),
          ),
          animationProvider.overrideWithBuilder((ref) => false),
          globalReduxProvider.overrideWithGlobalReducer(
            reducer: {
              SendTabInitAction: null,
              PickFileAction: null,
            },
          ),
        ],
        child: Builder(
          builder: (context) => MaterialApp(
            navigatorKey: context.read(navigationProvider).key,
            theme: getTheme(ColorMode.localsend, Colors.teal, Brightness.light, null),
            home: RouterinoHome(builder: () => const Scaffold(body: SendTab())),
          ),
        ),
      );
      await tester.pumpWidget(scope);
      await tester.pumpAndSettle();
      if (scenario == 'already selected') {
        scope.redux(selectedSendingFilesProvider).dispatch(AddMessageAction(message: 'QR transfer test'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byIcon(Icons.qr_code_scanner));
      await tester.pumpAndSettle();
      if (scenario == 'cancel scan') {
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(client.ip, isNull);
        expect(sender.sessions, 0);
      } else {
        scanner.detect('http://192.168.1.20:54321/?pin=1234');
        await tester.pumpAndSettle();
        await tester.tap(find.text(t.sendTab.title));
        await tester.pumpAndSettle();
        expect(client.ip, '192.168.1.20');
        expect(client.port, 54321);
        expect(client.protocol, rust_model.ProtocolType.http);
        if (scenario == 'unreachable receiver') {
          expect(find.byType(AddressInputDialog), findsOneWidget);
          expect(find.text(t.general.error), findsOneWidget);
          expect(find.text(t.qrScanPage.connectionFailed), findsOneWidget);
          expect(sender.sessions, 0);
          client.fail = false;
          await tester.tap(find.text(t.qrScanPage.retryConnection));
          await tester.pumpAndSettle();
          expect(find.byType(AddressInputDialog), findsNothing);
          expect(find.text(t.qrScanPage.connectionFailed), findsNothing);
          expect(find.byType(AddFileDialog), findsOneWidget);
          expect(client.port, 54321);
          expect(client.protocol, rust_model.ProtocolType.http);
          scope.read(navigationProvider).pop();
          await tester.pumpAndSettle();
          expect(sender.sessions, 0);
        } else if (scenario == 'cancel file picker') {
          expect(find.byType(AddFileDialog), findsOneWidget);
          scope.read(navigationProvider).pop();
          await tester.pumpAndSettle();
          expect(sender.sessions, 0);
        } else {
          if (scenario == 'choose file') {
            expect(find.byType(AddFileDialog), findsOneWidget);
            // Supply the native picker result without opening the host file picker.
            scope.redux(selectedSendingFilesProvider).dispatch(AddMessageAction(message: 'QR transfer test'));
            await tester.tap(find.descendant(of: find.byType(AddFileDialog), matching: find.text(t.sendTab.picker.file)));
            await tester.pumpAndSettle();
            expect(find.byType(AddFileDialog), findsNothing);
          }
          expect(sender.sessions, 1);
          expect(sender.target!.ip, '192.168.1.20');
          expect(sender.target!.port, 54321);
          expect(sender.target!.https, isFalse);
          expect(sender.target!.fingerprint, 'receiver-fingerprint');
          expect(sender.files!.single.bytes, 'QR transfer test'.codeUnits);
          expect(scope.read(lastDevicesProvider).single, sender.target);
        }
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 50));
    }, variant: const TargetPlatformVariant({TargetPlatform.android, TargetPlatform.iOS}));
  }

  testWidgets('shows and copies only the first valid IP, stops camera, and scans again', (tester) async {
    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copiedText = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(const MaterialApp(home: QrScanPage()));
    await tester.pumpAndSettle();

    scanner.detect('https://192.168.1.20:53317/?pin=1234');
    scanner.detect('http://10.0.0.1:53317');
    await tester.pumpAndSettle();
    // Stream cancellation completes outside the widget test clock.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(find.text('192.168.1.20'), findsOneWidget);
    expect(find.text('10.0.0.1'), findsNothing);
    expect(find.byType(MobileScanner), findsNothing);
    expect(scanner.stops, 1);
    expect(scanner.disposals, 1);

    await tester.tap(find.text(t.general.copy));
    await tester.pumpAndSettle();
    expect(copiedText, '192.168.1.20');

    await tester.tap(find.text(t.qrScanPage.scanAgain));
    await tester.pumpAndSettle();
    expect(find.byType(MobileScanner), findsOneWidget);
    expect(scanner.starts, 2);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    // Stream cancellation completes outside the widget test clock.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  });

  testWidgets('returns the scanned endpoint to the sending flow only after confirmation', (tester) async {
    QrConnectionInfo? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await Navigator.of(context).push<QrConnectionInfo>(MaterialPageRoute(builder: (_) => const QrScanPage()));
              },
              child: const Text('scan'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('scan'));
    await tester.pumpAndSettle();
    scanner.detect('http://192.168.1.20:54321/?pin=1234');
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(find.text('http://192.168.1.20:54321'), findsOneWidget);
    await tester.tap(find.text(t.sendTab.title));
    await tester.pumpAndSettle();
    expect(result!.ip, '192.168.1.20');
    expect(result!.port, 54321);
    expect(result!.https, isFalse);
    expect(find.byType(QrScanPage), findsNothing);
  });

  for (final scenario in ['reachable receiver', 'unreachable receiver then retry']) {
    testWidgets('QR receive workflow: $scenario', (tester) async {
      final client = _RegisterClient()..fail = scenario != 'reachable receiver';
      final sender = _RecordingSender();
      await tester.pumpWidget(
        RefenaScope(
          overrides: [
            deviceFullInfoProvider.overrideWithBuilder((ref) => _localDevice),
            qrDiscoveryClientProvider.overrideWithBuilder((ref) => client),
            sendProvider.overrideWithNotifier((ref) => sender),
          ],
          child: const MaterialApp(home: QrScanPage()),
        ),
      );
      await tester.pumpAndSettle();
      scanner.detect('http://192.168.1.20:54321/?pin=1234');
      await tester.pumpAndSettle();
      expect(find.text(t.qrScanPage.receive), findsOneWidget);

      await tester.tap(find.text(t.qrScanPage.receive));
      await tester.pumpAndSettle();

      // The announcement is the regular register request carrying this device's address.
      expect(client.ip, '192.168.1.20');
      expect(client.port, 54321);
      expect(client.protocol, rust_model.ProtocolType.http);
      expect(client.payload!.port, 53317);
      expect(client.payload!.protocol, rust_model.ProtocolType.https);
      expect(client.payload!.alias, 'Sender');
      expect(client.payload!.token, 'sender-fingerprint');
      // Receiving must not start a sending session.
      expect(sender.sessions, 0);

      if (scenario == 'reachable receiver') {
        expect(find.text(t.qrScanPage.receiveWaiting(alias: 'QR receiver')), findsOneWidget);
        expect(find.text(t.qrScanPage.connectionFailed), findsNothing);
      } else {
        expect(find.text(t.qrScanPage.connectionFailed), findsOneWidget);
        expect(find.text(t.qrScanPage.receiveWaiting(alias: 'QR receiver')), findsNothing);

        client.fail = false;
        await tester.tap(find.text(t.qrScanPage.retryConnection));
        await tester.pumpAndSettle();
        expect(find.text(t.qrScanPage.connectionFailed), findsNothing);
        expect(find.text(t.qrScanPage.receiveWaiting(alias: 'QR receiver')), findsOneWidget);
      }

      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 50));
    }, variant: const TargetPlatformVariant({TargetPlatform.android, TargetPlatform.iOS}));
  }

  testWidgets('an invalid QR code leaves the scanner ready for a valid code', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: QrScanPage()));
    await tester.pumpAndSettle();
    scanner.detect('https://example.com');
    await tester.pumpAndSettle();
    expect(find.text(t.qrScanPage.invalidCode), findsOneWidget);
    expect(find.byType(MobileScanner), findsOneWidget);
    scanner.detect('http://10.0.0.5:53317');
    await tester.pumpAndSettle();
    expect(find.text('10.0.0.5'), findsOneWidget);
  });

  testWidgets('permission denial offers settings and a retry', (tester) async {
    scanner.error = const MobileScannerException(errorCode: MobileScannerErrorCode.permissionDenied);
    await tester.pumpWidget(const MaterialApp(home: QrScanPage()));
    await tester.pumpAndSettle();
    expect(find.text(t.qrScanPage.permissionDenied), findsOneWidget);
    expect(find.text(t.general.settings), findsOneWidget);
    scanner.error = null;
    await tester.tap(find.text(t.qrScanPage.scanAgain));
    await tester.pumpAndSettle();
    expect(scanner.starts, 1);
    scanner.detect('http://10.0.0.5:53317');
    await tester.pumpAndSettle();
    expect(find.text('10.0.0.5'), findsOneWidget);
  });

  testWidgets('backgrounding stops camera, returning restarts it, and leaving disposes it', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: QrScanPage()));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(scanner.stops, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(scanner.starts, 2);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    // Stream cancellation completes outside the widget test clock.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(scanner.disposals, 1);
  });
}
