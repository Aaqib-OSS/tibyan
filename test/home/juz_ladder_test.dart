import 'package:flutter_test/flutter_test.dart';
import 'package:tibyan/features/hifz/hifz_providers.dart';

void main() {
  // Two verses in juz 1, four in juz 30.
  const verses = [
    ('1:1', 1, 1),
    ('1:2', 2, 1),
    ('114:1', 3, 30),
    ('114:2', 4, 30),
    ('114:3', 5, 30),
    ('114:4', 6, 30),
  ];

  test('empty: every juz is empty', () {
    final l = juzLadder(verses, {}, {});
    expect(l.memorized, everyElement(0));
    expect(l.mastered, everyElement(0));
    expect(l.memorized.length, 30);
  });

  test('shares per juz from the memorized and mastered sets', () {
    final l = juzLadder(verses, {'1:1', '114:1', '114:2'}, {3});
    expect(l.memorized[0], .5);
    expect(l.memorized[29], .5);
    expect(l.mastered[29], .25);
    expect(l.mastered[0], 0);
    expect(l.memorized[14], 0);
  });
}
