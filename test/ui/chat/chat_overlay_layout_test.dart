import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/ui/chat/chat_corner.dart';
import 'package:meowwatch/ui/chat/chat_overlay_layout.dart';

void main() {
  test('defaults to bottomLeft, expanded', () {
    const l = ChatOverlayLayout();
    expect(l.corner, ChatCorner.bottomLeft);
    expect(l.collapsed, isFalse);
  });

  test('applySnap to a corner moves there and stays expanded', () {
    final l = const ChatOverlayLayout()
        .applySnap(const SnapResult.corner(ChatCorner.topRight));
    expect(l.corner, ChatCorner.topRight);
    expect(l.collapsed, isFalse);
  });

  test('applySnap collapse remembers the current corner', () {
    final l = const ChatOverlayLayout(corner: ChatCorner.topRight)
        .applySnap(const SnapResult.collapse());
    expect(l.collapsed, isTrue);
    expect(l.lastCorner, ChatCorner.topRight);
  });

  test('toggle collapses an expanded card, remembering corner', () {
    final l = const ChatOverlayLayout(corner: ChatCorner.bottomRight).toggle();
    expect(l.collapsed, isTrue);
    expect(l.lastCorner, ChatCorner.bottomRight);
  });

  test('toggle expands a collapsed card back to lastCorner', () {
    const collapsed = ChatOverlayLayout(
      corner: ChatCorner.bottomLeft,
      collapsed: true,
      lastCorner: ChatCorner.topRight,
    );
    final l = collapsed.toggle();
    expect(l.collapsed, isFalse);
    expect(l.corner, ChatCorner.topRight);
  });
}
