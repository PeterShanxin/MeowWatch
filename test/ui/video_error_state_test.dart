import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/meow_context.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/ui/motion/reveal_in.dart';
import 'package:meowwatch/ui/video_error_state.dart';

/// The reveal's own Opacity — not any Opacity the Material chrome may add.
double _revealOpacity(WidgetTester tester) => tester
    .widget<Opacity>(
      find
          .descendant(of: find.byType(RevealIn), matching: find.byType(Opacity))
          .first,
    )
    .opacity;

Widget _host(Widget child) => MaterialApp(
      theme: themeDataFor(MeowThemeId.cozy),
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('shows the message and detail, and wires the load action',
      (tester) async {
    var loadTapped = false;
    await tester.pumpWidget(_host(VideoErrorState(
      message: "Couldn't play that link.",
      detail: 'mpv: Failed to open.',
      onLoadVideo: () => loadTapped = true,
    )));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('video-error-message')), findsOneWidget);
    expect(find.textContaining("Couldn't play"), findsOneWidget);
    expect(find.textContaining('Failed to open'), findsOneWidget);

    await tester.tap(find.byKey(const Key('video-error-load')));
    expect(loadTapped, isTrue);
  });

  testWidgets('offers one load entry, not separate browse/paste buttons (#222)',
      (tester) async {
    await tester.pumpWidget(_host(VideoErrorState(
      message: "Couldn't play that link.",
      onLoadVideo: () {},
    )));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('video-error-load')), findsOneWidget);
    expect(find.byKey(const Key('video-error-browse')), findsNothing);
    expect(find.byKey(const Key('video-error-paste')), findsNothing);
  });

  testWidgets('omits the detail line when none is given', (tester) async {
    await tester.pumpWidget(_host(VideoErrorState(
      message: "Couldn't play that video.",
      onLoadVideo: () {},
    )));
    await tester.pumpAndSettle();
    expect(find.textContaining('mpv'), findsNothing);
  });

  testWidgets('Try again is hidden when no onRetry is given', (tester) async {
    await tester.pumpWidget(_host(VideoErrorState(
      message: "Couldn't play that video.",
      onLoadVideo: () {},
    )));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('video-error-retry')), findsNothing);
  });

  testWidgets('Try again shows and fires onRetry when provided',
      (tester) async {
    var retried = false;
    await tester.pumpWidget(_host(VideoErrorState(
      message: "Couldn't play that link.",
      onLoadVideo: () {},
      onRetry: () => retried = true,
    )));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('video-error-retry')), findsOneWidget);
    await tester.tap(find.byKey(const Key('video-error-retry')));
    expect(retried, isTrue);
  });

  testWidgets(
    'a repeat failure replays the reveal even when the copy is identical (#232)',
    (tester) async {
      // The exact case from the issue: a second failing paste produces the same
      // generic headline as the first, so the only thing that can tell the user
      // it was even tried is the surface re-announcing itself.
      const same = "Couldn't play that link.";
      await tester.pumpWidget(_host(const VideoErrorState(
        message: same,
        onLoadVideo: _noop,
        attempt: 1,
      )));
      await tester.pumpAndSettle();
      expect(_revealOpacity(tester), 1.0);

      // Same message, next attempt: the reveal restarts, so mid-animation the
      // content is part-way in rather than sitting untouched at full opacity.
      await tester.pumpWidget(_host(const VideoErrorState(
        message: same,
        onLoadVideo: _noop,
        attempt: 2,
      )));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(_revealOpacity(tester), lessThan(1.0));

      await tester.pumpAndSettle();
      expect(_revealOpacity(tester), 1.0);
    },
  );

  testWidgets('an unchanged attempt does not restart the reveal (#232)',
      (tester) async {
    await tester.pumpWidget(_host(const VideoErrorState(
      message: "Couldn't play that link.",
      onLoadVideo: _noop,
      attempt: 3,
    )));
    await tester.pumpAndSettle();

    // A plain rebuild (e.g. a peer heartbeat repainting the room) must not
    // flash the surface — only a *new* failure does.
    await tester.pumpWidget(_host(const VideoErrorState(
      message: "Couldn't play that link.",
      detail: 'mpv: Failed to open.',
      onLoadVideo: _noop,
      attempt: 3,
    )));
    await tester.pump(const Duration(milliseconds: 40));
    expect(_revealOpacity(tester), 1.0);
  });
}

void _noop() {}
