import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/ui/brand/meow_logo.dart';
import 'package:meowwatch/ui/gallery/design_gallery.dart';

void main() {
  // Note: the component zoo embeds EmptyState -> IdleMascot, which animates
  // forever. Never use pumpAndSettle here; pump fixed durations instead. The
  // ListView is lazy, so the bottom "Components" section must be scrolled into
  // view before it exists in the element tree.

  testWidgets('gallery includes the Brand specimen', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DesignGallery()));
    // Brand leads the list, so it's on screen without scrolling. Never
    // pumpAndSettle here (IdleMascot animates forever); pump a fixed duration.
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('BRAND'), findsOneWidget);
    expect(find.byType(MeowLogo), findsWidgets);
  });

  testWidgets('gallery renders the hero and its sections', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DesignGallery()));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Design System'), findsOneWidget); // hero
    expect(find.text('BRAND'), findsOneWidget); // first section

    // Scroll down in steps to build the lazy "Components" section (the list is
    // tall; one big drag can over/under-shoot, so step until it appears).
    // The main list is the only ListView; target it directly so the top bar's
    // horizontal scroll view is never picked up instead.
    final scrollable = find.byType(ListView);
    for (var i = 0; i < 40 && find.text('COMPONENTS').evaluate().isEmpty; i++) {
      await tester.drag(scrollable, const Offset(0, -500));
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('COMPONENTS'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('gallery includes the launch-reveal motion section', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: DesignGallery()));
    await tester.pump(const Duration(milliseconds: 300));

    // The section is lazy; step-scroll until its title is built.
    // The main list is the only ListView; target it directly so the top bar's
    // horizontal scroll view is never picked up instead.
    final scrollable = find.byType(ListView);
    for (
      var i = 0;
      i < 30 && find.text('MOTION · REVEAL').evaluate().isEmpty;
      i++
    ) {
      await tester.drag(scrollable, const Offset(0, -400));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('MOTION · REVEAL'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching theme does not throw', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DesignGallery()));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text(MeowThemeId.noir.label));
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
  });

  testWidgets('reduce-motion preview toggle flips without throwing', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: DesignGallery()));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Reduce motion'), findsOneWidget);

    // Flip it on, then off — the gallery keeps rendering its hero either way.
    await tester.tap(find.text('Reduce motion'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Design System'), findsOneWidget);

    await tester.tap(find.text('Reduce motion'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Design System'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });
}
