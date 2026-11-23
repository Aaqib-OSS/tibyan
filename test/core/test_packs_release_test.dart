import 'package:flutter_test/flutter_test.dart';
import 'package:tibyan/core/testing/test_packs.dart';

void main() {
  test('every build lists the packs, release included', () {
    expect(includeTestPacks, isTrue);
    expect(testPacksEnabled(release: true, forced: false), isTrue);
  });

  test('no title says «مسودة للاختبار»', () {
    for (final s in testBookPacks) {
      expect(s.title, isNot(contains('مسودة')), reason: s.title);
    }
    for (final s in testEnglishTafsirPacks) {
      expect(s.title, isNot(contains('draft')), reason: s.title);
    }
  });
}
