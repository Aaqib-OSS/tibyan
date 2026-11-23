import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/settings/app_settings.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/ui/app_toast.dart';
import '../../core/ui/meta_separator.dart';
import '../../l10n/app_localizations.dart';
import '../mushaf/data/page_pack.dart';
import '../mushaf/mushaf_providers.dart';
import '../mushaf/presentation/widgets/illuminated_frame.dart'
    show NumberFormatter;
import 'credits.dart';
import 'english_tafsir.dart';
import 'tafsir_library_specs.dart';

/// The Quranpedia dump version the packs were built from
/// (tools/build_quranpedia_tafsir_packs.py).
const quranpediaDumpVersion = '2026-11-23';

/// «الجامع الوجيز» (CC BY-ND 4.0), built by tools/build_wajiz_pack.py.
const jamiWajizPack = TafsirTextPackSpec(
  id: 'tafsir-jami-wajiz-v1',
  url: 'https://altibyan.app/mirror/packs/tafsir/tafsir-jami-wajiz-v1.pack.db',
  sha256: '99a203e8bdb8a8859719056b2203b61fc908d6cc3f4c1a0fd3bddc2253149557',
  bytes: 18075648,
  title: 'الجامع الوجيز في تفسير آي الكتاب العزيز',
  author: 'د. أيمن فاتح آل عامر',
);

/// The Arabic tafsir packs the reader can download (the tafsir library):
/// al-Jami' al-Wajiz, then the classical books from Quranpedia by the
/// author's death year.
const tafsirLibraryPacks = <TafsirTextPackSpec>[
  jamiWajizPack,
  ...quranpediaTafsirPacks,
];

/// The library's sources as About › Sources lists them.
const tafsirLibrarySources = [
  (
    key: ContentSources.jamiWajiz,
    url: 'https://github.com/yamanamr/quran-tafsir-jami-wajiz',
    version: '1.0',
  ),
  (
    key: ContentSources.quranpedia,
    url: 'https://quranpedia.net',
    version: quranpediaDumpVersion,
  ),
];

/// The settings key of a library pack (shared with the book tafsirs'
/// hidden set, so every tafsir is shown until the reader hides it).
String tafsirPackKey(TafsirTextPackSpec spec) => 'pack:${spec.id}';

/// The library packs the app knows (overridden in tests).
final tafsirLibrarySpecsProvider = Provider<List<TafsirTextPackSpec>>(
  (ref) => tafsirLibraryPacks,
);

/// An installed library pack, opened.
typedef InstalledTafsirPack = ({TafsirTextPackSpec spec, TafsirTextPack pack});

/// Installed library packs, opened, in library order. A pack that does not
/// open (damaged, or of a newer format) is left out.
final installedTafsirPacksProvider = Provider<List<InstalledTafsirPack>>((ref) {
  ref.watch(packInstallsProvider);
  final root = ref.watch(packsDirProvider);
  final out = <InstalledTafsirPack>[];
  for (final spec in ref.watch(tafsirLibrarySpecsProvider)) {
    final installer = tafsirTextInstaller(root, spec);
    if (!installer.isInstalled) continue;
    try {
      final pack = TafsirTextPack.open(
        File(p.join(installer.dir.path, bookPackFile)),
      );
      ref.onDispose(pack.close);
      out.add((spec: spec, pack: pack));
    } on Object {
      // Not shown.
    }
  }
  return out;
});

/// Downloads of the library packs, by pack id.
class TafsirLibraryDownloads extends Notifier<Map<String, PackProgress>> {
  StreamSubscription<(String, PackProgress)>? _sub;

  @override
  Map<String, PackProgress> build() {
    ref.onDispose(() => _sub?.cancel());
    final ids = {for (final s in ref.watch(tafsirLibrarySpecsProvider)) s.id};
    if (ids.isEmpty) return const {};
    _sub = ref.read(backgroundPacksProvider).progress.listen((e) {
      if (!ids.contains(e.$1)) return;
      state = {...state, e.$1: e.$2};
      if (e.$2.phase == PackPhase.installed) {
        ref.read(packInstallsProvider.notifier).changed();
      }
    });
    return const {};
  }

  Future<void> start(TafsirTextPackSpec spec, String notification) async {
    state = {
      ...state,
      spec.id: PackProgress(PackPhase.downloading, total: spec.bytes),
    };
    await ref.read(backgroundPacksProvider).enqueue(spec.pack, notification);
  }

  /// Removes an installed pack from the device.
  Future<void> remove(TafsirTextPackSpec spec) async {
    final dir = tafsirTextInstaller(ref.read(packsDirProvider), spec).dir;
    if (await dir.exists()) await dir.delete(recursive: true);
    state = {...state}..remove(spec.id);
    ref.read(packInstallsProvider.notifier).changed();
  }
}

final tafsirLibraryDownloadsProvider =
    NotifierProvider<TafsirLibraryDownloads, Map<String, PackProgress>>(
      TafsirLibraryDownloads.new,
    );

