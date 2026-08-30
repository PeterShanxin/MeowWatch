import 'package:flutter/foundation.dart';

/// How a player session behaves: solo playback, or a Syncplay room.
enum SessionMode {
  local,
  synced;

  bool get isLocal => this == SessionMode.local;
  bool get isSynced => this == SessionMode.synced;
}

/// How the user asked to enter the player from the lobby.
enum SessionLaunch { start, continueWatching, joinCode, savedRoom }

/// Pick [SessionMode] from the remembered Local Player Mode setting and the
/// lobby action. Explicit toggles in either the lobby or player update this
/// default; join-code and saved-room launches stay synced without updating it.
SessionMode resolveSessionMode({
  required bool localPlayerMode,
  required SessionLaunch launch,
}) {
  if (!localPlayerMode) return SessionMode.synced;
  return switch (launch) {
    SessionLaunch.start || SessionLaunch.continueWatching => SessionMode.local,
    SessionLaunch.joinCode || SessionLaunch.savedRoom => SessionMode.synced,
  };
}

/// Which multiplayer chrome a session should mount. HomeScreen uses this so
/// local vs synced is one decision, not a scatter of `if (localMode)` checks.
@immutable
class SessionChrome {
  const SessionChrome({
    required this.chat,
    required this.reactions,
    required this.reactionBar,
    required this.syncBanners,
    required this.chatTabHint,
    required this.roomShare,
    required this.roster,
    required this.peerLoadPrompt,
  });

  factory SessionChrome.forMode(SessionMode mode) {
    final on = mode.isSynced;
    return SessionChrome(
      chat: on,
      reactions: on,
      reactionBar: on,
      syncBanners: on,
      chatTabHint: on,
      roomShare: on,
      roster: on,
      peerLoadPrompt: on,
    );
  }

  final bool chat;
  final bool reactions;
  final bool reactionBar;
  final bool syncBanners;
  final bool chatTabHint;
  final bool roomShare;
  final bool roster;
  final bool peerLoadPrompt;

  bool get isSynced => chat;
}

/// Which text the over-video notice slot should show.
///
/// An in-flight page-URL resolve outranks everything. Media/load transients
/// ([notice]) stay visible in local mode — they are the only failure
/// feedback when a bad paste leaves the current video playing. Derived
/// sync banners ([derivedSync]: waiting / connecting / friend hints) only
/// appear when [syncBanners] is on.
String? selectSessionBanner({
  required bool leavingRoom,
  String? resolving,
  String? notice,
  String? derivedSync,
  required bool syncBanners,
}) {
  if (leavingRoom) return null;
  return resolving ?? notice ?? (syncBanners ? derivedSync : null);
}

/// Parse the persisted Local Player Mode flag. Absent / unknown → off, so
/// existing installs keep today's start-a-room default.
bool localPlayerModeFromSetting(String? value) => value == 'true';

/// Snack shown when a Local-default user explicitly joins a room.
const String kLocalJoinOverrideNotice =
    'Local mode off for this session — joining room.';

/// Manual Join / saved-room override the lobby Local default for this
/// session only. Invalid codes never override.
bool shouldShowLocalJoinOverride({
  required bool persistedLocal,
  required SessionLaunch launch,
  bool validDestination = true,
}) {
  if (!persistedLocal || !validDestination) return false;
  return launch == SessionLaunch.joinCode || launch == SessionLaunch.savedRoom;
}
