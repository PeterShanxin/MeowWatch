import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/audio/notify_sounds.dart';
import 'package:meowwatch/core/theme/meow_context.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/ui/settings/settings_panel.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
        theme: themeDataFor(MeowThemeId.cozy),
        home: Scaffold(body: child),
      );

  testWidgets('picker row previews the current selection and fires onChanged',
      (tester) async {
    String? changed;
    String? previewed;

    await tester.pumpWidget(host(
      SoundPickerRow(
        key: const Key('primary-sound-picker'),
        title: 'Notification sound',
        options: kPrimarySounds,
        currentId: kDefaultPrimarySoundId,
        onChanged: (id) => changed = id,
        onPreview: (asset) => previewed = asset,
      ),
    ));

    // Preview the current selection.
    await tester.tap(find.byKey(const Key('primary-sound-picker-preview')));
    await tester.pump();
    expect(previewed, resolvePrimary(kDefaultPrimarySoundId).asset);

    // Open the dropdown and pick a different option.
    await tester.tap(find.byKey(const Key('primary-sound-picker-dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Glass chime').last);
    await tester.pumpAndSettle();
    expect(changed, 'glass');
  });
}
