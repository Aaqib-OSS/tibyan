import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../data/adhan_catalog.dart';
import '../domain/prayer_calc.dart';
import '../domain/prayer_settings.dart';
import '../prayer_providers.dart';
import '../services/prayer_alarms.dart';
import '../services/prayer_runtime.dart';
import '../../../core/router/app_router.dart' show openOverHome;
import 'adhan_scene.dart';
import 'prayer_times_screen.dart' show prayerTimesLocation;
import 'prayer_widgets.dart';

export 'adhan_scene.dart' show AdhanScene, AdhanBackdrop;

/// The full-screen adhan: the prayer's scene, its name and time, the
/// muezzin, «إيقاف الأذان» and «فتح المواقيت». Opened from the alert (the
/// full adhan starts if its time was within the last minutes and nothing
/// plays yet) or by the app when it starts the adhan itself.
class AdhanScreen extends ConsumerStatefulWidget {
  const AdhanScreen({
    super.key,
    required this.prayer,
    this.at,
    this.test = false,
  });

  /// «جرّب الأذان»: the scene only, no claim of a prayer time.
  final bool test;

  final PrayerKind prayer;
  final DateTime? at;

  /// How late a tap on the alert still starts the full adhan.
  static const startWithin = Duration(minutes: 10);

  @override
  ConsumerState<AdhanScreen> createState() => _AdhanScreenState();
}

class _AdhanScreenState extends ConsumerState<AdhanScreen> {
  @override
  void initState() {
    super.initState();
    final at = widget.at;
    if (at != null) {
      final late = DateTime.now().difference(at);
      final native = ref.read(prayerNativeProvider);
      // Android's adhan service is already playing it.
      if (!Platform.isAndroid &&
          !late.isNegative &&
          late < AdhanScreen.startWithin &&
          !native.playing.value &&
          // Stopped moments ago: reopening the screen does not restart it.
          !native.stoppedRecently &&
          PrayerRuntime.instance?.wasPlayed(at) != true) {
        PrayerRuntime.instance?.markPlayed(at);
        unawaited(PrayerRuntime.instance?.playAdhan(widget.prayer));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = ref.watch(prayerSettingsProvider);
    final native = ref.watch(prayerNativeProvider);
    final scene = AdhanScene.of(widget.prayer);
    final place = s.place;
    final at = widget.at;
    final arabic = l.localeName == 'ar';
    final ink = TextStyle(color: scene.ink);
    return Scaffold(
      backgroundColor: scene.sky3,
      body: Stack(
        fit: StackFit.expand,
        children: [
          ExcludeSemantics(
            child: AdhanBackdrop(
              prayer: widget.prayer,
              hijriDay: hijriOf(
                place == null
                    ? DateTime.now()
                    : placeToday(place, DateTime.now()),
                s.hijriOffset,
              ).hDay,
              night: place == null
                  ? (widget.prayer == PrayerKind.fajr ? .92 : .15)
                  : nightFraction(place, at ?? DateTime.now(), s),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight:
                      MediaQuery.sizeOf(context).height -
                      MediaQuery.paddingOf(context).vertical -
                      64,
                ),
                child: Column(
                  children: [
                    if (place != null)
                      Text(
                        '${place.label(arabic)} · ${dateLine(l, placeToday(place, DateTime.now()), s.hijriOffset)}',
                        textAlign: TextAlign.center,
                        style: ink.copyWith(fontSize: 14),
                      ),
                    const SizedBox(height: 56),
                    if (!widget.test)
                      Text(l.adhanNowLabel, style: ink.copyWith(fontSize: 18)),
                    Semantics(
                      header: true,
                      child: Text(
                        widget.test
                            ? l.adhanTestBody
                            : l.adhanOf(prayerName(l, widget.prayer)),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: scene.title,
                          fontSize: 54,
                          height: 1.2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (!widget.test && at != null && place != null)
                      Text(
                        formatPrayerTime(l, at, place),
                        style: ink.copyWith(
                          fontSize: 40,
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                    Text(
                      l.adhanByMuezzin(muezzinOf(s.muezzin).name(arabic)),
                      style: ink.copyWith(fontSize: 14),
                    ),
                    const SizedBox(height: 240),
                    ValueListenableBuilder<bool>(
                      valueListenable: native.playing,
                      builder: (context, playing, _) => FilledButton(
                        key: const ValueKey('adhan-stop'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                          backgroundColor: scene.accent,
                          foregroundColor: const Color(0xFF17130C),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        // Always enabled: over the lock screen the app may
                        // not know yet that the service plays.
                        onPressed: () async {
                          await native.stop();
                          await native.leaveLockScreen();
                          if (!context.mounted) return;
                          if (context.canPop()) {
                            context.pop();
                          } else {
                            await openOverHome(
                              GoRouter.of(context),
                              prayerTimesLocation,
                            );
                          }
                        },
                        child: Text(
                          l.adhanStop,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      key: const ValueKey('adhan-open-times'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        foregroundColor: const Color(0xFFF6F1E8),
                        backgroundColor: Colors.black.withValues(alpha: .18),
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: .4),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      onPressed: () async {
                        await native.leaveLockScreen(open: true);
                        if (!context.mounted) return;
                        // Over home: back returns to Tibyan, not out of it.
                        await openOverHome(
                          GoRouter.of(context),
                          prayerTimesLocation,
                        );
                      },
                      child: Text(l.adhanOpenTimes),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
