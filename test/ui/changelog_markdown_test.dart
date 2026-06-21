// test/ui/changelog_markdown_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/meow_context.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/core/update/changelog_markup.dart';
import 'package:meowwatch/ui/changelog_markdown.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
        theme: themeDataFor(MeowThemeId.cozy),
        home: Scaffold(body: child),
      );

  testWidgets('renders bullet text and a tag chip', (tester) async {
    final parsed = parseChangelogNotes('### Added\n- a shiny **thing**');
    await tester.pumpWidget(host(
      ChangelogMarkdown(sections: parsed.sections, onIssueTap: (_) {}),
    ));
    expect(find.text('New'), findsOneWidget); // chip label
    expect(find.text('a shiny thing', findRichText: true), findsOneWidget);
  });

  testWidgets('showTags: false hides chips', (tester) async {
    final parsed = parseChangelogNotes('### Fixed\n- a bug');
    await tester.pumpWidget(host(ChangelogMarkdown(
      sections: parsed.sections,
      onIssueTap: (_) {},
      showTags: false,
    )));
    expect(find.text('Fixed'), findsNothing);
  });

  testWidgets('tapping an issue ref invokes onIssueTap with the number',
      (tester) async {
    int? tapped;
    final parsed = parseChangelogNotes('- fixed it (#147)');
    await tester.pumpWidget(host(ChangelogMarkdown(
      sections: parsed.sections,
      onIssueTap: (n) => tapped = n,
    )));
    await tester.tap(find.text('#147', findRichText: true));
    expect(tapped, 147);
  });
}
