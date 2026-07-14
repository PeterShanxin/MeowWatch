import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/meow_context.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/core/video/playback_bar_view.dart';
import 'package:meowwatch/core/video/playback_state.dart';
import 'package:meowwatch/ui/playback_bar.dart';

const _sample = PlaybackState(
  status: PlaybackStatus.paused,
  position: Duration(minutes: 1),
  duration: Duration(minutes: 5),
  fileName: 'movie.mkv',
);

double _thumbR(WidgetTester tester) =>
    (tester.widget<SliderTheme>(find.byType(SliderTheme)).data.thumbShape
            as RoundSliderThumbShape)
        .enabledThumbRadius;

void main() {
  test('scrubber metrics grow from rest to active', () {
    expect(scrubberMetrics(0).thumb, 6);
    expect(scrubberMetrics(1).thumb, greaterThan(scrubberMetrics(0).thumb));
    expect(scrubberMetrics(1).track, greaterThan(scrubberMetrics(0).track));
    expect(scrubberMetrics(1).overlay, greaterThan(scrubberMetrics(0).overlay));
  });

  testWidgets('scrubber thumb grows while dragging, shrinks on release',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: themeDataFor(MeowThemeId.cozy),
      home: Scaffold(
        body: PlaybackBar(
          view: PlaybackBarView.of(_sample),
          onSeek: (_) {},
          onTogglePlay: () {},
          onToggleMute: () {},
          onSetVolume: (_) {},
          isFullscreen: false,
          onToggleFullscreen: () {},
        ),
      ),
    ));
    expect(_thumbR(tester), closeTo(6, 0.01));

    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(Slider)));
    await tester.pump();
    await gesture.moveBy(const Offset(8, 0)); // ensure the drag actually starts
    await tester.pumpAndSettle();
    expect(_thumbR(tester), greaterThan(6));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(_thumbR(tester), closeTo(6, 0.01));
  });
  testWidgets('shows current position and total duration', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: themeDataFor(MeowThemeId.cozy),
      home: Scaffold(
        body: PlaybackBar(
          view: PlaybackBarView.of(_sample),
          onSeek: (_) {},
          onTogglePlay: () {},
          onToggleMute: () {},
          onSetVolume: (_) {},
          isFullscreen: false,
          onToggleFullscreen: () {},
        ),
      ),
    ));
    expect(find.text('01:00'), findsOneWidget);
    expect(find.text('05:00'), findsOneWidget);
  });

  testWidgets('play/pause button fires onTogglePlay', (tester) async {
    var toggled = false;
    await tester.pumpWidget(MaterialApp(
      theme: themeDataFor(MeowThemeId.cozy),
      home: Scaffold(
        body: PlaybackBar(
          view: PlaybackBarView.of(_sample),
          onSeek: (_) {},
          onTogglePlay: () => toggled = true,
          onToggleMute: () {},
          onSetVolume: (_) {},
          isFullscreen: false,
          onToggleFullscreen: () {},
        ),
      ),
    ));
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    // Drain the play/pause icon's double-tap recognizer countdown timer.
    await tester.pump(const Duration(milliseconds: 400));
    expect(toggled, isTrue);
  });

  testWidgets('volume button fires onToggleMute', (tester) async {
    var muted = false;
    await tester.pumpWidget(MaterialApp(
      theme: themeDataFor(MeowThemeId.cozy),
      home: Scaffold(
        body: PlaybackBar(
          view: PlaybackBarView.of(_sample),
          onSeek: (_) {},
          onTogglePlay: () {},
          onToggleMute: () => muted = true,
          onSetVolume: (_) {},
          isFullscreen: false,
          onToggleFullscreen: () {},
        ),
      ),
    ));
    // _sample leaves volume at its 1.0 default → "up" icon.
    await tester.tap(find.byIcon(Icons.volume_up_rounded));
    // Drain the volume icon's double-tap recognizer countdown timer.
    await tester.pump(const Duration(milliseconds: 400));
    expect(muted, isTrue);
  });

  testWidgets('PlaybackBar accepts onSetVolume callback', (tester) async {
    double? set;
    await tester.pumpWidget(MaterialApp(
      theme: themeDataFor(MeowThemeId.cozy),
      home: Scaffold(
        body: PlaybackBar(
          view: PlaybackBarView.of(_sample),
          onSeek: (_) {},
          onTogglePlay: () {},
          onToggleMute: () {},
          onSetVolume: (v) => set = v,
          isFullscreen: false,
          onToggleFullscreen: () {},
        ),
      ),
    ));
    // Param wired — compile-time check sufficient; runtime wiring tested in volume_control_test.
    expect(set, isNull); // slider not yet interacted
  });

  testWidgets('volume icon reflects the current level', (tester) async {
    Future<void> pumpAt(double volume) async {
      await tester.pumpWidget(MaterialApp(
        theme: themeDataFor(MeowThemeId.cozy),
        home: Scaffold(
          body: PlaybackBar(
            view: PlaybackBarView.of(_sample.copyWith(volume: volume)),
            onSeek: (_) {},
            onTogglePlay: () {},
            onToggleMute: () {},
            onSetVolume: (_) {},
            isFullscreen: false,
            onToggleFullscreen: () {},
          ),
        ),
      ));
    }

    await pumpAt(0.0);
    expect(find.byIcon(Icons.volume_off_rounded), findsOneWidget);

    await pumpAt(0.3);
    expect(find.byIcon(Icons.volume_down_rounded), findsOneWidget);

    await pumpAt(0.9);
    expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);
  });

  testWidgets('fullscreen icon reflects state and button fires callback',
      (tester) async {
    var toggled = false;
    Future<void> pumpAt(bool isFullscreen) async {
      await tester.pumpWidget(MaterialApp(
        theme: themeDataFor(MeowThemeId.cozy),
        home: Scaffold(
          body: PlaybackBar(
            view: PlaybackBarView.of(_sample),
            onSeek: (_) {},
            onTogglePlay: () {},
            onToggleMute: () {},
            onSetVolume: (_) {},
            isFullscreen: isFullscreen,
            onToggleFullscreen: () => toggled = true,
          ),
        ),
      ));
    }

    await pumpAt(false);
    expect(find.byIcon(Icons.fullscreen_rounded), findsOneWidget);
    expect(find.byIcon(Icons.fullscreen_exit_rounded), findsNothing);

    await tester.tap(find.byIcon(Icons.fullscreen_rounded));
    // Drain the icon's double-tap recognizer countdown timer.
    await tester.pump(const Duration(milliseconds: 400));
    expect(toggled, isTrue);

    await pumpAt(true);
    expect(find.byIcon(Icons.fullscreen_exit_rounded), findsOneWidget);
    expect(find.byIcon(Icons.fullscreen_rounded), findsNothing);
  });
}
