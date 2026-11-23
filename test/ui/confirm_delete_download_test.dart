import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tibyan/core/ui/confirm_delete_download.dart';
import 'package:tibyan/l10n/app_localizations.dart';

/// Opens the shared dialog for [file] and taps [tap]; the file is removed
/// only when the reader confirms, as every delete entry point does.
Future<void> _ask(
  WidgetTester tester,
  Locale locale,
  File file,
  String tap,
) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            if (await confirmDeleteDownload(
              context,
              name: 'تفسير سفيان الثوري',
              bytes: 12500000,
            )) {
              file.deleteSync();
            }
          },
          child: const Text('go'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
  expect(find.byType(AlertDialog), findsOneWidget);
  await tester.tap(find.text(tap));
  await tester.pumpAndSettle();
  expect(find.byType(AlertDialog), findsNothing);
}

void main() {
  late Directory dir;
  late File file;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('confirm-delete');
    file = File('${dir.path}/pack.db')..writeAsStringSync('x');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  testWidgets('cancel keeps the file', (tester) async {
    await _ask(tester, const Locale('ar'), file, 'إلغاء');
    expect(file.existsSync(), isTrue);
  });

  testWidgets('delete removes the file', (tester) async {
    await _ask(tester, const Locale('ar'), file, 'حذف');
    expect(file.existsSync(), isFalse);
  });

  testWidgets('Arabic title, size and body', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                confirmDeleteDownload(context, name: 'X', bytes: 12500000),
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('حذف «X»؟'), findsOneWidget);
    expect(
      find.textContaining('سيُحذف من جهازك ويمكنك تنزيله مرة أخرى في أي وقت.'),
      findsOneWidget,
    );
    expect(find.textContaining('ميجا'), findsOneWidget);
  });

  testWidgets('English buttons', (tester) async {
    await _ask(tester, const Locale('en'), file, 'Cancel');
    expect(file.existsSync(), isTrue);
  });
}
