import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/ui/chat/chat_corner.dart';
import 'package:meowwatch/ui/chat/chat_overlay_layout.dart';

void main() {
  test('defaults have null size fractions', () {
    const l = ChatOverlayLayout();
    expect(l.widthFrac, isNull);
    expect(l.heightFrac, isNull);
  });

  test('applyResize derives fractions from px over window', () {
    const l = ChatOverlayLayout();
    final r = l.applyResize(const Size(300, 400), const Size(1000, 800));
    expect(r.widthFrac, closeTo(0.30, 1e-9));
    expect(r.heightFrac, closeTo(0.50, 1e-9));
  });

  test('resetSize clears fractions but keeps corner', () {
    final l = const ChatOverlayLayout(corner: ChatCorner.topRight)
        .applyResize(const Size(500, 600), const Size(1000, 800));
    final r = l.resetSize();
    expect(r.widthFrac, isNull);
    expect(r.heightFrac, isNull);
    expect(r.corner, ChatCorner.topRight);
  });

  test('format and parse round-trip', () {
    expect(formatCardSizeFraction(0.42, 0.63), '0.42,0.63');
    expect(parseCardSizeFraction('0.42,0.63'), (0.42, 0.63));
  });

  test('parse returns nulls for empty or malformed input', () {
    expect(parseCardSizeFraction(null), (null, null));
    expect(parseCardSizeFraction(''), (null, null));
    expect(parseCardSizeFraction('garbage'), (null, null));
    expect(parseCardSizeFraction('1.5,0.5'), (null, null)); // out of range
  });

  test('equality includes size fractions', () {
    final a = const ChatOverlayLayout()
        .applyResize(const Size(300, 400), const Size(1000, 800));
    final b = const ChatOverlayLayout()
        .applyResize(const Size(300, 400), const Size(1000, 800));
    expect(a, b);
    expect(a, isNot(const ChatOverlayLayout()));
  });
}
