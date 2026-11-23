import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/look_kit.dart';
import '../../../core/ui/responsive.dart';
import '../../../l10n/app_localizations.dart';
import '../../mushaf/presentation/widgets/illuminated_frame.dart'
    show NumberFormatter;
import '../data/prayer_log_repository.dart';
import '../domain/prayer_calc.dart';
import '../domain/prayer_settings.dart';
import '../prayer_providers.dart';
import '../services/prayer_alarms.dart' show prayerName;
import 'prayer_times_screen.dart' show prayerTimesLocation;

const prayerTrackerLocation = '$prayerTimesLocation/tracker';

String prayedName(AppLocalizations l, PrayedHow h) => switch (h) {
  PrayedHow.onTime => l.prayedOnTime,
  PrayedHow.late => l.prayedLate,
  PrayedHow.jamaah => l.prayedJamaah,
};

IconData prayedIcon(PrayedHow h) => switch (h) {
  PrayedHow.onTime => Icons.check_circle,
  PrayedHow.late => Icons.schedule,
  PrayedHow.jamaah => Icons.groups,
};

/// The reader's «today»: the prayer place's calendar day when there is one.
DateTime trackerToday(PrayerSettings s, [DateTime? now]) {
  final n = now ?? DateTime.now();
  final place = s.place;
  return place == null
      ? DateTime(n.year, n.month, n.day)
      : placeToday(place, n);
}

