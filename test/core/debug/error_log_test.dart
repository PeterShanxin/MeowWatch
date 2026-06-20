import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/debug/error_log.dart';

void main() {
  test('formats kind and message under the error: prefix', () {
    expect(
      errorLogLine('flutter', 'Boom went the widget'),
      'error: flutter: Boom went the widget',
    );
  });

  test('redacts a credential-bearing URL in the message', () {
    final line = errorLogLine(
      'uncaught',
      'failed loading https://user:tok@cdn.example/c.mp4?sig=abc#x',
    );
    expect(line, contains('https://cdn.example/c.mp4'));
    expect(line, isNot(contains('tok')));
    expect(line, isNot(contains('sig=abc')));
  });

  test('appends the stack trace on a second line when given', () {
    final stack = StackTrace.fromString('#0 foo\n#1 bar');
    final line = errorLogLine('uncaught', 'kaboom', stack);
    expect(line, startsWith('error: uncaught: kaboom\n'));
    expect(line, contains('#0 foo'));
    expect(line, contains('#1 bar'));
  });

  test('omits the stack section when null or empty', () {
    expect(errorLogLine('flutter', 'x', null), 'error: flutter: x');
    expect(
      errorLogLine('flutter', 'x', StackTrace.fromString('   ')),
      'error: flutter: x',
    );
  });

  test('error: lines are neat-kept (not the verbose firehose)', () {
    // No trace:/raw/apply=false markers, so isVerboseOnly must not drop them.
    expect(errorLogLine('flutter', 'x'), startsWith('error: '));
  });
}
