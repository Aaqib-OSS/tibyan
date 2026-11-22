import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/settings_controller.dart';
import 'data/cities.dart';
import 'domain/prayer_settings.dart';

/// The preferences key of [PrayerSettings].
const prayerSettingsKey = 'prayer.settings.v1';

/// «مواقيت الصلاة»: every choice, kept on the device.
class PrayerSettingsController extends Notifier<PrayerSettings> {
  @override
  PrayerSettings build() => PrayerSettings.decode(
    ref.read(sharedPreferencesProvider).getString(prayerSettingsKey),
  );

  Future<void> update(PrayerSettings Function(PrayerSettings) change) async {
    state = change(state);
    await ref
        .read(sharedPreferencesProvider)
        .setString(prayerSettingsKey, state.encode());
  }

  /// [p]'s own adhan, or null for «حسب الإعدادات العامة».
  Future<void> setCustom(PrayerKind p, PrayerAdhan? c) => update(
    (x) => x.copyWith(
      custom: {...x.custom}
        ..remove(p)
        ..addAll({p: ?c}),
    ),
  );

  /// [p]'s sound; the rest of its own setup stays.
  Future<void> setSound(PrayerKind p, AlertSound s) => update(
    (x) => x.copyWith(
      custom: {
        ...x.custom,
        p: (x.custom[p] ?? const PrayerAdhan()).copyWith(sound: s),
      },
    ),
  );

  Future<void> setReminder(PrayerKind p, int minutes) =>
      update((x) => x.copyWith(reminders: {...x.reminders, p: minutes}));

  Future<void> setOffset(PrayerKind p, int minutes) => update(
    (x) => x.copyWith(
      offsets: {
        ...x.offsets,
        p: minutes.clamp(-PrayerSettings.maxOffset, PrayerSettings.maxOffset),
      },
    ),
  );

  /// «تطبيق على كل الصلوات»: [p]'s adhan setup and reminder for all five.
  Future<void> applyToAll(PrayerKind p) => update(
    (x) => x.copyWith(
      custom: {for (final q in obligatoryPrayers) q: ?x.custom[p]},
      reminders: {for (final q in obligatoryPrayers) q: x.reminderOf(p)},
    ),
  );
}

final prayerSettingsProvider =
    NotifierProvider<PrayerSettingsController, PrayerSettings>(
      PrayerSettingsController.new,
    );

/// The offline city list, read once from the app's assets.
final cityListProvider = FutureProvider<CityList>((ref) => CityList.load());
