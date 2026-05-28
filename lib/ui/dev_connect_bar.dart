import 'package:flutter/material.dart';

import '../core/sync/peer_state.dart';
import '../core/sync/syncplay_constants.dart';

/// TEMPORARY dev-only connect bar. Replaced by the Phase 4 connect screen.
/// Lets a human type a room + username and connect to a public server so two
/// instances can be synced during development.
class DevConnectBar extends StatefulWidget {
  const DevConnectBar({
    required this.connectionStatus,
    required this.onConnect,
    super.key,
  });

  final SyncConnectionStatus connectionStatus;
  final void Function({
    required String server,
    required int port,
    required String username,
    required String room,
  }) onConnect;

  @override
  State<DevConnectBar> createState() => _DevConnectBarState();
}

class _DevConnectBarState extends State<DevConnectBar> {
  final _server = TextEditingController(text: SyncplayConstants.defaultServer);
  final _port = TextEditingController(text: '${SyncplayConstants.defaultPort}');
  final _room = TextEditingController(text: 'meow-dev-room');
  final _user = TextEditingController();

  @override
  void dispose() {
    _server.dispose();
    _port.dispose();
    _room.dispose();
    _user.dispose();
    super.dispose();
  }

  void _submit() {
    final port = int.tryParse(_port.text) ?? SyncplayConstants.defaultPort;
    widget.onConnect(
      server: _server.text.trim(),
      port: port,
      username: _user.text.trim().isEmpty ? 'dev' : _user.text.trim(),
      room: _room.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final connecting =
        widget.connectionStatus == SyncConnectionStatus.connecting ||
            widget.connectionStatus == SyncConnectionStatus.handshaking;
    return Material(
      color: const Color(0xFF1A1410),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            _field(_user, 'username', 120),
            _field(_room, 'room', 160),
            _field(_server, 'server', 140),
            _field(_port, 'port', 70),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: connecting ? null : _submit,
              child: Text(connecting ? 'Connecting…' : 'Connect'),
            ),
            const SizedBox(width: 12),
            Text(
              widget.connectionStatus.name,
              style: const TextStyle(color: Color(0xFFD4A574)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String hint, double width) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SizedBox(
        width: width,
        child: TextField(
          controller: c,
          style: const TextStyle(color: Color(0xFFF5E6D3)),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0x88F5E6D3)),
            isDense: true,
          ),
        ),
      ),
    );
  }
}
