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

/// «عندما يكون الهاتف قيد الاستخدام» (Android): how an adhan sounds while
/// the screen is on and unlocked or other media plays. During a call it
/// is always a silent notification.
enum InUseAdhan {
  /// A notification with a light sound and «تشغيل الأذان» (the default).
  notify,

  /// «حي على الصلاة» only: the short cut.
  short,

  /// The adhan as when the phone is idle.
  full,
}

/// One prayer's own adhan («إعداد خاص»). A prayer with none follows the
/// general adhan settings («حسب الإعدادات العامة»). Each null field is
/// «نفس العام»: it takes the general value.
@immutable
class PrayerAdhan {
  const PrayerAdhan({
    this.sound = AlertSound.adhan,
    this.muezzin,
    this.length,
    this.volume,
  });

  final AlertSound sound;

  /// A muezzin's slug; null: the general one.
  final String? muezzin;
  final AdhanLength? length;

  /// Android only (0…1); null: the general level.
  final double? volume;

  PrayerAdhan copyWith({
    AlertSound? sound,
    String? Function()? muezzin,
    AdhanLength? Function()? length,
    double? Function()? volume,
  }) => PrayerAdhan(
    sound: sound ?? this.sound,
    muezzin: muezzin != null ? muezzin() : this.muezzin,
    length: length != null ? length() : this.length,
    volume: volume != null ? volume()?.clamp(0.0, 1.0) : this.volume,
  );

  Map<String, Object?> toJson() => {
    'sound': sound.name,
    if (muezzin != null) 'muezzin': muezzin,
    if (length != null) 'length': length!.name,
    if (volume != null) 'volume': volume,
  };

