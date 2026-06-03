import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/ui/gallery/design_gallery.dart';

void main() {
  // Note: the component zoo embeds EmptyState -> IdleMascot, which animates
  // forever. Never use pumpAndSettle here; pump fixed durations instead. The
  // ListView is lazy, so the bottom "Components" section must be scrolled into
  // view before it exists in the element tree.

  testWidgets('gallery renders the hero and its sections', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DesignGallery()));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Design System'), findsOneWidget); // hero
    expect(find.text('COLOR'), findsOneWidget); // first section

    // Scroll down in steps to build the lazy "Components" section (the list is
    // tall; one big drag can over/under-shoot, so step until it appears).
    final scrollable = find.byType(Scrollable).first;
    for (var i = 0; i < 20 && find.text('COMPONENTS').evaluate().isEmpty; i++) {
      await tester.drag(scrollable, const Offset(0, -500));
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('COMPONENTS'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching theme does not throw', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DesignGallery()));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text(MeowThemeId.noir.label));
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
  });
}
