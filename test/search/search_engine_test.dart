import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tibyan/core/db/content_database.dart';
import 'package:tibyan/features/search/search_engine.dart';

/// A verse as stored in content.db: the printed text (with diacritics and
/// Quranic marks), the search text (Tanzil Simple Clean) and its juz.
typedef DbVerse = ({
  int surah,
  int ayah,
  int juz,
  String display,
  String plain,
});

/// Every Quran text in these tests is read from content.db; none is typed.
void main() {
  late List<DbVerse> rows;
  late List<SearchVerse> verses;

  setUpAll(() async {
    final db = ContentDatabase(
      NativeDatabase(
        File('assets/db/content.db'),
        setup: (raw) => raw.execute('PRAGMA query_only = ON'),
      ),
    );
    final result = await db
        .customSelect(
          'SELECT surah, number, juz, display_text, text_search, '
          'search_basmala_prefix FROM ayah ORDER BY id',
        )
        .get();
    await db.close();
    rows = [
      for (final r in result)
        (
          surah: r.read<int>('surah'),
          ayah: r.read<int>('number'),
          juz: r.read<int>('juz'),
          display: r.read<String>('display_text'),
          plain: r
              .read<String>('text_search')
              .substring(r.read<int>('search_basmala_prefix')),
        ),
    ];
    verses = [
      for (final r in rows) SearchVerse(r.surah, r.ayah, r.plain, juz: r.juz),
    ];
  });

  DbVerse verse(int surah, int ayah) =>
      rows.firstWhere((r) => r.surah == surah && r.ayah == ayah);

  /// The printed words of a verse, without the hizb sign.
  List<String> printed(DbVerse v) => v.display
      .split(RegExp(r'\s+'))
      .where((w) => RegExp('[\u0621-\u064A\u0671]').hasMatch(w))
      .toList();

  test('diacritics and common spelling differences are ignored', () {
    // The printed words of Ayat al-Kursi fold to its plain words, apart
    // from the Uthmani spellings (a dagger alif for a full one).
    final v = verse(2, 255);
    final a = printed(v);
    final b = v.plain.split(' ');
    expect(a.length, b.length);
    var same = 0;
    for (var i = 0; i < a.length; i++) {
      if (normalize(a[i]) == normalize(b[i])) same++;
    }
    expect(same, greaterThan(a.length * 0.9));
    // Every folded word of the whole text is free of the folded letters.
    for (final v in verses) {
      expect(v.folded, isNot(matches(RegExp('[أإآٱىةؤئـً-ٟ]'))));
    }
  });

  test('references by numbers or by name', () {
    final names = {
      1: ['الفاتحة', 'Al-Faatiha'],
      2: ['البقرة', 'Al-Baqara'],
      36: ['يس', 'Yaseen'],
    };
    expect(parseReference('2:255', names), (surah: 2, ayah: 255));
    expect(parseReference('٢:٢٥٥', names), (surah: 2, ayah: 255));
    expect(parseReference('2 255', names), (surah: 2, ayah: 255));
    expect(parseReference('البقرة 255', names), (surah: 2, ayah: 255));
    expect(parseReference('سورة البقرة', names), (surah: 2, ayah: null));
    expect(parseReference('بقره ٢٥٥', names), (surah: 2, ayah: 255));
    expect(parseReference('al-baqara 3', names), (surah: 2, ayah: 3));
    expect(parseReference('يس', names), (surah: 36, ayah: null));
    // A verse's words are not a reference.
    expect(parseReference(verse(1, 3).plain, names), isNull);
    expect(parseReference('200:1', names), isNull);
  });

  test('search over the whole Quran text', () {
    expect(verses.length, 6236);

    // Five words of Ayat al-Kursi, plain or as printed.
    final kursi = verse(2, 255);
    final plain = kursi.plain.split(' ').sublist(3, 8).join(' ');
    expect(
      search(verses, plain).map((h) => (h.surah, h.ayah)),
      contains((2, 255)),
    );
    final shown = printed(kursi).sublist(3, 6).join(' ');
    expect(
      search(verses, shown).map((h) => (h.surah, h.ayah)),
      contains((2, 255)),
    );

    // Every hit really contains the query (al-Fatiha 3, found in many).
    final query = verse(1, 3).plain;
    final hits = search(verses, query);
    expect(hits.length, greaterThan(1));
    for (final h in hits) {
      final v = verses.firstWhere(
        (v) => v.surah == h.surah && v.ayah == h.ayah,
      );
      expect(v.folded, contains(normalize(query)));
      expect(h.words, isNotEmpty);
      expect(h.words.every((i) => i < v.words.length), isTrue);
    }
    // Too short to search.
    expect(search(verses, verse(1, 3).plain.substring(0, 1)), isEmpty);
  });

  test('a scope keeps the search to a surah or a juz', () {
    // The first word of al-Fatiha 2 (the divine name), found all over.
    final word = verse(1, 2).plain.split(' ')[1];
    final all = searchIn(verses, word, const WholeMushaf());
    expect(all.length, greaterThan(100));
    final inSurah = searchIn(verses, word, const InSurah(3));
    expect(inSurah, isNotEmpty);
    expect(inSurah.every((h) => h.surah == 3), isTrue);
    final inJuz = searchIn(verses, word, const InJuz(3));
    expect(inJuz, isNotEmpty);
    expect(inJuz.every((h) => verse(h.surah, h.ayah).juz == 3), isTrue);
    expect(inJuz.length + inSurah.length, lessThan(all.length * 2));
  });
}
