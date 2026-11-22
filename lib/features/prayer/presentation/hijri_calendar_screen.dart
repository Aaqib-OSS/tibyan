import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/look_kit.dart';
import '../../../core/ui/responsive.dart';
import '../../../l10n/app_localizations.dart';
import '../../khatma/khatma_providers.dart' show reminderSchedulerProvider;
import '../../mushaf/presentation/widgets/illuminated_frame.dart'
    show NumberFormatter;
import '../domain/hijri_occasions.dart';
import '../domain/prayer_calc.dart';
import '../domain/prayer_settings.dart';
import '../prayer_providers.dart';
import '../services/occasion_reminders.dart';
import 'prayer_times_screen.dart' show prayerTimesLocation;

const hijriCalendarLocation = '$prayerTimesLocation/hijri';

/// The page index of the month that holds today (the pager runs both ways).
const _todayPage = 6000;

/// «التقويم الهجري»: a month grid of Hijri and Gregorian dates (with the
/// reader's ±day adjustment), the year's occasions by name and date, how
/// long until the next one, and an optional reminder the day before.
class HijriCalendarScreen extends ConsumerStatefulWidget {
  const HijriCalendarScreen({super.key, this.now});

  /// Fixed "now" (tests).
  final DateTime? now;

  @override
  ConsumerState<HijriCalendarScreen> createState() =>
      _HijriCalendarScreenState();
}

class _HijriCalendarScreenState extends ConsumerState<HijriCalendarScreen> {
  final _pages = PageController(initialPage: _todayPage);
  int _page = _todayPage;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  DateTime _today(PrayerSettings s) {
    final now = widget.now ?? DateTime.now();
    final place = s.place;
    return place == null
        ? DateTime(now.year, now.month, now.day)
        : placeToday(place, now);
  }

  void _go(int page) => _pages.animateToPage(
    page,
    duration: MediaQuery.of(context).disableAnimations
        ? const Duration(milliseconds: 1)
        : const Duration(milliseconds: 280),
    curve: Curves.easeOutCubic,
  );

