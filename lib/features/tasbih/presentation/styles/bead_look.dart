import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../tasbih_settings.dart';

/// A bead material: its colour, how it takes light, and the thread and
/// metal that go with it.
@immutable
class BeadLook {
  const BeadLook({
    required this.kind,
    required this.base,
    required this.shine,
    this.scatter = 0,
    required this.middle,
    required this.ends,
    required this.rough,
    required this.coat,
    required this.coatRough,
    required this.env,
    this.emit = const Color(0xFF000000),
    required this.thread,
    required this.metal,
  });

  /// The surface the shader draws (`uKind` in shaders/bead.frag).
  final int kind;

  /// The bead's colour in the suggested look.
  final Color base;

  /// Specular strength, 0..1.
  final double shine;

  /// Light passing through the bead (amber, pearl), 0..1.
  final double scatter;

  /// The colour round the bead's middle and at its two holes.
  final Color middle, ends;

  /// Roughness under the clear coat; the coat's strength and roughness;
  /// how strongly the studio is reflected.
  final double rough, coat, coatRough, env;

  /// The glow from within (amber).
  final Color emit;

  /// The string and tassel, and the joint and the imam's cap (the
  /// mockup's table gives these as linear values; here as displayed).
  final Color thread, metal;

  /// The shader's surface for metal.
  static const metalKind = 6;

  /// The terminal bead of the suggested look: the same material, deeper.
  static BeadLook terminalOf(BeadLook l) => BeadLook(
    kind: l.kind,
    base: Color.lerp(l.base, Colors.black, .28)!,
    shine: l.shine,
    scatter: l.scatter * .6,
    middle: l.middle,
    ends: l.ends,
    rough: l.rough,
    coat: l.coat,
    coatRough: l.coatRough,
    env: l.env,
    emit: l.emit,
    thread: l.thread,
    metal: l.metal,
  );

  static BeadLook of(BeadMaterial m) => switch (m) {
    BeadMaterial.amber => const BeadLook(
      kind: 0,
      base: Color(0xFFC77A1C),
      shine: .9,
      scatter: .75,
      middle: Color(0xFFDB8E24),
      ends: Color(0xFFA5570E),
      rough: .1,
      coat: 1,
      coatRough: .05,
      env: 1.3,
      emit: Color(0xFF6B2A00),
      thread: Color(0xFF9F5A50),
      metal: Color(0xFFE5CF91),
    ),
    BeadMaterial.wood => const BeadLook(
      kind: 1,
      base: Color(0xFF6E4326),
      shine: .28,
      middle: Color(0xFF7A4B2B),
      ends: Color(0xFF4A2A17),
      rough: .36,
      coat: .55,
      coatRough: .25,
      env: .9,
      thread: Color(0xFF826657),
      metal: Color(0xFFD7C39C),
    ),
    BeadMaterial.pearl => const BeadLook(
      kind: 2,
      base: Color(0xFFE6E0D3),
      shine: .75,
      scatter: .3,
      middle: Color(0xFFF7F2E8),
      ends: Color(0xFFE3DAC9),
      rough: .2,
      coat: 1,
      coatRough: .1,
      env: 1.25,
      thread: Color(0xFFEDEAE6),
      metal: Color(0xFFECEDEE),
    ),
    BeadMaterial.rosewood => const BeadLook(
      kind: 3,
      base: Color(0xFF5A1F1A),
      shine: .35,
      middle: Color(0xFF5A1F1A),
      ends: Color(0xFF2E0F0D),
      rough: .36,
      coat: .55,
      coatRough: .25,
      env: .9,
      thread: Color(0xFF826657),
      metal: Color(0xFFD7C39C),
    ),
    BeadMaterial.turquoise => const BeadLook(
      kind: 4,
      base: Color(0xFF2AA9A2),
      shine: .5,
      middle: Color(0xFF31B8B0),
      ends: Color(0xFF1B8F8A),
      rough: .32,
      coat: .6,
      coatRough: .2,
      env: 1,
      thread: Color(0xFFDCBE72),
      metal: Color(0xFFE5CF91),
    ),
    BeadMaterial.yusr => const BeadLook(
      kind: 5,
      base: Color(0xFF1B1918),
      shine: .7,
      middle: Color(0xFF201D1C),
      ends: Color(0xFF0C0B0B),
      rough: .28,
      coat: .85,
      coatRough: .15,
      env: 1.1,
      thread: Color(0xFFCBCDCE),
      metal: Color(0xFFECEDEE),
    ),
  };
}

/// The bead shader (shaders/bead.frag), loaded once. Where fragment
/// shaders are not available the misbaha draws its suggested look.
abstract final class BeadShader {
  /// The program, once loaded.
  static ui.FragmentProgram? program;

  /// Whether fragment shaders work here; null until that is known.
  static final available = ValueNotifier<bool?>(null);

  static bool _asked = false;

  static void ensureLoaded() {
    if (_asked) return;
    _asked = true;
    try {
      unawaited(
        ui.FragmentProgram.fromAsset('shaders/bead.frag').then(
          (p) {
            program = p;
            available.value = true;
          },
          onError: (Object _) {
            available.value = false;
          },
        ),
      );
    } on Object {
      available.value = false;
    }
  }

  /// For tests: as if the shader had loaded ([works]) or could not.
  @visibleForTesting
  static void debugSetAvailable(bool? works) {
    _asked = works != null;
    program = null;
    available.value = works;
  }
}

/// Draws a bead as a flat disc shaded to look round: a radial gradient lit
/// from [light] (a direction on screen, y down), a glow through it, a
/// specular spot and a soft shadow.
void paintShadedBead(
  Canvas canvas,
  Offset c,
  double r,
  BeadLook look, {
  Offset light = const Offset(-.45, -.6),
  double fade = 0,
  bool shadow = true,
}) {
  if (shadow) {
    canvas.drawCircle(
      c + Offset(-light.dx * r * .35, -light.dy * r * .45),
      r * .98,
      Paint()
        ..color = Colors.black.withValues(alpha: .28 * (1 - fade))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * .35),
    );
  }
  final base = Color.lerp(look.base, Colors.black, fade * .5)!;
  final hi = Color.lerp(base, Colors.white, .45 * look.shine + .1)!;
  final dark = Color.lerp(base, Colors.black, .62)!;
  final rect = Rect.fromCircle(center: c, radius: r);
  canvas.drawCircle(
    c,
    r,
    Paint()
      ..shader = RadialGradient(
        center: Alignment(light.dx * .7, light.dy * .7),
        radius: 1.15,
        colors: [hi, base, dark],
        stops: const [0, .5, 1],
      ).createShader(rect),
  );
  if (look.scatter > 0) {
    // Light through the bead, gathering on the side away from the light.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = RadialGradient(
          center: Alignment(-light.dx * .55, -light.dy * .55),
          radius: .7,
          colors: [
            Color.lerp(
              base,
              Colors.white,
              .3,
            )!.withValues(alpha: .45 * look.scatter),
            Colors.transparent,
          ],
        ).createShader(rect),
    );
  }
  // The specular spot.
  final spot = Rect.fromCenter(
    center: c + Offset(light.dx * r * .5, light.dy * r * .5),
    width: r * .46,
    height: r * .3,
  );
  canvas.drawOval(
    spot,
    Paint()
      ..color = Colors.white.withValues(alpha: .25 + .6 * look.shine)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * .06),
  );
}
