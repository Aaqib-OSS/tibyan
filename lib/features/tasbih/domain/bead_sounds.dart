import 'dart:math' as math;

import '../tasbih_settings.dart';

/// The misbaha's bead sounds (`assets/tasbih/beads/`, synthesized by
/// `tools/build_bead_sounds.py`): four variants of a count and two of the
/// imam's joint crossing for each material. A count never plays the
/// variant it played last, so a run of counts does not sound mechanical.
class BeadSoundPicker {
  BeadSoundPicker([math.Random? random]) : _random = random ?? math.Random();

  final math.Random _random;

  static const countVariants = 4, endVariants = 2;
  static const _dir = 'assets/tasbih/beads';

  static String countAsset(BeadMaterial m, int n) =>
      '$_dir/${m.soundKey}_$n.wav';
  static String endAsset(BeadMaterial m, int n) =>
      '$_dir/${m.soundKey}_end_$n.wav';

  /// Every sound of [m], to load before the first count.
  static List<String> assetsOf(BeadMaterial m) => [
    for (var n = 1; n <= countVariants; n++) countAsset(m, n),
    for (var n = 1; n <= endVariants; n++) endAsset(m, n),
  ];

  int _lastCount = 0;

  /// The sound of one count of [m].
  String count(BeadMaterial m) {
    var n = 1 + _random.nextInt(countVariants);
    if (n == _lastCount) n = n % countVariants + 1;
    _lastCount = n;
    return countAsset(m, n);
  }

  /// The sound of the joint crossing: the lap's end.
  String end(BeadMaterial m) => endAsset(m, 1 + _random.nextInt(endVariants));
}
