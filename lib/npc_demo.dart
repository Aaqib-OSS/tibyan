// TEMPORARY screenshot harness, not committed.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import 'core/settings/settings_controller.dart';
import 'features/home/next_prayer_card.dart';
import 'features/prayer/domain/prayer_calc.dart';
import 'features/prayer/domain/prayer_settings.dart';
import 'features/prayer/prayer_providers.dart';
import 'l10n/app_localizations.dart';

const cairo = PrayerPlace(
  name: 'Cairo',
  arabicName: 'القاهرة',
  country: 'EG',
  lat: 30.044,
  lon: 31.236,
  timeZone: 'Africa/Cairo',
);
const s = PrayerSettings(enabled: true, place: cairo);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();
  SharedPreferences.setMockInitialValues({prayerSettingsKey: s.encode()});
  final sp = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(sp)],
      child: const Demo(),
    ),
  );
}

class Demo extends StatefulWidget {
  const Demo({super.key});
  @override
  State<Demo> createState() => _DemoState();
}

class _DemoState extends State<Demo> {
  late final Timer t;
  int get idx => (DateTime.now().second ~/ 6) % 10;
  @override
  void initState() {
    super.initState();
    t = Timer.periodic(const Duration(milliseconds: 250), (_) => setState(() {}));
  }

  @override
  Widget build(BuildContext context) {
    final i = idx;
    final dark = i >= 5;
    final p = obligatoryPrayers[i % 5];
    final day = computeDay(cairo, DateTime(2026, 11, 24), s);
    final fake = day[p].subtract(const Duration(minutes: 23, seconds: 40));
    final drift = DateTime.now().difference(DateTime.now().copyWith(millisecond: 0, microsecond: 0));
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF8B5A2B)),
      darkTheme: ThemeData(colorSchemeSeed: const Color(0xFF8B5A2B), brightness: Brightness.dark),
      home: Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: ListTile(
                  title: const Text('مسيرة الحفظ'),
                  subtitle: const Text('محفوظ ١١٢ آية، منها ١٨ متقنة'),
                ),
              ),
              const SizedBox(height: 16),
              NextPrayerCard(key: ValueKey(p), clock: () => fake.add(drift)),
            ],
          ),
        ),
      ),
    );
  }
}
