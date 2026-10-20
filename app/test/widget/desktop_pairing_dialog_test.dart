import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/provider/desktop_pairing_provider.dart';
import 'package:localsend_app/util/desktop_pairing_invitation.dart';
import 'package:localsend_app/widget/dialogs/desktop_pairing_dialog.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:mockito/mockito.dart';
import 'package:refena_flutter/refena_flutter.dart';

class _PairingService extends Mock implements DesktopPairingService {
  int attempts = 0;
  bool fail = false;
  @override
  Future<Device> connect(DesktopPairingInvitation invitation) async {
    attempts++;
    if (fail) throw StateError('Unreachable');
    return Device.empty.copyWith(ip: invitation.ip, alias: invitation.alias, fingerprint: invitation.fingerprint);
  }
}

void main() {
  setUp(() => LocaleSettings.setLocaleSync(AppLocale.en));
  for (final action in ['accept', 'decline', 'retry']) {
    testWidgets(
      'desktop invitation $action requires confirmation before contacting peer',
      (tester) async {
        final service = _PairingService()..fail = action == 'retry';
        Device? connected;
        await tester.pumpWidget(
          RefenaScope(
            overrides: [desktopPairingProvider.overrideWithValue(service)],
            child: MaterialApp(
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () async {
                      connected = await showDialog<Device>(
                        context: context,
                        builder: (_) => DesktopPairingDialog(
                          phoneAlias: 'Phone',
                          peer: DesktopPairingInvitation(
                            ip: '192.168.1.20',
                            port: 54321,
                            https: true,
                            fingerprint: 'B' * 64,
                            alias: 'Other computer',
                          ),
                        ),
                      );
                    },
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(service.attempts, 0);
        if (action == 'decline') {
          await tester.tap(find.text(t.general.cancel));
          await tester.pumpAndSettle();
          expect(service.attempts, 0);
          expect(connected, isNull);
        } else {
          await tester.tap(find.text(t.desktopPairing.connect));
          await tester.pumpAndSettle();
          if (action == 'retry') {
            expect(find.text(t.desktopPairing.failed), findsOneWidget);
            expect(connected, isNull);
            service.fail = false;
            await tester.tap(find.text(t.qrScanPage.retryConnection));
            await tester.pumpAndSettle();
          }
          expect(connected!.ip, '192.168.1.20');
        }
      },
      variant: const TargetPlatformVariant({TargetPlatform.macOS, TargetPlatform.windows}),
    );
  }
}
