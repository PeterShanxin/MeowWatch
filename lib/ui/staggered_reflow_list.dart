import 'package:flutter/material.dart';

import '../core/theme/tokens/motion.dart';

/// One child of a [StaggeredReflowList], paired with the stable [id] that lets
/// the list tell a card that *moved* from one that *left while a new one
/// arrived*. Two builds with the same [id] are the same logical row.
@immutable
class ReflowChild {
  const ReflowChild({required this.id, required this.child});

  /// Stable identity across rebuilds (e.g. a history row's database id).
  final Object id;
  final Widget child;
}

/// A vertical list that animates its own reflow: when [children] changes,
/// surviving rows glide to their new slot, arriving rows ripple in top-to-bottom
/// (the "staggered cascade"), and leaving rows fade + collapse out.
///
/// This is the Flutter port of the design-system Motion study's variant C.
/// `AnimatedSwitcher` can't reorder, so each row is keyed by [ReflowChild.id]
/// and animated independently.
///
/// Two timelines per row keep the motion smooth:
///  * **Height** animates on a single shared duration ([glideDuration]) with no
///    stagger, so the list's *total* height grows/shrinks as one even tween and
///    the surrounding layout glides instead of lurching in steps.
///  * **Content** (fade + scale + rise) is staggered top-to-bottom, so the
///    visible ripple still reads as a cascade.
///
/// The very first build is static — only later [children] changes animate — so
/// opening a screen doesn't cascade every time.
class StaggeredReflowList extends StatefulWidget {
  const StaggeredReflowList({
    super.key,
    required this.children,
    this.stagger = Motion.stagger,
    this.glideDuration = Motion.base,
    this.enterDuration = Motion.base,
    this.exitDuration = Motion.base,
    this.curve = Motion.standard,
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
  });

  final List<ReflowChild> children;

  /// Per-row content delay applied top-to-bottom so arrivals ripple instead of
  /// popping in together. Does not affect the height glide.
  final Duration stagger;

  /// How long the list's height takes to settle — shared by every row so the
  /// total height moves as one smooth tween.
  final Duration glideDuration;

  /// How long a row's fade/scale-in takes (the stagger lead is added on top).
  final Duration enterDuration;
  final Duration exitDuration;
  final Curve curve;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  State<StaggeredReflowList> createState() => _StaggeredReflowListState();
}

/// A mounted row, including ones still animating out (kept until their exit
/// finishes so they collapse in place rather than vanishing).
class _Slot {
  _Slot({
    required this.id,
    required this.child,
    required this.height,
    required this.content,
    required this.heightCurve,
    required this.contentCurve,
  });

  final Object id;
  Widget child;

  /// Layout timeline (shared duration, no stagger) → smooth aggregate height.
  final AnimationController height;

  /// Visual timeline (staggered) → the fade/scale/rise ripple.
  final AnimationController content;
  final CurvedAnimation heightCurve;
  final CurvedAnimation contentCurve;
  bool leaving = false;
}

