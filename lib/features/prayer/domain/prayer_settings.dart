import 'dart:convert';

import 'package:flutter/foundation.dart';

/// The times of a day the app knows: the five prayers, and sunrise
/// (الشروق) and the forenoon (الضحى), which have no adhan.
enum PrayerKind { fajr, shuruq, duha, dhuhr, asr, maghrib, isha }

/// The five prayers that have an adhan.
const obligatoryPrayers = [
  PrayerKind.fajr,
  PrayerKind.dhuhr,
  PrayerKind.asr,
  PrayerKind.maghrib,
  PrayerKind.isha,
];

/// What a prayer's alert sounds like when its time comes.
enum AlertSound { silent, tone, adhan }

/// Which recording of the adhan plays: the whole adhan, or only the cut
/// that ends at «حي على الصلاة» (under 30 seconds).
enum AdhanLength { full, short }

/// The calculation methods offered (the adhan package's, by name).
enum CalcMethod {
  egyptian,
  ummAlQura,
  muslimWorldLeague,
  karachi,
  northAmerica,
  dubai,
  kuwait,
  qatar,
  singapore,
  turkey,
  moonsighting,
}

/// The Asr shadow rule: the majority (Shafi'i, Maliki, Hanbali) or Hanafi.
enum AsrRule { shafii, hanafi }

/// The default method for a country (ISO 3166 code): the authority people
/// there follow; the Muslim World League elsewhere.
CalcMethod defaultMethodFor(String? country) => switch (country) {
  'EG' || 'SD' || 'LY' || 'SY' || 'LB' || 'IQ' || 'PS' || 'JO' => .egyptian,
  'SA' || 'YE' => .ummAlQura,
  'AE' => .dubai,
  'KW' => .kuwait,
  'QA' || 'BH' || 'OM' => .qatar,
  'PK' || 'IN' || 'BD' || 'AF' => .karachi,
  'US' || 'CA' => .northAmerica,
  'SG' || 'MY' || 'ID' || 'BN' => .singapore,
  'TR' => .turkey,
  'GB' || 'IE' => .moonsighting,
  _ => .muslimWorldLeague,
};

/// A place to compute for: a city from the list, or the device's position
/// (named after the nearest city).
@immutable
class PrayerPlace {
  const PrayerPlace({
    required this.name,
    required this.arabicName,
    required this.country,
    required this.lat,
    required this.lon,
    required this.timeZone,
  });

  final String name;
  final String arabicName;

  /// ISO 3166 code.
  final String country;
  final double lat;
  final double lon;

  /// IANA name ("Africa/Cairo").
  final String timeZone;

  String label(bool arabic) =>
      arabic && arabicName.isNotEmpty ? arabicName : name;

  Map<String, Object?> toJson() => {
    'n': name,
    'a': arabicName,
    'c': country,
    'lat': lat,
    'lon': lon,
    'tz': timeZone,
  };

