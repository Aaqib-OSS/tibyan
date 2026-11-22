import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/look_kit.dart';
import '../../../core/ui/responsive.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/prayer_calc.dart';
import '../domain/prayer_settings.dart';
import '../prayer_providers.dart';
import '../services/prayer_alarms.dart';
import 'hijri_calendar_screen.dart' show hijriCalendarLocation;
import 'prayer_alert_sheet.dart';
import 'prayer_enable.dart';
import 'prayer_widgets.dart';
import 'qibla_screen.dart' show qiblaLocation;

const prayerTimesLocation = '/prayer';

/// The rows of the times list: the five prayers and sunrise.
const _rows = [
  PrayerKind.fajr,
  PrayerKind.shuruq,
  PrayerKind.dhuhr,
  PrayerKind.asr,
  PrayerKind.maghrib,
  PrayerKind.isha,
];

/// «مواقيت الصلاة»: today's times at the reader's place, the next prayer
/// and how long until it, and each prayer's alert (its icon opens the
/// prayer's alert settings).
class PrayerTimesScreen extends ConsumerStatefulWidget {
  const PrayerTimesScreen({super.key});

  @override
  ConsumerState<PrayerTimesScreen> createState() => _PrayerTimesScreenState();
}

class _PrayerTimesScreenState extends ConsumerState<PrayerTimesScreen> {
  Timer? _clock;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(
      const Duration(seconds: 30),
      (_) => setState(() => _now = DateTime.now()),
    );
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _changePlace() async {
    final place = await choosePlace(context, ref);
    if (place == null) return;
    await ref
        .read(prayerSettingsProvider.notifier)
        .update((s) => s.copyWith(place: place));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens.colors;
    final s = ref.watch(prayerSettingsProvider);
    final place = s.place;
    final arabic = l.localeName == 'ar';
    return LookScaffold(
      maxWidth: ContentWidth.text,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            LookTopBar(
              title: l.prayerTimesTitle,
              actions: [
                IconButton(
                  key: const ValueKey('prayer-qibla'),
                  tooltip: l.qiblaOpen,
                  onPressed: () => context.push(qiblaLocation),
                  icon: const Icon(Icons.explore_outlined),
                ),
                IconButton(
                  key: const ValueKey('prayer-settings'),
                  tooltip: l.prayerSettingsTitle,
                  onPressed: () =>
                      context.push('$prayerTimesLocation/settings'),
                  icon: const Icon(Icons.tune),
                ),
              ],
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: [
                  TextButton.icon(
                    key: const ValueKey('prayer-place'),
                    style: TextButton.styleFrom(
                      alignment: AlignmentDirectional.centerStart,
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: _changePlace,
                    icon: const Icon(Icons.place_outlined, size: 18),
                    label: Text(
                      place == null
                          ? l.prayerChooseCity
                          : '${place.label(arabic)} · ${l.prayerChangePlace}',
                    ),
                  ),
                  if (!s.enabled) ...[
                    const SizedBox(height: 8),
                    _EnableCard(
                      onEnable: () => enablePrayerTimes(context, ref),
                    ),
                  ],
                  if (place != null) ...[
                    const SizedBox(height: 12),
                    _NextCard(settings: s, place: place, now: _now),
                    const SizedBox(height: 14),
                    _TimesList(settings: s, place: place, now: _now),
                    const SizedBox(height: 12),
                    Text(
                      l.prayerMethodLine(
                        methodName(l, s.effectiveMethod),
                        asrName(l, s.asr),
                      ),
                      style: TextStyle(
                        color: t.muted,
                        fontSize: 12,
                        height: 1.7,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EnableCard extends StatelessWidget {
  const _EnableCard({required this.onEnable});

  final VoidCallback onEnable;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                l.prayerEnableTitle,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(l.prayerEnableBody, style: const TextStyle(height: 1.6)),
            const SizedBox(height: 12),
            FilledButton(
              key: const ValueKey('prayer-enable'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: onEnable,
              child: Text(l.prayerEnable),
            ),
          ],
        ),
      ),
    );
  }
}

class _NextCard extends StatelessWidget {
  const _NextCard({
    required this.settings,
    required this.place,
    required this.now,
  });

  final PrayerSettings settings;
  final PrayerPlace place;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens.colors;
    final next = nextPrayer(place, now, settings);
    final today = placeToday(place, now);
    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: t.control.withValues(alpha: .14),
          border: Border.all(color: t.goldText.withValues(alpha: .3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // A tap on the date opens the Hijri calendar.
            Semantics(
              button: true,
              hint: l.hijriOpenCalendar,
              child: InkWell(
                key: const ValueKey('prayer-hijri-date'),
                borderRadius: BorderRadius.circular(8),
                onTap: () => context.push(hijriCalendarLocation),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          dateLine(l, today, settings.hijriOffset),
                          style: TextStyle(
                            color: t.muted,
                            fontSize: 13,
                            decoration: TextDecoration.underline,
                            decorationColor: t.muted.withValues(alpha: .5),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        Icons.calendar_month_outlined,
                        size: 18,
                        color: t.control,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (next != null) ...[
              const SizedBox(height: 6),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.end,
                spacing: 12,
                children: [
                  Text(
                    prayerName(l, next.prayer),
                    style: TextStyle(
                      fontSize: 34,
                      color: t.goldText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    formatPrayerTime(l, next.at, place),
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                ],
              ),
              Text(
                untilLine(l, next.at.difference(now)),
                style: const TextStyle(fontSize: 15),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TimesList extends ConsumerWidget {
  const _TimesList({
    required this.settings,
    required this.place,
    required this.now,
  });

  final PrayerSettings settings;
  final PrayerPlace place;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = context.tokens.colors;
    final day = computeDay(place, placeToday(place, now), settings);
    final next = nextPrayer(place, now, settings);
    final rows = <Widget>[];
    for (final p in _rows) {
      final current =
          next != null && next.prayer == p && next.at.isAtSameMomentAs(day[p]);
      final obligatory = obligatoryPrayers.contains(p);
      final sound = obligatory
          ? settings.soundOf(p)
          : (settings.shuruqAlert ? AlertSound.tone : null);
      final name = prayerName(l, p);
      final time = formatPrayerTime(l, day[p], place);
      final style = TextStyle(
        fontSize: 16,
        fontWeight: current ? FontWeight.w700 : FontWeight.w400,
        color: current ? t.goldText : (obligatory ? null : t.muted),
      );
      rows.add(
        Container(
          key: ValueKey('prayer-row-${p.name}'),
          color: current ? t.goldText.withValues(alpha: .08) : null,
          constraints: const BoxConstraints(minHeight: 58),
          padding: const EdgeInsetsDirectional.only(start: 16, end: 4),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  label: '$name $time',
                  excludeSemantics: true,
                  child: Row(
                    children: [
                      Expanded(child: Text(name, style: style)),
                      Text(time, style: style),
                    ],
                  ),
                ),
              ),
              IconButton(
                key: ValueKey('prayer-sound-${p.name}'),
                tooltip: sound == null
                    ? l.reminderNone
                    : '${soundName(l, sound)} · $name',
                onPressed: obligatory
                    ? () => showPrayerAlertSheet(context, p)
                    : () => context.push('$prayerTimesLocation/settings'),
                icon: Icon(
                  sound == null
                      ? Icons.notifications_off_outlined
                      : soundIcon(sound),
                  color: current ? t.goldText : t.control,
                ),
              ),
            ],
          ),
        ),
      );
      if (p != _rows.last) rows.add(Divider(height: 1, color: t.border));
    }
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: Column(children: rows),
    );
  }
}
