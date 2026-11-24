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
    final small = TextStyle(
      fontSize: 12,
      color: Colors.white.withValues(alpha: .92),
    );
    return Semantics(
      button: true,
      hint: l.nextPrayerOpenHint,
      child: ClipRRect(
        key: const ValueKey('next-prayer-card'),
        borderRadius: BorderRadius.circular(18),
        child: _Sky(
          prayer: w.next,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => context.push(prayerTimesLocation),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                child: DefaultTextStyle.merge(
                  style: white,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          ExcludeSemantics(
                            child: SizedBox.square(
                              dimension: 52,
                              child: CustomPaint(
                                painter: PrayerIconPainter(w.next),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${l.nextPrayerLabel} · ${l.nextPrayerAdhanAt(adhan)}',
                                  style: small,
                                ),
                                Text(
                                  name,
                                  style: TextStyle(
                                    fontFamily: arabic ? 'ArefRuqaa' : null,
                                    fontSize: 26,
                                    height: 1.25,
                                    fontWeight: arabic ? null : FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Semantics(
                              label: '$name ${l.nextPrayerAdhanAt(adhan)}',
                              excludeSemantics: true,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  count,
                                  key: const ValueKey('next-prayer-count'),
                                  textDirection: TextDirection.ltr,
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800,
                                    height: 1.1,
                                    fontFeatures: [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: windowProgress(w, now),
                          minHeight: 4,
                          color: Colors.white,
                          backgroundColor: Colors.white.withValues(alpha: .25),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        spacing: 12,
                        children: [
                          Text(
                            '${prayerName(l, w.previous)} ${formatPrayerTime(l, w.previousAt, place)}',
                            style: small,
                          ),
                          Text('$name $adhan', style: small),
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
      child: widget.child,
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

/// The prayer's icon, drawn on the mockup's 64×64 grid.
class PrayerIconPainter extends CustomPainter {
  PrayerIconPainter(this.prayer);
  final PrayerKind prayer;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 64);
    void disc(double cx, double cy, double r, Color c) =>
        canvas.drawCircle(Offset(cx, cy), r, Paint()..color = c);
    void line(double x1, double y1, double x2, double y2, Color c, double sw) =>
        canvas.drawLine(
          Offset(x1, y1),
          Offset(x2, y2),
          Paint()
            ..color = c
            ..strokeWidth = sw
            ..strokeCap = StrokeCap.round,
        );
    void rays(double cy, double r, Color c) {
      for (var i = 0; i < 8; i++) {
        final a = i * math.pi / 4;
        line(
          32 + math.cos(a) * (r + 4),
          cy + math.sin(a) * (r + 4),
          32 + math.cos(a) * (r + 10),
          cy + math.sin(a) * (r + 10),
          c,
          3,
        );
      }
    }

    const white = Colors.white;
    switch (prayer) {
      case PrayerKind.fajr:
        const c = Color(0xFFFFC18F);
        canvas.save();
        canvas.clipRect(const Rect.fromLTWH(0, 0, 64, 41));
        disc(32, 42, 13, c);
        rays(42, 13, c);
        canvas.restore();
        line(4, 42, 60, 42, white, 2.5);
        disc(52, 11, 1.8, white);
        disc(12, 16, 1.3, white.withValues(alpha: .8));
      case PrayerKind.dhuhr:
        const c = Color(0xFFFFD57A);
        disc(32, 32, 13, c);
        rays(32, 13, c);
      case PrayerKind.asr:
        const c = Color(0xFFFFCF6E);
        disc(32, 28, 12, c);
        rays(28, 12, c);
        line(6, 56, 58, 56, white.withValues(alpha: .75), 2.5);
      case PrayerKind.maghrib:
        canvas.save();
        canvas.clipRect(const Rect.fromLTWH(0, 0, 64, 44));
        disc(32, 46, 17, const Color(0xFFFFAD62));
        canvas.restore();
        line(4, 45, 60, 45, white, 2.5);
        line(14, 52, 50, 52, white.withValues(alpha: .6), 2);
        line(22, 58, 42, 58, white.withValues(alpha: .4), 2);
      default:
        const crater = Color(0xFFE3D6B0);
        disc(32, 32, 19, const Color(0xFFF6EDD2));
        disc(25, 27, 3.4, crater);
        disc(38, 38, 2.6, crater);
        disc(36, 24, 1.6, crater);
        disc(8, 10, 1.5, white);
        disc(58, 16, 1.2, white);
    }
  }

  @override
  bool shouldRepaint(PrayerIconPainter old) => old.prayer != prayer;
}

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
    // CSS «linear-gradient(160deg, …)»: down and a little to the left.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: const Alignment(.36, -1),
          end: const Alignment(-.36, 1),
          colors: c,
          stops: const [0, .6, 1],
        ).createShader(rect),
    );
    final w = size.width, h = size.height;
    if (prayer == PrayerKind.isha || prayer == PrayerKind.fajr) {
      // The mockup's sin(t / 650 ms), over a 44 s loop.
      final t = twinkle.value * 44000 / 650;
      final star = Paint();
      for (final s in _stars) {
        var a = still ? .6 : .3 + .45 * math.sin(t + s.phase);
        if (prayer == PrayerKind.fajr) a *= .45;
        star.color = Colors.white.withValues(alpha: a.clamp(0, 1));
        canvas.drawCircle(Offset(s.x * w, s.y / .7 * h * .8), s.r, star);
      }
    }
    // A soft glow behind the icon at the inline start.
    final glow = switch (prayer) {
      PrayerKind.fajr => const Color(0xFFFFAA82),
      PrayerKind.dhuhr => const Color(0xFFFFE196),
      PrayerKind.asr => const Color(0xFFFFCD78),
      PrayerKind.maghrib => const Color(0xFFFF965A),
      _ => const Color(0xFFF6EDD2),
    };
    final center = Offset(rtl ? w - 40 : 40, 34);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          colors: [glow.withValues(alpha: .45), glow.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: center, radius: 90)),
    );
  }

  @override
  bool shouldRepaint(SkyPainter old) =>
      old.prayer != prayer || old.still != still || old.rtl != rtl;
}
