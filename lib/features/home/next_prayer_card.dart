import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/reveal.dart';
import '../../l10n/app_localizations.dart';
import '../mushaf/presentation/widgets/illuminated_frame.dart'
    show NumberFormatter;
import '../prayer/domain/prayer_settings.dart';
import '../prayer/domain/prayer_window.dart';
import '../prayer/presentation/prayer_enable.dart' show choosePlace;
import '../prayer/presentation/prayer_times_screen.dart'
    show prayerTimesLocation;
import '../prayer/prayer_providers.dart';
import '../prayer/services/prayer_alarms.dart'
    show formatPrayerTime, prayerName;

/// The colours of the sky before [p] (top, middle, horizon).
List<Color> skyColors(PrayerKind p) => switch (p) {
  PrayerKind.fajr => const [
    Color(0xFF0D1A4A),
    Color(0xFF4B3A7D),
    Color(0xFFF0A088),
  ],
  PrayerKind.dhuhr => const [
    Color(0xFF1F6FB8),
    Color(0xFF4FA3E0),
    Color(0xFFBFE3FA),
  ],
  PrayerKind.asr => const [
    Color(0xFF2F74A6),
    Color(0xFFE0A856),
    Color(0xFFF7D79A),
  ],
  PrayerKind.maghrib => const [
    Color(0xFF2B1F55),
    Color(0xFFC2456A),
    Color(0xFFF59A4A),
  ],
  _ => const [Color(0xFF060B22), Color(0xFF0F1E4A), Color(0xFF22356E)],
};

const _shadow = [
  Shadow(color: Color(0x59000000), blurRadius: 14, offset: Offset(0, 2)),
];

/// «الصلاة القادمة» on the home: the whole card is the sky before the next
/// prayer, with a live countdown to its adhan. Without a place it is a calm
/// card that asks for the city. Only this card rebuilds each second.
class NextPrayerCard extends ConsumerStatefulWidget {
  const NextPrayerCard({super.key, this.clock});

  /// The time source, for tests.
  final DateTime Function()? clock;

  @override
  ConsumerState<NextPrayerCard> createState() => _NextPrayerCardState();
}

class _NextPrayerCardState extends ConsumerState<NextPrayerCard> {
  Timer? _timer;
  DateTime _now() => (widget.clock ?? DateTime.now)();