  static PrayerPlace? fromJson(Object? j) {
    if (j is! Map) return null;
    try {
      return PrayerPlace(
        name: j['n'] as String,
        arabicName: j['a'] as String? ?? '',
        country: j['c'] as String,
        lat: (j['lat'] as num).toDouble(),
        lon: (j['lon'] as num).toDouble(),
        timeZone: j['tz'] as String,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is PrayerPlace &&
      other.name == name &&
      other.country == country &&
      other.lat == lat &&
      other.lon == lon &&
      other.timeZone == timeZone;

  @override
  int get hashCode => Object.hash(name, country, lat, lon, timeZone);
}

/// Every choice of «مواقيت الصلاة», kept as one JSON value.
@immutable
class PrayerSettings {
  const PrayerSettings({
    this.enabled = false,
    this.place,
    this.method,
    this.asr = AsrRule.shafii,
    this.offsets = const {},
    this.sounds = const {},
    this.reminders = const {},
    this.shuruqAlert = false,
    this.duhaAlert = false,
    this.suhoorAlert = true,
    this.suhoorMinutes = 10,
    this.iftarAlert = true,
    this.iftarMinutes = 15,
    this.hijriOffset = 0,
    this.muezzin = defaultMuezzin,
    this.length = AdhanLength.full,
    this.duaAfter = false,
    this.desktopAsked = false,
    this.tray = false,
    this.launchAtLogin = false,
  });

  static const defaultMuezzin = 'refaat';

  /// Reminder lengths offered before a prayer (0 = none).
  static const reminderChoices = [0, 5, 10, 15, 30];

  /// The furthest a time can be moved by hand, in minutes.
  static const maxOffset = 30;

  final bool enabled;
  final PrayerPlace? place;

  /// Null: the place's country decides ([defaultMethodFor]).
  final CalcMethod? method;
  final AsrRule asr;

  /// Minutes added to each time (negative: earlier).
  final Map<PrayerKind, int> offsets;
  final Map<PrayerKind, AlertSound> sounds;

  /// Minutes before each prayer to remind (absent or 0: none).
  final Map<PrayerKind, int> reminders;
  final bool shuruqAlert;
  final bool duhaAlert;

  /// Ramadan: a reminder before Fajr (the end of suhoor) and before
  /// Maghrib (iftar).
  final bool suhoorAlert;
  final int suhoorMinutes;
  final bool iftarAlert;
  final int iftarMinutes;

  /// Days added to the Umm al-Qura date (−2 … 2).
  final int hijriOffset;
  final String muezzin;
  final AdhanLength length;

  /// The after-prayer dua right after the adhan.
  final bool duaAfter;

  /// Desktop: the tray and launch-at-login question was asked.
  final bool desktopAsked;
  final bool tray;
  final bool launchAtLogin;

  CalcMethod get effectiveMethod => method ?? defaultMethodFor(place?.country);

  int offsetOf(PrayerKind p) => offsets[p] ?? 0;

  /// The five prayers sound the gentle tone until a choice is made; the
  /// adhan is chosen for them once its recording is downloaded.
  AlertSound soundOf(PrayerKind p) => sounds[p] ?? AlertSound.adhan;

  int reminderOf(PrayerKind p) => reminders[p] ?? 0;

  PrayerSettings copyWith({
    bool? enabled,
    PrayerPlace? place,
    CalcMethod? method,
    bool clearMethod = false,
    AsrRule? asr,
    Map<PrayerKind, int>? offsets,
    Map<PrayerKind, AlertSound>? sounds,
    Map<PrayerKind, int>? reminders,
    bool? shuruqAlert,
    bool? duhaAlert,
    bool? suhoorAlert,
    int? suhoorMinutes,
    bool? iftarAlert,
    int? iftarMinutes,
    int? hijriOffset,
    String? muezzin,
    AdhanLength? length,
    bool? duaAfter,
    bool? desktopAsked,
    bool? tray,
    bool? launchAtLogin,
  }) => PrayerSettings(
    enabled: enabled ?? this.enabled,
    place: place ?? this.place,
    method: clearMethod ? null : method ?? this.method,
    asr: asr ?? this.asr,
    offsets: offsets ?? this.offsets,
    sounds: sounds ?? this.sounds,
    reminders: reminders ?? this.reminders,
    shuruqAlert: shuruqAlert ?? this.shuruqAlert,
    duhaAlert: duhaAlert ?? this.duhaAlert,
    suhoorAlert: suhoorAlert ?? this.suhoorAlert,
    suhoorMinutes: suhoorMinutes ?? this.suhoorMinutes,
    iftarAlert: iftarAlert ?? this.iftarAlert,
    iftarMinutes: iftarMinutes ?? this.iftarMinutes,
    hijriOffset: (hijriOffset ?? this.hijriOffset).clamp(-2, 2),
    muezzin: muezzin ?? this.muezzin,
    length: length ?? this.length,
    duaAfter: duaAfter ?? this.duaAfter,
    desktopAsked: desktopAsked ?? this.desktopAsked,
    tray: tray ?? this.tray,
    launchAtLogin: launchAtLogin ?? this.launchAtLogin,
  );

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'place': place?.toJson(),
    'method': method?.name,
    'asr': asr.name,
    'offsets': {for (final e in offsets.entries) e.key.name: e.value},
    'sounds': {for (final e in sounds.entries) e.key.name: e.value.name},
    'reminders': {for (final e in reminders.entries) e.key.name: e.value},
    'shuruq': shuruqAlert,
    'duha': duhaAlert,
    'suhoor': suhoorAlert,
    'suhoorMin': suhoorMinutes,
    'iftar': iftarAlert,
    'iftarMin': iftarMinutes,
    'hijri': hijriOffset,
    'muezzin': muezzin,
    'length': length.name,
    'dua': duaAfter,
    'desktopAsked': desktopAsked,
    'tray': tray,
    'login': launchAtLogin,
  };

  String encode() => jsonEncode(toJson());

  static T? _enum<T extends Enum>(List<T> values, Object? name) {
    for (final v in values) {
      if (v.name == name) return v;
    }
    return null;
  }

  static Map<PrayerKind, V> _map<V>(Object? j, V? Function(Object?) read) {
    if (j is! Map) return const {};
    final out = <PrayerKind, V>{};
    for (final e in j.entries) {
      final k = _enum(PrayerKind.values, e.key);
      final v = read(e.value);
      if (k != null && v != null) out[k] = v;
    }
    return out;
  }

  static int? _int(Object? v) => v is num ? v.toInt() : null;

  /// Reads [source]; anything missing or broken falls back to the default.
  static PrayerSettings decode(String? source) {
    if (source == null || source.isEmpty) return const PrayerSettings();
    try {
      final j = jsonDecode(source) as Map<String, dynamic>;
      const d = PrayerSettings();
      return PrayerSettings(
        enabled: j['enabled'] as bool? ?? d.enabled,
        place: PrayerPlace.fromJson(j['place']),
        method: _enum(CalcMethod.values, j['method']),
        asr: _enum(AsrRule.values, j['asr']) ?? d.asr,
        offsets: _map(
          j['offsets'],
          (v) => _int(v)?.clamp(-maxOffset, maxOffset),
        ),
        sounds: _map(j['sounds'], (v) => _enum(AlertSound.values, v)),
        reminders: _map(j['reminders'], _int),
        shuruqAlert: j['shuruq'] as bool? ?? d.shuruqAlert,
        duhaAlert: j['duha'] as bool? ?? d.duhaAlert,
        suhoorAlert: j['suhoor'] as bool? ?? d.suhoorAlert,
        suhoorMinutes: _int(j['suhoorMin']) ?? d.suhoorMinutes,
        iftarAlert: j['iftar'] as bool? ?? d.iftarAlert,
        iftarMinutes: _int(j['iftarMin']) ?? d.iftarMinutes,
        hijriOffset: (_int(j['hijri']) ?? 0).clamp(-2, 2),
        muezzin: j['muezzin'] as String? ?? d.muezzin,
        length: _enum(AdhanLength.values, j['length']) ?? d.length,
        duaAfter: j['dua'] as bool? ?? d.duaAfter,
        desktopAsked: j['desktopAsked'] as bool? ?? d.desktopAsked,
        tray: j['tray'] as bool? ?? d.tray,
        launchAtLogin: j['login'] as bool? ?? d.launchAtLogin,
      );
    } catch (_) {
      return const PrayerSettings();
    }
  }
}
