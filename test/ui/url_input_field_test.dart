import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/meow_context.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/ui/url_input_field.dart';

Widget _host(Widget child) => MaterialApp(
      theme: themeDataFor(MeowThemeId.cozy),
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('a valid link fires onSubmit with the trimmed URL',
      (tester) async {
    String? submitted;
    await tester.pumpWidget(_host(UrlInputField(onSubmit: (u) => submitted = u)));

    await tester.enterText(
        find.byKey(const Key('url-input-field')), '  https://x.test/a.mp4 ');
    await tester.tap(find.byKey(const Key('url-load-button')));
    await tester.pump();

    expect(submitted, 'https://x.test/a.mp4');
    expect(find.byKey(const Key('url-input-error')), findsNothing);
  });

  testWidgets('an invalid link shows an inline error and does not submit',
      (tester) async {
    String? submitted;
    await tester.pumpWidget(_host(UrlInputField(onSubmit: (u) => submitted = u)));

    await tester.enterText(
        find.byKey(const Key('url-input-field')), 'not-a-link');
    await tester.tap(find.byKey(const Key('url-load-button')));
    await tester.pump();

    expect(submitted, isNull);
    expect(find.byKey(const Key('url-input-error')), findsOneWidget);
  });

  testWidgets('an empty entry shows an error and does not submit',
      (tester) async {
    String? submitted;
    await tester.pumpWidget(_host(UrlInputField(onSubmit: (u) => submitted = u)));

    await tester.tap(find.byKey(const Key('url-load-button')));
    await tester.pump();

    expect(submitted, isNull);
    expect(find.byKey(const Key('url-input-error')), findsOneWidget);
  });

  testWidgets('editing clears a stale error', (tester) async {
    await tester.pumpWidget(_host(UrlInputField(onSubmit: (_) {})));

    await tester.tap(find.byKey(const Key('url-load-button')));
    await tester.pump();
    expect(find.byKey(const Key('url-input-error')), findsOneWidget);

    await tester.enterText(
        find.byKey(const Key('url-input-field')), 'https://x.test/a.mp4');
    await tester.pump();
    expect(find.byKey(const Key('url-input-error')), findsNothing);
  });

  testWidgets('submitting from the keyboard also validates', (tester) async {
    String? submitted;
    await tester.pumpWidget(_host(UrlInputField(onSubmit: (u) => submitted = u)));

    await tester.enterText(
        find.byKey(const Key('url-input-field')), 'https://x.test/a.mp4');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pump();

    expect(submitted, 'https://x.test/a.mp4');
  });
}
