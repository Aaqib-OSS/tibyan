import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_toast.dart';
import '../../../l10n/app_localizations.dart';
import '../../mushaf/presentation/widgets/illuminated_frame.dart'
    show NumberFormatter;
import '../data/adhan_catalog.dart';
import '../data/adhan_downloads.dart';
import '../domain/prayer_calc.dart';
import '../domain/prayer_settings.dart';
import '../prayer_providers.dart';
import '../services/prayer_alarms.dart';
import '../services/prayer_runtime.dart';
import 'prayer_widgets.dart';

/// One prayer's alert: its sound, the muezzin, a reminder before it, and
/// a hand adjustment of its time.
Future<void> showPrayerAlertSheet(BuildContext context, PrayerKind prayer) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => PrayerAlertSheet(prayer: prayer),
    );

class PrayerAlertSheet extends ConsumerWidget {
  const PrayerAlertSheet({super.key, required this.prayer});

  final PrayerKind prayer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = context.tokens.colors;
    final s = ref.watch(prayerSettingsProvider);
    final ctrl = ref.read(prayerSettingsProvider.notifier);
    final adhan = ref.watch(adhanDownloadsProvider);
    final digits = NumberFormatter(Localizations.localeOf(context));
    final place = s.place;
    final sound = s.soundOf(prayer);
    final reminder = s.reminderOf(prayer);
    final offset = s.offsetOf(prayer);
    final name = prayerName(l, prayer);
    final label = TextStyle(color: t.muted, fontSize: 13);
    return ListenableBuilder(
      listenable: adhan.changes,
      builder: (context, _) {
        final own = s.customOf(prayer);
        final general = muezzinOf(s.muezzin);
        // The muezzin this prayer asks for (its own, or the general one).
        final m = muezzinOf(own?.muezzin ?? s.muezzin);
        String stateText(String slug) {
          final state = adhan.stateOf(slug);
          return switch (state.phase) {
            AdhanPhase.installed => l.adhanDownloaded,
            AdhanPhase.downloading => l.adhanDownloading(
              '${digits((state.progress * 100).round())}٪',
            ),
            AdhanPhase.paused => l.adhanPausedState,
            AdhanPhase.failed => l.adhanFailedState,
            AdhanPhase.idle => l.adhanNotDownloaded,
          };
        }

        final installed = adhan.isInstalled(m.slug);
        final android = Theme.of(context).platform == TargetPlatform.android;
        void setOwn(PrayerAdhan c) => ctrl.setCustom(prayer, c);
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        name,
                        style: TextStyle(
                          fontSize: 28,
                          color: t.goldText,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  if (place != null)
                    Text(
                      formatPrayerTime(
                        l,
                        computeDay(
                          place,
                          placeToday(place, DateTime.now()),
                          s,
                        )[prayer],
                        place,
                      ),
                      style: TextStyle(color: t.muted, fontSize: 15),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  ChoiceChip(
                    key: const ValueKey('prayer-mode-general'),
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    label: Text(l.prayerFollowGeneral),
                    selected: own == null,
                    onSelected: (_) => ctrl.setCustom(prayer, null),
                  ),
                  ChoiceChip(
                    key: const ValueKey('prayer-mode-custom'),
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    label: Text(l.prayerCustomSetup),
                    selected: own != null,
                    onSelected: (_) {
                      if (own == null) setOwn(const PrayerAdhan());
                    },
                  ),
                ],
              ),
              if (own != null) ...[
                const SizedBox(height: 12),
                Text(l.prayerSoundAtTime, style: label),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (final option in AlertSound.values) ...[
                      if (option != AlertSound.values.first)
                        const SizedBox(width: 8),
                      Expanded(
                        child: _SoundChoice(
                          key: ValueKey('prayer-sound-choice-${option.name}'),
                          sound: option,
                          selected: option == sound,
                          onTap: () => ctrl.setSound(prayer, option),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
              if (own != null && own.sound == AlertSound.adhan) ...[
                const SizedBox(height: 14),
                Text(l.prayerMuezzin, style: label),
                const SizedBox(height: 4),
                DropdownButtonFormField<String?>(
                  key: const ValueKey('prayer-own-muezzin'),
                  initialValue: own.muezzin,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                  ),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(
                        '${l.prayerSameAsGeneral} (${general.name(l.localeName == 'ar')})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    for (final x in muezzins)
                      DropdownMenuItem<String?>(
                        value: x.slug,
                        child: Text(
                          x.name(l.localeName == 'ar'),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => setOwn(own.copyWith(muezzin: () => v)),
                ),
                if (!installed) ...[
                  const SizedBox(height: 8),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      l.prayerMuezzinState(
                        m.name(l.localeName == 'ar'),
                        stateText(m.slug),
                      ),
                      style: label,
                    ),
                  ),
                  if (adhan.stateOf(m.slug).phase != AdhanPhase.downloading)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: FilledButton.tonalIcon(
                        key: const ValueKey('prayer-own-download'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                        icon: const Icon(Icons.download_outlined),
                        label: Text(
                          l.prayerDownloadMuezzin(m.name(l.localeName == 'ar')),
                        ),
                        onPressed: () => adhan.download(
                          m.slug,
                          label: m.name(l.localeName == 'ar'),
                        ),
                      ),
                    ),
                  const SizedBox(height: 6),
                  Text(l.prayerMuezzinFallback, style: label),
                ],
                const SizedBox(height: 14),
                Text(l.adhanLength, style: label),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final len in <AdhanLength?>[
                      null,
                      ...AdhanLength.values,
                    ])
                      ChoiceChip(
                        key: ValueKey(
                          'prayer-own-length-${len?.name ?? 'general'}',
                        ),
                        materialTapTargetSize: MaterialTapTargetSize.padded,
                        label: Text(switch (len) {
                          null => l.prayerSameAsGeneral,
                          AdhanLength.full => l.adhanFull,
                          AdhanLength.short => l.adhanShort,
                        }),
                        selected: own.length == len,
                        onSelected: (_) =>
                            setOwn(own.copyWith(length: () => len)),
                      ),
                  ],
                ),
                // Android only: Apple and the desktops use one level.
                if (android) ...[
                  const SizedBox(height: 14),
                  Text(l.prayerOwnVolume, style: label),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    children: [
                      ChoiceChip(
                        key: const ValueKey('prayer-own-volume-general'),
                        materialTapTargetSize: MaterialTapTargetSize.padded,
                        label: Text(l.prayerSameAsGeneral),
                        selected: own.volume == null,
                        onSelected: (_) =>
                            setOwn(own.copyWith(volume: () => null)),
                      ),
                      ChoiceChip(
                        key: const ValueKey('prayer-own-volume-custom'),
                        materialTapTargetSize: MaterialTapTargetSize.padded,
                        label: Text(l.prayerCustomSetup),
                        selected: own.volume != null,
                        onSelected: (_) =>
                            setOwn(own.copyWith(volume: () => s.adhanVolume)),
                      ),
                    ],
                  ),
                  if (own.volume case final v?)
                    Slider(
                      key: const ValueKey('prayer-own-volume'),
                      value: v,
                      label: '${digits((v * 100).round())}٪',
                      semanticFormatterCallback: (x) =>
                          '${l.prayerOwnVolume} ${digits((x * 100).round())}٪',
                      onChanged: (x) => setOwn(own.copyWith(volume: () => x)),
                    ),
                ],
              ],
              if (own == null && !installed) ...[
                const SizedBox(height: 6),
                Text(l.adhanUntilDownloaded, style: label),
              ],
              if (own == null) ...[
                const SizedBox(height: 14),
                Material(
                  color: t.control.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(16),
                  child: ListTile(
                    key: const ValueKey('prayer-muezzin'),
                    minTileHeight: 60,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    title: Text(l.prayerMuezzin),
                    subtitle: Text(
                      l.prayerMuezzinState(
                        general.name(l.localeName == 'ar'),
                        stateText(general.slug),
                      ),
                      style: TextStyle(color: t.control),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/prayer/library'),
                  ),
                ),
              ],
              if (sound == AlertSound.adhan) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  key: const ValueKey('prayer-own-try'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  icon: const Icon(Icons.play_circle_outline),
                  label: Text(l.prayerTryOwn),
                  onPressed: () async {
                    // The sheet closes first, so the toast shows on the
                    // screen beneath it, like «جرّب الأذان» in the settings.
                    final messenger = ScaffoldMessenger.maybeOf(context);
                    final router = GoRouter.maybeOf(context);
                    final alarms = ref.read(prayerAlarmsProvider);
                    Navigator.of(context).pop();
                    await alarms.testAdhan(
                      s,
                      l,
                      prayer: prayer,
                      showScene: router == null
                          ? null
                          : (loc) => unawaited(router.push(loc)),
                      playInApp: () async =>
                          PrayerRuntime.instance?.playAdhan(prayer),
                    );
                    messenger?.showSnackBar(
                      appToast(content: Text(l.adhanTestScheduled)),
                    );
                  },
                ),
              ],
              const SizedBox(height: 16),
              Text(l.prayerReminderBefore, style: label),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final n in PrayerSettings.reminderChoices)
                    ChoiceChip(
                      key: ValueKey('prayer-reminder-$n'),
                      materialTapTargetSize: MaterialTapTargetSize.padded,
                      label: Text(
                        n == 0 ? l.reminderNone : l.reminderMinutes(digits(n)),
                      ),
                      selected: reminder == n,
                      onSelected: (_) => ctrl.setReminder(prayer, n),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.prayerOffset,
                          style: const TextStyle(fontSize: 15),
                        ),
                        Text(l.prayerOffsetNote, style: label),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    key: const ValueKey('prayer-offset-less'),
                    tooltip: l.minuteLess,
                    onPressed: offset <= -PrayerSettings.maxOffset
                        ? null
                        : () => ctrl.setOffset(prayer, offset - 1),
                    icon: const Icon(Icons.remove),
                  ),
                  SizedBox(
                    width: 64,
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        l.prayerOffsetValue(signedMinutes(l, offset)),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 15),
                      ),
                    ),
                  ),
                  IconButton.filledTonal(
                    key: const ValueKey('prayer-offset-more'),
                    tooltip: l.minuteMore,
                    onPressed: offset >= PrayerSettings.maxOffset
                        ? null
                        : () => ctrl.setOffset(prayer, offset + 1),
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              OutlinedButton(
                key: const ValueKey('prayer-apply-all'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: () async {
                  await ctrl.applyToAll(prayer);
                  if (context.mounted) {
                    ScaffoldMessenger.maybeOf(
                      context,
                    )?.showSnackBar(appToast(content: Text(l.prayerApplied)));
                  }
                },
                child: Text(l.prayerApplyAll),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SoundChoice extends StatelessWidget {
  const _SoundChoice({
    super.key,
    required this.sound,
    required this.selected,
    required this.onTap,
  });

  final AlertSound sound;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens.colors;
    final color = selected ? t.goldText : null;
    return Semantics(
      selected: selected,
      button: true,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 64),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          side: BorderSide(
            color: selected ? t.goldText : t.border,
            width: selected ? 2 : 1,
          ),
          backgroundColor: selected ? t.goldText.withValues(alpha: .1) : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        onPressed: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(soundIcon(sound), color: color, size: 20),
            const SizedBox(height: 4),
            Text(
              soundName(l, sound),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: color,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A prayer's row in «أذان كل صلاة»: its name and its adhan summary;
/// a tap opens its sheet.
class PrayerAdhanRow extends ConsumerWidget {
  const PrayerAdhanRow({super.key, required this.prayer});

  final PrayerKind prayer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final s = ref.watch(prayerSettingsProvider);
    final name = prayerName(l, prayer);
    final summary = prayerAdhanSummary(l, s.customOf(prayer));
    return Semantics(
      button: true,
      label: l.prayerAdhanSummaryLabel(name, summary),
      excludeSemantics: true,
      child: ListTile(
        key: ValueKey('prayer-adhan-row-${prayer.name}'),
        minTileHeight: 56,
        leading: Icon(soundIcon(s.soundOf(prayer))),
        title: Text(name),
        subtitle: Text(summary),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => showPrayerAlertSheet(context, prayer),
      ),
    );
  }
}
