import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:tibyan/core/settings/app_settings.dart';

void main() {
  test('a chosen language wins', () {
    expect(
      resolveAppLocale(const Locale('en'), device: const [Locale('ar')]),
      const Locale('en'),
    );
  });

  test('«device language» on an English device is English, not Arabic '
      '(notification buttons came out half Arabic)', () {
    expect(
      resolveAppLocale(null, device: const [Locale('en', 'US')]),
      const Locale('en'),
    );
  });

  test('the first supported device language is used', () {
    expect(
      resolveAppLocale(null, device: const [Locale('fr'), Locale('ar', 'EG')]),
      const Locale('ar'),
    );
  });

  test('no Arabic or English on the device: Arabic', () {
    expect(
      resolveAppLocale(null, device: const [Locale('fr')]),
      const Locale('ar'),
    );
  });
}
