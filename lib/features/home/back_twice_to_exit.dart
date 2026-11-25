import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/ui/app_toast.dart';
import '../../l10n/app_localizations.dart';

/// How long a second Back still exits after the first.
const kBackToExitWindow = Duration(seconds: 2);

/// On Android, when home is the root with nothing under it, the first Back
/// shows a toast and only a second one within [kBackToExitWindow] exits.
/// Other platforms, and home with something to pop, are unchanged.
class BackTwiceToExit extends StatefulWidget {
  const BackTwiceToExit({super.key, required this.child});

  final Widget child;

  @override
  State<BackTwiceToExit> createState() => _BackTwiceToExitState();
}

class _BackTwiceToExitState extends State<BackTwiceToExit> {
  /// Running while a second Back exits.
  Timer? _window;

  @override
  void dispose() {
    _window?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final guard =
        defaultTargetPlatform == TargetPlatform.android &&
        !(Navigator.maybeOf(context)?.canPop() ?? false);
    if (!guard) return widget.child;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_window?.isActive ?? false) {
          _window!.cancel();
          SystemNavigator.pop();
          return;
        }
        _window = Timer(kBackToExitWindow, () {});
        final messenger = ScaffoldMessenger.maybeOf(context);
        messenger?.hideCurrentSnackBar();
        messenger?.showSnackBar(
          appToast(
            content: Text(AppLocalizations.of(context).backAgainToExit),
            duration: kBackToExitWindow,
          ),
        );
      },
      child: widget.child,
    );
  }
}
