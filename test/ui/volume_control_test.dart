import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/meow_context.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/ui/volume_control.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: themeDataFor(MeowThemeId.cozy),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  group('VolumeControl', () {
    testWidgets('shows volume_up icon at high volume', (tester) async {
      await tester.pumpWidget(_wrap(VolumeControl(
        volume: 0.9,
        onSetVolume: (_) {},
        onToggleMute: () {},
      )));
      expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);
    });

    testWidgets('shows volume_down icon at mid volume', (tester) async {
      await tester.pumpWidget(_wrap(VolumeControl(
        volume: 0.3,
        onSetVolume: (_) {},
        onToggleMute: () {},
      )));
      expect(find.byIcon(Icons.volume_down_rounded), findsOneWidget);
    });

    testWidgets('shows volume_off icon at zero', (tester) async {
      await tester.pumpWidget(_wrap(VolumeControl(
        volume: 0.0,
        onSetVolume: (_) {},
        onToggleMute: () {},
      )));
      expect(find.byIcon(Icons.volume_off_rounded), findsOneWidget);
    });

    testWidgets('icon tap fires onToggleMute', (tester) async {
      var muted = false;
      await tester.pumpWidget(_wrap(VolumeControl(
        volume: 0.8,
        onSetVolume: (_) {},
        onToggleMute: () => muted = true,
      )));
      await tester.tap(find.byIcon(Icons.volume_up_rounded));
      expect(muted, isTrue);
    });

    testWidgets('slider not visible before hover', (tester) async {
      await tester.pumpWidget(_wrap(VolumeControl(
        volume: 0.5,
        onSetVolume: (_) {},
        onToggleMute: () {},
      )));
      expect(find.byType(Slider), findsNothing);
    });

    testWidgets('slider appears on hover', (tester) async {
      await tester.pumpWidget(_wrap(VolumeControl(
        volume: 0.5,
        onSetVolume: (_) {},
        onToggleMute: () {},
      )));

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer();
      await gesture.moveTo(tester.getCenter(find.byType(VolumeControl)));
      await tester.pump();

      expect(find.byType(Slider), findsOneWidget);
      await gesture.removePointer();
    });

    testWidgets('slider fires onSetVolume on drag', (tester) async {
      double? set;
      await tester.pumpWidget(_wrap(VolumeControl(
        volume: 0.5,
        onSetVolume: (v) => set = v,
        onToggleMute: () {},
      )));

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer();
      await gesture.moveTo(tester.getCenter(find.byType(VolumeControl)));
      await tester.pump();

      expect(find.byType(Slider), findsOneWidget);
      await tester.drag(find.byType(Slider), const Offset(0, -20));
      await tester.pump();

      expect(set, isNotNull);
      await gesture.removePointer();
    });

    testWidgets('slider hidden after cursor leaves widget', (tester) async {
      await tester.pumpWidget(_wrap(VolumeControl(
        volume: 0.5,
        onSetVolume: (_) {},
        onToggleMute: () {},
      )));

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer();

      await gesture.moveTo(tester.getCenter(find.byType(VolumeControl)));
      await tester.pump();
      expect(find.byType(Slider), findsOneWidget);

      // Move 200px below the widget's bottom edge to guarantee exit.
      final bottom = tester.getBottomLeft(find.byType(VolumeControl));
      await gesture.moveTo(bottom + const Offset(0, 200));
      await tester.pump(); // process onExit, schedule hide timer
      await tester.pump(const Duration(milliseconds: 300)); // fire 150ms timer
      await tester.pump(); // process resulting setState

      expect(find.byType(Slider), findsNothing);
      await gesture.removePointer();
    });
  });
}
