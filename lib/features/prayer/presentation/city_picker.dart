import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_toast.dart';
import '../../../core/ui/look_kit.dart';
import '../../../core/ui/responsive.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/prayer_settings.dart';
import '../prayer_providers.dart';
import 'prayer_enable.dart';

/// Where the times are for: «حدّد موقعي» (one coarse fix) or a city from
/// the offline list. Pops with the chosen [PrayerPlace].
class CityPickerScreen extends ConsumerStatefulWidget {
  const CityPickerScreen({super.key});

  @override
  ConsumerState<CityPickerScreen> createState() => _CityPickerScreenState();
}

class _CityPickerScreenState extends ConsumerState<CityPickerScreen> {
  String _query = '';
  bool _locating = false;

  Future<void> _locate() async {
    final l = AppLocalizations.of(context);
    setState(() => _locating = true);
    final place = await locateMe(ref);
    if (!mounted) return;
    setState(() => _locating = false);
    if (place == null) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(appToast(content: Text(l.prayerLocateFailed)));
      return;
    }
    Navigator.pop(context, place);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens.colors;
    final arabic = l.localeName == 'ar';
    final list = ref.watch(cityListProvider).value;
    final results = list?.search(_query) ?? const <PrayerPlace>[];
    return LookScaffold(
      maxWidth: ContentWidth.text,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            LookTopBar(title: l.prayerChooseCity),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: FilledButton.tonalIcon(
                key: const ValueKey('prayer-locate'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: _locating ? null : _locate,
                icon: _locating
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location),
                label: Text(l.prayerLocateMe),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                l.prayerLocateNote,
                textAlign: TextAlign.center,
                style: TextStyle(color: t.muted, fontSize: 13),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                key: const ValueKey('prayer-city-search'),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: l.prayerSearchCity,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: list == null
                  ? const Center(child: CircularProgressIndicator())
                  : results.isEmpty
                  ? Center(child: Text(l.prayerNoCity))
                  : ListView.builder(
                      itemCount: results.length,
                      itemBuilder: (context, i) {
                        final c = results[i];
                        final country = list.countries[c.country] ?? c.country;
                        return ListTile(
                          minTileHeight: 56,
                          title: Text(c.label(arabic)),
                          subtitle: Text(
                            arabic && c.arabicName.isNotEmpty
                                ? '${c.name} · $country'
                                : country,
                          ),
                          onTap: () => Navigator.pop(context, c),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
