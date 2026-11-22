import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/user_database.dart';
import '../../mushaf/mushaf_providers.dart' show userDatabaseProvider;
import '../domain/prayer_settings.dart';

/// How a prayer was prayed («صليت»).
enum PrayedHow { onTime, late, jamaah }

/// A local calendar day as the log keeps it (`yyyy-MM-dd`).
String logDay(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// A week of the log: how many of the 35 prayers were marked, by how.
class WeekSummary {
  const WeekSummary(this.counts, {this.days = 7});

  final Map<PrayedHow, int> counts;
  final int days;

  int get prayed => counts.values.fold(0, (a, b) => a + b);
  int get possible => days * obligatoryPrayers.length;
}

/// «صلواتي»: the reader's own record of their prayers and qada counts.
/// Kept on the device; it goes to the backup and to the reader's own
/// sync like the rest of their data.
class PrayerLogRepository {
  PrayerLogRepository(this._db);

  final UserDatabase _db;

  static PrayerKind? _kind(String name) =>
      PrayerKind.values.where((p) => p.name == name).firstOrNull;

  static PrayedHow? _how(String name) =>
      PrayedHow.values.where((h) => h.name == name).firstOrNull;

  Stream<Map<PrayerKind, PrayedHow>> watchDay(DateTime day) =>
      (_db.select(_db.prayerLogs)
            ..where((t) => t.day.equals(logDay(day)) & t.deletedAt.isNull()))
          .watch()
          .map(
            (rows) => {
              for (final r in rows)
                if (_kind(r.prayer) != null && _how(r.how) != null)
                  _kind(r.prayer)!: _how(r.how)!,
            },
          );

  /// Marks [prayer] of [day] as prayed [how]; null clears the mark.
  Future<void> mark(DateTime day, PrayerKind prayer, PrayedHow? how) async {
    final d = logDay(day);
    final now = DateTime.now();
    final existing =
        await (_db.select(_db.prayerLogs)
              ..where((t) => t.day.equals(d) & t.prayer.equals(prayer.name)))
            .getSingleOrNull();
    if (existing == null) {
      if (how == null) return;
      await _db
          .into(_db.prayerLogs)
          .insert(
            PrayerLogsCompanion.insert(
              day: d,
              prayer: prayer.name,
              how: how.name,
            ),
          );
      return;
    }
    await (_db.update(
      _db.prayerLogs,
    )..where((t) => t.id.equals(existing.id))).write(
      PrayerLogsCompanion(
        how: how == null ? const Value.absent() : Value(how.name),
        updatedAt: Value(now),
        deletedAt: Value(how == null ? now : null),
      ),
    );
  }

  /// The week ending on [lastDay] (included).
  Future<WeekSummary> week(DateTime lastDay) async {
    final first = DateTime(lastDay.year, lastDay.month, lastDay.day - 6);
    final rows =
        await (_db.select(_db.prayerLogs)..where(
              (t) =>
                  t.day.isBetweenValues(logDay(first), logDay(lastDay)) &
                  t.deletedAt.isNull(),
            ))
            .get();
    final counts = {for (final h in PrayedHow.values) h: 0};
    for (final r in rows) {
      final h = _how(r.how);
      if (h != null && _kind(r.prayer) != null) counts[h] = counts[h]! + 1;
    }
    return WeekSummary(counts);
  }

  Stream<Map<PrayerKind, int>> watchQada() =>
      (_db.select(
        _db.qadaCounts,
      )..where((t) => t.deletedAt.isNull())).watch().map(
        (rows) => {
          for (final r in rows)
            if (_kind(r.prayer) != null) _kind(r.prayer)!: r.count,
        },
      );

  /// Adds [by] (negative: settled) to the qada count of [prayer], never
  /// below zero.
  Future<void> changeQada(PrayerKind prayer, int by) async {
    final existing = await (_db.select(
      _db.qadaCounts,
    )..where((t) => t.prayer.equals(prayer.name))).getSingleOrNull();
    final next = ((existing?.count ?? 0) + by).clamp(0, 99999);
    if (existing == null) {
      if (next == 0) return;
      await _db
          .into(_db.qadaCounts)
          .insert(
            QadaCountsCompanion.insert(prayer: prayer.name, count: Value(next)),
          );
      return;
    }
    await (_db.update(
      _db.qadaCounts,
    )..where((t) => t.id.equals(existing.id))).write(
      QadaCountsCompanion(
        count: Value(next),
        updatedAt: Value(DateTime.now()),
        deletedAt: const Value(null),
      ),
    );
  }
}

final prayerLogRepositoryProvider = Provider<PrayerLogRepository>(
  (ref) => PrayerLogRepository(ref.watch(userDatabaseProvider)),
);

/// A day's marks (by `logDay`), live.
final dayMarksProvider =
    StreamProvider.family<Map<PrayerKind, PrayedHow>, String>((ref, day) {
      final p = day.split('-').map(int.parse).toList();
      return ref
          .watch(prayerLogRepositoryProvider)
          .watchDay(DateTime(p[0], p[1], p[2]));
    });
