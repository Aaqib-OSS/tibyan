import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tibyan/core/ui/look_kit.dart';
import 'package:tibyan/features/search/search_screen.dart';

import '../tasmee/tasmee_test_env.dart';

/// The search field stays pinned over the results; the scope filter is an
/// icon in the field's row and opens the scope chooser.
void main() {
  late TasmeeTestData data;
  setUpAll(() => data = TasmeeTestData.open());
  tearDownAll(() => data.close());

  Future<void> pump(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(390, 700)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = await tasmeeContainer(tester, data);
    await tester.pumpWidget(
      tasmeeApp(
        container,
        const LookTheme(child: SearchScreen()),
        theme: tasmeeTheme(container),
      ),
    );
    await settle(tester);
  }

  testWidgets('field pinned; scope is an icon beside it', (tester) async {
    await pump(tester);
    final field = find.byType(TextField);
    final scope = find.byKey(const ValueKey('search-scope'));
    expect(scope, findsOneWidget);
    // Same row as the field, and no text label.
    expect(
      (tester.getCenter(scope).dy - tester.getCenter(field).dy).abs(),
      lessThan(12),
    );
    expect(
      find.descendant(of: scope, matching: find.text('كل المصحف')),
      findsNothing,
    );
    expect(find.byTooltip('النطاق: كل المصحف'), findsOneWidget);

    await tester.enterText(field, 'الله');
    await tester.pump(const Duration(milliseconds: 300));
    await settle(tester);
    final before = tester.getTopLeft(field);
    await tester.drag(find.byType(ListView).first, const Offset(0, -500));
    await tester.pump();
    expect(tester.getTopLeft(field), before);
    expect(field.hitTestable(), findsOneWidget);

    await tester.tap(scope);
    await settle(tester);
    expect(find.byType(DraggableScrollableSheet), findsOneWidget);
    expect(find.text('كل المصحف'), findsWidgets);
  });
}
