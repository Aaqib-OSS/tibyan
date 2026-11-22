import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs before every test file. The connectivity plugin has no native side
/// in tests, so its channels answer as if on Wi‑Fi; tests that need another
/// network state set their own handlers.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel('dev.fluttercommunity.plus/connectivity'),
    (call) async => call.method == 'check' ? <String>['wifi'] : null,
  );
  // The status stream: «listen» and «cancel» succeed, and no event comes.
  messenger.setMockMethodCallHandler(
    const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
    (_) async => null,
  );
  await testMain();
}
