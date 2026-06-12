import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/meow_context.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/ui/video_error_state.dart';

Widget _host(Widget child) => MaterialApp(
      theme: themeDataFor(MeowThemeId.cozy),
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('shows the message and detail, and wires both actions',
      (tester) async {
    var browsed = false;
    var pasted = false;
    await tester.pumpWidget(_host(VideoErrorState(
      message: "Couldn't play that link.",
      detail: 'mpv: Failed to open.',
      onBrowse: () => browsed = true,
      onPasteLink: () => pasted = true,
    )));

    expect(find.byKey(const Key('video-error-message')), findsOneWidget);
    expect(find.textContaining("Couldn't play"), findsOneWidget);
    expect(find.textContaining('Failed to open'), findsOneWidget);

    await tester.tap(find.byKey(const Key('video-error-browse')));
    await tester.tap(find.byKey(const Key('video-error-paste')));
    expect(browsed, isTrue);
    expect(pasted, isTrue);
  });

  testWidgets('omits the detail line when none is given', (tester) async {
    await tester.pumpWidget(_host(VideoErrorState(
      message: "Couldn't play that video.",
      onBrowse: () {},
      onPasteLink: () {},
    )));
    expect(find.textContaining('mpv'), findsNothing);
  });
}
