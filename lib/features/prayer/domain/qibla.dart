import 'dart:math' as math;

/// The Kaaba (the centre of its roof), degrees.
const kaabaLat = 21.422487;
const kaabaLon = 39.826206;

/// The mean Earth radius (IUGG), km.
const earthRadiusKm = 6371.0088;

/// How close to the Qibla counts as facing it, degrees either way.
const qiblaTolerance = 3.0;

double _rad(double d) => d * math.pi / 180;
double _deg(double r) => r * 180 / math.pi;

/// The great-circle bearing from a place to the Kaaba, degrees from true
/// north clockwise (0 ≤ b < 360).
double qiblaBearing(double lat, double lon) {
  final p1 = _rad(lat), p2 = _rad(kaabaLat);
  final dl = _rad(kaabaLon - lon);
  final y = math.sin(dl) * math.cos(p2);
  final x =
      math.cos(p1) * math.sin(p2) - math.sin(p1) * math.cos(p2) * math.cos(dl);
  return normalizeDegrees(_deg(math.atan2(y, x)));
}

/// The great-circle distance from a place to the Kaaba, km (haversine).
double kaabaDistanceKm(double lat, double lon) {
  final p1 = _rad(lat), p2 = _rad(kaabaLat);
  final dp = p2 - p1, dl = _rad(kaabaLon - lon);
  final a =
      math.pow(math.sin(dp / 2), 2) +
      math.cos(p1) * math.cos(p2) * math.pow(math.sin(dl / 2), 2);
  return 2 * earthRadiusKm * math.asin(math.sqrt(a));
}

double normalizeDegrees(double d) => ((d % 360) + 360) % 360;

/// The signed turn from [heading] to [target], degrees (−180 … 180):
/// positive turns clockwise (right).
double turnTo(double heading, double target) {
  final d = normalizeDegrees(target - heading);
  return d > 180 ? d - 360 : d;
}

/// Whether facing [heading] is within [qiblaTolerance] of [target].
bool facesQibla(double heading, double target) =>
    turnTo(heading, target).abs() <= qiblaTolerance;
