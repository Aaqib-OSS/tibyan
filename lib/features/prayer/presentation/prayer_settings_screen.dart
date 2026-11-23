import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_toast.dart';
import '../../../core/ui/look_kit.dart';
import '../../../core/ui/responsive.dart';
import '../../../l10n/app_localizations.dart';
import '../../mushaf/presentation/widgets/illuminated_frame.dart'
    show NumberFormatter;
import '../data/adhan_catalog.dart';
import '../data/adhan_downloads.dart';
import '../domain/prayer_settings.dart';
import '../prayer_providers.dart';
import '../services/prayer_desktop.dart';
import '../services/prayer_runtime.dart';
import 'adhan_library_screen.dart' show MuezzinAvatar;
import 'prayer_alert_sheet.dart' show PrayerAdhanRow;
import 'prayer_enable.dart';
import 'prayer_widgets.dart';

/// «إعدادات المواقيت»: the place, the calculation, the adhan, the extra
/// alerts, Ramadan, and on the desktops the tray and login item.
class PrayerSettingsScreen extends ConsumerWidget {
  const PrayerSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = context.tokens.colors;
    final s = ref.watch(prayerSettingsProvider);
    final ctrl = ref.read(prayerSettingsProvider.notifier);
    final adhan = ref.watch(adhanDownloadsProvider);
    final digits = NumberFormatter(Localizations.localeOf(context));
    final arabic = l.localeName == 'ar';
    final m = muezzinOf(s.muezzin);
    final countryMethod = defaultMethodFor(s.place?.country);

