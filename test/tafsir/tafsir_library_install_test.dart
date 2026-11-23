import 'package:flutter_test/flutter_test.dart';
import 'package:tibyan/features/content_extras/tafsir_library.dart';
import 'package:tibyan/features/mushaf/data/background_packs.dart';

void main() {
  test('every tafsir library pack is installable after its download', () {
    expect(tafsirLibraryPacks, isNotEmpty);
    for (final t in tafsirLibraryPacks) {
      expect(downloadablePackSpec(t.pack.id), isNotNull, reason: t.id);
    }
  });
}
