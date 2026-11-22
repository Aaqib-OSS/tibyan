import 'dart:math' as math;

import 'package:flutter/services.dart';

import '../domain/prayer_settings.dart';

/// The offline city list: GeoNames `cities15000` (CC BY 4.0), every city
/// of 15,000 people or more, largest first, with its Arabic name where
/// GeoNames has one and its IANA time zone.
const citiesAsset = 'assets/prayer/cities.tsv';

class CityList {
  CityList._(this.cities, this.countries);

  final List<PrayerPlace> cities;

  /// ISO code → English country name.
  final Map<String, String> countries;

  static CityList parse(String text) {
    var zones = const <String>[];
    final countries = <String, String>{};
    final cities = <PrayerPlace>[];
    for (final line in text.split('\n')) {
      if (line.isEmpty) continue;
      if (line.startsWith('#tz\t')) {
        zones = line.substring(4).split('\t');
        continue;
      }
      if (line.startsWith('#cc\t')) {
        for (final kv in line.substring(4).split('\t')) {
          final i = kv.indexOf('=');
          if (i > 0) countries[kv.substring(0, i)] = kv.substring(i + 1);
        }
        continue;
      }
      if (line.startsWith('#')) continue;
      final f = line.split('\t');
      if (f.length < 6) continue;
      final z = int.tryParse(f[5]);
      if (z == null || z >= zones.length) continue;
      cities.add(
        PrayerPlace(
          name: f[0],
          arabicName: f[1],
          country: f[2],
          lat: double.parse(f[3]),
          lon: double.parse(f[4]),
          timeZone: zones[z],
        ),
      );
    }
    return CityList._(cities, countries);
  }

  static Future<CityList> load([AssetBundle? bundle]) async =>
      parse(await (bundle ?? rootBundle).loadString(citiesAsset));

  static String _fold(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[أإآ]'), 'ا')
      .replaceAll('ة', 'ه')
      .replaceAll('ى', 'ي')
      .replaceAll(RegExp('[ً-ْـ]'), '');

  /// Cities whose English or Arabic name starts with [query] (then those
  /// that contain it), largest first.
  List<PrayerPlace> search(String query, {int max = 40}) {
    final q = _fold(query.trim());
    if (q.isEmpty) return cities.take(max).toList();
    final starts = <PrayerPlace>[];
    final contains = <PrayerPlace>[];
    for (final c in cities) {
      final en = _fold(c.name);
      final ar = _fold(c.arabicName);
      var ar2 = ar;
      if (ar2.startsWith('ال')) ar2 = ar2.substring(2);
      if (en.startsWith(q) || ar.startsWith(q) || ar2.startsWith(q)) {
        starts.add(c);
        if (starts.length >= max) break;
      } else if (contains.length < max && (en.contains(q) || ar.contains(q))) {
        contains.add(c);
      }
    }
    return [...starts, ...contains].take(max).toList();
  }

  /// The city nearest to a position (for «حدّد موقعي»).
  PrayerPlace? nearest(double lat, double lon) {
    PrayerPlace? best;
    var bestD = double.infinity;
    for (final c in cities) {
      final d = distanceKm(lat, lon, c.lat, c.lon);
      if (d < bestD) {
        bestD = d;
        best = c;
      }
    }
    return best;
  }
}

/// Great-circle distance in kilometres.
double distanceKm(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLon = rad(lon2 - lon1);
  final a =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) *
          math.cos(rad(lat2)) *
          math.pow(math.sin(dLon / 2), 2);
  return 2 * r * math.asin(math.sqrt(a));
}
