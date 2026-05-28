import 'dart:convert';

import 'syncplay_constants.dart';
import 'peer_state.dart';

/// Buffers raw socket bytes and yields complete lines. The Syncplay protocol
/// sends one JSON object per line terminated by `\r\n`; we also tolerate a lone
/// `\n`.
class LineFramer {
  final List<int> _buffer = <int>[];

  List<String> addChunk(List<int> chunk) {
    _buffer.addAll(chunk);
    final lines = <String>[];
    var start = 0;
    for (var i = 0; i < _buffer.length; i++) {
      if (_buffer[i] == 0x0A) {
        // newline
        var end = i;
        if (end > start && _buffer[end - 1] == 0x0D) {
          end -= 1; // strip preceding carriage return
        }
        lines.add(utf8.decode(_buffer.sublist(start, end)));
        start = i + 1;
      }
    }
    _buffer.removeRange(0, start);
    return lines;
  }
}

// ---------------------------------------------------------------------------
// Encoders — each returns the Map to be json.encode()'d and written as a line.
// ---------------------------------------------------------------------------

Map<String, Object?> encodeHello({
  required String username,
  required String room,
  String? password,
}) {
  final hello = <String, Object?>{
    'username': username,
    'room': {'name': room},
    'version': SyncplayConstants.protocolVersion,
    'realversion': SyncplayConstants.realVersion,
    'features': SyncplayConstants.features,
  };
  if (password != null && password.isNotEmpty) {
    hello['password'] = password;
  }
  return {'Hello': hello};
}

Map<String, Object?> encodeFile({
  required String name,
  required int sizeBytes,
  required Duration duration,
}) {
  return {
    'Set': {
      'file': {
        'name': name,
        'duration': duration.inMilliseconds / 1000.0,
        'size': sizeBytes,
      },
    },
  };
}

Map<String, Object?> encodeTlsRequest() => {
      'TLS': {'startTLS': 'send'},
    };

Map<String, Object?> encodeChat(String text) => {'Chat': text};

Map<String, Object?> encodeList() => {'List': null};

Map<String, Object?> encodeState({
  required Duration position,
  required bool paused,
  required bool doSeek,
  required double? latencyCalculation,
  required double clientLatencyCalculation,
  required double clientRtt,
  required int clientIgnore,
  required int serverIgnore,
}) {
  final playstate = <String, Object?>{
    'position': position.inMilliseconds / 1000.0,
    'paused': paused,
  };
  if (doSeek) playstate['doSeek'] = true;

  final ping = <String, Object?>{
    'clientLatencyCalculation': clientLatencyCalculation,
    'clientRtt': clientRtt,
  };
  if (latencyCalculation != null) {
    ping['latencyCalculation'] = latencyCalculation;
  }

  final state = <String, Object?>{
    'playstate': playstate,
    'ping': ping,
  };

  if (clientIgnore != 0 || serverIgnore != 0) {
    final ignore = <String, Object?>{};
    if (serverIgnore != 0) ignore['server'] = serverIgnore;
    if (clientIgnore != 0) ignore['client'] = clientIgnore;
    state['ignoringOnTheFly'] = ignore;
  }

  return {'State': state};
}

// ---------------------------------------------------------------------------
// Decoder — classify an incoming parsed Map into a typed ServerMessage.
// ---------------------------------------------------------------------------

sealed class ServerMessage {
  const ServerMessage();
}

class HelloMessage extends ServerMessage {
  const HelloMessage();
}

class StateMessage extends ServerMessage {
  const StateMessage({
    this.peer,
    this.latencyCalculation,
    this.clientIgnore,
    this.serverIgnore,
  });

  /// Peer playstate, or null if this State carried no playstate block.
  final PeerPlayState? peer;
  final double? latencyCalculation;
  final int? clientIgnore;
  final int? serverIgnore;
}

class PresenceMessage extends ServerMessage {
  const PresenceMessage(this.events);
  final List<PresenceEvent> events;
}

class ChatServerMessage extends ServerMessage {
  const ChatServerMessage(this.message);
  final ChatMessage message;
}

class TlsMessage extends ServerMessage {
  const TlsMessage({required this.startTls});
  final bool startTls;
}

class ErrorMessage extends ServerMessage {
  const ErrorMessage(this.message);
  final String message;
}

class UnknownMessage extends ServerMessage {
  const UnknownMessage();
}

ServerMessage decodeServerMessage(Map<dynamic, dynamic> message) {
  if (message.containsKey('Hello')) return const HelloMessage();
  if (message.containsKey('State')) return _decodeState(message['State'] as Map);
  if (message.containsKey('Set')) return _decodeSet(message['Set'] as Map);
  if (message.containsKey('Chat')) {
    final chat = message['Chat'] as Map;
    return ChatServerMessage(ChatMessage(
      username: chat['username'] as String? ?? '',
      text: chat['message'] as String? ?? '',
    ));
  }
  if (message.containsKey('TLS')) {
    final tls = message['TLS'] as Map;
    final answer = tls['startTLS'];
    return TlsMessage(startTls: answer is String && answer.contains('true'));
  }
  if (message.containsKey('Error')) {
    final err = message['Error'] as Map;
    return ErrorMessage(err['message'] as String? ?? 'unknown error');
  }
  return const UnknownMessage();
}

StateMessage _decodeState(Map<dynamic, dynamic> state) {
  PeerPlayState? peer;
  if (state['playstate'] is Map) {
    final ps = state['playstate'] as Map;
    final pos = ps['position'];
    final paused = ps['paused'];
    if (pos is num && paused is bool) {
      peer = PeerPlayState.fromSeconds(
        seconds: pos.toDouble(),
        paused: paused,
        doSeek: ps['doSeek'] == true,
        setBy: ps['setBy'] as String?,
      );
    }
  }
  double? latency;
  if (state['ping'] is Map) {
    final ping = state['ping'] as Map;
    final lc = ping['latencyCalculation'];
    if (lc is num) latency = lc.toDouble();
  }
  int? clientIgnore;
  int? serverIgnore;
  if (state['ignoringOnTheFly'] is Map) {
    final ig = state['ignoringOnTheFly'] as Map;
    if (ig['client'] is num) clientIgnore = (ig['client'] as num).toInt();
    if (ig['server'] is num) serverIgnore = (ig['server'] as num).toInt();
  }
  return StateMessage(
    peer: peer,
    latencyCalculation: latency,
    clientIgnore: clientIgnore,
    serverIgnore: serverIgnore,
  );
}

ServerMessage _decodeSet(Map<dynamic, dynamic> set) {
  if (set['user'] is Map) {
    final events = <PresenceEvent>[];
    (set['user'] as Map).forEach((name, value) {
      if (value is! Map) return;
      final room =
          value['room'] is Map ? (value['room'] as Map)['name'] as String? : null;
      final fileName =
          value['file'] is Map ? (value['file'] as Map)['name'] as String? : null;
      final event = value['event'];
      if (event is Map && event['left'] != null) {
        events.add(PresenceEvent(
          username: name as String,
          kind: PresenceKind.left,
          room: room,
          fileName: fileName,
        ));
      } else if (event is Map && event['joined'] != null) {
        events.add(PresenceEvent(
          username: name as String,
          kind: PresenceKind.joined,
          room: room,
          fileName: fileName,
        ));
      }
    });
    if (events.isNotEmpty) return PresenceMessage(events);
  }
  return const UnknownMessage();
}
