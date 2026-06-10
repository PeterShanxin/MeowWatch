import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/connect/join_code.dart';
import '../../core/connect/room_code.dart';
import '../../core/connect/room_config.dart';
import '../../core/data/history_entry.dart';
import '../../core/data/saved_profile.dart';
import '../../core/data/stores.dart';
import '../../core/sync/syncplay_constants.dart';
import '../../core/theme/meow_context.dart';
import '../../core/theme/meow_text.dart';
import '../../core/theme/meow_theme.dart';
import '../../core/theme/tokens/icon_sizes.dart';
import '../../core/theme/tokens/radii.dart';
import '../../core/theme/tokens/spacing.dart';
import '../../core/theme/tokens/type_scale.dart';
import '../theme/theme_swatches.dart';
import '../version_badge.dart';
import 'history_format.dart';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({
    required this.profiles,
    required this.history,
    required this.currentTheme,
    required this.onThemeChanged,
    required this.onConnect,
    super.key,
  });

  final ProfileStore profiles;
  final HistoryStore history;
  final MeowThemeId currentTheme;
  final ValueChanged<MeowThemeId> onThemeChanged;
  final Future<void> Function(RoomConfig config) onConnect;

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _name = TextEditingController();
  final _code = TextEditingController();
  final _server = TextEditingController(text: SyncplayConstants.defaultServer);
  final _port = TextEditingController(text: '${SyncplayConstants.defaultPort}');
  final _password = TextEditingController();
  final _scroll = ScrollController();
  bool _advancedOpen = false;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _server.dispose();
    _port.dispose();
    _password.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String get _username {
    final typed = _name.text.trim();
    return typed.isEmpty ? 'meow' : typed;
  }

  String get _serverValue => _server.text.trim().isEmpty
      ? SyncplayConstants.defaultServer
      : _server.text.trim();

  int get _portValue =>
      int.tryParse(_port.text.trim()) ?? SyncplayConstants.defaultPort;

  String? get _passwordValue => _password.text.isEmpty ? null : _password.text;

  Future<void> _connect(RoomConfig config) async {
    await widget.profiles.saveUsed(
      name: config.room,
      server: config.server,
      port: config.port,
      room: config.room,
      username: config.username,
      password: config.password,
    );
    if (!mounted) return;
    await widget.onConnect(config);
  }

  Future<void> _startNewRoom() async {
    // A fresh random passphrase folds into the room name to make a private
    // room. If the user typed their own Advanced password, honour that instead.
    final password = _passwordValue ?? generatePassphrase();
    final code = buildJoinCode(generateRoomCode(), password);
    // Copy without blocking the join — clipboard is a convenience, and on a
    // headless test binding the platform channel never replies.
    Clipboard.setData(ClipboardData(text: code)).ignore();
    _showCopiedSnack(code);
    await _connect(RoomConfig(
      server: _serverValue,
      port: _portValue,
      room: code,
      username: _username,
      password: password,
    ));
  }

  /// Confirm the new join code was copied. Shown on the app-level messenger so
  /// it stays visible after we navigate into the watch screen.
  void _showCopiedSnack(String code) {
    final m = context.meow;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: m.surface,
        duration: const Duration(seconds: 3),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: IconSizes.md, color: m.online),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Text('Room code $code copied — share it with your friend',
                  style: TextStyle(color: m.textPrimary)),
            ),
          ],
        ),
      ));
  }

  Future<void> _joinTypedCode() async {
    final raw = _code.text.trim();
    if (raw.isEmpty) return;
    // A pasted code may carry its own password; fall back to an Advanced one the
    // user typed (e.g. a friend shared a room-only code separately). Re-folding
    // is idempotent for an already-folded code, so the friend lands in the exact
    // same private room as the host.
    final parsed = parseJoinCode(raw);
    final password = parsed.password ?? _passwordValue;
    await _connect(RoomConfig(
      server: _serverValue,
      port: _portValue,
      room: buildJoinCode(parsed.room, password),
      username: _username,
      password: password,
    ));
  }

  Future<void> _connectProfile(SavedProfile p) async {
    _name.text = p.username;
    await _connect(RoomConfig(
      server: p.server,
      port: p.port,
      room: p.room,
      username: p.username,
      password: p.password,
    ));
  }

  Future<void> _resumeHistory(HistoryEntry entry, SavedProfile? recent) async {
    // Identity priority: a freshly typed name wins; otherwise reuse the name
    // this file was watched as, then the most-recent room's name, then the
    // default. Falling straight to "meow" lost the user's identity on resume
    // and, by colliding with a peer's default, triggered a server rename that
    // flipped chat ownership (#40).
    final typed = _name.text.trim();
    final entryName = entry.username;
    final username = typed.isNotEmpty
        ? typed
        : (entryName != null && entryName.isNotEmpty)
            ? entryName
            : (recent?.username ?? 'meow');
    // Reflect the resolved name in the field so the user sees who they joined as.
    _name.text = username;
    final room = (entry.room != null && entry.room!.isNotEmpty)
        ? entry.room!
        : (recent?.room ?? generateRoomCode());
    await _connect(RoomConfig(
      server: recent?.server ?? _serverValue,
      port: recent?.port ?? _portValue,
      room: room,
      username: username,
      password: recent?.password ?? _passwordValue,
      resumeFilePath: entry.filePath,
      resumePositionMs: entry.lastPositionMs,
    ));
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
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: Center(
                      child: StreamBuilder<List<SavedProfile>>(
                        stream: widget.profiles.watchProfiles(),
                        initialData: const [],
                        builder: (context, profileSnap) {
                          final savedProfiles = profileSnap.data ?? const [];
                          final mostRecent =
                              savedProfiles.isEmpty ? null : savedProfiles.first;
                          // Only go two-column when there's a library to fill the
                          // right side; first-run (no saved rooms) stays centered.
                          final twoColumn = wide && savedProfiles.isNotEmpty;
                          return ConstrainedBox(
                            constraints: BoxConstraints(
                                maxWidth: twoColumn ? 920 : 460),
                            child: Padding(
                              padding: const EdgeInsets.all(Spacing.xxl),
                              child: twoColumn
                                  ? Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              ..._formColumn(),
                                              const SizedBox(height: Spacing.lg),
                                              _advancedSection(),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 40),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children:
                                                _libraryColumn(savedProfiles, mostRecent),
                                          ),
                                        ),
                                      ],
                                    )
                                  : Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        ..._formColumn(),
                                        ..._libraryColumn(savedProfiles, mostRecent),
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
      Text('MeowWatch',
          style: context.meowText.display
              .copyWith(fontWeight: TypeScale.semibold)),
      const SizedBox(height: Spacing.xs),
      Text('Watch together, in sync.',
          style: context.meowText.body.copyWith(color: m.textDim)),
      const SizedBox(height: Spacing.lg),
      _label('Theme'),
      ThemeSwatches(
        current: widget.currentTheme,
        onChanged: widget.onThemeChanged,
      ),
      const SizedBox(height: Spacing.xxl),
      _label('Your name'),
      _textField(
          key: const Key('connect-name'), controller: _name, hint: 'e.g. lin'),
      const SizedBox(height: Spacing.xl),
      FilledButton(
        key: const Key('connect-start-new'),
        style: FilledButton.styleFrom(
          backgroundColor: m.accent,
          foregroundColor: m.background,
          padding: const EdgeInsets.symmetric(vertical: Spacing.lg),
        ),
        onPressed: _startNewRoom,
        child: const Text('Start new room',
            style: TextStyle(fontWeight: TypeScale.bold)),
      ),
      const SizedBox(height: 8),
      Text('A private code is generated and copied to clipboard.',
          style: context.meowText.body.copyWith(color: m.textDim)),
      const SizedBox(height: Spacing.xl),
      _label('Enter code from friend'),
      Row(children: [
        Expanded(
          child: _textField(
              key: const Key('connect-code'),
              controller: _code,
              hint: 'cozy-fox-42-k3pn'),
        ),
        const SizedBox(width: Spacing.sm),
        FilledButton(
          key: const Key('connect-join'),
          style: FilledButton.styleFrom(
              backgroundColor: m.surface, foregroundColor: m.textPrimary),
          onPressed: _joinTypedCode,
          child: const Text('Join'),
        ),
      ]),
    ];
  }

  /// Saved rooms + continue-watching — the right column when wide, appended
  /// below the form when narrow.
  List<Widget> _libraryColumn(
      List<SavedProfile> savedProfiles, SavedProfile? mostRecent) {
    return [
      if (savedProfiles.isNotEmpty) ...[
        const SizedBox(height: Spacing.xxl),
        _label('Saved rooms'),
        ...savedProfiles
            .map((p) => _profileCard(p, isMostRecent: p == mostRecent)),
      ],
      _ContinueWatching(
        history: widget.history,
        onResume: (entry) => _resumeHistory(entry, mostRecent),
      ),
    ];
  }

  Widget _label(String text) {
    final m = context.meow;
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Text(text, style: context.meowText.body.copyWith(color: m.textDim)),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String hint,
    Key? key,
    bool obscure = false,
  }) {
    final m = context.meow;
    return TextField(
      key: key,
      controller: controller,
      obscureText: obscure,
      style: TextStyle(color: m.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: m.textDim),
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
    return Card(
      color: m.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        side: BorderSide(color: m.border),
      ),
      child: ListTile(
        onTap: () => _connectProfile(p),
        leading: Icon(Icons.circle,
            size: 10, color: isMostRecent ? m.online : m.textDim),
        title: Text(p.name, style: TextStyle(color: m.textPrimary)),
        subtitle: Text('${p.username} · ${p.server}',
            style: context.meowText.body.copyWith(color: m.textDim)),
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
          _textField(controller: _server, hint: SyncplayConstants.defaultServer),
          const SizedBox(height: Spacing.md),
          _label('Port'),
          _textField(controller: _port, hint: '${SyncplayConstants.defaultPort}'),
          const SizedBox(height: Spacing.md),
          _label('Room password (optional)'),
          _textField(controller: _password, hint: 'leave blank for none'),
        ],
      ),
    );
  }
}

