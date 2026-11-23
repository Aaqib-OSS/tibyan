import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../khatma/domain/khatmah.dart' show EntryPoint;
import '../mushaf_providers.dart';

var _visit = 0;

/// Placed over the index when another screen (the tafsir) opens it to
/// choose a verse: a chosen surah, verse or page goes to [onPick] instead
/// of opening the mushaf.
class IndexPickScope extends InheritedWidget {
  const IndexPickScope({super.key, required this.onPick, required super.child});

  /// Receives the chosen verse (Hafs numbers).
  final void Function(int surah, int ayah) onPick;

  static IndexPickScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<IndexPickScope>();

  @override
  bool updateShouldNotify(IndexPickScope old) => false;
}

/// The page view's location for [page] (and a verse to select). Each call
/// gives a new location: going to the one already open would otherwise
/// do nothing, though the reader may have turned the page since.
///
/// [entry] says where the reading was opened from (the khatma's reading
/// tracker counts only what comes after the page a search landed on).
String mushafLocation(
  int page, {
  int? surah,
  int? ayah,
  EntryPoint entry = EntryPoint.other,
}) =>
    '/mushaf?page=$page'
    '${surah == null || ayah == null ? '' : '&s=$surah&a=$ayah'}'
    '${entry == EntryPoint.other ? '' : '&entry=${entry.name}'}'
    '&v=${++_visit}';

/// Opens a verse in the page view. Navigation only turns the page; it
/// never selects a verse.
Future<void> openVerse(
  BuildContext context,
  WidgetRef ref, {
  required int surah,
  required int ayah,
  EntryPoint entry = EntryPoint.other,
}) async {
  final pick = IndexPickScope.maybeOf(context);
  if (pick != null) {
    pick.onPick(surah, ayah);
    return;
  }
  // [surah]:[ayah] is in Hafs numbers; a riwaya edition opens the page of
  // the riwaya verse that holds it.
  final page = await ref.read(versePageProvider((surah, ayah)).future);
  if (!context.mounted) return;
  context.go(mushafLocation(page, entry: entry));
}

/// Where a `tibyan://verse` link (a shared verse, «آية اليوم» on the home
/// screen) opens: the page holding [surah]:[ayah] (Hafs numbers) in the
/// edition being read, 1441, 1405 or a riwaya's, with the verse named;
/// [listen]: and recited from it.
Future<String> verseLinkLocation(
  ProviderContainer container,
  int surah,
  int ayah, {
  bool listen = false,
}) async {
  final at = mushafLocation(
    await container.read(versePageProvider((surah, ayah)).future),
    surah: surah,
    ayah: ayah,
  );
  return listen ? '$at&listen=1' : at;
}

/// Opens a page of the edition being read.
Future<void> openPage(BuildContext context, WidgetRef ref, int page) async {
  final pick = IndexPickScope.maybeOf(context);
  if (pick != null) {
    final ayahs = await ref.read(pageAyahsProvider(page).future);
    if (ayahs.isEmpty || !context.mounted) return;
    pick.onPick(ayahs.first.surah, ayahs.first.number);
    return;
  }
  context.go(mushafLocation(page));
}

/// A link to a verse (Hafs numbers) that opens the app on it:
/// `tibyan://verse?s=2&a=255`.
Uri verseLink(int surah, int ayah) => Uri(
  scheme: 'tibyan',
  host: 'verse',
  queryParameters: {'s': '$surah', 'a': '$ayah'},
);

/// The source attached to a Khatma link when opening the reader.
EntryPoint khatmaEntryOfLink(Uri uri) {
  if (uri.queryParameters.containsKey('homeWidget') || uri.host == 'action') {
    return EntryPoint.widget;
  }
  if (uri.host == 'khatmah' || uri.host == 'reader') {
    return EntryPoint.khatmahContinue;
  }
  if (uri.host == 'khatma') return EntryPoint.notification;
  return EntryPoint.other;
}

/// Whether a `tibyan://verse` link asks for the verse to be recited
/// (`listen=1`: «استمع» on the «آية اليوم» widget).
bool verseLinkListens(Uri uri) => uri.queryParameters['listen'] == '1';

/// The verse a `tibyan://verse` link names, if it is one and is valid.
({int surah, int ayah})? verseOfLink(Uri? uri) {
  if (uri == null || uri.scheme != 'tibyan' || uri.host != 'verse') return null;
  final s = int.tryParse(uri.queryParameters['s'] ?? '');
  final a = int.tryParse(uri.queryParameters['a'] ?? '');
  if (s == null || a == null || s < 1 || s > 114 || a < 1 || a > 286) {
    return null;
  }
  return (surah: s, ayah: a);
}
