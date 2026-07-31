import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/meow_context.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/ui/load_video_choices.dart';

Widget _host(Widget child) => MaterialApp(
  theme: themeDataFor(MeowThemeId.cozy),
  home: Scaffold(body: child),
);

void main() {
  group('LoadVideoChoices', () {
    testWidgets('offers both sources as peers under the "or" rule', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(LoadVideoChoices(onBrowse: () {}, onSubmitUrl: (_) {})),
      );

      expect(find.byKey(const Key('load-video-from-computer')), findsOneWidget);
      expect(find.byKey(const Key('url-input-field')), findsOneWidget);
      expect(find.text('or'), findsOneWidget);
    });

    testWidgets('fires onBrowse for the local-file half', (tester) async {
      var browsed = false;
      await tester.pumpWidget(
        _host(LoadVideoChoices(onBrowse: () => browsed = true)),
      );

      await tester.tap(find.byKey(const Key('load-video-from-computer')));
      await tester.pump();
      expect(browsed, isTrue);
    });

    testWidgets('hides the link half when onSubmitUrl is null', (tester) async {
      await tester.pumpWidget(_host(LoadVideoChoices(onBrowse: () {})));

      expect(find.byKey(const Key('url-input-field')), findsNothing);
      expect(find.text('or'), findsNothing);
      expect(find.byKey(const Key('load-video-from-computer')), findsOneWidget);
    });

    testWidgets('forwards only a validated link', (tester) async {
      String? submitted;
      await tester.pumpWidget(
        _host(
          LoadVideoChoices(onBrowse: () {}, onSubmitUrl: (u) => submitted = u),
        ),
      );

      await tester.enterText(
        find.byKey(const Key('url-input-field')),
        'not a link',
      );
      await tester.tap(find.byKey(const Key('url-load-button')));
      await tester.pump();
      expect(submitted, isNull);

      await tester.enterText(
        find.byKey(const Key('url-input-field')),
        'https://x.test/a.mp4',
      );
      await tester.tap(find.byKey(const Key('url-load-button')));
      await tester.pump();
      expect(submitted, 'https://x.test/a.mp4');
    });
  });

  group('showLoadVideoDialog', () {
    // The dialog's future only completes on dismissal, so capture its result
    // through a callback rather than awaiting it while it's still on screen.
    Future<void> open(
      WidgetTester tester,
      void Function(LoadVideoChoice? choice) onResult,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: themeDataFor(MeowThemeId.cozy),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () =>
                    showLoadVideoDialog(context).then(onResult),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('resolves to the computer choice', (tester) async {
      LoadVideoChoice? choice;
      var resolved = false;
      await open(tester, (c) {
        choice = c;
        resolved = true;
      });

      await tester.tap(find.byKey(const Key('load-video-from-computer')));
      await tester.pumpAndSettle();

      expect(resolved, isTrue);
      expect(choice?.source, LoadVideoSource.computer);
      expect(choice?.url, isNull);
    });

    testWidgets('resolves to the pasted link', (tester) async {
      LoadVideoChoice? choice;
      await open(tester, (c) => choice = c);

      await tester.enterText(
        find.byKey(const Key('url-input-field')),
        'https://x.test/a.mp4',
      );
      await tester.tap(find.byKey(const Key('url-load-button')));
      await tester.pumpAndSettle();

      expect(choice?.source, LoadVideoSource.link);
      expect(choice?.url, 'https://x.test/a.mp4');
    });

    testWidgets('resolves to null when dismissed', (tester) async {
      LoadVideoChoice? choice;
      var resolved = false;
      await open(tester, (c) {
        choice = c;
        resolved = true;
      });

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(resolved, isTrue);
      expect(choice, isNull);
    });
  });
}
