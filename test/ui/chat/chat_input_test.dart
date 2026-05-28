import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/ui/chat/chat_input.dart';

void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('send button fires onSend with text and clears field',
      (tester) async {
    final sent = <String>[];
    await tester.pumpWidget(host(ChatInput(onSend: sent.add)));

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    expect(sent, ['hello']);
    expect(find.text('hello'), findsNothing); // field cleared
  });

  testWidgets('blank input does not fire onSend', (tester) async {
    final sent = <String>[];
    await tester.pumpWidget(host(ChatInput(onSend: sent.add)));

    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    expect(sent, isEmpty);
  });
}
