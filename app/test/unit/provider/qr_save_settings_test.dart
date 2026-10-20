import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/model/state/settings_state.dart';
import 'package:localsend_app/provider/persistence_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('QR auto save defaults off, persists and remains independent of global quick save', () async {
    SharedPreferences.setMockInitialValues({
      'ls_version': 3,
      'ls_show_token': 'test-token',
      'ls_alias': 'Test',
      'ls_security_context': '{}',
      'ls_locale': 'en',
      'ls_color': 'localsend',
      'ls_quick_save': 'on',
    });
    final persistence = await PersistenceService.initialize(supportsDynamicColors: false);
    expect(persistence.getQrConnectionAutoSave(), isFalse);
    final settings = Notifier.test<SettingsService, SettingsState>(notifier: SettingsService(persistence));
    expect(settings.state.qrConnectionAutoSave, isFalse);
    expect(settings.state.quickSave, isTrue);
    await settings.notifier.setQrConnectionAutoSave(true);
    expect(settings.state.qrConnectionAutoSave, isTrue);
    final reloaded = await PersistenceService.initialize(supportsDynamicColors: false);
    expect(reloaded.getQrConnectionAutoSave(), isTrue);
    await settings.notifier.setQrConnectionAutoSave(false);
    expect(persistence.getQrConnectionAutoSave(), isFalse);
    expect(settings.state.quickSave, isTrue);
  });
}