class _ContinueWatching extends StatelessWidget {
  const _ContinueWatching({required this.history, required this.onResume});

  final HistoryStore history;
  final void Function(HistoryEntry entry) onResume;

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    return StreamBuilder<List<HistoryEntry>>(
      stream: history.watchRecent(),
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
                  child: Text('Continue watching',
                      style: context.meowText.body.copyWith(color: m.textDim)),
                ),
                TextButton(
                  key: const Key('continue-clear-all'),
                  onPressed: () => history.clearAll(),
                  style: TextButton.styleFrom(
                    foregroundColor: m.textDim,
                    padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child:
                      const Text('Clear all', style: TextStyle(fontSize: TypeScale.body)),
                ),
              ],
            ),
            const SizedBox(height: Spacing.xs),
            ...recent.map(
              (e) => _HistoryCard(
                entry: e,
                onResume: () => onResume(e),
                onDelete: () => history.delete(e.id),
              ),
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
    required this.onResume,
    required this.onDelete,
  });

  final HistoryEntry entry;
  final VoidCallback onResume;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    final frac = progressFraction(entry);
    final roomLine = historyRoomLine(entry);
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
            title: Text(entry.fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: m.textPrimary)),
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
                            style: context.meowText.body.copyWith(color: m.accent),
                          ),
                        ),
                      ],
                    ),
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
                  Spacing.lg, 0, Spacing.lg, Spacing.md),
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
