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
/// and animated independently: arrivals/departures drive a [SizeTransition], and
/// the surrounding [Column] reflows survivors as those heights change — no
/// explicit per-survivor transform needed, since here rows only shift vertically
/// (they never cross each other).
///
/// The very first build is static — only later [children] changes animate — so
/// opening a screen doesn't cascade every time.
class StaggeredReflowList extends StatefulWidget {
  const StaggeredReflowList({
    super.key,
    required this.children,
    this.stagger = Motion.stagger,
    this.enterDuration = Motion.slow,
    this.exitDuration = Motion.base,
    this.curve = Motion.standard,
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
  });

  final List<ReflowChild> children;

  /// Per-row delay applied top-to-bottom so arrivals ripple instead of popping
  /// in together.
  final Duration stagger;
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
    required this.controller,
    required this.animation,
  });

  final Object id;
  Widget child;
  final AnimationController controller;
  final CurvedAnimation animation;
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
      s.animation.dispose();
      s.controller.dispose();
    }
    super.dispose();
  }

  /// Build a row's controller + curve. [staggerIndex] bakes the cascade delay
  /// into the entrance as a leading [Interval] on the curve, so the whole
  /// animation is driven by the controller clock alone (deterministic, no
  /// timers): lower rows hold at 0 for `staggerIndex * stagger` before easing
  /// open. The exit ignores that lead-in ([reverseCurve]) so departures collapse
  /// promptly.
  _Slot _createSlot(
    Object id,
    Widget child, {
    required double value,
    int staggerIndex = 0,
  }) {
    final delay = widget.stagger * staggerIndex;
    final enterTotal = widget.enterDuration + delay;
    final controller = AnimationController(
      vsync: this,
      duration: enterTotal,
      reverseDuration: widget.exitDuration,
      value: value,
    );
    final lead = enterTotal.inMicroseconds == 0
        ? 0.0
        : delay.inMicroseconds / enterTotal.inMicroseconds;
    final animation = CurvedAnimation(
      parent: controller,
      curve: Interval(lead, 1, curve: widget.curve),
      reverseCurve: widget.curve,
    );
    return _Slot(
      id: id,
      child: child,
      controller: controller,
      animation: animation,
    );
  }

  /// Diff [next] against the mounted rows: refresh survivors, schedule arrivals
  /// (staggered) and departures (collapse), then re-sort so leavers stay where
  /// they were while survivors/arrivals take the new order.
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
          existing.controller.forward();
        }
      } else {
        // staggerIndex is the row's position in the new list, so rows lower down
        // open slightly later and the list ripples top-to-bottom.
        final slot = _createSlot(c.id, c.child, value: 0, staggerIndex: i);
        _slots.add(slot);
        byId[c.id] = slot;
        slot.controller.forward();
      }
    }

    for (final s in oldOrder) {
      if (!nextSet.contains(s.id) && !s.leaving) {
        s.leaving = true;
        s.controller.reverse().then((_) => _onExitDone(s));
      }
    }

    _reorder(nextIds, oldOrder);
    setState(() {});
  }

  void _onExitDone(_Slot slot) {
    // Only finalize a row that is still leaving and actually finished collapsing
    // — a revived or interrupted exit is handled elsewhere.
    if (!slot.leaving ||
        slot.controller.status != AnimationStatus.dismissed) {
      return;
    }
    slot.animation.dispose();
    slot.controller.dispose();
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
      sizeFactor: slot.animation,
      alignment: Alignment.topCenter, // collapse toward the top edge
      child: FadeTransition(
        opacity: slot.animation,
        child: AnimatedBuilder(
          animation: slot.animation,
          builder: (context, child) {
            final t = slot.animation.value;
            return Transform.translate(
              offset: Offset(0, (1 - t) * 8),
              child: Transform.scale(
                scale: 0.97 + 0.03 * t,
                alignment: Alignment.topCenter,
                child: child,
              ),
            );
          },
          child: slot.child,
        ),
      ),
    );
  }
}
