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

/// Pick [SessionMode] from the persisted Local Player Mode toggle and the
/// lobby action. The toggle only changes the default solo path — join-code
/// and saved-room stay synced.
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

/// Parse the persisted Local Player Mode flag. Absent / unknown → off, so
/// existing installs keep today's start-a-room default.
bool localPlayerModeFromSetting(String? value) => value == 'true';