  Future<void> _setReminders(bool on) async {
    if (on) {
      final ok = await ref.read(reminderSchedulerProvider).requestPermission();
      if (!ok) return;
    }
    await ref
        .read(prayerSettingsProvider.notifier)
        .update((s) => s.copyWith(occasionReminders: on));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens.colors;
    final s = ref.watch(prayerSettingsProvider);
    final today = _today(s);
    final offset = s.hijriOffset;
    final current = hijriMonthOf(today, offset);
    final month = shiftMonth(current, _page - _todayPage);
    final digits = NumberFormatter(Locale(l.localeName));
    final upcoming = upcomingOccasions(today, offset);
    final next = upcoming.firstWhere(
      (u) => daysUntil(today, u.start) >= 0,
      orElse: () => upcoming.first,
    );
    final ongoing = upcoming.where((u) => daysUntil(today, u.start) < 0);
    return LookScaffold(
      maxWidth: ContentWidth.text,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            LookTopBar(
              title: l.hijriCalendarTitle,
              actions: [
                if (_page != _todayPage)
                  TextButton(
                    key: const ValueKey('hijri-today'),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: () => _go(_todayPage),
                    child: Text(l.hijriBackToToday),
                  ),
              ],
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: [
                  for (final u in ongoing)
                    _OccasionCard(
                      name: occasionName(l, u.occasion),
                      date: occasionDateLabel(l, u.occasion),
                      status: l.occasionOngoing,
                    ),
                  _OccasionCard(
                    key: const ValueKey('hijri-next'),
                    caption: l.occasionNext,
                    name: occasionName(l, next.occasion),
                    date:
                        '${occasionDateLabel(l, next.occasion)} '
                        '${digits(next.year)} · '
                        '${_gregorian(l, next.start)}',
                    status: l.occasionIn(
                      daysUntil(today, next.start),
                      digits(daysUntil(today, next.start)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _MonthHeader(
                    title:
                        '${hijriMonthName(l, month.month)} ${digits(month.year)}',
                    subtitle: _gregorianSpan(l, month, offset),
                    onPrev: () => _go(_page - 1),
                    onNext: () => _go(_page + 1),
                  ),
                  const SizedBox(height: 6),
                  _MonthPager(
                    controller: _pages,
                    onPage: (p) => setState(() => _page = p),
                    monthOf: (p) => shiftMonth(current, p - _todayPage),
                    today: today,
                    offset: offset,
                  ),
                  if (offset != 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: TextButton(
                        key: const ValueKey('hijri-offset'),
                        style: TextButton.styleFrom(
                          alignment: AlignmentDirectional.centerStart,
                          minimumSize: const Size(48, 48),
                        ),
                        onPressed: () =>
                            context.push('$prayerTimesLocation/settings'),
                        child: Text(
                          l.hijriAdjustment(
                            '${offset > 0 ? '+' : '−'}${digits(offset.abs())}',
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 18),
                  Semantics(
                    header: true,
                    child: Text(
                      l.occasionsTitle,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    margin: EdgeInsets.zero,
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (final u in upcoming) ...[
                          _OccasionRow(
                            key: ValueKey('occasion-${u.occasion.name}'),
                            name: occasionName(l, u.occasion),
                            hijri:
                                '${occasionDateLabel(l, u.occasion)} '
                                '${digits(u.year)}',
                            gregorian: _gregorian(l, u.start),
                          ),
                          if (u != upcoming.last)
                            Divider(height: 1, color: t.border),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    margin: EdgeInsets.zero,
                    child: SwitchListTile(
                      key: const ValueKey('occasion-reminders'),
                      value: s.occasionReminders,
                      onChanged: _setReminders,
                      title: Text(l.occasionRemindersTitle),
                      subtitle: Text(l.occasionRemindersNote),
                    ),
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

/// «الأحد ٦ يوليو ٢٠٢٦».
String _gregorian(AppLocalizations l, DateTime d) =>
    NumberFormatter(Locale(l.localeName))
        .decimal(DateFormat('EEEE d MMMM y', l.localeName).format(d));

/// «نوفمبر – ديسمبر ٢٠٢٦»: the Gregorian months a Hijri month spans.
String _gregorianSpan(AppLocalizations l, HijriMonth m, int offset) {
  final first = gregorianOf(m.year, m.month, 1, offset);
  final last = first.add(Duration(days: hijriMonthLength(m) - 1));
  final digits = NumberFormatter(Locale(l.localeName));
  final f = DateFormat('MMMM', l.localeName);
  final y = DateFormat('MMMM y', l.localeName);
  final text = first.month == last.month
      ? y.format(first)
      : first.year == last.year
      ? '${f.format(first)} – ${y.format(last)}'
      : '${y.format(first)} – ${y.format(last)}';
  return digits.decimal(text);
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.title,
    required this.subtitle,
    required this.onPrev,
    required this.onNext,
  });

  final String title;
  final String subtitle;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens.colors;
    return Row(
      children: [
        IconButton(
          key: const ValueKey('hijri-prev'),
          tooltip: l.hijriPrevMonth,
          onPressed: onPrev,
          icon: const Icon(Icons.chevron_left),
          style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
        ),
        Expanded(
          child: Semantics(
            header: true,
            liveRegion: true,
            child: Column(
              children: [
                Text(
                  title,
                  key: const ValueKey('hijri-month-title'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: t.goldText,
                  ),
                ),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: t.muted, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
        IconButton(
          key: const ValueKey('hijri-next-month'),
          tooltip: l.hijriNextMonth,
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right),
          style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
        ),
      ],
    );
  }
}

class _MonthPager extends StatelessWidget {
  const _MonthPager({
    required this.controller,
    required this.onPage,
    required this.monthOf,
    required this.today,
    required this.offset,
  });

  final PageController controller;
  final ValueChanged<int> onPage;
  final HijriMonth Function(int page) monthOf;
  final DateTime today;
  final int offset;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    final cell = 52.0 * (1 + (scale - 1) * .6);
    return SizedBox(
      // A weekday row and six weeks.
      height: cell * 6 + 28 * scale,
      child: PageView.builder(
        controller: controller,
        onPageChanged: onPage,
        itemBuilder: (context, p) => _MonthGrid(
          month: monthOf(p),
          today: today,
          offset: offset,
          cellHeight: cell,
        ),
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.today,
    required this.offset,
    required this.cellHeight,
  });

  final HijriMonth month;
  final DateTime today;
  final int offset;
  final double cellHeight;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens.colors;
    final digits = NumberFormatter(Locale(l.localeName));
    final firstDow = MaterialLocalizations.of(context).firstDayOfWeekIndex;
    final first = gregorianOf(month.year, month.month, 1, offset);
    final length = hijriMonthLength(month);
    // DateTime.weekday: 1 Monday … 7 Sunday; firstDow: 0 Sunday … 6.
    final lead = (first.weekday % 7 - firstDow) % 7;
    final names = DateFormat.E(l.localeName).dateSymbols.NARROWWEEKDAYS;
    final monthName = hijriMonthName(l, month.month);
    final rows = <Widget>[
      ExcludeSemantics(
        child: Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Text(
                  names[(firstDow + i) % 7],
                  textAlign: TextAlign.center,
                  style: TextStyle(color: t.muted, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    ];
    var day = 1 - lead;
    while (day <= length) {
      final cells = <Widget>[];
      for (var i = 0; i < 7; i++, day++) {
        if (day < 1 || day > length) {
          cells.add(const Expanded(child: SizedBox()));
          continue;
        }
        final g = DateTime(first.year, first.month, first.day + day - 1);
        final isToday = g == today;
        final occasion = occasionOn(month.month, day);
        final label = [
          if (isToday) l.hijriTodayLabel,
          '${digits(day)} $monthName ${digits(month.year)}',
          _gregorian(l, g),
          if (occasion != null) occasionName(l, occasion),
        ].join('، ');
        cells.add(
          Expanded(
            child: Semantics(
              label: label,
              selected: isToday,
              excludeSemantics: true,
              child: Container(
                key: isToday ? const ValueKey('hijri-today-cell') : null,
                height: cellHeight,
                margin: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: isToday
                      ? t.goldText.withValues(alpha: .18)
                      : occasion != null
                      ? t.control.withValues(alpha: .10)
                      : null,
                  border: isToday
                      ? Border.all(color: t.goldText, width: 1.5)
                      : null,
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          digits(day),
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: isToday || occasion != null
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: isToday || occasion != null
                                ? t.goldText
                                : null,
                          ),
                        ),
                        Text(
                          digits(g.day),
                          style: TextStyle(fontSize: 11, color: t.muted),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }
      rows.add(Row(children: cells));
    }
    return Column(children: rows);
  }
}

class _OccasionCard extends StatelessWidget {
  const _OccasionCard({
    super.key,
    this.caption,
    required this.name,
    required this.date,
    required this.status,
  });

  final String? caption;
  final String name;
  final String date;
  final String status;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens.colors;
    return Semantics(
      container: true,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: t.control.withValues(alpha: .14),
          border: Border.all(color: t.goldText.withValues(alpha: .3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (caption != null)
              Text(caption!, style: TextStyle(color: t.muted, fontSize: 13)),
            Text(
              name,
              style: TextStyle(
                fontSize: 24,
                color: t.goldText,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(date, style: const TextStyle(fontSize: 14, height: 1.6)),
            const SizedBox(height: 4),
            Text(
              status,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _OccasionRow extends StatelessWidget {
  const _OccasionRow({
    super.key,
    required this.name,
    required this.hijri,
    required this.gregorian,
  });

  final String name;
  final String hijri;
  final String gregorian;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens.colors;
    return Semantics(
      container: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(hijri, style: const TextStyle(fontSize: 14)),
              Text(gregorian, style: TextStyle(fontSize: 13, color: t.muted)),
            ],
          ),
        ),
      ),
    );
  }
}
