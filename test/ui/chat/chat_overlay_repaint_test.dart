import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/meow_context.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/ui/chat/chat_overlay.dart';

// Counts how many times its layer is painted. It shares a layer with its
// siblings unless something (a RepaintBoundary) isolates them — so its paint
// count rising in lockstep with a sibling's repaints is exactly the symptom we
// guard against.
class _PaintProbe extends CustomPainter {
  _PaintProbe(this.onPaint);
  final VoidCallback onPaint;
  @override
  void paint(Canvas canvas, Size size) => onPaint();
  @override
  bool shouldRepaint(covariant _PaintProbe oldDelegate) => false;
}

void main() {
  // Regression guard for #50 (a deeper recurrence of #42): resizing the chat
  // card must not repaint the rest of the screen.
  //
  // Why this matters: the chat card resizes by calling setState on every
  // pointer-move. With no RepaintBoundary isolating the overlay, that
  // markNeedsPaint walks to the root and repaints the WHOLE screen each frame.
  // Under the extra per-frame load of being in a room (heartbeat/presence) or
  // playing (texture + position stream), those full-screen repaints overran the
  // frame budget; the dropped raster frame let the Windows window's white clear
  // colour flash through ("whole screen goes white"). Isolating the overlay in
  // its own layer keeps resize repaints local, so the player layer never
  // repaints during a resize — no frame drop, no white flash.
  testWidgets('resizing the chat card does not repaint the sibling player layer',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    var playerPaints = 0;
    // One painter instance reused across pumps so its paint count only ever
    // rises from a *layer* invalidation, never from the widget being rebuilt.
    final probe = _PaintProbe(() => playerPaints++);

    await tester.pumpWidget(
      MaterialApp(
        theme: themeDataFor(MeowThemeId.cozy),
        home: Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: [
              // Stand-in for the player surface that sits behind the chat card.
              CustomPaint(painter: probe, child: const SizedBox.expand()),
              ChatOverlay(
                messages: const [],
                myUsername: 'me',
                collapsed: false,
                onSend: (_) {},
                onToggleCollapsed: () {},
                onSnap: (_) {},
                onResize: (_) {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Begin a resize from the bottom-right grip and take one move so the card
    // has switched into its free-floating render path. Baseline the player's
    // paint count *after* that structural switch — we care about the per-frame
    // repaints during the ongoing drag, not the one-off transition.
    final grip = find.byKey(const ValueKey('chat-resize-grip-bottomRight'));
    expect(grip, findsOneWidget);
    final gesture = await tester.startGesture(tester.getCenter(grip));
    await gesture.moveBy(const Offset(20, 20));
    await tester.pump();

    final baseline = playerPaints;

    // Several more resize frames. With the overlay isolated these must NOT
    // repaint the player layer.
    await gesture.moveBy(const Offset(20, 20));
    await tester.pump();
    await gesture.moveBy(const Offset(20, 20));
    await tester.pump();
    await gesture.moveBy(const Offset(20, 20));
    await tester.pump();

    expect(
      playerPaints,
      baseline,
      reason: 'the player layer repainted during a chat-card resize — the '
          'overlay is not isolated in its own layer (#50)',
    );

    await gesture.up();
    await tester.pump();
  });

  // The actual root cause of #50. HomeScreen mounts ChatOverlay under
  // IgnorePointer/AnimatedOpacity — NOT directly inside a Stack. The drag/resize
  // render path therefore must not return a `Positioned` (a ParentDataWidget
  // that requires a Stack parent): doing so is a misuse that throws in
  // debug/tests and, in release, made the engine composite the whole screen
  // wrong — a translucent pale-white wash for the entire drag, on every theme,
  // with or without a video. The original tests missed it because their host
  // wrapped the overlay in a Stack, which made the misused Positioned legal.
  testWidgets('resizes cleanly when mounted outside a Stack (like HomeScreen) (#50)',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        theme: themeDataFor(MeowThemeId.cozy),
        home: Scaffold(
          // Single-child ancestor (no Stack), mirroring HomeScreen's
          // AnimatedOpacity > IgnorePointer > ChatOverlay.
          body: IgnorePointer(
            ignoring: false,
            child: ChatOverlay(
              messages: const [],
              myUsername: 'me',
              collapsed: false,
              onSend: (_) {},
              onToggleCollapsed: () {},
              onSnap: (_) {},
              onResize: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Enter the free-floating resize render path.
    final grip = find.byKey(const ValueKey('chat-resize-grip-bottomRight'));
    expect(grip, findsOneWidget);
    final gesture = await tester.startGesture(tester.getCenter(grip));
    await gesture.moveBy(const Offset(30, 30));
    await tester.pump();

    // Pre-fix this threw "Incorrect use of ParentDataWidget" (Positioned outside
    // a Stack); the fix uses SizedBox.expand for the overlay's own fill.
    expect(tester.takeException(), isNull);

    await gesture.up();
    await tester.pumpAndSettle();
  });
}
