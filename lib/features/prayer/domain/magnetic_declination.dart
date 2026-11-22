import 'dart:math' as math;

/// The magnetic declination (degrees, east positive) at a place: how far
/// a compass's north is from true north. World Magnetic Model 2025, valid
/// 2025.0 to 2030.0 (a later date uses the model's last year).
double magneticDeclination(double lat, double lon, DateTime when) {
  final year =
      when.year + (when.difference(DateTime(when.year)).inDays / 365.25);
  final dt = (year.clamp(wmm2025Epoch, wmm2025Epoch + 5)) - wmm2025Epoch;
  const a = 6378.137, b = 6356.7523142, re = 6371.2;
  const alt = 0.0;
  final rlat = lat * math.pi / 180;
  final rlon = lon * math.pi / 180;
  final srlat = math.sin(rlat), crlat = math.cos(rlat);
  final srlat2 = srlat * srlat, crlat2 = crlat * crlat;
  const a2 = a * a, b2 = b * b, c2 = a2 - b2;
  const a4 = a2 * a2, b4 = b2 * b2, c4 = a4 - b4;
  // Geodetic to spherical (geocentric) coordinates.
  final q = math.sqrt(a2 - c2 * srlat2);
  final q1 = alt * q;
  final q2 = math.pow((q1 + a2) / (q1 + b2), 2);
  final ct = srlat / math.sqrt(q2 * crlat2 + srlat2);
  final st = math.sqrt(1 - ct * ct);
  final r = math.sqrt(alt * alt + 2 * q1 + (a4 - c4 * srlat2) / (q * q));
  final d = math.sqrt(a2 * crlat2 + b2 * srlat2);
  final ca = (alt + d) / r;
  final sa = c2 * crlat * srlat / (r * d);

  const size = 13;
  final p = List.generate(size, (_) => List.filled(size, 0.0));
  final dp = List.generate(size, (_) => List.filled(size, 0.0));
  final g = List.generate(size, (_) => List.filled(size, 0.0));
  final h = List.generate(size, (_) => List.filled(size, 0.0));
  for (final c in wmm2025) {
    final n = c[0].toInt(), m = c[1].toInt();
    g[n][m] = c[2] + dt * c[4];
    h[n][m] = c[3] + dt * c[5];
  }
  p[0][0] = 1;
  for (var n = 1; n < size; n++) {
    for (var m = 0; m <= n; m++) {
      if (n == m) {
        final k = n == 1 ? 1.0 : math.sqrt((2 * n - 1) / (2 * n));
        p[n][n] = k * st * p[n - 1][n - 1];
        dp[n][n] = k * (st * dp[n - 1][n - 1] + ct * p[n - 1][n - 1]);
      } else {
        final k1 = math.sqrt((n * n - m * m).toDouble());
        final k2 = n - 2 >= m
            ? math.sqrt(((n - 1) * (n - 1) - m * m).toDouble())
            : 0.0;
        final pm2 = n - 2 >= m ? p[n - 2][m] : 0.0;
        final dpm2 = n - 2 >= m ? dp[n - 2][m] : 0.0;
        p[n][m] = ((2 * n - 1) * ct * p[n - 1][m] - k2 * pm2) / k1;
        dp[n][m] =
            ((2 * n - 1) * (ct * dp[n - 1][m] - st * p[n - 1][m]) - k2 * dpm2) /
            k1;
      }
    }
  }
  var north = 0.0, east = 0.0, down = 0.0;
  for (var n = 1; n < size; n++) {
    final ar = math.pow(re / r, n + 2).toDouble();
    for (var m = 0; m <= n; m++) {
      final cm = math.cos(m * rlon), sm = math.sin(m * rlon);
      final gc = g[n][m] * cm + h[n][m] * sm;
      north += ar * gc * dp[n][m];
      east += ar * m * (g[n][m] * sm - h[n][m] * cm) * p[n][m] / st;
      down -= ar * (n + 1) * gc * p[n][m];
    }
  }
  // Back to the geodetic frame.
  final x = north * ca + down * sa;
  return math.atan2(east, x) * 180 / math.pi;
}

