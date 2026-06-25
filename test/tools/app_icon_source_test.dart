// Generator (not a behavior test): renders the launcher-icon SOURCE image —
// the Neon Nine mark centred on a rounded Aurora tile — and writes it to
// assets/brand/app_icon_source.png. That PNG is the input for
// `dart run flutter_launcher_icons`, which bakes windows/runner/resources/
// app_icon.ico. Regenerate after any mark change:
//   flutter test test/tools/app_icon_source_test.dart --update-goldens
// On a normal run it doubles as a golden, so the committed icon source can't
// drift from the mark unnoticed.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/ui/brand/meow_logo_mark.dart';

void main() {
  testWidgets('app icon source = mark on an Aurora tile (1024px)',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 1024));
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            child: SizedBox(
              width: 1024,
              height: 1024,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.all(Radius.circular(232)),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF2A1B4D),
                      Color(0xFF1E3A5F),
                      Color(0xFF0E3A4A),
                    ],
                  ),
                ),
                child: Center(
                  child: MeowLogoMark(size: 900, color: Color(0xFF7DF9C2)),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await expectLater(
      find.byType(RepaintBoundary),
      matchesGoldenFile('../../assets/brand/app_icon_source.png'),
    );
  });
}
