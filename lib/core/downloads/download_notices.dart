import 'dart:async';

import 'package:flutter/foundation.dart';

/// One «download finished / failed» notice: what the toast says.
@immutable
class DownloadNotice {
  const DownloadNotice({
    required this.failed,
    required this.count,
    required this.names,
    this.retry,
  });

  /// True for «تعذّر تنزيل …», false for «اكتمل تنزيل …».
  final bool failed;

  /// How many downloads the notice covers.
  final int count;

  /// Their distinct names, in order (several surahs of one reciter share
  /// a name).
  final List<String> names;

  /// Queues the failed downloads again, when they can be.
  final VoidCallback? retry;
}

/// Gathers download completions and failures into few toasts: those that
/// end within [window] of each other (the window starts again with each,
/// up to [maxWait]) make ONE notice; failures make one of their own.
/// While the app is in the background the notices wait, and go out as one
/// each when it comes back.
class DownloadNotices {
  DownloadNotices({
    this.window = const Duration(seconds: 3),
    this.maxWait = const Duration(seconds: 15),
  });

  final Duration window;
  final Duration maxWait;

  void Function(DownloadNotice notice)? _show;

  /// Shows notices from now on (set by the app once its toasts can be
  /// shown); those already due go out at once.
  void attach(void Function(DownloadNotice notice)? show) {
    _show = show;
    foreground = _foreground;
  }

  bool _foreground = true;
  final _done = _Batch();
  final _failed = _Batch();

  /// A download finished and is installed.
  void completed(String name) => _add(_done, name);

  /// Several that finished while the app was closed: one summary.
  void completedWhileAway(Iterable<String> names) {
    for (final n in names) {
      _add(_done, n);
    }
  }

  /// A download failed for good; [retry] queues it again.
  void failed(String name, {VoidCallback? retry}) {
    if (retry != null) _failed.retries.add(retry);
    _add(_failed, name);
  }

  /// The app came to the foreground (true) or left it.
  set foreground(bool value) {
    _foreground = value;
    if (value) {
      for (final b in [_done, _failed]) {
        if (b.ready) _flush(b);
      }
    }
  }

  void _add(_Batch b, String name) {
    b.count++;
    if (!b.names.contains(name)) b.names.add(name);
    b.ready = false;
    void due() {
      b.timer?.cancel();
      b.cap?.cancel();
      b.cap = null;
      b.ready = true;
      if (_foreground) _flush(b);
    }

    b.timer?.cancel();
    b.timer = Timer(window, due);
    b.cap ??= Timer(maxWait, due);
  }

  void _flush(_Batch b) {
    final show = _show;
    if (b.count == 0 || show == null) return;
    final retries = [...b.retries];
    show(
      DownloadNotice(
        failed: identical(b, _failed),
        count: b.count,
        names: [...b.names],
        retry: retries.isEmpty
            ? null
            : () {
                for (final r in retries) {
                  r();
                }
              },
      ),
    );
    b.clear();
  }

  void dispose() {
    _done.timer?.cancel();
    _failed.timer?.cancel();
    _done.cap?.cancel();
    _failed.cap?.cancel();
  }
}

class _Batch {
  int count = 0;
  final names = <String>[];
  final retries = <VoidCallback>[];
  Timer? cap;
  Timer? timer;
  bool ready = false;

  void clear() {
    count = 0;
    names.clear();
    retries.clear();
    cap = null;
    timer = null;
    ready = false;
  }
}