  static PrayerAdhan? fromJson(Object? j) {
    if (j is! Map) return null;
    AlertSound? sound;
    AdhanLength? length;
    for (final v in AlertSound.values) {
      if (v.name == j['sound']) sound = v;
    }
    for (final v in AdhanLength.values) {
      if (v.name == j['length']) length = v;
    }
    if (sound == null) return null;
    final m = j['muezzin'];
    final vol = j['volume'];
    return PrayerAdhan(
      sound: sound,
      muezzin: m is String && m.isNotEmpty ? m : null,
      length: length,
      volume: vol is num ? vol.toDouble().clamp(0.0, 1.0) : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PrayerAdhan &&
      other.sound == sound &&
      other.muezzin == muezzin &&
      other.length == length &&
      other.volume == volume;

  @override
  int get hashCode => Object.hash(sound, muezzin, length, volume);
}

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
    this.custom = const {},
    this.reminders = const {},
    this.shuruqAlert = false,
    this.duhaAlert = false,
    this.suhoorAlert = true,
    this.suhoorMinutes = 10,
    this.iftarAlert = true,
    this.iftarMinutes = 15,
    this.hijriOffset = 0,
    this.occasionReminders = false,
    this.muezzin = defaultMuezzin,
    this.length = AdhanLength.full,
    this.inUse = InUseAdhan.notify,
    this.duaAfter = false,
    this.adhanVolume = defaultVolume,
    this.desktopAsked = false,
    this.tray = false,
    this.launchAtLogin = false,
  });

  static const defaultMuezzin = 'refaat';

  /// «مستوى صوت الأذان» until the user sets it.
  static const defaultVolume = 0.7;

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

  /// The prayers with their own adhan; the others follow the general
  /// settings (the adhan, the general muezzin, length and volume).
  final Map<PrayerKind, PrayerAdhan> custom;

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

  /// A reminder the day before each Hijri occasion (off until chosen).
  final bool occasionReminders;
  final String muezzin;
  final AdhanLength length;
  final InUseAdhan inUse;

  /// The after-prayer dua right after the adhan.
  final bool duaAfter;

  /// «مستوى صوت الأذان» (0…1). Android: the alarm stream's level while the
  /// adhan plays (restored after). Apple: the in-app player only (the
  /// system volume applies to alerts). Desktop: the player's volume.
  final double adhanVolume;

  /// Desktop: the tray and launch-at-login question was asked.
  final bool desktopAsked;
  final bool tray;
  final bool launchAtLogin;

  CalcMethod get effectiveMethod => method ?? defaultMethodFor(place?.country);

  int offsetOf(PrayerKind p) => offsets[p] ?? 0;

  /// A prayer's sound: its own when it has one, else the adhan (the tone
  /// until a recording is downloaded).
  AlertSound soundOf(PrayerKind p) => custom[p]?.sound ?? AlertSound.adhan;

  PrayerAdhan? customOf(PrayerKind p) => custom[p];

  /// These settings as [p]'s alert sees them: its own muezzin, length and
  /// volume in place of the general ones where it sets them. The general
  /// muezzin stays the fallback (see `adhanSlugFor`).
  PrayerSettings forPrayer(PrayerKind? p) {
    final c = p == null ? null : custom[p];
    if (c == null) return this;
    return copyWith(
      muezzin: c.muezzin,
      length: c.length,
      adhanVolume: c.volume,
    );
  }

  int reminderOf(PrayerKind p) => reminders[p] ?? 0;

  PrayerSettings copyWith({
    bool? enabled,
    PrayerPlace? place,
    CalcMethod? method,
    bool clearMethod = false,
    AsrRule? asr,
    Map<PrayerKind, int>? offsets,
    Map<PrayerKind, PrayerAdhan>? custom,
    Map<PrayerKind, int>? reminders,
    bool? shuruqAlert,
    bool? duhaAlert,
    bool? suhoorAlert,
    int? suhoorMinutes,
    bool? iftarAlert,
    int? iftarMinutes,
    int? hijriOffset,
    bool? occasionReminders,
    String? muezzin,
    AdhanLength? length,
    InUseAdhan? inUse,
    bool? duaAfter,
    double? adhanVolume,
    bool? desktopAsked,
    bool? tray,
    bool? launchAtLogin,
  }) => PrayerSettings(
    enabled: enabled ?? this.enabled,
    place: place ?? this.place,
    method: clearMethod ? null : method ?? this.method,
    asr: asr ?? this.asr,
    offsets: offsets ?? this.offsets,
    custom: custom ?? this.custom,
    reminders: reminders ?? this.reminders,
    shuruqAlert: shuruqAlert ?? this.shuruqAlert,
    duhaAlert: duhaAlert ?? this.duhaAlert,
    suhoorAlert: suhoorAlert ?? this.suhoorAlert,
    suhoorMinutes: suhoorMinutes ?? this.suhoorMinutes,
    iftarAlert: iftarAlert ?? this.iftarAlert,
    iftarMinutes: iftarMinutes ?? this.iftarMinutes,
    hijriOffset: (hijriOffset ?? this.hijriOffset).clamp(-2, 2),
    occasionReminders: occasionReminders ?? this.occasionReminders,
    muezzin: muezzin ?? this.muezzin,
    length: length ?? this.length,
    inUse: inUse ?? this.inUse,
    duaAfter: duaAfter ?? this.duaAfter,
    adhanVolume: (adhanVolume ?? this.adhanVolume).clamp(0.0, 1.0),
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
    'perPrayer': {for (final e in custom.entries) e.key.name: e.value.toJson()},
    'reminders': {for (final e in reminders.entries) e.key.name: e.value},
    'shuruq': shuruqAlert,
    'duha': duhaAlert,
    'suhoor': suhoorAlert,
    'suhoorMin': suhoorMinutes,
    'iftar': iftarAlert,
    'iftarMin': iftarMinutes,
    'hijri': hijriOffset,
    'occasions': occasionReminders,
    'muezzin': muezzin,
    'length': length.name,
    'inUse': inUse.name,
    'dua': duaAfter,
    'volume': adhanVolume,
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

  /// Before per-prayer adhans: each prayer kept only its sound. The adhan
  /// is what «حسب العام» gives; silent or the tone become that prayer's
  /// own setup with everything else as the general one.
  static Map<PrayerKind, PrayerAdhan> migrateSounds(Object? j) => {
    for (final e in _map(j, (v) => _enum(AlertSound.values, v)).entries)
      if (e.value != AlertSound.adhan) e.key: PrayerAdhan(sound: e.value),
  };

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
        custom: j.containsKey('perPrayer')
            ? _map(j['perPrayer'], PrayerAdhan.fromJson)
            : migrateSounds(j['sounds']),
        reminders: _map(j['reminders'], _int),
        shuruqAlert: j['shuruq'] as bool? ?? d.shuruqAlert,
        duhaAlert: j['duha'] as bool? ?? d.duhaAlert,
        suhoorAlert: j['suhoor'] as bool? ?? d.suhoorAlert,
        suhoorMinutes: _int(j['suhoorMin']) ?? d.suhoorMinutes,
        iftarAlert: j['iftar'] as bool? ?? d.iftarAlert,
        iftarMinutes: _int(j['iftarMin']) ?? d.iftarMinutes,
        hijriOffset: (_int(j['hijri']) ?? 0).clamp(-2, 2),
        occasionReminders: j['occasions'] as bool? ?? d.occasionReminders,
        muezzin: j['muezzin'] as String? ?? d.muezzin,
        length: _enum(AdhanLength.values, j['length']) ?? d.length,
        inUse: _enum(InUseAdhan.values, j['inUse']) ?? d.inUse,
        duaAfter: j['dua'] as bool? ?? d.duaAfter,
        adhanVolume: ((j['volume'] as num?)?.toDouble() ?? d.adhanVolume).clamp(
          0.0,
          1.0,
        ),
        desktopAsked: j['desktopAsked'] as bool? ?? d.desktopAsked,
        tray: j['tray'] as bool? ?? d.tray,
        launchAtLogin: j['login'] as bool? ?? d.launchAtLogin,
      );
    } catch (_) {
      return const PrayerSettings();
    }
  }
}
