import 'package:drift/drift.dart';

import 'habit_tables.dart' show SyncColumns;

/// «صلواتي»: how a prayer of a local day (`yyyy-MM-dd`) was prayed. One
/// row a prayer a day; private to the reader (device, backup and their
/// own sync only).
@DataClassName('PrayerLogRow')
class PrayerLogs extends Table with SyncColumns {
  @override
  String get tableName => 'prayer_log';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get day => text()();

  /// `PrayerKind.name` of one of the five.
  TextColumn get prayer => text()();

  /// `PrayedHow.name`: onTime, late or jamaah.
  TextColumn get how => text()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {day, prayer},
  ];
}

/// «القضاء»: how many of a prayer the reader still owes, by their own
/// count. One row a prayer.
@DataClassName('QadaRow')
class QadaCounts extends Table with SyncColumns {
  @override
  String get tableName => 'qada_count';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get prayer => text().unique()();
  IntColumn get count => integer().withDefault(const Constant(0))();
}