/// «صليت»: how [prayer] of [day] was prayed (or clear the mark).
Future<void> showPrayedSheet(
  BuildContext context,
  WidgetRef ref,
  PrayerKind prayer,
  DateTime day, {
  PrayedHow? current,
}) async {
  final l = AppLocalizations.of(context);
  final repo = ref.read(prayerLogRepositoryProvider);
  final choice = await showModalBottomSheet<Object>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Semantics(
              header: true,
              child: Text(
                l.prayedAsk(prayerName(l, prayer)),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          for (final h in PrayedHow.values)
            ListTile(
              key: ValueKey('prayed-${h.name}'),
              minTileHeight: 56,
              leading: Icon(prayedIcon(h)),
              title: Text(prayedName(l, h)),
              selected: current == h,
              onTap: () => Navigator.pop(context, h),
            ),
          if (current != null)
            ListTile(
              key: const ValueKey('prayed-clear'),
              minTileHeight: 56,
              leading: const Icon(Icons.undo),
              title: Text(l.prayedClear),
              onTap: () => Navigator.pop(context, 'clear'),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (choice == null) return;
  await repo.mark(day, prayer, choice is PrayedHow ? choice : null);
}

/// «صلواتي»: a day's five prayers as the reader marked them, their qada
/// count, and a calm look at the last seven days (no streaks, no blame).
class PrayerTrackerScreen extends ConsumerStatefulWidget {
  const PrayerTrackerScreen({super.key, this.mark, this.now});

  /// Opened from «صليت» on an adhan alert: ask about this prayer at once.
  final PrayerKind? mark;

  /// Fixed "now" (tests).
  final DateTime? now;

  @override
  ConsumerState<PrayerTrackerScreen> createState() =>
      _PrayerTrackerScreenState();
}

class _PrayerTrackerScreenState extends ConsumerState<PrayerTrackerScreen> {
  late DateTime _day;
  late final DateTime _today;
  int _version = 0;

  @override
  void initState() {
    super.initState();
    _today = trackerToday(ref.read(prayerSettingsProvider), widget.now);
    _day = _today;
    final mark = widget.mark;
    if (mark != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await showPrayedSheet(context, ref, mark, _today);
        if (mounted) setState(() => _version++);
      });
    }
  }

  void _shift(int days) =>
      setState(() => _day = DateTime(_day.year, _day.month, _day.day + days));

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens.colors;
    final repo = ref.watch(prayerLogRepositoryProvider);
    final digits = NumberFormatter(Locale(l.localeName));
    final dayText = digits.decimal(
      DateFormat('EEEE d MMMM', l.localeName).format(_day),
    );
    return LookScaffold(
      maxWidth: ContentWidth.text,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            LookTopBar(title: l.trackerTitle),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: [
                  Row(
                    children: [
                      IconButton(
                        key: const ValueKey('tracker-prev'),
                        tooltip: l.trackerPrevDay,
                        onPressed: () => _shift(-1),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Expanded(
                        child: Semantics(
                          header: true,
                          liveRegion: true,
                          child: Text(
                            dayText,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('tracker-next'),
                        tooltip: l.trackerNextDay,
                        onPressed: _day.isBefore(_today)
                            ? () => _shift(1)
                            : null,
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  StreamBuilder<Map<PrayerKind, PrayedHow>>(
                    stream: repo.watchDay(_day),
                    builder: (context, snap) {
                      final marks = snap.data ?? const {};
                      return Card(
                        margin: EdgeInsets.zero,
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            for (final p in obligatoryPrayers) ...[
                              _DayRow(
                                prayer: p,
                                how: marks[p],
                                onTap: () async {
                                  await showPrayedSheet(
                                    context,
                                    ref,
                                    p,
                                    _day,
                                    current: marks[p],
                                  );
                                  if (mounted) setState(() => _version++);
                                },
                              ),
                              if (p != obligatoryPrayers.last)
                                Divider(height: 1, color: t.border),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 18),
                  FutureBuilder<WeekSummary>(
                    key: ValueKey('week-$_version-${logDay(_today)}'),
                    future: repo.week(_today),
                    builder: (context, snap) {
                      final w = snap.data;
                      if (w == null) return const SizedBox(height: 80);
                      return _WeekCard(summary: w);
                    },
                  ),
                  const SizedBox(height: 18),
                  Semantics(
                    header: true,
                    child: Text(
                      l.qadaTitle,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l.qadaNote,
                    style: TextStyle(color: t.muted, fontSize: 13, height: 1.6),
                  ),
                  const SizedBox(height: 8),
                  StreamBuilder<Map<PrayerKind, int>>(
                    stream: repo.watchQada(),
                    builder: (context, snap) {
                      final q = snap.data ?? const {};
                      return Card(
                        margin: EdgeInsets.zero,
                        child: Column(
                          children: [
                            for (final p in obligatoryPrayers)
                              _QadaRow(
                                prayer: p,
                                count: q[p] ?? 0,
                                onAdd: () => repo.changeQada(p, 1),
                                onSettle: () => repo.changeQada(p, -1),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({required this.prayer, required this.how, required this.onTap});

  final PrayerKind prayer;
  final PrayedHow? how;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens.colors;
    final h = how;
    return ListTile(
      key: ValueKey('tracker-row-${prayer.name}'),
      minTileHeight: 56,
      title: Text(prayerName(l, prayer)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            h == null ? l.trackerNotMarked : prayedName(l, h),
            style: TextStyle(color: h == null ? t.muted : t.goldText),
          ),
          const SizedBox(width: 8),
          Icon(
            h == null ? Icons.radio_button_unchecked : prayedIcon(h),
            color: h == null ? t.muted : t.goldText,
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _WeekCard extends StatelessWidget {
  const _WeekCard({required this.summary});

  final WeekSummary summary;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens.colors;
    final d = NumberFormatter(Locale(l.localeName));
    final c = summary.counts;
    return Semantics(
      container: true,
      child: Container(
        key: const ValueKey('tracker-week'),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: t.control.withValues(alpha: .12),
          border: Border.all(color: t.goldText.withValues(alpha: .25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.weekTitle, style: TextStyle(color: t.muted, fontSize: 13)),
            const SizedBox(height: 4),
            Text(
              l.weekSummary(d(summary.prayed), d(summary.possible)),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              l.weekBreakdown(
                d(c[PrayedHow.onTime] ?? 0),
                d(c[PrayedHow.late] ?? 0),
                d(c[PrayedHow.jamaah] ?? 0),
              ),
              style: const TextStyle(height: 1.6),
            ),
            const SizedBox(height: 6),
            Text(
              l.weekGentle,
              style: TextStyle(color: t.muted, fontSize: 13, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }
}

class _QadaRow extends StatelessWidget {
  const _QadaRow({
    required this.prayer,
    required this.count,
    required this.onAdd,
    required this.onSettle,
  });

  final PrayerKind prayer;
  final int count;
  final Future<void> Function() onAdd;
  final Future<void> Function() onSettle;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final name = prayerName(l, prayer);
    final d = NumberFormatter(Locale(l.localeName));
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 16, end: 4),
      child: Row(
        children: [
          Expanded(child: Text(name, style: const TextStyle(fontSize: 16))),
          IconButton(
            key: ValueKey('qada-settle-${prayer.name}'),
            tooltip: l.qadaSettle(name),
            onPressed: count > 0 ? () => unawaited(onSettle()) : null,
            icon: const Icon(Icons.remove_circle_outline),
          ),
          SizedBox(
            width: 44,
            child: Text(
              d(count),
              key: ValueKey('qada-count-${prayer.name}'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            key: ValueKey('qada-add-${prayer.name}'),
            tooltip: l.qadaAdd(name),
            onPressed: () => unawaited(onAdd()),
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
    );
  }
}
