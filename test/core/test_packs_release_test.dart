import 'package:flutter_test/flutter_test.dart';
import 'package:tibyan/core/testing/test_packs.dart';

void main() {
  test('release builds hide every test draft by default', () {
    expect(testPacksEnabled(release: true, forced: false), isFalse);
    expect(testPacksEnabled(release: true, forced: true), isTrue);
    expect(testPacksEnabled(release: false, forced: false), isTrue);
  });

  test('the constant follows the same rule as the build', () {
    // Tests run as a debug build, so the drafts are listed here.
    expect(
      includeTestPacks,
      testPacksEnabled(
        release: const bool.fromEnvironment('dart.vm.product'),
        forced: const bool.fromEnvironment('TEST_PACKS'),
      ),
    );
  });
}
