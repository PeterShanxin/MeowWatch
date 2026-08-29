import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/sync/peer_state.dart';
import 'package:meowwatch/core/theme/meow_context.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/ui/chat/chat_overlay.dart';

import '../../helpers/hosted_windows_golden.dart';

void main() {
  // Hosted windows-2025 rasterizes the card text a few hundred pixels
  // off the goldens from the maintainer box. See hosted_windows_golden.dart.
  late GoldenFileComparator previousComparator;
  setUpAll(() {
    previousComparator = goldenFileComparator;
    final testFile = goldenFileComparator is LocalFileComparator
        ? Uri.parse(
            '${(goldenFileComparator as LocalFileComparator).basedir}chat_overlay_golden_test.dart',
          )
        : Uri.parse('test/ui/chat/chat_overlay_golden_test.dart');
    goldenFileComparator = HostedWindowsGoldenComparator(testFile);
  });
  tearDownAll(() {
    goldenFileComparator = previousComparator;
  });

  testWidgets('GOLDEN: expanded card over black, bottom-left', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    // Replicate home_screen: black backdrop, Stack(fit: expand), overlay on top.
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: themeDataFor(MeowThemeId.cozy),
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Colors.black),
            ChatOverlay(
              messages: const [
                ChatMessage(username: 'lin', text: 'hi', isMine: false),
                ChatMessage(username: 'me', text: 'yo', isMine: true),
              ],
              collapsed: false,
              onSend: (_) {},
              onToggleCollapsed: () {},
              onSnap: (_) {},
            ),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/chat_overlay_expanded.png'),
    );
  });

  testWidgets('GOLDEN: empty card over black, bottom-left', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: themeDataFor(MeowThemeId.cozy),
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Colors.black),
            ChatOverlay(
              messages: const [],
              collapsed: false,
              onSend: (_) {},
              onToggleCollapsed: () {},
              onSnap: (_) {},
            ),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/chat_overlay_empty.png'),
    );
  });
}
