import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/reduce_motion.dart';

void main() {
  testWidgets('reduceMotion is false by default', (tester) async {
    late bool value;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(builder: (context) {
          value = context.reduceMotion;
          return const SizedBox();
        }),
      ),
    );
    expect(value, isFalse);
  });

  testWidgets('a ReduceMotionScope turns it on for descendants',
      (tester) async {
    late bool value;
    await tester.pumpWidget(
      MaterialApp(
        home: ReduceMotionScope(
          reduceMotion: true,
          child: Builder(builder: (context) {
            value = context.reduceMotion;
            return const SizedBox();
          }),
        ),
      ),
    );
    expect(value, isTrue);
  });

  testWidgets('the OS disableAnimations flag turns it on', (tester) async {
    late bool value;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: Builder(builder: (context) {
            value = context.reduceMotion;
            return const SizedBox();
          }),
        ),
      ),
    );
    expect(value, isTrue);
  });
}