  void _ensureTimer(bool on) {
    if (on && _timer == null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!on) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = ref.watch(prayerSettingsProvider);
    final place = s.place;
    _ensureTimer(place != null);
    if (place == null) return _SetupCard(l: l);
    final now = _now();
    final w = prayerWindow(place, now, s);
    final digits = NumberFormatter(Localizations.localeOf(context));
    final arabic = l.localeName == 'ar';
    final name = prayerName(l, w.next);
    final adhan = formatPrayerTime(l, w.nextAt, place);
    final left = w.nextAt.difference(now);
    final count = formatCountdown(left, digits.call);
    const white = TextStyle(color: Colors.white, shadows: _shadow);
    return Semantics(
      button: true,
      hint: l.nextPrayerOpenHint,
      child: ClipRRect(
        key: const ValueKey('next-prayer-card'),
        borderRadius: BorderRadius.circular(20),
        child: _Sky(
          prayer: w.next,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => context.push(prayerTimesLocation),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                child: DefaultTextStyle.merge(
                  style: white,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        spacing: 12,
                        children: [
                          Text(
                            l.nextPrayerLabel,
                            style: const TextStyle(fontSize: 14),
                          ),
                          Text(
                            l.nextPrayerAdhanAt(adhan),
                            style: const TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        name,
                        style: TextStyle(
                          fontFamily: arabic ? 'ArefRuqaa' : null,
                          fontSize: 40,
                          height: 1.25,
                          fontWeight: arabic ? null : FontWeight.w700,
                        ),
                      ),
                      Semantics(
                        liveRegion: false,
                        label: '$name ${l.nextPrayerAdhanAt(adhan)}',
                        excludeSemantics: true,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            count,
                            key: const ValueKey('next-prayer-count'),
                            textDirection: TextDirection.ltr,
                            style: const TextStyle(
                              fontSize: 38,
                              fontWeight: FontWeight.w800,
                              height: 1.1,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: windowProgress(w, now),
                          minHeight: 6,
                          color: Colors.white,
                          backgroundColor: Colors.white.withValues(alpha: .25),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        spacing: 12,
                        children: [
                          Text(
                            '${prayerName(l, w.previous)} ${formatPrayerTime(l, w.previousAt, place)}',
                            style: const TextStyle(fontSize: 13),
                          ),
                          Text(
                            '$name $adhan',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// No place yet: a quiet dusk card that opens the city choice.
class _SetupCard extends ConsumerWidget {
  const _SetupCard({required this.l});
  final AppLocalizations l;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Semantics(
      button: true,
      child: ClipRRect(
        key: const ValueKey('next-prayer-setup'),
        borderRadius: BorderRadius.circular(20),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF1B2A55), Color(0xFF3A3F72)],
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () async {
                final place = await choosePlace(context, ref);
                if (place == null) return;
                await ref
                    .read(prayerSettingsProvider.notifier)
                    .update((s) => s.copyWith(place: place));
              },
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    const Icon(
                      Icons.place_outlined,
                      color: Colors.white,
                      size: 28,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l.nextPrayerLabel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            l.nextPrayerSetupBody,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: .85),
                              fontSize: 13,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            l.prayerChooseCity,
                            style: const TextStyle(
                              color: Color(0xFFFFD57A),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
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
}

/// The sky, the sun or moon and (at night) the stars, behind [child].
/// Stars twinkle on their own ticker, repainting only the sky.
class _Sky extends StatefulWidget {
  const _Sky({required this.prayer, required this.child});
  final PrayerKind prayer;
  final Widget child;

  @override
  State<_Sky> createState() => _SkyState();
}

class _SkyState extends State<_Sky> with SingleTickerProviderStateMixin {
  late final _twinkle = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 44),
  );

  bool get _night =>
      widget.prayer == PrayerKind.isha || widget.prayer == PrayerKind.fajr;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_Sky old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final run = _night && !reduceMotion(context);
    if (run && !_twinkle.isAnimating) {
      _twinkle.repeat();
    } else if (!run && _twinkle.isAnimating) {
      _twinkle.stop();
    }
  }

  @override
  void dispose() {
    _twinkle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: SkyPainter(
        prayer: widget.prayer,
        twinkle: _twinkle,
        still: reduceMotion(context),
        rtl: Directionality.of(context) == TextDirection.rtl,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 230),
        child: widget.child,
      ),
    );
  }
}

class _Star {
  const _Star(this.x, this.y, this.r, this.phase);
  final double x, y, r, phase;
}

final _stars = () {
  final rnd = math.Random(1441);
  return List.generate(
    60,
    (_) => _Star(
      rnd.nextDouble(),
      rnd.nextDouble() * .7,
      rnd.nextDouble() * 1.3 + .3,
      rnd.nextDouble() * 6,
    ),
  );
}();

/// Paints the sky of the approved «السماء الحية» mockup.
class SkyPainter extends CustomPainter {
  SkyPainter({
    required this.prayer,
    required this.twinkle,
    required this.still,
    required this.rtl,
  }) : super(repaint: twinkle);

  final PrayerKind prayer;
  final Animation<double> twinkle;
  final bool still;
  final bool rtl;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final c = skyColors(prayer);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: c,
          stops: const [0, .62, 1],
        ).createShader(rect),
    );
    final w = size.width, h = size.height;
    final night = prayer == PrayerKind.isha || prayer == PrayerKind.fajr;
    if (night) {
      // The mockup's sin(t / 700 ms), over a 44 s loop.
      final t = twinkle.value * 44000 / 700;
      final star = Paint();
      for (final s in _stars) {
        var a = still ? .7 : .35 + .45 * math.sin(t + s.phase);
        if (prayer == PrayerKind.fajr) a *= .5;
        star.color = Colors.white.withValues(alpha: a.clamp(0, 1));
        canvas.drawCircle(Offset(s.x * w, s.y * h), s.r, star);
      }
    }
    final pos = switch (prayer) {
      PrayerKind.fajr => const Offset(.18, .98),
      PrayerKind.dhuhr => const Offset(.22, .2),
      PrayerKind.asr => const Offset(.16, .42),
      PrayerKind.maghrib => const Offset(.2, .9),
      _ => const Offset(.2, .24),
    };
    // The sky body sits opposite the text's start.
    final x = (rtl ? pos.dx : 1 - pos.dx) * w;
    final center = Offset(x, pos.dy * h);
    if (prayer == PrayerKind.isha) {
      const moon = Color(0xFFF6EDD2);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            colors: [moon.withValues(alpha: .35), moon.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: center, radius: 70)),
      );
      canvas.drawCircle(center, 22, Paint()..color = moon);
      final crater = Paint()..color = const Color(0xFFE3D6B0);
      canvas.drawCircle(center + const Offset(-6, -5), 4, crater);
      canvas.drawCircle(center + const Offset(7, 6), 3, crater);
    } else {
      final sun = switch (prayer) {
        PrayerKind.maghrib => const Color(0xFFFFA05A),
        PrayerKind.fajr => const Color(0xFFFFB48C),
        _ => const Color(0xFFFFDE8C),
      };
      final r = switch (prayer) {
        PrayerKind.dhuhr => 26.0,
        PrayerKind.asr => 24.0,
        _ => 30.0,
      };
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            colors: [sun.withValues(alpha: .55), sun.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: center, radius: r * 4)),
      );
      canvas.drawCircle(center, r, Paint()..color = sun);
    }
  }

  @override
  bool shouldRepaint(SkyPainter old) =>
      old.prayer != prayer || old.still != still || old.rtl != rtl;
}
