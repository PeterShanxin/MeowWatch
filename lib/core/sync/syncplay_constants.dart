/// Wire-protocol constants for the Syncplay client, verified against upstream
/// syncplay/constants.py (May 2026).
class SyncplayConstants {
  SyncplayConstants._();

  /// Sent as `version` in Hello for backward compat; real version goes in
  /// `realversion`. Upstream clients do exactly this.
  static const protocolVersion = '1.2.255';
  static const realVersion = '1.7.5';

  static const defaultServer = 'syncplay.pl';
  static const defaultPort = 8999;

  /// Feature map advertised in Hello. We support chat receive only this phase,
  /// but advertise the standard static flags so servers treat us as a modern
  /// client.
  static const features = <String, Object>{
    'sharedPlaylists': false,
    'chat': true,
    'featureList': true,
    'readiness': true,
    'managedRooms': true,
    'persistentRooms': true,
    'setOthersReadiness': false,
  };

  /// If the local position differs from the latency-adjusted peer position by
  /// more than this while following, hard-seek to match. Upstream uses ~1s.
  static const seekThreshold = Duration(milliseconds: 1500);

  /// Below this, a position change is treated as natural playback drift rather
  /// than a user seek.
  static const seekDetectThreshold = Duration(milliseconds: 1000);
}