class _StaggeredReflowListState extends State<StaggeredReflowList>
    with TickerProviderStateMixin {
  final List<_Slot> _slots = [];

  @override
  void initState() {
    super.initState();
    // First build is static: every row starts fully present.
    for (final c in widget.children) {
      _slots.add(_createSlot(c.id, c.child, value: 1));
    }
  }

  @override
  void didUpdateWidget(StaggeredReflowList old) {
    super.didUpdateWidget(old);
    _sync(widget.children);
  }

  @override
  void dispose() {
    for (final s in _slots) {
      s.heightCurve.dispose();
      s.contentCurve.dispose();
      s.height.dispose();
      s.content.dispose();
    }
    super.dispose();
  }

  /// Build a row's two controllers + curves. Height runs over [glideDuration]
  /// for every row (so the list height settles as one even tween). Content runs
  /// over `enterDuration + staggerIndex * stagger`, with the lead-in expressed
  /// as a leading [Interval] on the curve — controller-driven, so it is
  /// deterministic with no timers. The exit ignores the lead ([reverseCurve]).
  _Slot _createSlot(
    Object id,
    Widget child, {
    required double value,
    int staggerIndex = 0,
  }) {
    final height = AnimationController(
      vsync: this,
      duration: widget.glideDuration,
      reverseDuration: widget.exitDuration,
      value: value,
    );
    final delay = widget.stagger * staggerIndex;
    final contentTotal = widget.enterDuration + delay;
    final content = AnimationController(
      vsync: this,
      duration: contentTotal,
      reverseDuration: widget.exitDuration,
      value: value,
    );
    final lead = contentTotal.inMicroseconds == 0
        ? 0.0
        : delay.inMicroseconds / contentTotal.inMicroseconds;
    return _Slot(
      id: id,
      child: child,
      height: height,
      content: content,
      heightCurve: CurvedAnimation(parent: height, curve: widget.curve),
      contentCurve: CurvedAnimation(
        parent: content,
        curve: Interval(lead, 1, curve: widget.curve),
        reverseCurve: widget.curve,
      ),
    );
  }

  /// Diff [next] against the mounted rows: refresh survivors, schedule arrivals
  /// (staggered content, shared height) and departures (collapse), then re-sort
  /// so leavers stay where they were while survivors/arrivals take the new
  /// order.
  void _sync(List<ReflowChild> next) {
    final nextIds = <Object>[for (final c in next) c.id];
    final nextSet = nextIds.toSet();
    final byId = <Object, _Slot>{for (final s in _slots) s.id: s};
    final oldOrder = List<_Slot>.of(_slots);

    for (var i = 0; i < next.length; i++) {
      final c = next[i];
      final existing = byId[c.id];
      if (existing != null) {
        existing.child = c.child; // content may have changed (progress, time)
        if (existing.leaving) {
          // It was on its way out but reappeared before finishing — reverse the
          // exit back to fully present.
          existing.leaving = false;
          existing.height.forward();
          existing.content.forward();
        }
      } else {
        // staggerIndex is the row's position in the new list, so rows lower down
        // ripple their content in slightly later.
        final slot = _createSlot(c.id, c.child, value: 0, staggerIndex: i);
        _slots.add(slot);
        byId[c.id] = slot;
        slot.height.forward();
        slot.content.forward();
      }
    }

    for (final s in oldOrder) {
      if (!nextSet.contains(s.id) && !s.leaving) {
        s.leaving = true;
        s.content.reverse();
        s.height.reverse().then((_) => _onExitDone(s));
      }
    }

    _reorder(nextIds, oldOrder);
    setState(() {});
  }

  void _onExitDone(_Slot slot) {
    // Only finalize a row that is still leaving and actually finished collapsing
    // — a revived or interrupted exit is handled elsewhere.
    if (!slot.leaving || slot.height.status != AnimationStatus.dismissed) {
      return;
    }
    slot.heightCurve.dispose();
    slot.contentCurve.dispose();
    slot.height.dispose();
    slot.content.dispose();
    if (mounted) {
      setState(() => _slots.remove(slot));
    } else {
      _slots.remove(slot);
    }
  }

  /// Order survivors/arrivals by their index in [nextIds]; splice each leaver in
  /// just after the survivor it followed in [oldOrder] so it collapses in place.
  void _reorder(List<Object> nextIds, List<_Slot> oldOrder) {
    final keyOf = <Object, double>{};
    for (var i = 0; i < nextIds.length; i++) {
      keyOf[nextIds[i]] = i.toDouble();
    }
    var lastKey = -1.0;
    for (final s in oldOrder) {
      final present = keyOf[s.id];
      if (present != null) {
        lastKey = present;
      } else {
        lastKey += 0.001; // keep consecutive leavers in their old order
        keyOf[s.id] = lastKey;
      }
    }
    _slots.sort(
      (a, b) => (keyOf[a.id] ?? double.maxFinite)
          .compareTo(keyOf[b.id] ?? double.maxFinite),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: widget.crossAxisAlignment,
      mainAxisSize: MainAxisSize.min,
      children: [for (final s in _slots) _buildSlot(s)],
    );
  }

  Widget _buildSlot(_Slot slot) {
    return SizeTransition(
      key: ValueKey(slot.id),
      sizeFactor: slot.heightCurve,
      alignment: Alignment.topCenter, // collapse toward the top edge
      child: AnimatedBuilder(
        animation: slot.contentCurve,
        builder: (context, child) {
          final t = slot.contentCurve.value.clamp(0.0, 1.0);
          return Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, (1 - t) * 8),
              child: Transform.scale(
                scale: 0.97 + 0.03 * t,
                alignment: Alignment.topCenter,
                child: child,
              ),
            ),
          );
        },
        child: slot.child,
      ),
    );
  }
}
