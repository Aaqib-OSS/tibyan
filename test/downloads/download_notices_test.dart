import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tibyan/core/downloads/download_notices.dart';
import 'package:tibyan/core/downloads/download_notices_host.dart';
import 'package:tibyan/l10n/app_localizations.dart';

void main() {
  test('several completions in the window make one notice', () {
    fakeAsync((async) {
      final shown = <DownloadNotice>[];
      final n = DownloadNotices()..attach(shown.add);
      for (var i = 0; i < 5; i++) {
        n.completed('item $i');
        async.elapse(const Duration(seconds: 1));
      }
      expect(shown, isEmpty, reason: 'the window grows while more finish');
      async.elapse(const Duration(seconds: 3));
      expect(shown, hasLength(1));
      expect(shown.single.count, 5);
      expect(shown.single.failed, isFalse);

      // A later one, after the window: a new notice.
      async.elapse(const Duration(seconds: 10));
      n.completed('تفسير سفيان الثوري');
      async.elapse(const Duration(seconds: 3));
      expect(shown, hasLength(2));
      expect(shown.last.names, ['تفسير سفيان الثوري']);
    });
  });

  test('failures get their own notice with a retry', () {
    fakeAsync((async) {
      final shown = <DownloadNotice>[];
      var retried = 0;
      final n = DownloadNotices()..attach(shown.add);
      n.completed('a');
      n.failed('b', retry: () => retried++);
      async.elapse(const Duration(seconds: 3));
      expect(shown, hasLength(2));
      final f = shown.firstWhere((s) => s.failed);
      expect(f.names, ['b']);
      f.retry!();
      expect(retried, 1);
    });
  });

  test('in the background notices wait, then go out as one', () {
    fakeAsync((async) {
      final shown = <DownloadNotice>[];
      final n = DownloadNotices()..attach(shown.add);
      n.foreground = false;
      n.completedWhileAway(['a', 'b', 'c']);
      n.completed('d');
      async.elapse(const Duration(seconds: 20));
      expect(shown, isEmpty);
      n.foreground = true;
      expect(shown, hasLength(1));
      expect(shown.single.count, 4);
    });
  });

  testWidgets('the toast text and its × close it', (tester) async {
    final notices = DownloadNotices();
    final key = GlobalKey<ScaffoldMessengerState>();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        scaffoldMessengerKey: key,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => DownloadNoticesHost(
          notices: notices,
          messengerKey: key,
          child: child!,
        ),
        home: const Scaffold(body: SizedBox()),
      ),
    );
    notices.completed('تفسير سفيان الثوري');
    notices.completed('تفسير سفيان الثوري');
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('اكتمل تنزيل «تفسير سفيان الثوري»'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('download-notice')), findsNothing);

    for (var i = 0; i < 5; i++) {
      notices.completed('item $i');
    }
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('اكتمل تنزيل ٥ عناصر'), findsOneWidget);
    // It goes by itself after about four seconds.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('download-notice')), findsNothing);
  });
}
