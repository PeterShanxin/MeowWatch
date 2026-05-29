import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/connect/room_code.dart';
import '../../core/connect/room_config.dart';
import '../../core/data/history_entry.dart';
import '../../core/data/saved_profile.dart';
import '../../core/data/stores.dart';
import '../../core/sync/syncplay_constants.dart';

// Cozy theme (hardcoded until Phase 5).
const _bg = Color(0xFF1A1410);
const _card = Color(0xF2241B14);
const _amber = Color(0xFFD4A574);
const _cream = Color(0xFFF5E6D3);
const _dim = Color(0x99F5E6D3);
const _border = Color(0x55D4A574);

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({
    required this.profiles,
    required this.history,
    required this.onConnect,
    super.key,
  });

  final ProfileStore profiles;
  final HistoryStore history;
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
  bool _advancedOpen = false;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _server.dispose();
    _port.dispose();
    _password.dispose();
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
    final room = generateRoomCode();
    // Copy without blocking the join — clipboard is a convenience, and on a
    // headless test binding the platform channel never replies.
    Clipboard.setData(ClipboardData(text: room)).ignore();
    await _connect(RoomConfig(
      server: _serverValue,
      port: _portValue,
      room: room,
      username: _username,
      password: _passwordValue,
    ));
  }

  Future<void> _joinTypedCode() async {
    final room = _code.text.trim();
    if (room.isEmpty) return;
    await _connect(RoomConfig(
      server: _serverValue,
      port: _portValue,
      room: room,
      username: _username,
      password: _passwordValue,
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
    final room = recent?.room ?? generateRoomCode();
    await _connect(RoomConfig(
      server: recent?.server ?? _serverValue,
      port: recent?.port ?? _portValue,
      room: room,
      username: _username,
      password: recent?.password ?? _passwordValue,
      resumeFilePath: entry.filePath,
      resumePositionMs: entry.lastPositionMs,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: StreamBuilder<List<SavedProfile>>(
              stream: widget.profiles.watchProfiles(),
              initialData: const [],
              builder: (context, profileSnap) {
                final savedProfiles = profileSnap.data ?? const [];
                final mostRecent =
                    savedProfiles.isEmpty ? null : savedProfiles.first;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('MeowWatch',
                        style: TextStyle(
                            color: _cream,
                            fontSize: 30,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    const Text('Watch together, in sync.',
                        style: TextStyle(color: _dim, fontSize: 14)),
                    const SizedBox(height: 24),
                    _label('Your name'),
                    _textField(
                        key: const Key('connect-name'),
                        controller: _name,
                        hint: 'e.g. lin'),
                    const SizedBox(height: 20),
                    FilledButton(
                      key: const Key('connect-start-new'),
                      style: FilledButton.styleFrom(
                        backgroundColor: _amber,
                        foregroundColor: _bg,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed: _startNewRoom,
                      child: const Text('Start new room',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(height: 8),
                    const Text('A code is generated and copied to clipboard.',
                        style: TextStyle(color: _dim, fontSize: 12)),
                    const SizedBox(height: 20),
                    _label('Enter code from friend'),
                    Row(children: [
                      Expanded(
                        child: _textField(
                            key: const Key('connect-code'),
                            controller: _code,
                            hint: 'cozy-fox-42'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        key: const Key('connect-join'),
                        style: FilledButton.styleFrom(
                            backgroundColor: _card, foregroundColor: _cream),
                        onPressed: _joinTypedCode,
                        child: const Text('Join'),
                      ),
                    ]),
                    if (savedProfiles.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      _label('Saved rooms'),
                      ...savedProfiles.map((p) =>
                          _profileCard(p, isMostRecent: p == mostRecent)),
                    ],
                    _ContinueWatching(
                      history: widget.history,
                      onResume: (entry) => _resumeHistory(entry, mostRecent),
                    ),
                    const SizedBox(height: 16),
                    _advancedSection(),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: const TextStyle(color: _dim, fontSize: 13)),
      );

  Widget _textField({
    required TextEditingController controller,
    required String hint,
    Key? key,
    bool obscure = false,
  }) {
    return TextField(
      key: key,
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(color: _cream),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: _dim),
        filled: true,
        fillColor: _card,
        isDense: true,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _amber),
        ),
      ),
    );
  }

  Widget _profileCard(SavedProfile p, {required bool isMostRecent}) {
    return Card(
      color: _card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _border),
      ),
      child: ListTile(
        onTap: () => _connectProfile(p),
        leading: Icon(Icons.circle,
            size: 10, color: isMostRecent ? const Color(0xFF7BC47F) : _dim),
        title: Text(p.name, style: const TextStyle(color: _cream)),
        subtitle: Text('${p.username} · ${p.server}',
            style: const TextStyle(color: _dim, fontSize: 12)),
        trailing: IconButton(
          key: Key('connect-delete-${p.id}'),
          icon: const Icon(Icons.close, color: _dim, size: 18),
          onPressed: () => widget.profiles.delete(p.id),
        ),
      ),
    );
  }

  Widget _advancedSection() {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: const Key('connect-advanced'),
        initiallyExpanded: _advancedOpen,
        onExpansionChanged: (v) => setState(() => _advancedOpen = v),
        title: const Text('Advanced', style: TextStyle(color: _dim)),
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        children: [
          _label('Server'),
          _textField(controller: _server, hint: SyncplayConstants.defaultServer),
          const SizedBox(height: 12),
          _label('Port'),
          _textField(controller: _port, hint: '${SyncplayConstants.defaultPort}'),
          const SizedBox(height: 12),
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
    return StreamBuilder<List<HistoryEntry>>(
      stream: history.watchRecent(),
      initialData: const [],
      builder: (context, snap) {
        final recent = snap.data ?? const [];
        if (recent.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Text('Continue watching',
                  style: TextStyle(color: _dim, fontSize: 13)),
            ),
            ...recent.map(
              (e) => Card(
                color: _card,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: _border),
                ),
                child: ListTile(
                  key: Key('continue-${e.id}'),
                  onTap: () => onResume(e),
                  leading: const Icon(Icons.play_circle, color: _amber),
                  title: Text(e.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _cream)),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
