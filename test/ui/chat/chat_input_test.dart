import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/meow_context.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/ui/chat/chat_input.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
        theme: themeDataFor(MeowThemeId.cozy),
        home: Scaffold(body: child),
      );

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

  testWidgets('typing pulses onTypingChanged true then false on idle',
      (tester) async {
    final events = <bool>[];
    await tester.pumpWidget(host(ChatInput(
      onSend: (_) {},
      onTypingChanged: events.add,
    )));

    await tester.enterText(find.byType(TextField), 'h');
    expect(events, [true]);

    // After the idle delay (1800ms) it reports stopped.
    await tester.pump(const Duration(milliseconds: 2000));
    expect(events, [true, false]);
  });

  testWidgets('sending restores focus to the input (issue #8)', (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(host(ChatInput(onSend: (_) {}, focusNode: focus)));

    // Focus the field, type, and send — focus should bounce straight back so
    // the user can keep typing without re-clicking the box.
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'hi');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    expect(focus.hasFocus, isTrue);
  });

  testWidgets('sending clears the typing state', (tester) async {
    final events = <bool>[];
    await tester.pumpWidget(host(ChatInput(
      onSend: (_) {},
      onTypingChanged: events.add,
    )));

    await tester.enterText(find.byType(TextField), 'hi');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    expect(events, [true, false]);
  });
}
