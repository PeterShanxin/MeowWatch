import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/ui/chat/peek_tab.dart';

void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('is 14px wide and taps to expand', (tester) async {
    var tapped = false;
    await tester.pumpWidget(host(PeekTab(
      pulsing: false,
      onTap: () => tapped = true,
    )));

    final box = tester.getSize(find.byType(PeekTab));
    expect(box.width, 14);

    await tester.tap(find.byType(PeekTab));
    await tester.pump();
    expect(tapped, isTrue);
  });
}
