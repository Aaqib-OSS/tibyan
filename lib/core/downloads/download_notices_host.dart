import 'package:flutter/material.dart';

import '../../features/mushaf/presentation/widgets/illuminated_frame.dart'
    show NumberFormatter;
import '../../l10n/app_localizations.dart';
import '../ui/app_toast.dart';
import 'download_notices.dart';

/// The app's messenger, for toasts raised outside any screen.
final appMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// The text of [n]: names when there are one or two, else the count.
String downloadNoticeText(
  AppLocalizations l,
  NumberFormatter digits,
  DownloadNotice n,
) {
  final names = n.names;
  if (names.length == 1) {
    return n.failed
        ? l.downloadFailedOne(names[0])
        : l.downloadDoneOne(names[0]);
  }
  if (names.length == 2) {
    return n.failed
        ? l.downloadFailedTwo(names[0], names[1])
        : l.downloadDoneTwo(names[0], names[1]);
  }
  final count = digits.decimal('${n.count}');
  return n.failed
      ? l.downloadFailedMany(n.count, count)
      : l.downloadDoneMany(n.count, count);
}

/// Shows [notices] as the app's toasts while the app is in the
/// foreground; those due while it was away go out when it comes back.
class DownloadNoticesHost extends StatefulWidget {
  const DownloadNoticesHost({
    super.key,
    required this.notices,
    required this.child,
    this.messengerKey,
  });

  final DownloadNotices notices;
  final GlobalKey<ScaffoldMessengerState>? messengerKey;
  final Widget child;

  @override
  State<DownloadNoticesHost> createState() => _DownloadNoticesHostState();
}

class _DownloadNoticesHostState extends State<DownloadNoticesHost>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.notices.attach(_show);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.notices.attach(null);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    widget.notices.foreground = state == AppLifecycleState.resumed;
  }

  void _show(DownloadNotice n) {
    final messenger = (widget.messengerKey ?? appMessengerKey).currentState;
    if (messenger == null || !mounted) return;
    final l = AppLocalizations.of(context);
    final digits = NumberFormatter(Localizations.localeOf(context));
    final retry = n.retry;
    messenger.showSnackBar(
      appToast(
        content: Text(
          downloadNoticeText(l, digits, n),
          key: const ValueKey('download-notice'),
        ),
        // Four seconds, with a retry or without.
        duration: kToastDuration,
        action: retry == null
            ? null
            : SnackBarAction(label: l.downloadRetry, onPressed: retry),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
