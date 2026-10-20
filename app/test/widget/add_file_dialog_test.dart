import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/util/native/file_picker.dart';
import 'package:localsend_app/widget/big_button.dart';
import 'package:localsend_app/widget/dialogs/add_file_dialog.dart';
import 'package:refena_flutter/refena_flutter.dart';

void main() {
  setUpAll(() async => LocaleSettings.setLocale(AppLocale.zhCn));
  for (final size in [const Size(640, 480), const Size(1200, 800), const Size(400, 300)]) {
    testWidgets('desktop file choices stay in two columns at $size', (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        RefenaScope(
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => AddFileDialog.open(context: context, options: FilePickerOption.getOptionsForPlatform()),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final tiles = find.byType(BigButton);
      expect(tiles, findsNWidgets(4));
      final positions = List.generate(4, (i) => tester.getCenter(tiles.at(i)));
      expect(positions[0].dy, positions[1].dy);
      expect(positions[2].dy, positions[3].dy);
      expect(positions[0].dx, positions[2].dx);
      expect(positions[1].dx, positions[3].dx);
      expect(positions[0].dy, lessThan(positions[2].dy));
      expect(positions[0].dx, lessThan(positions[1].dx));
      expect(tiles.evaluate().map((e) => (e.widget as BigButton).label), [
        t.sendTab.picker.file,
        t.sendTab.picker.folder,
        t.sendTab.picker.text,
        t.sendTab.picker.clipboard,
      ]);
      expect(tester.takeException(), isNull);
    }, variant: const TargetPlatformVariant({TargetPlatform.macOS, TargetPlatform.windows}));
  }
}
