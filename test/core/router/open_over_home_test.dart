import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tibyan/core/router/app_router.dart' show openOverHome;

/// A screen opened from outside the app (a notification, the adhan, a
/// widget, a link) has home underneath: a back button, and back returns
/// home instead of closing the app.
void main() {
  GoRouter router() => GoRouter(
    initialLocation: '/splash',
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const Text('splash')),
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: Text('home')),
      ),
      for (final p in ['/prayer', '/downloads', '/khatma/report', '/mushaf'])
        GoRoute(
          path: p,
          builder: (_, s) => Scaffold(appBar: AppBar(), body: Text(s.uri.path)),
        ),
    ],
  );

  for (final (entry, location) in [
    ('the adhan’s «فتح المواقيت»', '/prayer'),
    ('a download’s notification', '/downloads'),
    ('the weekly report reminder', '/khatma/report'),
    ('a widget tap or verse link', '/mushaf?page=3'),
  ]) {
    testWidgets('$entry opens over home', (tester) async {
      final r = router();
      addTearDown(r.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: r));
      await tester.pumpAndSettle();

      final done = openOverHome(r, location);
      await tester.pumpAndSettle();
      await done;
      await tester.pumpAndSettle();

      final path = Uri.parse(location).path;
      expect(find.text(path), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);
      expect(r.canPop(), isTrue);

      // The system back gesture: home, not out of the app.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
      expect(r.canPop(), isFalse);
    });
  }
}
