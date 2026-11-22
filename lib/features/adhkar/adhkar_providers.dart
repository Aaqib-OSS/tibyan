import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/settings_controller.dart';
import 'data/adhkar_data.dart';
import 'domain/adhkar_settings.dart';

const adhkarSettingsKey = 'adhkar.settings.v1';
const adhkarProgressKey = 'adhkar.progress.v1';

class AdhkarSettingsController extends Notifier<AdhkarSettings> {
  @override
  AdhkarSettings build() => AdhkarSettings.decode(
    ref.read(sharedPreferencesProvider).getString(adhkarSettingsKey),
  );

  Future<void> update(AdhkarSettings Function(AdhkarSettings) change) async {
    state = change(state);
    await ref
        .read(sharedPreferencesProvider)
        .setString(adhkarSettingsKey, state.encode());
  }
}

final adhkarSettingsProvider =
    NotifierProvider<AdhkarSettingsController, AdhkarSettings>(
      AdhkarSettingsController.new,
    );

String _today(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Today's counts, by time and item order; a new day starts at zero.
typedef AdhkarCounts = Map<AdhkarTime, Map<int, int>>;

class AdhkarProgressController extends Notifier<AdhkarCounts> {
  /// The clock (tests).
  static DateTime Function() now = DateTime.now;

  @override
  AdhkarCounts build() {
    final raw = ref
        .read(sharedPreferencesProvider)
        .getString(adhkarProgressKey);
    final empty = {for (final t in AdhkarTime.values) t: <int, int>{}};
    if (raw == null) return empty;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      if (j['date'] != _today(now())) return empty;
      return {
        for (final t in AdhkarTime.values)
          t: {
            for (final e in ((j[t.name] as Map?) ?? const {}).entries)
              int.parse('${e.key}'): (e.value as num).toInt(),
          },
      };
    } catch (_) {
      return empty;
    }
  }

  Future<void> _save() => ref
      .read(sharedPreferencesProvider)
      .setString(
        adhkarProgressKey,
        jsonEncode({
          'date': _today(now()),
          for (final t in AdhkarTime.values)
            t.name: {for (final e in state[t]!.entries) '${e.key}': e.value},
        }),
      );

  /// One more of [item], up to its count. Returns the new count.
  Future<int> tap(AdhkarTime t, AdhkarItem item) async {
    final cur = state[t]![item.order] ?? 0;
    if (cur >= item.count) return cur;
    state = {
      ...state,
      t: {...state[t]!, item.order: cur + 1},
    };
    await _save();
    return cur + 1;
  }

  Future<void> reset(AdhkarTime t) async {
    state = {...state, t: <int, int>{}};
    await _save();
  }
}

final adhkarProgressProvider =
    NotifierProvider<AdhkarProgressController, AdhkarCounts>(
      AdhkarProgressController.new,
    );