    Widget header(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 6),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: TextStyle(
            color: t.goldText,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ),
    );

    Future<void> pickMethod() async {
      final chosen = await showDialog<Object>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text(l.prayerMethod),
          children: [
            _Option(
              label: l.prayerMethodAuto(methodName(l, countryMethod)),
              selected: s.method == null,
              onTap: () => Navigator.pop(context, 'auto'),
            ),
            for (final method in CalcMethod.values)
              _Option(
                label: methodName(l, method),
                selected: s.method == method,
                onTap: () => Navigator.pop(context, method),
              ),
          ],
        ),
      );
      if (chosen == 'auto') {
        await ctrl.update((x) => x.copyWith(clearMethod: true));
      } else if (chosen is CalcMethod) {
        await ctrl.update((x) => x.copyWith(method: chosen));
      }
    }

    Widget minutesRow({
      required Key key,
      required String title,
      required bool on,
      required int minutes,
      required ValueChanged<bool> onToggle,
      required ValueChanged<int> onMinutes,
    }) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          key: key,
          title: Text(title),
          value: on,
          onChanged: onToggle,
        ),
        if (on)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 16, bottom: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final n in const [5, 10, 15, 20, 30])
                  ChoiceChip(
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    label: Text(l.reminderMinutes(digits(n))),
                    selected: minutes == n,
                    onSelected: (_) => onMinutes(n),
                  ),
              ],
            ),
          ),
      ],
    );

    return LookScaffold(
      maxWidth: ContentWidth.text,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            LookTopBar(title: l.prayerSettingsTitle),
            Expanded(
              child: ListenableBuilder(
                listenable: adhan.changes,
                builder: (context, _) => ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  children: [
                    SwitchListTile(
                      key: const ValueKey('prayer-enabled'),
                      title: Text(l.prayerEnabledSwitch),
                      value: s.enabled,
                      onChanged: (v) => v
                          ? enablePrayerTimes(context, ref)
                          : ctrl.update((x) => x.copyWith(enabled: false)),
                    ),
                    header(l.prayerSectionPlace),
                    ListTile(
                      key: const ValueKey('prayer-settings-place'),
                      minTileHeight: 56,
                      leading: const Icon(Icons.place_outlined),
                      title: Text(s.place?.label(arabic) ?? l.prayerChooseCity),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        final place = await choosePlace(context, ref);
                        if (place != null) {
                          await ctrl.update((x) => x.copyWith(place: place));
                        }
                      },
                    ),
                    header(l.prayerSectionCalc),
                    ListTile(
                      key: const ValueKey('prayer-settings-method'),
                      minTileHeight: 56,
                      title: Text(l.prayerMethod),
                      subtitle: Text(
                        s.method == null
                            ? l.prayerMethodAuto(methodName(l, countryMethod))
                            : methodName(l, s.method!),
                      ),
                      onTap: pickMethod,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(l.prayerAsrRule),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: SegmentedButton<AsrRule>(
                        segments: [
                          for (final r in AsrRule.values)
                            ButtonSegment(value: r, label: Text(asrName(l, r))),
                        ],
                        selected: {s.asr},
                        onSelectionChanged: (v) =>
                            ctrl.update((x) => x.copyWith(asr: v.first)),
                      ),
                    ),
                    ListTile(
                      title: Text(l.prayerHijriOffset),
                      subtitle: Text(l.prayerHijriOffsetNote),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: SegmentedButton<int>(
                        segments: [
                          for (final n in const [-2, -1, 0, 1, 2])
                            ButtonSegment(
                              value: n,
                              label: Text(signedMinutes(l, n)),
                              tooltip: l.prayerDays(signedMinutes(l, n)),
                            ),
                        ],
                        selected: {s.hijriOffset},
                        onSelectionChanged: (v) => ctrl.update(
                          (x) => x.copyWith(hijriOffset: v.first),
                        ),
                      ),
                    ),
                    header(l.prayerSectionAdhan),
                    ListTile(
                      key: const ValueKey('prayer-settings-muezzin'),
                      minTileHeight: 60,
                      leading: MuezzinAvatar(muezzin: m, size: 40),
                      title: Text(l.prayerMuezzin),
                      subtitle: Text(
                        l.prayerMuezzinState(
                          m.name(arabic),
                          adhan.isInstalled(m.slug)
                              ? l.adhanDownloaded
                              : l.adhanNotDownloaded,
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/prayer/library'),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Text(l.adhanLength),
                    ),
                    for (final len in AdhanLength.values)
                      // ignore: deprecated_member_use
                      RadioListTile<AdhanLength>(
                        key: ValueKey('prayer-length-${len.name}'),
                        title: Text(
                          len == AdhanLength.full ? l.adhanFull : l.adhanShort,
                        ),
                        value: len,
                        // ignore: deprecated_member_use
                        groupValue: s.length,
                        // ignore: deprecated_member_use
                        onChanged: (v) =>
                            ctrl.update((x) => x.copyWith(length: v)),
                      ),
                    // Android only: Apple plays the notification's own
                    // sound, and the desktops play it from the tray.
                    if (Theme.of(context).platform ==
                        TargetPlatform.android) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: Text(l.adhanInUseTitle),
                      ),
                      for (final u in InUseAdhan.values)
                        // ignore: deprecated_member_use
                        RadioListTile<InUseAdhan>(
                          key: ValueKey('prayer-inuse-${u.name}'),
                          title: Text(switch (u) {
                            InUseAdhan.notify => l.adhanInUseNotify,
                            InUseAdhan.short => l.adhanInUseShort,
                            InUseAdhan.full => l.adhanInUseFull,
                          }),
                          value: u,
                          // ignore: deprecated_member_use
                          groupValue: s.inUse,
                          // ignore: deprecated_member_use
                          onChanged: (v) =>
                              ctrl.update((x) => x.copyWith(inUse: v)),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Text(
                          l.adhanInUseNote,
                          style: TextStyle(
                            color: t.muted,
                            fontSize: 12,
                            height: 1.6,
                          ),
                        ),
                      ),
                    ],
                    if (isApplePlatform)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Text(
                          l.adhanAppleNote,
                          style: TextStyle(
                            color: t.muted,
                            fontSize: 12,
                            height: 1.6,
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Text(l.adhanVolume),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Slider(
                            key: const ValueKey('prayer-volume'),
                            value: s.adhanVolume,
                            divisions: 10,
                            label: '${digits((s.adhanVolume * 100).round())}٪',
                            semanticFormatterCallback: (v) =>
                                '${l.adhanVolume} ${digits((v * 100).round())}٪',
                            onChanged: (v) =>
                                ctrl.update((x) => x.copyWith(adhanVolume: v)),
                          ),
                        ),
                        IconButton(
                          key: const ValueKey('prayer-volume-preview'),
                          tooltip: l.adhanVolumePreview,
                          onPressed: () => PrayerRuntime.instance?.playAdhan(
                            PrayerKind.maghrib,
                            full: false,
                            general: true,
                          ),
                          icon: const Icon(Icons.volume_up_outlined),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Text(
                        isApplePlatform
                            ? l.adhanVolumeAppleNote
                            : l.adhanVolumeNote,
                        style: TextStyle(
                          color: t.muted,
                          fontSize: 12,
                          height: 1.6,
                        ),
                      ),
                    ),
                    SwitchListTile(
                      key: const ValueKey('prayer-dua'),
                      title: Text(l.prayerDuaAfter),
                      subtitle: Text(l.prayerDuaAfterNote),
                      value: s.duaAfter,
                      onChanged: (v) async {
                        await ctrl.update((x) => x.copyWith(duaAfter: v));
                        if (v && !adhan.isInstalled(duaSlug)) {
                          unawaited(
                            adhan.download(duaSlug, label: l.prayerDuaAfter),
                          );
                        }
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: OutlinedButton.icon(
                        key: const ValueKey('prayer-test-adhan'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                        icon: const Icon(Icons.play_circle_outline),
                        label: Text(l.adhanTest),
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.maybeOf(context);
                          final router = GoRouter.of(context);
                          await ref
                              .read(prayerAlarmsProvider)
                              .testAdhan(
                                s.copyWith(custom: const {}),
                                l,
                                showScene: (loc) => unawaited(router.push(loc)),
                                playInApp: () async =>
                                    PrayerRuntime.instance?.playAdhan(
                                      PrayerKind.maghrib,
                                      general: true,
                                    ),
                              );
                          messenger?.showSnackBar(
                            appToast(content: Text(l.adhanTestScheduled)),
                          );
                        },
                      ),
                    ),
                    header(l.prayerPerPrayerTitle),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                      child: Text(
                        l.prayerPerPrayerNote,
                        style: TextStyle(color: t.muted, fontSize: 12),
                      ),
                    ),
                    for (final p in obligatoryPrayers)
                      PrayerAdhanRow(prayer: p),
                    header(l.prayerSectionExtra),
                    SwitchListTile(
                      key: const ValueKey('prayer-shuruq'),
                      title: Text(l.prayerShuruqAlert),
                      value: s.shuruqAlert,
                      onChanged: (v) =>
                          ctrl.update((x) => x.copyWith(shuruqAlert: v)),
                    ),
                    SwitchListTile(
                      key: const ValueKey('prayer-duha'),
                      title: Text(l.prayerDuhaAlert),
                      subtitle: Text(l.prayerDuhaNote),
                      value: s.duhaAlert,
                      onChanged: (v) =>
                          ctrl.update((x) => x.copyWith(duhaAlert: v)),
                    ),
                    header(l.prayerSectionRamadan),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        l.prayerRamadanNote,
                        style: TextStyle(color: t.muted, fontSize: 12),
                      ),
                    ),
                    minutesRow(
                      key: const ValueKey('prayer-suhoor'),
                      title: l.prayerSuhoorAlert,
                      on: s.suhoorAlert,
                      minutes: s.suhoorMinutes,
                      onToggle: (v) =>
                          ctrl.update((x) => x.copyWith(suhoorAlert: v)),
                      onMinutes: (n) =>
                          ctrl.update((x) => x.copyWith(suhoorMinutes: n)),
                    ),
                    minutesRow(
                      key: const ValueKey('prayer-iftar'),
                      title: l.prayerIftarAlert,
                      on: s.iftarAlert,
                      minutes: s.iftarMinutes,
                      onToggle: (v) =>
                          ctrl.update((x) => x.copyWith(iftarAlert: v)),
                      onMinutes: (n) =>
                          ctrl.update((x) => x.copyWith(iftarMinutes: n)),
                    ),
                    if (PrayerDesktop.supported) ...[
                      header(l.prayerSectionDesktop),
                      SwitchListTile(
                        key: const ValueKey('prayer-tray'),
                        title: Text(l.prayerTray),
                        subtitle: Text(l.prayerTrayNote),
                        value: s.tray,
                        onChanged: (v) =>
                            ctrl.update((x) => x.copyWith(tray: v)),
                      ),
                      SwitchListTile(
                        key: const ValueKey('prayer-login'),
                        title: Text(l.prayerLaunchAtLogin),
                        value: s.launchAtLogin,
                        onChanged: (v) async {
                          final ok = await ref
                              .read(prayerDesktopProvider)
                              .setLaunchAtLogin(v);
                          if (ok) {
                            await ctrl.update(
                              (x) => x.copyWith(launchAtLogin: v),
                            );
                          }
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: SimpleDialogOption(
      onPressed: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            if (selected) const Icon(Icons.check),
          ],
        ),
      ),
    ),
  );
}
