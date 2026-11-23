import 'package:flutter_test/flutter_test.dart';
import 'package:tibyan/features/content_extras/tafsir_library.dart';

void main() {
  test('every library book covers 85% of the Quran, or is an exception', () {
    for (final s in tafsirLibraryPacks) {
      expect(s.verses, isNotNull, reason: s.id);
      expect(
        s.verses! >= 5301 || lowCoverageAllowed.contains(s.id),
        isTrue,
        reason: '${s.id}: ${s.verses}',
      );
    }
    final ids = tafsirLibraryPacks.map((s) => s.id).toSet();
    expect(ids, containsAll(lowCoverageAllowed));
    expect(ids, containsAll(['tafsir-qp-347', 'tafsir-qp-520']));
    // Dropped: Sufyan al-Thawri, Mujahid, al-Farra, Ibn Abi Hatim.
    for (final gone in [
      'tafsir-qp-27758',
      'tafsir-qp-269',
      'tafsir-qp-351',
      'tafsir-qp-149',
    ]) {
      expect(ids, isNot(contains(gone)));
    }
  });
}
