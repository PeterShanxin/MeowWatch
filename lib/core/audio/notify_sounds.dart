import 'package:flutter/foundation.dart';

/// One selectable notification sound: a stable [id] (persisted), a human
/// [label] for the picker, and the media_kit [asset] URI to play.
@immutable
class NotifySound {
  const NotifySound({
    required this.id,
    required this.label,
    required this.asset,
  });

  final String id;
  final String label;
  final String asset;
}

/// Loud, attention-grabbing sounds (played when the window is unfocused).
/// First entry is the default.
const List<NotifySound> kPrimarySounds = <NotifySound>[
  NotifySound(
    id: 'marimba',
    label: 'Wood marimba',
    asset: 'asset:///assets/sounds/primary_marimba.wav',
  ),
  NotifySound(
    id: 'warm_bell',
    label: 'Warm bell',
    asset: 'asset:///assets/sounds/primary_warm_bell.wav',
  ),
  NotifySound(
    id: 'glass',
    label: 'Glass chime',
    asset: 'asset:///assets/sounds/primary_glass.wav',
  ),
];

/// Quiet, felt-not-heard sounds (chat collapsed while playing). First entry is
/// the default.
const List<NotifySound> kSecondarySounds = <NotifySound>[
  NotifySound(
    id: 'low_thud',
    label: 'Low thud',
    asset: 'asset:///assets/sounds/secondary_low_thud.wav',
  ),
  NotifySound(
    id: 'soft_bell',
    label: 'Soft bell',
    asset: 'asset:///assets/sounds/secondary_soft_bell.wav',
  ),
];

const String kDefaultPrimarySoundId = 'marimba';
const String kDefaultSecondarySoundId = 'low_thud';

NotifySound _resolve(List<NotifySound> list, String? id, String defaultId) {
  for (final s in list) {
    if (s.id == id) return s;
  }
  return list.firstWhere((s) => s.id == defaultId);
}

/// Resolve a persisted primary id to its sound; unknown/null → default.
NotifySound resolvePrimary(String? id) =>
    _resolve(kPrimarySounds, id, kDefaultPrimarySoundId);

/// Resolve a persisted secondary id to its sound; unknown/null → default.
NotifySound resolveSecondary(String? id) =>
    _resolve(kSecondarySounds, id, kDefaultSecondarySoundId);
