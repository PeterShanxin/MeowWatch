import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/meow_context.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/ui/empty_state.dart';

void main() {
  testWidgets('shows prompt text and Browse button', (tester) async {
    var browseCalled = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: themeDataFor(MeowThemeId.cozy),
        home: Scaffold(body: EmptyState(onBrowse: () => browseCalled = true)),
      ),
    );

    expect(find.textContaining('Drop a video'), findsOneWidget);
    expect(find.text('Browse…'), findsOneWidget);

    await tester.tap(find.text('Browse…'));
    await tester.pump();
    expect(browseCalled, isTrue);
  });

  testWidgets('paste-a-link field loads a valid URL', (tester) async {
    String? loaded;
    await tester.pumpWidget(
      MaterialApp(
        theme: themeDataFor(MeowThemeId.cozy),
        home: Scaffold(
          body: EmptyState(onBrowse: () {}, onLoadUrl: (u) => loaded = u),
        ),
      ),
    );

    expect(find.byKey(const Key('url-input-field')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('url-input-field')),
      'https://x.test/a.mp4',
    );
    await tester.tap(find.byKey(const Key('url-load-button')));
    await tester.pump();
    expect(loaded, 'https://x.test/a.mp4');
  });

  testWidgets('leave button is available before a video is loaded', (
    tester,
  ) async {
    var left = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: themeDataFor(MeowThemeId.cozy),
        home: Scaffold(
          body: EmptyState(onBrowse: () {}, onLeave: () => left = true),
        ),
      ),
    );

    expect(find.text('Leave room'), findsOneWidget);
    await tester.tap(find.text('Leave room'));
    await tester.pump();
    expect(left, isTrue);
  });

  testWidgets('hides the paste-a-link field when onLoadUrl is null', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: themeDataFor(MeowThemeId.cozy),
        home: Scaffold(body: EmptyState(onBrowse: () {})),
      ),
    );
    expect(find.byKey(const Key('url-input-field')), findsNothing);
    expect(find.text('Browse…'), findsOneWidget);
  });

  testWidgets('shows a join notice above the prompt when provided (#60)', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: themeDataFor(MeowThemeId.cozy),
        home: Scaffold(
          body: EmptyState(
            onBrowse: () {},
            notice: 'lin started playback — load a video to join',
          ),
        ),
      ),
    );

    expect(find.textContaining('started playback'), findsOneWidget);
    // The usual prompt + Browse button still render.
    expect(find.textContaining('Drop a video'), findsOneWidget);
    expect(find.text('Browse…'), findsOneWidget);
  });
}
