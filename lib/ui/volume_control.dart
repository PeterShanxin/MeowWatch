import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme/meow_context.dart';
import '../core/theme/tokens/radii.dart';
import '../core/theme/tokens/spacing.dart';
import 'instant_tap_icon.dart';

/// Volume button with on-hover vertical slider.
///
/// - Hover the icon → a short vertical slider panel appears just above it.
/// - Move the cursor away → panel hides after a short debounce.
/// - Tap the icon → mute/unmute via [onToggleMute].
/// - Drag the slider → [onSetVolume] (0.0–1.0).
///
/// The panel is rendered in the [Overlay] (above all other content) so it
/// never displaces adjacent widgets and the PlaybackBar's layout height stays
/// constant. It is positioned with an explicit [Positioned] computed from the
/// icon's render box — NOT a [CompositedTransformFollower], because OverlayPortal
/// hands its overlay child tight full-screen constraints, which a follower
/// passes straight through (the panel would fill the whole window).
class VolumeControl extends StatefulWidget {
  const VolumeControl({
    required this.volume,
    required this.onSetVolume,
    required this.onToggleMute,
    super.key,
  });

  final double volume;
  final ValueChanged<double> onSetVolume;
  final VoidCallback onToggleMute;

  @override
  State<VolumeControl> createState() => _VolumeControlState();
}

class _VolumeControlState extends State<VolumeControl> {
  final OverlayPortalController _overlay = OverlayPortalController();
  final GlobalKey _iconKey = GlobalKey();

  bool _isDragging = false;
  bool _panelHovered = false;
  Timer? _hideTimer;

  static const _hideDelay = Duration(milliseconds: 150);
  static const double _panelWidth = 40;
  static const double _panelHeight = 120;
  // Vertical gap between the icon's top edge and the panel's bottom edge.
  static const double _gap = Spacing.xs;

  // ── icon hover ────────────────────────────────────────────────────────────

  void _onIconEnter(_) {
    _hideTimer?.cancel();
    if (!_overlay.isShowing) _overlay.show();
  }

  void _onIconExit(_) {
    if (_isDragging) return;
    _scheduleHide();
  }

  // ── panel hover ───────────────────────────────────────────────────────────

  void _onPanelEnter(_) {
    _hideTimer?.cancel();
    _panelHovered = true;
  }

  void _onPanelExit(_) {
    _panelHovered = false;
    if (_isDragging) return;
    _scheduleHide();
  }

  // ── drag ──────────────────────────────────────────────────────────────────

  void _onDragStart(_) {
    _hideTimer?.cancel();
    _isDragging = true;
  }

  void _onDragEnd(_) {
    _isDragging = false;
    // The cursor may have left the widget during the drag; run the hide
    // check after the debounce in case no enter event re-arms it.
    _scheduleHide();
  }

  // ── shared ────────────────────────────────────────────────────────────────

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_hideDelay, () {
      if (mounted && !_panelHovered && !_isDragging) _overlay.hide();
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  IconData get _icon {
    if (widget.volume <= 0.0) return Icons.volume_off_rounded;
    if (widget.volume < 0.5) return Icons.volume_down_rounded;
    return Icons.volume_up_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    return OverlayPortal(
      controller: _overlay,
      overlayChildBuilder: _buildPanel,
      child: MouseRegion(
        onEnter: _onIconEnter,
        onExit: _onIconExit,
        child: InstantTapIcon(
          key: _iconKey,
          icon: _icon,
          color: m.textPrimary,
          semanticLabel: 'Mute',
          onPressed: widget.onToggleMute,
        ),
      ),
    );
  }

  Widget _buildPanel(BuildContext context) {
    final box = _iconKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return const SizedBox.shrink();

    // Overlay fills the window from the origin, so global coordinates map
    // directly to overlay-local coordinates.
    final topLeft = box.localToGlobal(Offset.zero);
    final iconCenterX = topLeft.dx + box.size.width / 2;
    // Clamp to the window so the panel can't clip past an edge near a corner.
    final screen = MediaQuery.sizeOf(context);
    final left = (iconCenterX - _panelWidth / 2)
        .clamp(0.0, (screen.width - _panelWidth).clamp(0.0, double.infinity));
    final top = (topLeft.dy - _panelHeight - _gap)
        .clamp(0.0, (screen.height - _panelHeight).clamp(0.0, double.infinity));

    final m = context.meow;
    return Positioned(
      left: left,
      top: top,
      width: _panelWidth,
      height: _panelHeight,
      child: MouseRegion(
        onEnter: _onPanelEnter,
        onExit: _onPanelExit,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: m.scrim.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
            child: RotatedBox(
              quarterTurns: 3,
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 3,
                  activeTrackColor: m.accent,
                  inactiveTrackColor: m.textPrimary.withValues(alpha: 0.33),
                  thumbColor: m.accent,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                ),
                child: Semantics(
                  label: 'Volume',
                  child: Slider(
                    value: widget.volume.clamp(0.0, 1.0),
                    onChangeStart: _onDragStart,
                    onChanged: widget.onSetVolume,
                    onChangeEnd: _onDragEnd,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
