import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/provider/destination_directory_provider.dart';
import 'package:localsend_app/widget/destination_directory_button.dart';
import 'package:refena_flutter/refena_flutter.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.macOS, TargetPlatform.windows]) {
    testWidgets('shows resolved and custom directory on $platform', (tester) async {
      final directory = switch (platform) {
        TargetPlatform.windows => 'D:/Moved Downloads',
        TargetPlatform.macOS => '/Users/test/Downloads',
        _ => '/storage/emulated/0/Download',
      };
      final expected = platform == TargetPlatform.windows ? r'D:\Moved Downloads' : directory;
      var clicks = 0;
      Widget build(String? custom) => RefenaScope(
        overrides: [defaultDestinationDirectoryProvider.overrideWithFuture((_) async => directory)],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 280,
              child: DestinationDirectoryButton(destination: custom, onPressed: () => clicks++),
            ),
          ),
        ),
      );
      await tester.pumpWidget(build(null));
      await tester.pumpAndSettle();
      expect(find.text(expected), findsOneWidget);
      expect(find.text('(Downloads)'), findsNothing);
      await tester.tap(find.byType(TextButton));
      expect(clicks, 1);
      await tester.pumpWidget(build('/custom/folder'));
      await tester.pumpAndSettle();
      expect(find.text(platform == TargetPlatform.windows ? r'\custom\folder' : '/custom/folder'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(platform));
  }
}
