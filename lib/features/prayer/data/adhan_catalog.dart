import 'package:flutter/foundation.dart';

/// Where the adhan recordings are kept: one folder per muezzin with
/// `full.m4a`, `short.m4a` (up to «حي على الصلاة», under 30 s),
/// `short.caf` (the same cut as PCM, the Apple notification sound) and
/// `photo.jpg`; `extras/` holds the after-prayer dua. One `SHA256SUMS`
/// lists every file. Nothing is bundled with the app.
const adhanBaseUrl = 'https://tibyan.ahmedhelal.dev/mirror/packs/adhan/v1';

/// The licence of every recording in the library.
const adhanLicense = 'CC BY-NC-SA 4.0';
const adhanLicenseUrl = 'https://creativecommons.org/licenses/by-nc-sa/4.0/';

@immutable
class Muezzin {
  const Muezzin(this.slug, this.arabic, this.english);

  /// The folder on the server.
  final String slug;
  final String arabic;
  final String english;

  String name(bool arabicUi) => arabicUi ? arabic : english;
}

/// The library, in the order shown. Names as the recordings' folders give
/// them; Sheikh Muhammad Refaat is the default.
const muezzins = [
  Muezzin('refaat', 'محمد رفعت', 'Muhammad Refaat'),
  Muezzin('ali_mahmoud', 'علي محمود', 'Ali Mahmoud'),
  Muezzin('minshawi', 'محمد صديق المنشاوي', 'Muhammad Siddiq al-Minshawi'),
  Muezzin('mm_ramadan', 'محمد محمود رمضان', 'Muhammad Mahmoud Ramadan'),
  Muezzin('mustafa_ismail', 'مصطفى إسماعيل', 'Mustafa Ismail'),
  Muezzin('abdulbasit', 'عبد الباسط عبد الصمد', 'Abdul Basit Abdul Samad'),
  Muezzin('bahtimi', 'كامل يوسف البهتيمي', 'Kamel Youssef al-Bahtimi'),
  Muezzin('tobar', 'نصر الدين طوبار', 'Nasr al-Din Tobar'),
  Muezzin('fashni', 'طه الفشني', 'Taha al-Fashni'),
  Muezzin('banna', 'محمود علي البنا', 'Mahmoud Ali al-Banna'),
  Muezzin('omran', 'محمد عمران', 'Muhammad Omran'),
  Muezzin('gazy', 'محمد جازي', 'Muhammad Gazy'),
  Muezzin('ali_mulla', 'أحمد علي ملا', 'Ahmed Ali Mulla'),
];

Muezzin muezzinOf(String slug) =>
    muezzins.firstWhere((m) => m.slug == slug, orElse: () => muezzins.first);

/// The files a muezzin's download fetches. The Apple platforms take the
/// PCM cut for their notification sound; the others play the m4a cut.
List<String> adhanFilesFor({required bool apple}) => [
  'full.m4a',
  'short.m4a',
  if (apple) 'short.caf',
  'photo.jpg',
];

/// The after-prayer dua (Sheikh al-Sha'rawi), downloaded with the first
/// adhan when the reader turns it on.
const duaSlug = 'extras';
List<String> duaFilesFor({required bool apple}) => [
  'dua_shaarawy.m4a',
  if (apple) 'dua_shaarawy.caf',
];

/// Parses a `SHA256SUMS` file: `<hex>  <path>` per line.
Map<String, String> parseSums(String text) {
  final out = <String, String>{};
  for (final line in text.split('\n')) {
    final m = RegExp(r'^([0-9a-fA-F]{64})\s+\*?(.+)$').firstMatch(line.trim());
    if (m != null) out[m.group(2)!.trim()] = m.group(1)!.toLowerCase();
  }
  return out;
}
