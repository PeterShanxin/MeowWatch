import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/sync/loaded_notice.dart';

void main() {
  test('announces "in sync" only when synced and files match', () {
    expect(
      loadedInSyncNotice(syncHealthy: true, fileMismatch: false),
      '✓ Loaded — in sync!',
    );
  });

  test('stays silent when solo (no healthy sync)', () {
    expect(loadedInSyncNotice(syncHealthy: false, fileMismatch: false), isNull);
  });

  test('stays silent when the files mismatch (never a false sync claim)', () {
    expect(loadedInSyncNotice(syncHealthy: true, fileMismatch: true), isNull);
  });
}
