import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/sync/syncplay_constants.dart';
import 'package:meowwatch/core/theme/meow_context.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/ui/chat/chat_input.dart';

String _fieldText(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;

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

  testWidgets('plain Enter sends the message (#56)', (tester) async {
    final sent = <String>[];
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(host(ChatInput(onSend: sent.add, focusNode: focus)));

    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'hello');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(sent, ['hello']);
    expect(_fieldText(tester), isEmpty); // field cleared on send
  });

  // Shift+Enter must NOT send (the #56 regression). The newline insertion
  // itself is EditableText's built-in multiline behavior on desktop — the test
  // harness doesn't drive it from a synthetic key event, so we assert only the
  // contract this widget owns: the message isn't submitted and the draft is
  // left intact (not cleared as a send would).
  testWidgets('Shift+Enter does not send the message (#56)', (tester) async {
    final sent = <String>[];
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(host(ChatInput(onSend: sent.add, focusNode: focus)));

    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'line1');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(sent, isEmpty);
    expect(_fieldText(tester), 'line1'); // draft kept, not submitted/cleared
  });

  testWidgets('caps input at the Syncplay max chat length (#55)',
      (tester) async {
    await tester.pumpWidget(host(ChatInput(onSend: (_) {})));

    final tooLong = 'x' * (SyncplayConstants.maxChatMessageLength + 50);
    await tester.enterText(find.byType(TextField), tooLong);
    await tester.pump();

    expect(_fieldText(tester).length, SyncplayConstants.maxChatMessageLength);
  });

  testWidgets('draft survives via an external controller (#59)', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    // First mount: type a draft.
    await tester.pumpWidget(host(ChatInput(onSend: (_) {}, controller: controller)));
    await tester.enterText(find.byType(TextField), 'half-typed');
    await tester.pump();

    // Remount a fresh ChatInput around the SAME controller (simulates the input
    // being torn down on collapse/focus-loss while the parent keeps the draft).
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(host(ChatInput(onSend: (_) {}, controller: controller)));
    await tester.pump();

    expect(_fieldText(tester), 'half-typed');
  });
}
