import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import '../../core/audio/notify_sounds.dart';
import '../../core/connect/room_code.dart';
import '../../core/connect/room_config.dart';
import '../../core/connect/room_share.dart';
import '../../core/connect/username_generator.dart';
import '../../core/data/history_entry.dart';
import '../../core/data/history_mode.dart';
import '../../core/data/saved_profile.dart';
import '../../core/data/settings_store.dart';
import '../../core/data/stores.dart';
import '../../core/session/session_mode.dart';
import '../../core/debug/app_log.dart';
import '../../core/debug/log_archive.dart';
import '../../core/debug/log_level.dart';
import '../../core/sync/syncplay_constants.dart';
import '../../core/theme/meow_context.dart';
import '../../core/theme/meow_text.dart';
import '../../core/theme/meow_theme.dart';
import '../../core/theme/tokens/icon_sizes.dart';
import '../../core/theme/tokens/radii.dart';
import '../../core/theme/tokens/spacing.dart';
import '../../core/theme/tokens/type_scale.dart';
import '../../core/video/video_url.dart';
import '../brand/meow_logo.dart';
import '../motion/staggered_reveal.dart';
import '../settings/lobby_settings_button.dart';
import '../staggered_reflow_list.dart';
import '../version_badge.dart';
import 'history_format.dart';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({
    required this.profiles,
    required this.history,
    required this.settings,
    required this.currentTheme,
    required this.onThemeChanged,
    required this.onConnect,
    this.playLobbyEntrance = false,
    this.holdLobbyHidden = false,
    super.key,
  });

  final ProfileStore profiles;
  final HistoryStore history;
  final SettingsStore settings;
  final MeowThemeId currentTheme;
  final ValueChanged<MeowThemeId> onThemeChanged;

  /// Completes when the watch route pops, or with a named error if the join
  /// never logged in. The lobby stays visible until login succeeds.
  final Future<String?> Function(RoomConfig config) onConnect;

  /// Cold-start card cascade signals, driven by the launch reveal completing.
  /// [playLobbyEntrance] starts the one-shot ripple; [holdLobbyHidden] keeps the
  /// lobby content invisible until then so it doesn't flash during the reveal.
  /// Both lobby columns share these so they ripple in together (in parallel),
  /// not one-then-the-other.
  final bool playLobbyEntrance;
  final bool holdLobbyHidden;

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _name = TextEditingController();
  final _code = TextEditingController();
  final _server = TextEditingController(text: SyncplayConstants.defaultServer);
  final _port = TextEditingController(
    text: '${SyncplayConstants.publicServerPort}',
  );
  final _password = TextEditingController();
  final _serverFocus = FocusNode();
  final _portFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _scroll = ScrollController();
  bool _advancedOpen = false;

  /// Named error from a join that never logged in (STARTTLS refused, unreachable
  /// server, rejected room/password). Shown under Join on this screen.
  String? _joinError;

  /// True while [onConnect] is in flight. The lobby stays up for that wait;
  /// a second tap must not start another join.
  bool _joining = false;

  // Who a blank name field joins as (#172). Shown as the field's hint so the
  // user sees the name before connecting, rerollable via the dice button, and
  // regenerated after each join so every blank connect gets a fresh one — an
  // accepted name is already remembered through the saved room.
  String _suggestedName = generateUsername();

  String? _serverFocusStart;
  String? _portFocusStart;
  String? _passwordFocusStart;

  // Lobby-gear settings. These mirror the same SettingsStore keys the in-room
  // gear uses, so a change made here (before joining) and one made in a room are
  // the same setting. Seeded with defaults, then overwritten by [_loadSettings].
  String _primarySoundId = kDefaultPrimarySoundId;
  String _secondarySoundId = kDefaultSecondarySoundId;
  LogLevel _logLevel = LogLevel.verbose;
  HistoryMode _historyMode = HistoryMode.latestPerRoom;
  bool _localPlayerMode = false;

  /// Bumped by [_setLocalPlayerMode]. An in-flight [_loadSettings] that
  /// started before the bump must not write [_localPlayerMode] — the user's
  /// explicit choice is newer than the persisted snapshot it is about to
  /// apply.
  int _localPlayerModeRevision = 0;

  // Created lazily on the first sound preview so headless tests (and the common
  // case of never previewing) don't spin up a media player needlessly.
  Player? _preview;

  // Serializes lobby-settings writes so [_connect] can await all pending ones
  // before navigating into the room — otherwise a level/sound the user just
  // picked could still be mid-write when HomeScreen reads it (PR #131 review).
  // Errors are swallowed so a failed persist can't wedge the queue or block a
  // join.
  Future<void> _settingsWrites = Future<void>.value();

  // Completes when the first [_loadSettings] lands. Start / Continue Watching
  // await this so a persisted Local Player Mode can't lose a cold-start race
  // to the default-off [_localPlayerMode] seed (#254).
  late final Future<void> _settingsReady;

  @override
  void initState() {
    super.initState();
    _name.addListener(_refreshDynamicControls);
    _server.addListener(_refreshDynamicControls);
    _port.addListener(_refreshDynamicControls);
    _password.addListener(_refreshDynamicControls);
    _serverFocus.addListener(
      () => _handleAdvancedFocus(
        _serverFocus,
        _server,
        _serverFocusStart,
        (value) => _serverFocusStart = value,
      ),
    );
    _portFocus.addListener(
      () => _handleAdvancedFocus(
        _portFocus,
        _port,
        _portFocusStart,
        (value) => _portFocusStart = value,
      ),
    );
    _passwordFocus.addListener(
      () => _handleAdvancedFocus(
        _passwordFocus,
        _password,
        _passwordFocusStart,
        (value) => _passwordFocusStart = value,
      ),
    );
    _settingsReady = _loadSettings();
  }

  @override
  void dispose() {
    _name.removeListener(_refreshDynamicControls);
    _server.removeListener(_refreshDynamicControls);
    _port.removeListener(_refreshDynamicControls);
    _password.removeListener(_refreshDynamicControls);
    _name.dispose();
    _code.dispose();
    _server.dispose();
    _port.dispose();
    _password.dispose();
    _serverFocus.dispose();
    _portFocus.dispose();
    _passwordFocus.dispose();
    _scroll.dispose();
    unawaited(_preview?.dispose() ?? Future<void>.value());
    super.dispose();
  }

  void _refreshDynamicControls() {
    if (mounted) setState(() {});
  }

  void _handleAdvancedFocus(
    FocusNode node,
    TextEditingController controller,
    String? focusStart,
    ValueChanged<String?> setFocusStart,
  ) {
    if (node.hasFocus) {
      setFocusStart(controller.text);
      return;
    }
    if (focusStart != null && focusStart != controller.text) {
      _showSnack('Advanced setting updated.');
    }
    setFocusStart(null);
  }

  Future<void> _loadSettings() async {
    // Mode first: Start / Continue Watching wait on [_settingsReady], and
    // this key must be authoritative before those actions run. Reading it
    // last used to leave a cold-start window where the default-off seed won.
    final loadRevision = _localPlayerModeRevision;
    final localPlayerMode = localPlayerModeFromSetting(
      await widget.settings.get(kLocalPlayerModeSettingKey),
    );
    if (!mounted) return;
    if (loadRevision == _localPlayerModeRevision) {
      _localPlayerMode = localPlayerMode;
    }

    final primary = await widget.settings.get(kNotifyPrimarySoundKey);
    final secondary = await widget.settings.get(kNotifySecondarySoundKey);
    final level = logLevelFromName(
      await widget.settings.get(kLogLevelSettingKey),
    );
    final historyMode = historyModeFromName(
      await widget.settings.get(kHistoryModeSettingKey),
    );
    if (!mounted) return;
    setState(() {
      _primarySoundId = resolvePrimary(primary).id;
      _secondarySoundId = resolveSecondary(secondary).id;
      _logLevel = level;
      _historyMode = historyMode;
      if (loadRevision == _localPlayerModeRevision) {
        _localPlayerMode = localPlayerMode;
      }
    });
  }

  Future<void> _awaitInitialSettings() async {
    await _settingsReady;
  }

  void _setPrimarySound(String id) {
    appLog('settings: primary sound=$id');
    setState(() => _primarySoundId = id);
    _persistSetting(kNotifyPrimarySoundKey, id);
  }

  void _setSecondarySound(String id) {
    appLog('settings: secondary sound=$id');
    setState(() => _secondarySoundId = id);
    _persistSetting(kNotifySecondarySoundKey, id);
  }

  void _setLogLevel(LogLevel level) {
    // Log the change at the current level first (switching to `off` closes the
    // sink), then apply it live to the shared session log (#140) and persist it.
    appLog('settings: log level=${level.storageName}');
    setState(() => _logLevel = level);
    appLogInstance?.level = level;
    _persistSetting(kLogLevelSettingKey, level.storageName);
  }

  void _setHistoryMode(HistoryMode mode) {
    appLog('settings: history mode=${mode.storageName}');
    setState(() => _historyMode = mode);
    _persistSetting(kHistoryModeSettingKey, mode.storageName);
  }

  void _setLocalPlayerMode(bool enabled) {
    appLog('settings: local player mode=$enabled');
    _localPlayerModeRevision++;
    setState(() => _localPlayerMode = enabled);
    _persistSetting(kLocalPlayerModeSettingKey, enabled.toString());
  }

  /// Queue a settings write, chaining it onto [_settingsWrites] so [_connect]
  /// can await every pending write before entering the room. A failed write is
  /// swallowed — persistence must never block joining.
  void _persistSetting(String key, String value) {
    _settingsWrites = _settingsWrites
        .then((_) => widget.settings.set(key, value))
        .catchError((Object _) {});
  }

  /// Play a preset on demand for the Settings preview. Reuses one lazily-built
  /// player so repeated previews don't stack instances.
  Future<void> _previewSound(String asset) async {
    final player = _preview ??= Player();
    try {
      await player.open(Media(asset), play: true);
    } catch (e) {
      debugPrint('Failed to preview sound: $e');
    }
  }

  /// Bundle the rotating diagnostic logs from disk into a zip the user picks a
  /// location for. There is no live session log in the lobby, so this just zips
  /// whatever past sessions are already on disk.
  Future<void> _exportLogs() async {
    // Flush the live session log first: it's process-wide now (#140), so the
    // lobby holds the still-buffered tail of the run (and of a just-left room).
    // Without this, exporting right after leaving could miss the most relevant
    // lines (#146 review).
    await appLogInstance?.flush();
    final dir = await resolveAppLogsDir();
    // Zip in a background isolate so the lobby stays responsive (#197 P4).
    final zipBytes = await zipLogFilesInBackground(dir.path);
    if (zipBytes == null) {
      _showSnack('No diagnostic logs to export yet.');
      return;
    }
    try {
      final location = await getSaveLocation(
        suggestedName: 'meowwatch-logs.zip',
      );
      if (location == null) return; // user cancelled
      await File(location.path).writeAsBytes(zipBytes);
      _showSnack('Saved diagnostic logs.');
    } on Object {
      _showSnack('Could not save the logs.');
    }
  }

  void _showSnack(String text) {
    if (!mounted) return;
    final m = context.meow;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: m.surface,
          content: Text(text, style: TextStyle(color: m.textPrimary)),
        ),
      );
  }

  String get _username {
    final typed = _name.text.trim();
    return typed.isEmpty ? _suggestedName : typed;
  }

  String get _typedUsername => _name.text.trim();

  String get _serverValue => _server.text.trim().isEmpty
      ? SyncplayConstants.defaultServer
      : _server.text.trim();

  int get _portValue =>
      int.tryParse(_port.text.trim()) ?? SyncplayConstants.publicServerPort;

  String? get _passwordValue => _password.text.isEmpty ? null : _password.text;

  Future<void> _saveUsedProfile(
    RoomConfig config, {
    String? profileUsername,
  }) {
    return widget.profiles.saveUsed(
      name: config.room,
      server: config.server,
      port: config.port,
      room: config.room,
      username: profileUsername ?? config.username,
      password: config.password,
    );
  }

  Future<void> _connect(RoomConfig config, {String? profileUsername}) async {
    if (_joining) return;
    _joining = true;
    if (mounted) {
      setState(() {
        if (_joinError != null) _joinError = null;
      });
    }
    try {
      if (config.sessionMode.isSynced) {
        await _saveUsedProfile(config, profileUsername: profileUsername);
      }
      if (!mounted) return;
      // Flush any pending lobby-settings writes first, so the room reads the
      // values the user just picked rather than the previous ones — a Drift set()
      // can still be in flight when HomeScreen reads them (PR #131 review).
      await _settingsWrites;
      if (!mounted) return;
      // onConnect stays on this route until login completes, then pushes the
      // watch route and completes when it pops. A non-null result is a join
      // that never logged in: stay here with the named error. Re-read settings
      // only after a real visit — the in-room gear may have changed them.
      // Local Start and Continue Watching push immediately (#252, #254).
      final joinError = await widget.onConnect(config);
      if (!mounted) return;
      if (joinError != null && joinError.isNotEmpty) {
        setState(() => _joinError = joinError);
        return;
      }
      // Fresh suggestion for the next join: a blank name means "surprise me",
      // and the name just used is already remembered via the saved room (#172).
      setState(() => _suggestedName = generateUsername());
      await _loadSettings();
      // A Local Start that became synced in-player now has a real Syncplay
      // room. Persist it so Continue Watching can recover the server password.
      if (config.sessionMode.isLocal && !_localPlayerMode) {
        await _saveUsedProfile(config, profileUsername: profileUsername);
      }
    } finally {
      _joining = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _startPlayback() async {
    await _awaitInitialSettings();
    if (!mounted) return;
    final mode = resolveSessionMode(
      localPlayerMode: _localPlayerMode,
      launch: SessionLaunch.start,
    );
    if (mode.isLocal) {
      // Real room identity so this session can become synced later. No
      // clipboard copy — Local Start is not a share action.
      final code = generateRoomCode();
      await _connect(
        RoomConfig.local(
          username: _username,
          server: _serverValue,
          port: _portValue,
          room: code,
          password: _passwordValue,
        ),
      );
      return;
    }
    await _startNewRoom();
  }

  Future<void> _startNewRoom() async {
    // The generated "magic sentence" IS the private room name — its entropy
    // lives in the words themselves, so there is no separate secret to fold in.
    // It is NOT sent as a server password. The Advanced password (if any) is a
    // genuine Syncplay server password and rides along independently.
    final code = generateRoomCode();
    // The *shared* code is self-contained: on the default public server it's the
    // bare sentence, but a non-default server/port is appended so a friend joins
    // from one paste (#110). The room we actually join is still the bare [code].
    final share = encodeShareCode(
      room: code,
      server: _serverValue,
      port: _portValue,
    );
    // Copy without blocking the join — clipboard is a convenience, and on a
    // headless test binding the platform channel never replies.
    Clipboard.setData(ClipboardData(text: share)).ignore();
    _showCopiedSnack(share);
    await _connect(
      RoomConfig(
        server: _serverValue,
        port: _portValue,
        room: code,
        username: _username,
        password: _passwordValue,
      ),
    );
  }

  /// Confirm the new join code was copied. Shown on the app-level messenger so
  /// it stays visible after we navigate into the watch screen.
  void _showCopiedSnack(String code) {
    final m = context.meow;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: m.surface,
          duration: const Duration(seconds: 3),
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, size: IconSizes.md, color: m.online),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Text(
                  'Room code $code copied — share it with your friend',
                  style: TextStyle(color: m.textPrimary),
                ),
              ),
            ],
          ),
        ),
      );
  }

  /// Shown on the app-level messenger so it survives the push into the player.
  void _showLocalJoinOverrideSnack() {
    final m = context.meow;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: m.surface,
          duration: const Duration(seconds: 3),
          content: Text(
            kLocalJoinOverrideNotice,
            style: TextStyle(color: m.textPrimary),
          ),
        ),
      );
  }

  Future<void> _joinTypedCode() async {
    await _awaitInitialSettings();
    if (!mounted) return;
    final raw = _code.text.trim();
    if (raw.isEmpty) return;
    // Parse the pasted code: a plain string (magic sentence, bare `happy-cat-11`,
    // or folded `happy-cat-11-k3pn`) is the room verbatim; a `room@host[:port]`
    // share code carries the host's server so a non-default join works from one
    // paste (#110). A structured-but-broken code gets clear feedback instead of
    // a confusing failed join. The Advanced password is a separate server
    // password and is never part of the code.
    final parsed = parseShareCode(raw);
    if (!parsed.isValid) {
      _showSnack(parsed.error!);
      return;
    }
    if (shouldShowLocalJoinOverride(
      persistedLocal: _localPlayerMode,
      launch: SessionLaunch.joinCode,
    )) {
      _showLocalJoinOverrideSnack();
    }
    // A code that names a server describes a complete destination: it carries a
    // port only when non-default, so an omitted port means the Syncplay default
    // (8999) — NOT whatever sits in the joiner's Advanced Port. Only a bare room
    // code (no server in the code) falls back to the Advanced fields.
    final fromCode = parsed.server != null;
    await _connect(
      RoomConfig(
        server: fromCode ? parsed.server! : _serverValue,
        port: fromCode
            ? (parsed.port ?? SyncplayConstants.defaultPort)
            : _portValue,
        room: parsed.room,
        username: _username,
        password: _passwordValue,
      ),
    );
  }

  Future<void> _connectProfile(
    SavedProfile p, {
    String? usernameOverride,
  }) async {
    await _awaitInitialSettings();
    if (!mounted) return;
    if (shouldShowLocalJoinOverride(
      persistedLocal: _localPlayerMode,
      launch: SessionLaunch.savedRoom,
    )) {
      _showLocalJoinOverrideSnack();
    }
    final username = usernameOverride ?? p.username;
    await _connect(
      RoomConfig(
        server: p.server,
        port: p.port,
        room: p.room,
        username: username,
        password: p.password,
      ),
      profileUsername: p.username,
    );
  }

  Future<void> _resumeHistory(
    HistoryEntry entry,
    List<SavedProfile> profiles, {
    String? usernameOverride,
  }) async {
    await _awaitInitialSettings();
    if (!mounted) return;
    // Identity priority: tapping a history card means "resume as watched
    // before"; the inline "Join as current name" action is the explicit
    // override.
    // Legacy history did not retain an endpoint. Its fallback may only use a
    // same-room profile; a global most-recent profile can be unrelated or stale.
    final roomProfile = _matchingRoomProfile(entry, profiles);
    final room = (entry.room != null && entry.room!.isNotEmpty)
        ? entry.room!
        : (roomProfile?.room ?? generateRoomCode());
    final server = entry.server ?? roomProfile?.server ?? _serverValue;
    final port = entry.port ?? roomProfile?.port ?? _portValue;
    final endpointProfile = _matchingEndpointProfile(
      server: server,
      port: port,
      username: entry.username,
      profiles: profiles,
    );
    final typed = _name.text.trim();
    final entryName = entry.username;
    final username =
        usernameOverride ??
        ((entryName != null && entryName.isNotEmpty)
            ? entryName
            : typed.isNotEmpty
            ? typed
            : (roomProfile?.username ?? _suggestedName));
    final savedUsername = (entryName != null && entryName.isNotEmpty)
        ? entryName
        : roomProfile?.username;
    final mode = resolveSessionMode(
      localPlayerMode: _localPlayerMode,
      launch: SessionLaunch.continueWatching,
    );
    // A stored endpoint is authoritative. Never carry a same-room password
    // across servers/ports; only legacy rows may borrow their room profile.
    final legacyEntry = entry.server == null || entry.port == null;
    final password =
        endpointProfile?.password ??
        (legacyEntry ? roomProfile?.password : null) ??
        _passwordValue;
    if (mode.isLocal) {
      // Resume this card's progress locally. Keep the card's room identity so
      // the same session can become synced later. Do not treat old room
      // metadata as permission to sync now.
      await _connect(
        RoomConfig.local(
          username: username,
          server: server,
          port: port,
          room: room,
          password: password,
          resumeFilePath: entry.filePath,
          resumePositionMs: entry.lastPositionMs,
        ),
        profileUsername: usernameOverride == null ? null : savedUsername,
      );
      return;
    }
    await _connect(
      RoomConfig(
        server: server,
        port: port,
        room: room,
        username: username,
        password: password,
        resumeFilePath: entry.filePath,
        resumePositionMs: entry.lastPositionMs,
      ),
      profileUsername: usernameOverride == null ? null : savedUsername,
    );
  }

  SavedProfile? _matchingRoomProfile(
    HistoryEntry entry,
    List<SavedProfile> profiles,
  ) {
    final room = entry.room?.trim();
    if (room == null || room.isEmpty) return null;
    SavedProfile? sameRoom;
    for (final profile in profiles) {
      if (profile.room != room) continue;
      sameRoom ??= profile;
      if (entry.username == null ||
          entry.username!.isEmpty ||
          profile.username == entry.username) {
        return profile;
      }
    }
    return sameRoom;
  }

  // Syncplay passwords are server-wide, keyed by endpoint (server:port), not by
  // room. So the password to resume with is any saved profile on the same
  // endpoint — even if the exact room's card was since deleted. Requiring a room
  // match here would drop a valid password and fall back to the typed Advanced
  // one, breaking Continue watching against passworded self-hosted servers.
  SavedProfile? _matchingEndpointProfile({
    required String server,
    required int port,
    required String? username,
    required List<SavedProfile> profiles,
  }) {
    SavedProfile? sameEndpoint;
    for (final profile in profiles) {
      if (profile.server != server || profile.port != port) {
        continue;
      }
      sameEndpoint ??= profile;
      if (username == null ||
          username.isEmpty ||
          profile.username == username) {
        return profile;
      }
    }
    return sameEndpoint;
  }

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    return Scaffold(
      backgroundColor: m.background,
      // Stack wraps the scrollable form + the version badge pinned bottom-right.
      body: Stack(
        children: [
          // LayoutBuilder + minHeight lets the column center vertically when it
          // fits and switch to a normal top-aligned scroll when it's taller than
          // the window. The Scrollbar shares the controller so the track tracks the
          // actual scroll (and only shows when there's overflow), instead of a
          // stray bar floating beside the narrow centered content.
          LayoutBuilder(
            builder: (context, constraints) {
              // Past a comfortable width the single phone-like column wastes the
              // screen — split the form and the room library into two columns.
              final wide = constraints.maxWidth >= 880;
              return Scrollbar(
                controller: _scroll,
                child: SingleChildScrollView(
                  controller: _scroll,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Center(
                      child: StreamBuilder<List<SavedProfile>>(
                        stream: widget.profiles.watchProfiles(),
                        initialData: const [],
                        builder: (context, profileSnap) {
                          final savedProfiles = profileSnap.data ?? const [];
                          final mostRecent = savedProfiles.isEmpty
                              ? null
                              : savedProfiles.first;
                          // Only go two-column when there's a library to fill the
                          // right side; first-run (no saved rooms) stays centered.
                          final twoColumn = wide && savedProfiles.isNotEmpty;
                          return ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: twoColumn ? 920 : 460,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(Spacing.xxl),
                              child: twoColumn
                                  ? Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // Both columns share the same entrance
                                        // signals, so they ripple in together
                                        // (in parallel) once the splash clears —
                                        // not left-then-right.
                                        Expanded(
                                          child: StaggeredReveal(
                                            play: widget.playLobbyEntrance,
                                            holdHidden: widget.holdLobbyHidden,
                                            children: [
                                              ..._formColumn(),
                                              const SizedBox(
                                                height: Spacing.lg,
                                              ),
                                              _advancedSection(),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 40),
                                        Expanded(
                                          child: StaggeredReveal(
                                            play: widget.playLobbyEntrance,
                                            holdHidden: widget.holdLobbyHidden,
                                            children: _libraryColumn(
                                              savedProfiles,
                                              mostRecent,
                                            ),
                                          ),
                                        ),
                                      ],
                                    )
                                  : StaggeredReveal(
                                      play: widget.playLobbyEntrance,
                                      holdHidden: widget.holdLobbyHidden,
                                      children: [
                                        ..._formColumn(),
                                        ..._libraryColumn(
                                          savedProfiles,
                                          mostRecent,
                                        ),
                                        const SizedBox(height: Spacing.lg),
                                        _advancedSection(),
                                      ],
                                    ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          // Settings gear — top-right, so theme / sounds / diagnostic logging
          // are reachable before joining a room (mirrors the in-player gear).
          Positioned(
            top: Spacing.md,
            right: Spacing.md,
            child: LobbySettingsButton(
              localPlayerMode: _localPlayerMode,
              onLocalPlayerModeChanged: _setLocalPlayerMode,
              historyMode: _historyMode,
              onHistoryModeChanged: _setHistoryMode,
              currentTheme: widget.currentTheme,
              onThemeChanged: (theme) {
                appLog('settings: theme=${theme.name}');
                widget.onThemeChanged(theme);
              },
              primarySoundId: _primarySoundId,
              onPrimarySoundChanged: _setPrimarySound,
              secondarySoundId: _secondarySoundId,
              onSecondarySoundChanged: _setSecondarySound,
              onPreviewSound: _previewSound,
              logLevel: _logLevel,
              onLogLevelChanged: _setLogLevel,
              onExportLogs: _exportLogs,
            ),
          ),
          // Version badge — bottom-right, always visible on connect screen.
          const Positioned(
            right: Spacing.md,
            bottom: Spacing.md,
            child: VersionBadge(),
          ),
        ],
      ),
    );
  }

  /// The connect form (brand, theme, name, start/join) — shared by the single-
  /// and two-column layouts.
  List<Widget> _formColumn() {
    final m = context.meow;
    return [
      const MeowLogo(markSize: 52, fontSize: 30, markLeading: false),
      const SizedBox(height: Spacing.xs),
      Text(
        'Watch together, in sync.',
        style: context.meowText.body.copyWith(color: m.textDim),
      ),
      const SizedBox(height: Spacing.lg),
      _label('Your name'),
      _textField(
        key: const Key('connect-name'),
        controller: _name,
        // The hint is who a blank field joins as (#172) — a real committed
        // name, not example copy. The dice rerolls it; typing anything wins.
        hint: _suggestedName,
        suffixIcon: _name.text.isNotEmpty
            ? _clearNameButton(key: const Key('connect-name-clear'))
            : _diceNameButton(key: const Key('connect-name-dice')),
      ),
      const SizedBox(height: Spacing.xl),
      FilledButton(
        key: const Key('connect-start-new'),
        style: FilledButton.styleFrom(
          backgroundColor: m.accent,
          foregroundColor: m.background,
          padding: const EdgeInsets.symmetric(vertical: Spacing.lg),
        ),
        onPressed: _joining ? null : _startPlayback,
        child: Text(
          _localPlayerMode ? 'Start watching' : 'Start new room',
          style: const TextStyle(fontWeight: TypeScale.bold),
        ),
      ),
      const SizedBox(height: 8),
      Text(
        _localPlayerMode
            ? 'Play on this computer — no sync. This choice is remembered.'
            : 'A private code is generated and copied to clipboard.',
        style: context.meowText.body.copyWith(color: m.textDim),
      ),
      const SizedBox(height: Spacing.xl),
      _label('Enter code from friend'),
      Row(
        children: [
          Expanded(
            child: _textField(
              key: const Key('connect-code'),
              controller: _code,
              hint: 'sleepy-otter-counts-cozy-stars',
            ),
          ),
          const SizedBox(width: Spacing.sm),
          FilledButton(
            key: const Key('connect-join'),
            style: FilledButton.styleFrom(
              backgroundColor: m.surface,
              foregroundColor: m.textPrimary,
            ),
            onPressed: _joining ? null : _joinTypedCode,
            child: const Text('Join'),
          ),
        ],
      ),
      if (_joinError != null) ...[
        const SizedBox(height: Spacing.lg),
        _joinErrorBanner(),
      ],
    ];
  }

  Widget _joinErrorBanner() {
    final m = context.meow;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: m.error.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: m.error),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.lg,
          vertical: Spacing.md,
        ),
        child: Text(
          _joinError!,
          key: const Key('connect-join-error'),
          style: TextStyle(color: m.error, fontSize: TypeScale.body),
        ),
      ),
    );
  }

  /// Saved rooms + continue-watching — the right column when wide, appended
  /// below the form when narrow.
  List<Widget> _libraryColumn(
    List<SavedProfile> savedProfiles,
    SavedProfile? mostRecent,
  ) {
    return [
      if (savedProfiles.isNotEmpty) ...[
        const SizedBox(height: Spacing.xxl),
        _label('Saved rooms'),
        ...savedProfiles.map(
          (p) => _profileCard(p, isMostRecent: p == mostRecent),
        ),
      ],
      _ContinueWatching(
        history: widget.history,
        mode: _historyMode,
        currentUsername: _typedUsername,
        onResume: (entry, {usernameOverride}) => _resumeHistory(
          entry,
          savedProfiles,
          usernameOverride: usernameOverride,
        ),
      ),
    ];
  }

  Widget _label(String text) {
    final m = context.meow;
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Text(
        text,
        style: context.meowText.body.copyWith(color: m.textDim),
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String hint,
    Key? key,
    bool obscure = false,
    FocusNode? focusNode,
    Widget? suffixIcon,
  }) {
    final m = context.meow;
    return TextField(
      key: key,
      controller: controller,
      focusNode: focusNode,
      obscureText: obscure,
      style: TextStyle(color: m.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: m.textDim),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: m.surface,
        isDense: true,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide(color: m.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide(color: m.accent),
        ),
      ),
    );
  }

  Widget _profileCard(SavedProfile p, {required bool isMostRecent}) {
    final m = context.meow;
    final typed = _typedUsername;
    final showCurrentNameAction = typed.isNotEmpty && typed != p.username;
    return Card(
      color: m.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        side: BorderSide(color: m.border),
      ),
      child: ListTile(
        onTap: () => _connectProfile(p),
        leading: Icon(
          Icons.circle,
          size: 10,
          color: isMostRecent ? m.online : m.textDim,
        ),
        title: Text(p.name, style: TextStyle(color: m.textPrimary)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${p.username} · ${p.server}',
              style: context.meowText.body.copyWith(color: m.textDim),
            ),
            _CurrentNameAction(
              actionKey: showCurrentNameAction
                  ? Key('connect-profile-use-current-${p.id}')
                  : null,
              visible: showCurrentNameAction,
              username: typed,
              onPressed: () => _connectProfile(p, usernameOverride: typed),
            ),
          ],
        ),
        trailing: IconButton(
          key: Key('connect-delete-${p.id}'),
          icon: Icon(Icons.close, color: m.textDim, size: IconSizes.md),
          onPressed: () => widget.profiles.delete(p.id),
        ),
      ),
    );
  }

  Widget _advancedSection() {
    final m = context.meow;
    final serverChanged =
        _server.text.trim().isNotEmpty &&
        _server.text.trim() != SyncplayConstants.defaultServer;
    final portChanged =
        _port.text.trim().isNotEmpty &&
        _port.text.trim() != '${SyncplayConstants.publicServerPort}';
    final passwordChanged = _password.text.isNotEmpty;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: const Key('connect-advanced'),
        initiallyExpanded: _advancedOpen,
        onExpansionChanged: (v) => setState(() => _advancedOpen = v),
        title: Text('Advanced', style: TextStyle(color: m.textDim)),
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: Spacing.sm),
        children: [
          _label('Server'),
          _textField(
            key: const Key('connect-advanced-server'),
            controller: _server,
            focusNode: _serverFocus,
            hint: SyncplayConstants.defaultServer,
            suffixIcon: serverChanged
                ? _resetFieldButton(
                    key: const Key('connect-advanced-server-reset'),
                    onPressed: () =>
                        _server.text = SyncplayConstants.defaultServer,
                  )
                : null,
          ),
          const SizedBox(height: Spacing.md),
          _label('Port'),
          _textField(
            key: const Key('connect-advanced-port'),
            controller: _port,
            focusNode: _portFocus,
            hint: '${SyncplayConstants.publicServerPort}',
            suffixIcon: portChanged
                ? _resetFieldButton(
                    key: const Key('connect-advanced-port-reset'),
                    onPressed: () =>
                        _port.text = '${SyncplayConstants.publicServerPort}',
                  )
                : null,
          ),
          const SizedBox(height: Spacing.md),
          _label('Server password — advanced / self-hosted only'),
          _textField(
            key: const Key('connect-advanced-password'),
            controller: _password,
            focusNode: _passwordFocus,
            hint: 'only needed for a private Syncplay server',
            suffixIcon: passwordChanged
                ? _resetFieldButton(
                    key: const Key('connect-advanced-password-reset'),
                    onPressed: _password.clear,
                  )
                : null,
          ),
          const SizedBox(height: Spacing.xs),
          Text(
            'No effect on the public server. Private rooms come from the '
            'code you share, not this field.',
            style: context.meowText.body.copyWith(color: m.textDim),
          ),
        ],
      ),
    );
  }

  Widget _resetFieldButton({
    required Key key,
    required VoidCallback onPressed,
  }) {
    final m = context.meow;
    return IconButton(
      key: key,
      tooltip: 'Reset to default',
      icon: Icon(Icons.restart_alt, color: m.textDim, size: IconSizes.md),
      onPressed: onPressed,
    );
  }

  Widget _clearNameButton({required Key key}) {
    final m = context.meow;
    return IconButton(
      key: key,
      tooltip: 'Clear name',
      icon: Icon(Icons.close, color: m.textDim, size: IconSizes.md),
      onPressed: _name.clear,
    );
  }

  Widget _diceNameButton({required Key key}) {
    final m = context.meow;
    return IconButton(
      key: key,
      tooltip: 'New random name',
      icon: Icon(Icons.casino_outlined, color: m.textDim, size: IconSizes.md),
      onPressed: () => setState(() => _suggestedName = generateUsername()),
    );
  }
}