/// A pack's text as drawn: Quranpedia's passages carry HTML markup (verse
/// quotes, references); the tags are dropped and the entities read, the
/// words left as they are.
String tafsirPackDisplayText(String text, {required bool html}) {
  if (!html) return text;
  return text
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');
}

/// The credit line under a library pack's text.
String tafsirPackCredit(TafsirTextPack pack, String languageCode) {
  final line = contentCredit(pack.source, languageCode, version: pack.version);
  final author = pack.meta['author'];
  return [
    pack.title,
    if (author != null && author.isNotEmpty) author,
    line,
  ].join(' · ');
}

/// The tafsir of a (Hafs) verse from an installed library pack, with its
/// credit line.
class TafsirPackCard extends ConsumerWidget {
  const TafsirPackCard({
    super.key,
    required this.pack,
    required this.surah,
    required this.ayah,
  });

  final TafsirTextPack pack;
  final int surah;
  final int ayah;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = pack.entry(surah, ayah);
    if (entry == null) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final t = context.tokens.colors;
    final settings = ref.watch(settingsProvider);
    final languageCode = Localizations.localeOf(context).languageCode;
    final family = settings.tafsirFont == TafsirFont.naskh
        ? 'UthmanTahaNaskh'
        : settings.uiFont.family;
    final text = tafsirPackDisplayText(
      entry.text,
      html: pack.meta['markup'] == 'html',
    );
    final credit = tafsirPackCredit(pack, languageCode);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: t.bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    pack.title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: t.ink,
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: l.copyText,
                icon: Icon(Icons.copy, size: 18, color: t.muted),
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: '$text\n\n${plainMeta(credit)}'),
                  );
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context)
                      .showSnackBar(appToast(content: Text(l.copied)));
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            text,
            textDirection: TextDirection.rtl,
            textAlign: TextAlign.justify,
            style: TextStyle(
              fontFamily: family,
              fontSize: 19 * settings.tafsirFontScale,
              height: 1.9,
              color: t.ink,
            ),
          ),
          const SizedBox(height: 10),
          MetaText(
            credit,
            textDirection: TextDirection.rtl,
            style: TextStyle(fontSize: 11, color: t.muted),
          ),
        ],
      ),
    );
  }
}

/// Opens the tafsir library: every pack with its size, to download or
/// delete.
Future<void> showTafsirLibrary(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const TafsirLibrarySheet(),
    );

class TafsirLibrarySheet extends ConsumerWidget {
  const TafsirLibrarySheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = context.tokens.colors;
    final locale = Localizations.localeOf(context);
    final digits = NumberFormatter(locale);
    final specs = ref.watch(tafsirLibrarySpecsProvider);
    final installed = {
      for (final i in ref.watch(installedTafsirPacksProvider)) i.spec.id,
    };
    final progress = ref.watch(tafsirLibraryDownloadsProvider);
    final downloads = ref.read(tafsirLibraryDownloadsProvider.notifier);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      l.tafsirLibrary,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Text(l.tafsirLibraryHint, style: TextStyle(color: t.muted)),
                ],
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: specs.length,
                itemBuilder: (context, i) {
                  final s = specs[i];
                  final have = installed.contains(s.id);
                  final phase = progress[s.id]?.phase ?? PackPhase.idle;
                  final busy =
                      !have &&
                      (phase == PackPhase.downloading ||
                          phase == PackPhase.verifying ||
                          phase == PackPhase.installing);
                  final size = l.storageSize(
                    digits.decimal(
                      (s.bytes / 1e6).toStringAsFixed(s.bytes < 1e7 ? 1 : 0),
                    ),
                  );
                  final status = have
                      ? l.tafsirPackInstalled
                      : switch (phase) {
                          PackPhase.downloading => l.semanticPackDownloading(
                            digits(
                              ((progress[s.id]?.fraction ?? 0) * 100).round(),
                            ),
                          ),
                          PackPhase.verifying ||
                          PackPhase.installing => l.semanticPackVerifying,
                          PackPhase.failed => l.semanticPackFailed,
                          _ => size,
                        };
                  final author = s.author == null
                      ? null
                      : s.diedAh == null
                      ? s.author!
                      : l.tafsirLibraryAuthor(s.author!, digits(s.diedAh!));
                  return ListTile(
                    key: ValueKey('tafsir-library-${s.id}'),
                    title: Text(s.title),
                    subtitle: Semantics(
                      liveRegion: busy,
                      child: Text(
                        [?author, status].join('\n'),
                        style: TextStyle(color: t.muted),
                      ),
                    ),
                    isThreeLine: author != null,
                    trailing: busy
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        : have
                        ? IconButton(
                            tooltip: l.tafsirPackDeleteLabel(s.title),
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => downloads.remove(s),
                          )
                        : IconButton(
                            tooltip: l.tafsirPackDownloadLabel(s.title),
                            icon: const Icon(Icons.download_outlined),
                            onPressed: () => downloads.start(
                              s,
                              l.tafsirPackDownloadLabel(s.title),
                            ),
                          ),
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
