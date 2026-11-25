import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tibyan/features/home/back_twice_to_exit.dart';
import 'package:tibyan/l10n/app_localizations.dart';

/// Android: the first Back on home shows a toast; a second within 2 s
/// exits. Screens over home still pop to it.
void main() {
  late List<String> calls;
  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          calls.add(call.method);
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  final navKey = GlobalKey<NavigatorState>();
  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      navigatorKey: navKey,
      locale: const Locale('ar'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const BackTwiceToExit(child: Scaffold(body: Text('home'))),
    ),
  );

  int pops() => calls.where((m) => m == 'SystemNavigator.pop').length;
  const toast = 'اضغط رجوع مرة أخرى للخروج';

  testWidgets('android: back, toast; back again within 2 s exits; resets '
      'after 2 s', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await pump(tester);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text(toast), findsOneWidget);
    expect(pops(), 0);
    expect(find.text('home'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(pops(), 1);

    // After the window the first Back only warns again.
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2100));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(pops(), 1);
    expect(find.text(toast), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('android: a screen over home pops back to home', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await pump(tester);
    navKey.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const Text('over')),
    );
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    expect(find.text(toast), findsNothing);
    expect(pops(), 0);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('other platforms are unchanged', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await pump(tester);
    expect(find.byType(PopScope), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });
}