class _ContinueWatching extends StatelessWidget {
  const _ContinueWatching({
    required this.history,
    required this.mode,
    required this.currentUsername,
    required this.onResume,
  });

  final HistoryStore history;
  final HistoryMode mode;
  final String currentUsername;
  final void Function(HistoryEntry entry, {String? usernameOverride}) onResume;

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    return StreamBuilder<List<HistoryEntry>>(
      stream: history.watchRecent(mode: mode),
      initialData: const [],
      builder: (context, snap) {
        final recent = snap.data ?? const [];
        if (recent.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: Spacing.xxl),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Continue watching',
                    style: context.meowText.body.copyWith(color: m.textDim),
                  ),
                ),
                TextButton(
                  key: const Key('continue-clear-all'),
                  onPressed: () {
                    appLog('db: history cleared (all)');
                    history.clearAll();
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: m.textDim,
                    padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Clear all',
                    style: TextStyle(fontSize: TypeScale.body),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.xs),
            // Toggling Latest-per-room ⇄ Every-video (or recording/removing a
            // file) adds, removes and reorders these cards. The staggered
            // cascade glides survivors and ripples arrivals in instead of
            // hard-swapping the list. Keyed by row id so it can tell a card that
            // moved from one that left while a new one arrived.
            StaggeredReflowList(
              children: [
                for (final e in recent)
                  ReflowChild(
                    id: e.id,
                    child: _HistoryCard(
                      entry: e,
                      currentUsername: currentUsername,
                      onResume: () => onResume(e),
                      onResumeWithCurrentName: currentUsername.isEmpty
                          ? null
                          : () =>
                                onResume(e, usernameOverride: currentUsername),
                      onDelete: () => history.delete(e.id),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// One "Continue watching" row: filename, resume progress + last-played, a thin
/// progress bar, and a delete button.
class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.entry,
    required this.currentUsername,
    required this.onResume,
    required this.onResumeWithCurrentName,
    required this.onDelete,
  });

  final HistoryEntry entry;
  final String currentUsername;
  final VoidCallback onResume;
  final VoidCallback? onResumeWithCurrentName;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    final frac = progressFraction(entry);
    final roomLine = historyRoomLine(entry);
    final savedUsername = entry.username?.trim() ?? '';
    final showCurrentNameAction =
        savedUsername.isNotEmpty &&
        currentUsername.isNotEmpty &&
        currentUsername != savedUsername &&
        onResumeWithCurrentName != null;
    return Card(
      color: m.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        side: BorderSide(color: m.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            key: Key('continue-${entry.id}'),
            onTap: onResume,
            leading: Icon(Icons.play_circle, color: m.accent),
            title: Text(
              mediaDisplayName(entry.fileName),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: m.textPrimary),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  historySubtitle(entry, DateTime.now()),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.meowText.body.copyWith(color: m.textDim),
                ),
                if (roomLine != null)
                  Padding(
                    padding: const EdgeInsets.only(top: Spacing.xxs),
                    child: Row(
                      children: [
                        Icon(Icons.groups, size: 12, color: m.accent),
                        const SizedBox(width: Spacing.xs),
                        Flexible(
                          child: Text(
                            roomLine,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.meowText.body.copyWith(
                              color: m.accent,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (savedUsername.isNotEmpty)
                  _CurrentNameAction(
                    actionKey: showCurrentNameAction
                        ? Key('continue-use-current-${entry.id}')
                        : null,
                    visible: showCurrentNameAction,
                    username: currentUsername,
                    onPressed: onResumeWithCurrentName ?? () {},
                  ),
              ],
            ),
            trailing: IconButton(
              key: Key('continue-delete-${entry.id}'),
              icon: Icon(Icons.close, color: m.textDim, size: IconSizes.md),
              tooltip: 'Remove',
              onPressed: onDelete,
            ),
          ),
          if (frac != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.lg,
                0,
                Spacing.lg,
                Spacing.md,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Radii.xs),
                child: LinearProgressIndicator(
                  value: frac,
                  minHeight: 4,
                  backgroundColor: m.border,
                  valueColor: AlwaysStoppedAnimation<Color>(m.accent),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CurrentNameAction extends StatelessWidget {
  const _CurrentNameAction({
    required this.actionKey,
    required this.visible,
    required this.username,
    required this.onPressed,
  });

  final Key? actionKey;
  final bool visible;
  final String username;
  final VoidCallback onPressed;
  static const Duration _growDuration = Duration(milliseconds: 300);

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    return AnimatedSize(
      duration: _growDuration,
      reverseDuration: _growDuration,
      curve: Curves.easeInOutCubic,
      alignment: Alignment.topLeft,
      child: visible
          ? Padding(
              padding: const EdgeInsets.only(top: Spacing.xs),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: actionKey,
                  style: TextButton.styleFrom(
                    foregroundColor: m.accent,
                    padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.sm,
                      vertical: Spacing.xs,
                    ),
                    minimumSize: const Size(0, 30),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: onPressed,
                  icon: const Icon(Icons.person_outline, size: IconSizes.sm),
                  label: Text(
                    'Join as $username this time',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}
