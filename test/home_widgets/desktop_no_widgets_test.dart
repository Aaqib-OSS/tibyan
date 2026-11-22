// Windows and Linux have no home screen widgets: no `home_widget` call may
// run there (MissingPluginException on `home_widget/updates`, Windows 10,
// 0.8.6+52), and «الودجات» is not offered in the settings.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tibyan/features/khatma/services/home_widget_sync.dart';
import 'package:tibyan/features/settings/settings_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('widgets on Android, iOS and macOS only', () {
    expect(homeWidgetsSupported(TargetPlatform.android, false), isTrue);
    expect(homeWidgetsSupported(TargetPlatform.iOS, false), isTrue);
    expect(homeWidgetsSupported(TargetPlatform.macOS, false), isTrue);
    expect(homeWidgetsSupported(TargetPlatform.windows, false), isFalse);
    expect(homeWidgetsSupported(TargetPlatform.linux, false), isFalse);
    expect(homeWidgetsSupported(TargetPlatform.android, true), isFalse);
  });

  test('the plugin on Android and iOS, the app channel on macOS', () {
    expect(
      homeWidgetSyncFor(TargetPlatform.android, false),
      isA<PluginHomeWidgetSync>(),
    );
    expect(
      homeWidgetSyncFor(TargetPlatform.iOS, false),
      isA<PluginHomeWidgetSync>(),
    );
    expect(
      homeWidgetSyncFor(TargetPlatform.macOS, false),
      isA<MacHomeWidgetSync>(),
    );
    expect(
      homeWidgetSyncFor(TargetPlatform.windows, false),
      isA<NoHomeWidget>(),
    );
    expect(homeWidgetSyncFor(TargetPlatform.linux, false), isA<NoHomeWidget>());
    expect(
      homeWidgetSyncFor(TargetPlatform.android, true),
      isA<NoHomeWidget>(),
    );
  });

  for (final p in [TargetPlatform.windows, TargetPlatform.linux]) {
    test('the plugin sync never calls home_widget on ${p.name}', () async {
      debugDefaultTargetPlatformOverride = p;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final calls = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(const MethodChannel('home_widget'), (
        c,
      ) async {
        calls.add(c.method);
        return null;
      });
      messenger.setMockStreamHandler(
        const EventChannel('home_widget/updates'),
        MockStreamHandler.inline(onListen: (_, _) => calls.add('listen')),
      );
      addTearDown(() {
        messenger.setMockMethodCallHandler(
          const MethodChannel('home_widget'),
          null,
        );
        messenger.setMockStreamHandler(
          const EventChannel('home_widget/updates'),
          null,
        );
      });

      final sync = PluginHomeWidgetSync();
      await sync.writeVerses({'a': 'b'});
      await sync.writeLooks({'a': 'b'});
      await sync.saveFile('k', Uint8List(1), 'png');
      expect(await sync.launchUri(), isNull);
      expect(await sync.takePending(), isEmpty);
      await sync.taps.toList();
      expect(calls, isEmpty);
    });

    test('no widgets settings group on ${p.name}', () {
      debugDefaultTargetPlatformOverride = p;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final ids = [
        for (final s in SettingsSection.values)
          for (final g in s.groups)
            for (final e in g.entries) e.id,
      ];
      expect(ids, isNot(contains('homeWidgets')));
    });
  }

  test('the widgets settings group on Android', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final ids = [
      for (final s in SettingsSection.values)
        for (final g in s.groups)
          for (final e in g.entries) e.id,
    ];
    expect(ids, contains('homeWidgets'));
  });
}
