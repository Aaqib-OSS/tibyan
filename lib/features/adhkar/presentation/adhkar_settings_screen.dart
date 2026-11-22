import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/look_kit.dart';
import '../../../core/ui/responsive.dart';
import '../../../l10n/app_localizations.dart';
import '../../audio/audio_downloads_screen.dart' show confirmDeleteDownload;
import '../../khatma/khatma_providers.dart' show reminderSchedulerProvider;
import '../../mushaf/presentation/widgets/illuminated_frame.dart'
    show NumberFormatter;
import '../../prayer/data/adhan_catalog.dart';
import '../../prayer/data/adhan_downloads.dart';
import '../adhkar_providers.dart';
import '../domain/adhkar_settings.dart';

/// Where the salawat reminder can sound: Android (the adhan service) and
/// the Apple platforms (the notification's own sound).
bool get salawatSupported =>
    !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

/// «إعدادات الأذكار»: the morning and evening reminders and the
/// «الصلاة على النبي» reminder, all off until turned on.
class AdhkarSettingsScreen extends ConsumerWidget {
  const AdhkarSettingsScreen({super.key, this.salawat});

  /// Shows the salawat section regardless of the platform (tests).
  final bool? salawat;

  String _time(BuildContext context, int minute) =>
      TimeOfDay(hour: minute ~/ 60, minute: minute % 60).format(context);

