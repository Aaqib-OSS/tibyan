import 'package:flutter/material.dart';

import '../../features/mushaf/presentation/widgets/illuminated_frame.dart'
    show NumberFormatter;
import '../../l10n/app_localizations.dart';

/// [bytes] as the app writes a size («١٢٫٥ ميجا»).
String downloadSizeLabel(BuildContext context, int bytes) {
  final l = AppLocalizations.of(context);
  final digits = NumberFormatter(Localizations.localeOf(context));
  return l.storageSize(
    digits.decimal((bytes / 1e6).toStringAsFixed(bytes < 1e7 ? 1 : 0)),
  );
}

/// The app's one «delete this download?» dialog, for every downloaded
/// content (tafsir and book packs, mushaf editions, recitations, the
/// adhan, the tasmee model…). Cancel is the default; true only when the
/// reader chose «حذف».
Future<bool> confirmDeleteDownload(
  BuildContext context, {
  required String name,
  int? bytes,
}) async {
  final l = AppLocalizations.of(context);
  final body = [
    if (bytes != null && bytes > 0)
      l.deleteDownloadSize(downloadSizeLabel(context, bytes)),
    l.deleteDownloadBody,
  ].join('\n');
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      return AlertDialog(
        key: const ValueKey('confirm-delete-download'),
        title: Text(l.deleteDownloadTitle(name)),
        content: Text(body),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.delete),
          ),
        ],
      );
    },
  );
  return ok ?? false;
}
