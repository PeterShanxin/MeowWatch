import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/sync/peer_state.dart';
import 'package:meowwatch/core/theme/meow_context.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/ui/chat/chat_corner.dart';
import 'package:meowwatch/ui/chat/chat_overlay.dart';
import 'package:meowwatch/ui/chat/chat_overlay_layout.dart';
import 'package:meowwatch/ui/chat/chat_overlay_region.dart';

/// P3 of the 2026-07 perf review (#196): chat/typing/pulse/unread events must
/// dirty only the chat card's own subtree, not the whole room Stack. The
/// region subscribes to ValueNotifiers, so the parent never needs a setState
/// for those events — these tests pin down that a notifier bump updates the
/// card without rebuilding the host.
void main() {
  late ValueNotifier<List<ChatMessage>> messages;
  late ValueNotifier<String?> typingLabel;
  late ValueNotifier<bool> pulsing;
  late ValueNotifier<bool> hasUnread;

  setUp(() {
    messages = ValueNotifier<List<ChatMessage>>(const <ChatMessage>[]);
    typingLabel = ValueNotifier<String?>(null);
    pulsing = ValueNotifier<bool>(false);
    hasUnread = ValueNotifier<bool>(false);
  });

  tearDown(() {
    messages.dispose();
    typingLabel.dispose();
    pulsing.dispose();
    hasUnread.dispose();
  });

  Widget region({ChatOverlayLayout? layout, bool isUiIdle = false}) {
    return ChatOverlayRegion(
      messages: messages,
      typingLabel: typingLabel,
      pulsing: pulsing,
      hasUnread: hasUnread,
      layout: layout ??
          const ChatOverlayLayout(
            collapsed: false,
            corner: ChatCorner.bottomLeft,
            lastCorner: ChatCorner.bottomLeft,
          ),
      isUiIdle: isUiIdle,
      isUiDeepIdle: false,
      autoDim: true,
      wakeOnMessage: false,
      idleDimOpacity: 0.5,
      onSend: (_) {},
      onTypingChanged: (_) {},
      onToggleCollapsed: () {},
      onSnap: (_) {},
      onDraggingChanged: (_) {},
      onUnreadChanged: (_) {},
      onResize: (_) {},
      onResetSize: () {},
    );
  }

  /// Host whose build() is counted, so a notifier bump inside the region can
  /// be shown to leave the parent untouched — the property that kills the
  /// full-Stack rebuild per chat event.
  var hostBuilds = 0;
  Widget host(Widget child) {
    return MaterialApp(
      theme: themeDataFor(MeowThemeId.cozy),
      home: Scaffold(
        body: Builder(
          builder: (context) {
            hostBuilds++;
            return child;
          },
        ),
      ),
    );
  }

  testWidgets('new message appears without rebuilding the host', (tester) async {
    hostBuilds = 0;
    await tester.pumpWidget(host(region()));
    final builds = hostBuilds;

    messages.value = const [
      ChatMessage(username: 'lin', text: 'hi there', isMine: false),
    ];
    await tester.pump();

    expect(find.text('hi there'), findsOneWidget);
    expect(hostBuilds, builds);
  });

  testWidgets('typing label surfaces without rebuilding the host',
      (tester) async {
    hostBuilds = 0;
    await tester.pumpWidget(host(region()));
    final builds = hostBuilds;

    typingLabel.value = 'lin is typing…';
    await tester.pump();

    expect(find.text('lin is typing…'), findsOneWidget);
    expect(hostBuilds, builds);
  });

  testWidgets('unread flip drives the collapsed idle opacity', (tester) async {
    const collapsed = ChatOverlayLayout(
      collapsed: true,
      corner: ChatCorner.bottomLeft,
      lastCorner: ChatCorner.bottomLeft,
    );
    await tester.pumpWidget(host(region(layout: collapsed, isUiIdle: true)));

    // Collapsed + idle + nothing unread: the tab hides entirely.
    AnimatedOpacity fade() => tester.widget<AnimatedOpacity>(
          find
              .ancestor(
                of: find.byType(ChatOverlay),
                matching: find.byType(AnimatedOpacity),
              )
              .first,
        );
    expect(fade().opacity, 0.0);

    // An unread message keeps the minimized tab flagged (#43).
    hasUnread.value = true;
    await tester.pump();
    expect(fade().opacity, 1.0);
  });

  testWidgets('mounts ChatOverlay under IgnorePointer, never a bare Stack',
      (tester) async {
    // ChatOverlay's render path must stay legal outside a Stack (#50) — the
    // region preserves the AnimatedOpacity > IgnorePointer mount the real
    // room screen uses.
    await tester.pumpWidget(host(region()));
    expect(
      find.ancestor(
        of: find.byType(ChatOverlay),
        matching: find.byType(IgnorePointer),
      ),
      findsWidgets,
    );
  });
}