  Future<int?> _pick(BuildContext context, int minute) async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minute ~/ 60, minute: minute % 60),
    );
    return t == null ? null : t.hour * 60 + t.minute;
  }

  Future<bool> _permit(WidgetRef ref) =>
      ref.read(reminderSchedulerProvider).requestPermission();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = context.tokens.colors;
    final s = ref.watch(adhkarSettingsProvider);
    final ctrl = ref.read(adhkarSettingsProvider.notifier);
    final adhan = ref.watch(adhanDownloadsProvider);
    final digits = NumberFormatter(Locale(l.localeName));
    final showSalawat = salawat ?? salawatSupported;

    Widget reminder({
      required String key,
      required String title,
      required bool on,
      required int at,
      required AdhkarSettings Function(bool) toggle,
      required AdhkarSettings Function(int) setAt,
    }) => Card(
      child: Column(
        children: [
          SwitchListTile(
            key: ValueKey('adhkar-$key'),
            title: Text(title),
            value: on,
            onChanged: (v) async {
              if (v && !await _permit(ref)) return;
              await ctrl.update((_) => toggle(v));
            },
          ),
          if (on)
            ListTile(
              key: ValueKey('adhkar-$key-time'),
              minTileHeight: 48,
              leading: const Icon(Icons.schedule),
              title: Text(l.adhkarReminderTime(_time(context, at))),
              onTap: () async {
                final m = await _pick(context, at);
                if (m != null) await ctrl.update((_) => setAt(m));
              },
            ),
        ],
      ),
    );

    return LookScaffold(
      maxWidth: ContentWidth.text,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            LookTopBar(title: l.adhkarSettingsTitle),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: [
                  reminder(
                    key: 'morning',
                    title: l.adhkarMorningReminder,
                    on: s.morningOn,
                    at: s.morningAt,
                    toggle: (v) => s.copyWith(morningOn: v),
                    setAt: (m) => s.copyWith(morningAt: m),
                  ),
                  reminder(
                    key: 'evening',
                    title: l.adhkarEveningReminder,
                    on: s.eveningOn,
                    at: s.eveningAt,
                    toggle: (v) => s.copyWith(eveningOn: v),
                    setAt: (m) => s.copyWith(eveningAt: m),
                  ),
                  const SizedBox(height: 12),
                  if (!showSalawat)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        l.salawatUnsupported,
                        style: TextStyle(color: t.muted, height: 1.6),
                      ),
                    )
                  else
                    ListenableBuilder(
                      listenable: adhan.changes,
                      builder: (context, _) {
                        final st = adhan.stateOf(salawatSlug);
                        return Card(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SwitchListTile(
                                key: const ValueKey('adhkar-salawat'),
                                title: Text(l.salawatTitle),
                                subtitle: Text(l.salawatNote),
                                value: s.salawatOn,
                                onChanged: (v) async {
                                  if (v && !await _permit(ref)) return;
                                  if (v && !adhan.isInstalled(salawatSlug)) {
                                    await adhan.download(
                                      salawatSlug,
                                      label: l.salawatAudioName,
                                    );
                                  }
                                  await ctrl.update(
                                    (x) => x.copyWith(salawatOn: v),
                                  );
                                },
                              ),
                              _AudioRow(
                                state: st,
                                onDelete: () async {
                                  final ok = await confirmDeleteDownload(
                                    context,
                                    title: l.adhanDeleteTitle(
                                      l.salawatAudioName,
                                    ),
                                    body: l.adhanDeleteBody,
                                  );
                                  if (ok) await adhan.delete(salawatSlug);
                                },
                                onDownload: () => adhan.download(
                                  salawatSlug,
                                  label: l.salawatAudioName,
                                ),
                              ),
                              if (s.salawatOn) ...[
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    8,
                                    16,
                                    0,
                                  ),
                                  child: Text(l.salawatEvery),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  child: Wrap(
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      IconButton(
                                        key: const ValueKey('salawat-less'),
                                        tooltip: l.salawatLess,
                                        onPressed: s.salawatEvery > 1
                                            ? () => ctrl.update(
                                                (x) => x.copyWith(
                                                  salawatEvery:
                                                      x.salawatEvery - 1,
                                                ),
                                              )
                                            : null,
                                        icon: const Icon(
                                          Icons.remove_circle_outline,
                                        ),
                                      ),
                                      Text(
                                        digits(s.salawatEvery),
                                        key: const ValueKey('salawat-every'),
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      IconButton(
                                        key: const ValueKey('salawat-more'),
                                        tooltip: l.salawatMore,
                                        onPressed: () => ctrl.update(
                                          (x) => x.copyWith(
                                            salawatEvery: x.salawatEvery + 1,
                                          ),
                                        ),
                                        icon: const Icon(
                                          Icons.add_circle_outline,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      SegmentedButton<RepeatUnit>(
                                        key: const ValueKey('salawat-unit'),
                                        segments: [
                                          ButtonSegment(
                                            value: RepeatUnit.minutes,
                                            label: Text(l.salawatMinutes),
                                          ),
                                          ButtonSegment(
                                            value: RepeatUnit.hours,
                                            label: Text(l.salawatHours),
                                          ),
                                        ],
                                        selected: {s.salawatUnit},
                                        onSelectionChanged: (v) => ctrl.update(
                                          (x) =>
                                              x.copyWith(salawatUnit: v.first),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (s.salawatUnit == RepeatUnit.minutes &&
                                    s.salawatEvery < AdhkarSettings.minMinutes)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    child: Text(
                                      l.salawatMinNote(
                                        digits(AdhkarSettings.minMinutes),
                                      ),
                                      style: TextStyle(
                                        color: t.muted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                SwitchListTile(
                                  key: const ValueKey('salawat-window'),
                                  title: Text(l.salawatWindow),
                                  value: s.windowOn,
                                  onChanged: (v) => ctrl.update(
                                    (x) => x.copyWith(windowOn: v),
                                  ),
                                ),
                                if (s.windowOn) ...[
                                  ListTile(
                                    key: const ValueKey('salawat-from'),
                                    minTileHeight: 48,
                                    title: Text(
                                      l.salawatFrom(
                                        _time(context, s.windowFrom),
                                      ),
                                    ),
                                    onTap: () async {
                                      final m = await _pick(
                                        context,
                                        s.windowFrom,
                                      );
                                      if (m != null) {
                                        await ctrl.update(
                                          (x) => x.copyWith(windowFrom: m),
                                        );
                                      }
                                    },
                                  ),
                                  ListTile(
                                    key: const ValueKey('salawat-to'),
                                    minTileHeight: 48,
                                    title: Text(
                                      l.salawatTo(_time(context, s.windowTo)),
                                    ),
                                    onTap: () async {
                                      final m = await _pick(
                                        context,
                                        s.windowTo,
                                      );
                                      if (m != null) {
                                        await ctrl.update(
                                          (x) => x.copyWith(windowTo: m),
                                        );
                                      }
                                    },
                                  ),
                                ],
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    4,
                                    16,
                                    12,
                                  ),
                                  child: Text(
                                    l.salawatRulesNote,
                                    style: TextStyle(
                                      color: t.muted,
                                      fontSize: 12,
                                      height: 1.6,
                                    ),
                                  ),
                                ),
                              ],
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

class _AudioRow extends StatelessWidget {
  const _AudioRow({
    required this.state,
    required this.onDelete,
    required this.onDownload,
  });

  final AdhanState state;
  final VoidCallback onDelete;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final digits = NumberFormatter(Locale(l.localeName));
    final (status, action) = switch (state.phase) {
      AdhanPhase.installed => (
        l.adhanDownloaded,
        IconButton(
          key: const ValueKey('salawat-delete'),
          tooltip: l.adhanDelete(l.salawatAudioName),
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline),
        ),
      ),
      AdhanPhase.downloading || AdhanPhase.paused => (
        l.adhanDownloading('${digits((state.progress * 100).round())}٪'),
        null,
      ),
      AdhanPhase.failed => (
        l.adhanFailedState,
        IconButton(
          tooltip: l.downloadRetry,
          onPressed: onDownload,
          icon: const Icon(Icons.refresh),
        ),
      ),
      AdhanPhase.idle => (
        l.adhanNotDownloaded,
        IconButton(
          key: const ValueKey('salawat-download'),
          tooltip: l.adhanDownload(l.salawatAudioName),
          onPressed: onDownload,
          icon: const Icon(Icons.download),
        ),
      ),
    };
    return ListTile(
      minTileHeight: 56,
      leading: const Icon(Icons.graphic_eq),
      title: Text(l.salawatAudioName),
      subtitle: Text('$status · ${l.adhanLicense(adhanLicense)}'),
      trailing: action,
    );
  }
}
