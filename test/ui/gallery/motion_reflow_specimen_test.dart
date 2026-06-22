import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/meow_context.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/ui/gallery/gallery_sections.dart';

void main() {
  Widget host() => MaterialApp(
        theme: themeDataFor(MeowThemeId.cozy),
        home: const Scaffold(
          body: SingleChildScrollView(child: MotionReflowSpecimen()),
        ),
      );

  testWidgets('starts on Latest per room — one card per room', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    // Newest per room: three rooms, three cards.
    expect(find.text('The Bear — S03E08'), findsOneWidget);
    expect(find.text('Dune: Part Two'), findsOneWidget);
    expect(find.text('Frieren — S01E12'), findsOneWidget);
    // The older same-room entries are hidden.
    expect(find.text('The Bear — S03E07'), findsNothing);
    expect(find.text('Spirited Away'), findsNothing);
  });

  testWidgets('toggling to Every video cascades the hidden cards in',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Every video'));
    // Let the staggered cascade run to completion (no infinite animations here).
    await tester.pumpAndSettle();

    expect(find.text('The Bear — S03E07'), findsOneWidget);
    expect(find.text('Spirited Away'), findsOneWidget);
    expect(find.text('Frieren — S01E11'), findsOneWidget);
    expect(find.text('The Bear — S03E08'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Toggling back collapses them out again (and removes them once collapsed).
    await tester.tap(find.text('Latest per room'));
    await tester.pumpAndSettle();
    expect(find.text('The Bear — S03E07'), findsNothing);
    expect(find.text('Spirited Away'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
