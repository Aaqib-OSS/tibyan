import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Morning (الصباح) or evening (المساء).
enum AdhkarTime { morning, evening }

/// One dhikr exactly as Seen-Arabic's Morning-And-Evening-Adhkar-DB
/// publishes it (assets/adhkar, commit 39d422fb3e3a). Nothing here is
/// edited or written by the app.
@immutable
class AdhkarItem {
  const AdhkarItem({
    required this.order,
    required this.content,
    required this.count,
    required this.countDescription,
    required this.fadl,
    required this.source,
    required this.type,
    this.translation,
    this.transliteration,
  });

  final int order;
  final String content;
  final int count;
  final String countDescription;
  final String fadl;
  final String source;

  /// 0: morning and evening, 1: morning only, 2: evening only.
  final int type;
  final String? translation;
  final String? transliteration;

  bool isFor(AdhkarTime t) =>
      type == 0 || (t == AdhkarTime.morning ? type == 1 : type == 2);

  static String _s(Object? v) => v is String ? v : '';

  factory AdhkarItem.fromJson(Map<String, dynamic> j) => AdhkarItem(
    order: (j['order'] as num).toInt(),
    content: _s(j['content']),
    count: (j['count'] as num?)?.toInt() ?? 1,
    countDescription: _s(j['count_description']),
    fadl: _s(j['fadl']),
    source: _s(j['source']),
    type: (j['type'] as num?)?.toInt() ?? 0,
    translation: j['translation'] as String?,
    transliteration: j['transliteration'] as String?,
  );
}

/// Entries left out of the screen, by their published `order`. The bundled
/// files stay byte-for-byte as published; only the display skips these.
/// 29 (the salawat ten times): its source grades the hadith weak («ضعيف
/// الترغيب»), so it is left out, as in the misbaha.
const excludedAdhkarOrders = {29};

List<AdhkarItem> parseAdhkar(String json) => [
  for (final e in jsonDecode(json) as List)
    AdhkarItem.fromJson(e as Map<String, dynamic>),
]..sort((a, b) => a.order.compareTo(b.order));

/// The items of [time] for the interface language: Arabic from `ar.json`;
/// English from `en.json` (the same Arabic text with its published
/// translation, transliteration, fadl and source).
Future<List<AdhkarItem>> loadAdhkar(
  String languageCode,
  AdhkarTime time,
) async {
  final file = languageCode == 'ar' ? 'ar' : 'en';
  final all = parseAdhkar(
    await rootBundle.loadString('assets/adhkar/$file.json'),
  );
  return [
    for (final a in all)
      if (a.isFor(time) && !excludedAdhkarOrders.contains(a.order)) a,
  ];
}

final adhkarProvider =
    FutureProvider.family<List<AdhkarItem>, (String, AdhkarTime)>(
      (ref, k) => loadAdhkar(k.$1, k.$2),
    );
