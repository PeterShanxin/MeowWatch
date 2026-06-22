import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/ui/staggered_reflow_list.dart';

void main() {
  // A row of fixed height so the SizeTransition's reported size maps cleanly to
  // "how far open" each row is (0 = collapsed, 40 = fully present).
  ReflowChild row(String id, {String? text}) => ReflowChild(
        id: id,
        child: SizedBox(height: 40, child: Text(text ?? id)),
      );

  Widget host(List<ReflowChild> children) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StaggeredReflowList(children: children),
          ),
        ),
      );

  // The list keys each row ValueKey<Object>(id); match that exact type.
  double rowHeight(WidgetTester tester, String id) =>
      tester.getSize(find.byKey(ValueKey<Object>(id))).height;

  testWidgets('first build is static — all rows fully present', (tester) async {
    await tester.pumpWidget(host([row('a'), row('b'), row('c')]));
    await tester.pumpAndSettle();

    expect(find.text('a'), findsOneWidget);
    expect(find.text('b'), findsOneWidget);
    expect(find.text('c'), findsOneWidget);
    expect(rowHeight(tester, 'a'), 40);
    expect(rowHeight(tester, 'c'), 40);
  });

  testWidgets('arriving rows cascade open instead of hard-swapping',
      (tester) async {
    await tester.pumpWidget(host([row('a')]));
    await tester.pumpAndSettle();

    // b and c arrive; a survives.
    await tester.pumpWidget(host([row('a'), row('b'), row('c')]));

    // The instant they arrive they are collapsed (proving an animation, not a
    // hard swap), while the survivor keeps its full height.
    expect(rowHeight(tester, 'a'), 40);
    expect(rowHeight(tester, 'b'), lessThan(2));
    expect(rowHeight(tester, 'c'), lessThan(2));

    // c sits below b, so its staggered entrance lags b's.
    await tester.pump(const Duration(milliseconds: 80));
    expect(rowHeight(tester, 'b'), greaterThan(rowHeight(tester, 'c')));

    // Everything settles fully open.
    await tester.pump(const Duration(seconds: 1));
    expect(rowHeight(tester, 'b'), 40);
    expect(rowHeight(tester, 'c'), 40);
    expect(tester.takeException(), isNull);
  });

  testWidgets('leaving rows collapse out and are removed', (tester) async {
    await tester.pumpWidget(host([row('a'), row('b'), row('c')]));
    await tester.pumpAndSettle();

    // Remove the middle row.
    await tester.pumpWidget(host([row('a'), row('c')]));

    // Still mounted while collapsing.
    expect(find.text('b'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('b'), findsNothing);
    expect(find.text('a'), findsOneWidget);
    expect(find.text('c'), findsOneWidget);
    expect(rowHeight(tester, 'a'), 40);
    expect(rowHeight(tester, 'c'), 40);
    expect(tester.takeException(), isNull);
  });

  testWidgets('same id with new content swaps without re-animating',
      (tester) async {
    await tester.pumpWidget(host([row('a', text: 'first')]));
    await tester.pumpAndSettle();

    await tester.pumpWidget(host([row('a', text: 'second')]));
    await tester.pump();

    expect(find.text('second'), findsOneWidget);
    expect(find.text('first'), findsNothing);
    // No collapse/expand — the row stays put through the content change.
    expect(rowHeight(tester, 'a'), 40);
  });

  testWidgets('rapid toggling never throws and settles to the last state',
      (tester) async {
    await tester.pumpWidget(host([row('a')]));
    await tester.pumpAndSettle();

    for (var i = 0; i < 4; i++) {
      await tester.pumpWidget(host([row('a'), row('b')]));
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pumpWidget(host([row('a')]));
      await tester.pump(const Duration(milliseconds: 10));
    }

    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    expect(find.text('a'), findsOneWidget);
    expect(find.text('b'), findsNothing);
  });
}
