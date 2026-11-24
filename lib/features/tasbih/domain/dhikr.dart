import 'dart:convert';

import 'package:flutter/foundation.dart';

/// A dhikr the misbaha counts: one of the app's adhkar (from a licensed
/// source, copied verbatim with its reference) or one the reader added.
@immutable
class Dhikr {
  const Dhikr({
    required this.key,
    required this.text,
    this.reference,
    this.target,
    this.mine = false,
    this.stages = const [],
  });

  /// `app:<id>` or `user:<uuid>`: what the daily log is kept under.
  final String key;
  final String text;
  final String? reference;

  /// The suggested count to a round.
  final int? target;

  /// Added by the reader («من إضافتك»).
  final bool mine;

  /// Said in stages, one span of [text] after another (each its own
  /// count); empty for a dhikr said whole.
  final List<DhikrStage> stages;

  /// The counts of the stages, in order; null for a dhikr said whole.
  List<int>? get stageCounts =>
      stages.isEmpty ? null : [for (final s in stages) s.count];

  /// The uuid of the reader's own dhikr.
  String? get uuid => mine ? key.substring(5) : null;

  @override
  bool operator ==(Object other) =>
      other is Dhikr &&
      other.key == key &&
      other.text == text &&
      other.reference == reference &&
      other.target == target &&
      other.mine == mine &&
      listEquals(other.stages, stages);

  @override
  int get hashCode =>
      Object.hash(key, text, reference, target, mine, Object.hashAll(stages));
}

/// One stage of a dhikr said in stages: the characters [start]..[end] of
/// its text, said [count] times.
@immutable
class DhikrStage {
  const DhikrStage(this.start, this.end, this.count);

  final int start;
  final int end;
  final int count;

  @override
  bool operator ==(Object other) =>
      other is DhikrStage &&
      other.start == start &&
      other.end == end &&
      other.count == count;

  @override
  int get hashCode => Object.hash(start, end, count);
}

/// Where the app's adhkar come from (assets/tasbih/adhkar.json).
@immutable
class DhikrSource {
  const DhikrSource({
    required this.id,
    required this.url,
    required this.commit,
    required this.license,
  });

  final String id;
  final String url;
  final String commit;
  final String license;
}

/// Reads `assets/tasbih/adhkar.json`: its sources, and the adhkar copied
/// from them.
({List<DhikrSource> sources, List<Dhikr> adhkar}) parseAppAdhkar(String json) {
  final m = jsonDecode(json) as Map<String, Object?>;
  return (
    sources: [
      for (final s in (m['sources']! as List).cast<Map<String, Object?>>())
        DhikrSource(
          id: s['id']! as String,
          url: s['url']! as String,
          commit: s['commit']! as String,
          license: s['license']! as String,
        ),
    ],
    adhkar: [
      for (final e in (m['items']! as List).cast<Map<String, Object?>>())
        Dhikr(
          key: 'app:${e['id']}',
          text: e['text']! as String,
          reference: e['reference'] as String?,
          target: (e['count'] as num?)?.toInt(),
          stages: [
            for (final st
                in ((e['stages'] as List?) ?? const [])
                    .cast<Map<String, Object?>>())
              DhikrStage(
                (st['start']! as num).toInt(),
                (st['end']! as num).toInt(),
                (st['count']! as num).toInt(),
              ),
          ],
        ),
    ],
  );
}

/// «تسبيح ختام الصلاة», from the app's own staged dhikr (33, 33, 33, then
/// the closing tahlil): the 99 alone, cut from the source text verbatim
/// (its first three stages), and the full 100 as the source has it. Empty
/// when the data has no such dhikr.
({Dhikr ninetyNine, Dhikr hundred})? postPrayerTasbih(List<Dhikr> app) {
  final full = app
      .where((d) => !d.mine && listEquals(d.stageCounts, const [33, 33, 33, 1]))
      .firstOrNull;
  if (full == null) return null;
  final three = full.stages.take(3).toList();
  return (
    ninetyNine: Dhikr(
      key: '${full.key}.99',
      text: full.text.substring(0, three.last.end),
      reference: full.reference,
      target: 99,
      stages: three,
    ),
    hundred: full,
  );
}
