import 'dart:async';

import 'package:meowwatch/core/data/history_entry.dart';
import 'package:meowwatch/core/data/saved_profile.dart';
import 'package:meowwatch/core/data/settings_store.dart';
import 'package:meowwatch/core/data/stores.dart';

class FakeProfileStore implements ProfileStore {
  final _ctrl = StreamController<List<SavedProfile>>.broadcast();
  final List<SavedProfile> profiles = [];

  @override
  Stream<List<SavedProfile>> watchProfiles() async* {
    yield List.unmodifiable(profiles);
    yield* _ctrl.stream;
  }

  @override
  Future<void> saveUsed({
    required String name,
    required String server,
    required int port,
    required String room,
    required String username,
    String? password,
  }) async {}

  @override
  Future<void> delete(int id) async {}
}

class FakeHistoryStore implements HistoryStore {
  final List<HistoryEntry> recent = [];
  final _ctrl = StreamController<List<HistoryEntry>>.broadcast();

  void _emit() => _ctrl.add(List.unmodifiable(recent));

  @override
  Stream<List<HistoryEntry>> watchRecent({int limit = 6}) async* {
    yield List.unmodifiable(recent);
    yield* _ctrl.stream;
  }

  @override
  Future<void> recordOpen({
    required String filePath,
    required String fileName,
    required int fileSizeBytes,
    int? durationMs,
  }) async {}

  @override
  Future<void> updatePosition({
    required String filePath,
    required int positionMs,
  }) async {}

  @override
  Future<void> delete(int id) async {
    recent.removeWhere((e) => e.id == id);
    _emit();
  }

  @override
  Future<void> clearAll() async {
    recent.clear();
    _emit();
  }
}

class FakeSettingsStore implements SettingsStore {
  final Map<String, String> _map = {};

  @override
  Future<String?> get(String key) async => _map[key];

  @override
  Future<void> set(String key, String value) async => _map[key] = value;
}
