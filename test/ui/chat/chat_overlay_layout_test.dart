import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/ui/chat/chat_corner.dart';
import 'package:meowwatch/ui/chat/chat_overlay_layout.dart';

void main() {
  test('defaults have null px size', () {
    const l = ChatOverlayLayout();
    expect(l.widthPx, isNull);
    expect(l.heightPx, isNull);
  });

  test('applyResize stores the px size verbatim', () {
    const l = ChatOverlayLayout();
    final r = l.applyResize(const Size(300, 400));
    expect(r.widthPx, 300);
    expect(r.heightPx, 400);
  });

  test('resetSize clears the size but keeps corner', () {
    final l = const ChatOverlayLayout(corner: ChatCorner.topRight)
        .applyResize(const Size(500, 600));
    final r = l.resetSize();
    expect(r.widthPx, isNull);
    expect(r.heightPx, isNull);
    expect(r.corner, ChatCorner.topRight);
  });

  test('format and parse round-trip (rounded px)', () {
    expect(formatCardSize(360, 420), '360,420');
    expect(formatCardSize(360.6, 420.4), '361,420');
    expect(parseCardSize('360,420'), (360.0, 420.0));
  });

  test('parse returns nulls for empty or malformed input', () {
    expect(parseCardSize(null), (null, null));
    expect(parseCardSize(''), (null, null));
    expect(parseCardSize('garbage'), (null, null));
  });

  test('parse rejects legacy fraction strings (below px floor)', () {
    expect(parseCardSize('0.30,0.50'), (null, null));
  });

  test('parse rejects absurdly large values', () {
    expect(parseCardSize('99999,99999'), (null, null));
  });

  test('equality includes px size', () {
    final a = const ChatOverlayLayout().applyResize(const Size(300, 400));
    final b = const ChatOverlayLayout().applyResize(const Size(300, 400));
    expect(a, b);
    expect(a, isNot(const ChatOverlayLayout()));
  });

  test('corner format and parse round-trip for every corner', () {
    for (final corner in ChatCorner.values) {
      expect(parseCardCorner(formatCardCorner(corner)), corner);
    }
  });

  test('corner parse returns null for missing or unknown values', () {
    expect(parseCardCorner(null), isNull);
    expect(parseCardCorner(''), isNull);
    expect(parseCardCorner('garbage'), isNull);
    expect(parseCardCorner('BOTTOMLEFT'), isNull);
  });
}
