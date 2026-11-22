import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../../../core/platform/app_store.dart';
import '../../../core/ui/responsive.dart';
import 'prayer_native.dart';

/// The desktop side of prayer times: a tray icon (closing the window keeps
/// the app there, so the tray can play the full adhan) and launch at
/// login. Both are asked for when prayer times are switched on.
class PrayerDesktop with TrayListener, WindowListener {
  PrayerDesktop(this.native);

  final PrayerNative native;
  bool _tray = false;
  bool _listening = false;

  /// The tray menu's labels, in the interface language.
  ({String show, String stop, String quit}) labels = (
    show: 'Show',
    stop: 'Stop',
    quit: 'Quit',
  );

  /// Tray title shown on hover.
  String tooltip = 'Tibyan';

  static bool get supported => isDesktopPlatform;

  /// Shows or removes the tray icon; with it, closing the window hides it.
  Future<void> setTray(bool on) async {
    if (!supported || on == _tray) return;
    _tray = on;
    try {
      if (on) {
        await trayManager.setIcon(
          Platform.isWindows
              ? 'assets/prayer/tray.ico'
              : 'assets/prayer/tray.png',
        );
        if (!Platform.isLinux) await trayManager.setToolTip(tooltip);
        await _menu();
        if (!_listening) {
          trayManager.addListener(this);
          windowManager.addListener(this);
          _listening = true;
        }
        await windowManager.setPreventClose(true);
      } else {
        await trayManager.destroy();
        // macOS keeps its own hide-on-close (DesktopWindow).
        if (!Platform.isMacOS) await windowManager.setPreventClose(false);
      }
    } catch (_) {
      _tray = false;
    }
  }

  Future<void> _menu() => trayManager.setContextMenu(
    Menu(
      items: [
        MenuItem(key: 'show', label: labels.show),
        MenuItem(key: 'stop', label: labels.stop),
        MenuItem.separator(),
        MenuItem(key: 'quit', label: labels.quit),
      ],
    ),
  );

  /// Refreshes the menu after the language changed.
  Future<void> relabel() async {
    if (_tray) await _menu();
  }

  @override
  void onTrayIconMouseDown() => unawaited(_show());

  @override
  void onTrayIconRightMouseDown() => unawaited(trayManager.popUpContextMenu());

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        unawaited(_show());
      case 'stop':
        unawaited(native.stop());
      case 'quit':
        unawaited(_quit());
    }
  }

  @override
  void onWindowClose() {
    // With the tray on, the window hides and the app stays to play the
    // adhan (macOS hides it already).
    if (_tray && !Platform.isMacOS) unawaited(windowManager.hide());
  }

  Future<void> _show() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _quit() async {
    await trayManager.destroy();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  /// Starts the app when the user logs in (hidden in the tray).
  Future<bool> setLaunchAtLogin(bool on) async {
    if (!supported) return false;
    try {
      if (Platform.isMacOS) return await native.setMacLoginItem(on);
      final exe = Platform.resolvedExecutable;
      if (Platform.isWindows && appStore == 'msstore') {
        // The Store package declares a StartupTask (pubspec msix_config):
        // Windows runs it at login; the user manages it in Task Manager.
        return true;
      }
      if (Platform.isWindows) {
        const key = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
        final r = on
            ? await Process.run('reg', [
                'add',
                key,
                '/v',
                'Tibyan',
                '/t',
                'REG_SZ',
                '/d',
                '"$exe" --tray',
                '/f',
              ])
            : await Process.run('reg', ['delete', key, '/v', 'Tibyan', '/f']);
        return r.exitCode == 0;
      }
      // Linux: an XDG autostart entry.
      final home = Platform.environment['HOME'];
      if (home == null) return false;
      final config =
          Platform.environment['XDG_CONFIG_HOME'] ?? p.join(home, '.config');
      final file = File(p.join(config, 'autostart', 'app.tibyan.desktop'));
      if (on) {
        await file.parent.create(recursive: true);
        await file.writeAsString(
          '[Desktop Entry]\nType=Application\nName=Tibyan\n'
          'Exec="$exe" --tray\nX-GNOME-Autostart-enabled=true\n',
        );
      } else if (await file.exists()) {
        await file.delete();
      }
      return true;
    } catch (e) {
      debugPrint('launch at login: $e');
      return false;
    }
  }
}