// World Magnetic Model 2025 (NOAA NCEI / BGS), valid 2025.0–2030.0.
// Public domain (US Government work). n, m, g, h, dg, dh.
const wmm2025Epoch = 2025.0;
const wmm2025 = <List<double>>[
  [1, 0, -29351.8, 0.0, 12.0, 0.0],
  [1, 1, -1410.8, 4545.4, 9.7, -21.5],
  [2, 0, -2556.6, 0.0, -11.6, 0.0],
  [2, 1, 2951.1, -3133.6, -5.2, -27.7],
  [2, 2, 1649.3, -815.1, -8.0, -12.1],
  [3, 0, 1361.0, 0.0, -1.3, 0.0],
  [3, 1, -2404.1, -56.6, -4.2, 4.0],
  [3, 2, 1243.8, 237.5, 0.4, -0.3],
  [3, 3, 453.6, -549.5, -15.6, -4.1],
  [4, 0, 895.0, 0.0, -1.6, 0.0],
  [4, 1, 799.5, 278.6, -2.4, -1.1],
  [4, 2, 55.7, -133.9, -6.0, 4.1],
  [4, 3, -281.1, 212.0, 5.6, 1.6],
  [4, 4, 12.1, -375.6, -7.0, -4.4],
  [5, 0, -233.2, 0.0, 0.6, 0.0],
  [5, 1, 368.9, 45.4, 1.4, -0.5],
  [5, 2, 187.2, 220.2, 0.0, 2.2],
  [5, 3, -138.7, -122.9, 0.6, 0.4],
  [5, 4, -142.0, 43.0, 2.2, 1.7],
  [5, 5, 20.9, 106.1, 0.9, 1.9],
  [6, 0, 64.4, 0.0, -0.2, 0.0],
  [6, 1, 63.8, -18.4, -0.4, 0.3],
  [6, 2, 76.9, 16.8, 0.9, -1.6],
  [6, 3, -115.7, 48.8, 1.2, -0.4],
  [6, 4, -40.9, -59.8, -0.9, 0.9],
  [6, 5, 14.9, 10.9, 0.3, 0.7],
  [6, 6, -60.7, 72.7, 0.9, 0.9],
  [7, 0, 79.5, 0.0, -0.0, 0.0],
  [7, 1, -77.0, -48.9, -0.1, 0.6],
  [7, 2, -8.8, -14.4, -0.1, 0.5],
  [7, 3, 59.3, -1.0, 0.5, -0.8],
  [7, 4, 15.8, 23.4, -0.1, 0.0],
  [7, 5, 2.5, -7.4, -0.8, -1.0],
  [7, 6, -11.1, -25.1, -0.8, 0.6],
  [7, 7, 14.2, -2.3, 0.8, -0.2],
  [8, 0, 23.2, 0.0, -0.1, 0.0],
  [8, 1, 10.8, 7.1, 0.2, -0.2],
  [8, 2, -17.5, -12.6, 0.0, 0.5],
  [8, 3, 2.0, 11.4, 0.5, -0.4],
  [8, 4, -21.7, -9.7, -0.1, 0.4],
  [8, 5, 16.9, 12.7, 0.3, -0.5],
  [8, 6, 15.0, 0.7, 0.2, -0.6],
  [8, 7, -16.8, -5.2, -0.0, 0.3],
  [8, 8, 0.9, 3.9, 0.2, 0.2],
  [9, 0, 4.6, 0.0, -0.0, 0.0],
  [9, 1, 7.8, -24.8, -0.1, -0.3],
  [9, 2, 3.0, 12.2, 0.1, 0.3],
  [9, 3, -0.2, 8.3, 0.3, -0.3],
  [9, 4, -2.5, -3.3, -0.3, 0.3],
  [9, 5, -13.1, -5.2, 0.0, 0.2],
  [9, 6, 2.4, 7.2, 0.3, -0.1],
  [9, 7, 8.6, -0.6, -0.1, -0.2],
  [9, 8, -8.7, 0.8, 0.1, 0.4],
  [9, 9, -12.9, 10.0, -0.1, 0.1],
  [10, 0, -1.3, 0.0, 0.1, 0.0],
  [10, 1, -6.4, 3.3, 0.0, 0.0],
  [10, 2, 0.2, 0.0, 0.1, -0.0],
  [10, 3, 2.0, 2.4, 0.1, -0.2],
  [10, 4, -1.0, 5.3, -0.0, 0.1],
  [10, 5, -0.6, -9.1, -0.3, -0.1],
  [10, 6, -0.9, 0.4, 0.0, 0.1],
  [10, 7, 1.5, -4.2, -0.1, 0.0],
  [10, 8, 0.9, -3.8, -0.1, -0.1],
  [10, 9, -2.7, 0.9, -0.0, 0.2],
  [10, 10, -3.9, -9.1, -0.0, -0.0],
  [11, 0, 2.9, 0.0, 0.0, 0.0],
  [11, 1, -1.5, 0.0, -0.0, -0.0],
  [11, 2, -2.5, 2.9, 0.0, 0.1],
  [11, 3, 2.4, -0.6, 0.0, -0.0],
  [11, 4, -0.6, 0.2, 0.0, 0.1],
  [11, 5, -0.1, 0.5, -0.1, -0.0],
  [11, 6, -0.6, -0.3, 0.0, -0.0],
  [11, 7, -0.1, -1.2, -0.0, 0.1],
  [11, 8, 1.1, -1.7, -0.1, -0.0],
  [11, 9, -1.0, -2.9, -0.1, 0.0],
  [11, 10, -0.2, -1.8, -0.1, 0.0],
  [11, 11, 2.6, -2.3, -0.1, 0.0],
  [12, 0, -2.0, 0.0, 0.0, 0.0],
  [12, 1, -0.2, -1.3, 0.0, -0.0],
  [12, 2, 0.3, 0.7, -0.0, 0.0],
  [12, 3, 1.2, 1.0, -0.0, -0.1],
  [12, 4, -1.3, -1.4, -0.0, 0.1],
  [12, 5, 0.6, -0.0, -0.0, -0.0],
  [12, 6, 0.6, 0.6, 0.1, -0.0],
  [12, 7, 0.5, -0.1, -0.0, -0.0],
  [12, 8, -0.1, 0.8, 0.0, 0.0],
  [12, 9, -0.4, 0.1, 0.0, -0.0],
  [12, 10, -0.2, -1.0, -0.1, -0.0],
  [12, 11, -1.3, 0.1, -0.0, 0.0],
  [12, 12, -0.7, 0.2, -0.1, -0.1],
];
