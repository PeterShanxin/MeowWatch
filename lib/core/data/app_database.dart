import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

@DataClassName('ProfileRow')
class Profiles extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get server => text()();
  IntColumn get port => integer()();
  TextColumn get room => text()();
  TextColumn get username => text()();
  TextColumn get password => text().nullable()();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  DateTimeColumn get lastUsedAt => dateTime().nullable()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {server, port, room, username},
      ];
}

@DataClassName('HistoryRow')
class HistoryEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get filePath => text().unique()();
  TextColumn get fileName => text()();
  IntColumn get fileSizeBytes => integer().withDefault(const Constant(0))();
  IntColumn get durationMs => integer().nullable()();
  IntColumn get lastPositionMs => integer().withDefault(const Constant(0))();
  DateTimeColumn get playedAt => dateTime()();
}

@DriftDatabase(tables: [Profiles, HistoryEntries])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// In-memory database for tests.
  AppDatabase.memory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 1;
}

/// Opens the on-disk database under the app's support directory
/// (Windows: %APPDATA%\<org>\meowwatch\meowwatch.db or similar).
Future<AppDatabase> openAppDatabase() async {
  final dir = await getApplicationSupportDirectory();
  final file = File(p.join(dir.path, 'meowwatch.db'));
  return AppDatabase(NativeDatabase.createInBackground(file));
}
