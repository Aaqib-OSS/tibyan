import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/settings_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/ui/confirm_delete_download.dart';
import '../../l10n/app_localizations.dart';
import '../books/books_providers.dart';
import '../books/data/book_pack.dart';
import '../mushaf/data/page_pack.dart';
import '../mushaf/mushaf_providers.dart';
import '../mushaf/presentation/background_downloads_list.dart' show DownloadRow;
import '../mushaf/presentation/widgets/illuminated_frame.dart'
    show NumberFormatter;
import 'english_tafsir.dart';
import 'tafsir_library.dart';

/// Which items the library page lists.
enum TafsirLibraryFilter { all, onDevice, available }

/// The sub-groups of «التفاسير ومعاني القرآن».
enum TafsirDownloadGroup { tafsir, sciences, translations }

/// One downloadable book of the section: a library pack, a reviewed book
/// pack or the English tafsir.
class TafsirDownloadItem {
  const TafsirDownloadItem({
    required this.id,
    required this.group,
    required this.title,
    required this.bytes,
    required this.pack,
    required this.installDir,
    required this.progress,
    required this.start,
    this.author,
    this.diedAh,
    this.showKey,
    this.quranpedia = false,
    this.coverage,
  });

  /// Verses it has a passage for, once installed (library packs).
  final int? coverage;

  final String id;
  final TafsirDownloadGroup group;
  final String title;
  final String? author;
  final int? diedAh;
  final int bytes;
  final PagePackSpec pack;
  final Directory installDir;

  /// Settings key of its show/hide switch (installed library packs).
  final String? showKey;

  /// A Quranpedia book (listed by its author's death century).
  final bool quranpedia;

  /// The download's state (installed when on the device).
  final PackProgress progress;
  final Future<void> Function() start;

  bool get installed => progress.phase == PackPhase.installed;
  bool get busy =>
      progress.phase == PackPhase.downloading ||
      progress.phase == PackPhase.verifying ||
      progress.phase == PackPhase.installing;
}

/// Every item of the section, in order, from the same providers the
/// tafsir screen and the library use (so both lists stay in step).
final tafsirDownloadItemsProvider = Provider<List<TafsirDownloadItem>>((ref) {
  ref.watch(packInstallsProvider);
  final root = ref.watch(packsDirProvider);
  final library = ref.watch(tafsirLibraryDownloadsProvider);
  final books = ref.watch(bookDownloadsProvider);
  final english = ref.watch(englishTafsirDownloadsProvider);
  final locale = ref.watch(settingsProvider.select((s) => s.locale));
  final l = lookupAppLocalizations(locale ?? const Locale('ar'));

  PackProgress state(PagePackInstaller i, PackProgress? p) => i.isInstalled
      ? const PackProgress(PackPhase.installed)
      : p ?? const PackProgress(PackPhase.idle);

  final opened = {
    for (final i in ref.watch(installedTafsirPacksProvider)) i.spec.id: i.pack,
  };
  final specs = ref.watch(tafsirLibrarySpecsProvider);
  final wajiz = [
    for (final s in specs)
      if (s.diedAh == null) s,
  ];
  final classical = [
    for (final s in specs)
      if (s.diedAh != null) s,
  ]..sort((a, b) => a.diedAh!.compareTo(b.diedAh!));
  final out = <TafsirDownloadItem>[];
  for (final s in [...wajiz, ...classical]) {
    final i = tafsirTextInstaller(root, s);
    out.add(
      TafsirDownloadItem(
        id: s.id,
        group: TafsirDownloadGroup.tafsir,
        title: s.title,
        author: s.author,
        diedAh: s.diedAh,
        bytes: s.bytes,
        pack: s.pack,
        installDir: i.dir,
        showKey: tafsirPackKey(s),
        quranpedia: s.diedAh != null,
        coverage: s.verses ?? opened[s.id]?.verseCount,
        progress: state(i, library[s.id]),
        start: () =>
            ref.read(tafsirLibraryDownloadsProvider.notifier).start(s, s.title),
      ),
    );
  }
  final bookSpecs = ref.watch(bookPackSpecsProvider);
  for (final kind in [
    BookKind.tafsir,
    BookKind.asbabNuzul,
    BookKind.munasabat,
    BookKind.wujuhNazair,
  ]) {
    for (final b in bookSpecs) {
      if (b.kind != kind) continue;
      final i = bookInstaller(root, b);
      out.add(
        TafsirDownloadItem(
          id: b.id,
          group: kind == BookKind.tafsir
              ? TafsirDownloadGroup.tafsir
              : TafsirDownloadGroup.sciences,
          title: b.title,
          bytes: b.bytes,
          pack: b.pack,
          installDir: i.dir,
          progress: state(i, books[b.id]),
          start: () => ref.read(bookDownloadsProvider.notifier).start(b),
        ),
      );
    }
  }
  for (final s in ref.watch(englishTafsirSpecsProvider)) {
    final i = tafsirTextInstaller(root, s);
    out.add(
      TafsirDownloadItem(
        id: s.id,
        group: TafsirDownloadGroup.translations,
        title: s.title,
        author: s.author,
        bytes: s.bytes,
        pack: s.pack,
        installDir: i.dir,
        progress: state(i, english[s.id]),
        start: () => ref
            .read(englishTafsirDownloadsProvider.notifier)
            .start(s, l.downloadItem(s.title)),
      ),
    );
  }
  return out;
});

/// Whether [item] matches the library's [query] and [filter].
bool tafsirItemMatches(
  TafsirDownloadItem item,
  String query,
  TafsirLibraryFilter filter,
) {
  final q = query.trim();
  if (q.isNotEmpty &&
      !item.title.contains(q) &&
      !(item.author?.contains(q) ?? false)) {
    return false;
  }
  return switch (filter) {
    TafsirLibraryFilter.all => true,
    TafsirLibraryFilter.onDevice => item.installed,
    TafsirLibraryFilter.available => !item.installed,
  };
}

/// «التفاسير ومعاني القرآن»: the tafsir library, the reviewed books and
/// the translations, each row with its size and state, to download,
/// cancel or delete. One widget for the downloads center and the
/// library page ([library]: with search, filter and show/hide switches).
class TafsirDownloadsSection extends ConsumerStatefulWidget {
  const TafsirDownloadsSection({super.key, this.library = false});

  final bool library;

  @override
  ConsumerState<TafsirDownloadsSection> createState() =>
      _TafsirDownloadsSectionState();
}

class _TafsirDownloadsSectionState
    extends ConsumerState<TafsirDownloadsSection> {
  String _query = '';
  TafsirLibraryFilter _filter = TafsirLibraryFilter.all;

  String _size(int bytes) => downloadSizeLabel(context, bytes);

  Future<void> _remove(TafsirDownloadItem item) async {
    if (!await confirmDeleteDownload(
      context,
      name: item.title,
      bytes: item.bytes,
    )) {
      return;
    }
    // A pack folder is one file and a stamp: removed at once.
    if (item.installDir.existsSync()) {
      item.installDir.deleteSync(recursive: true);
    }
    ref.read(packInstallsProvider.notifier).changed();
  }

  Future<void> _downloadAll(List<TafsirDownloadItem> items) async {
    final l = AppLocalizations.of(context);
    final digits = NumberFormatter(Localizations.localeOf(context));
    final todo = [
      for (final i in items)
        if (!i.installed && !i.busy) i,
    ];
    if (todo.isEmpty) return;
    final total = todo.fold<int>(0, (a, i) => a + i.bytes);
    // Large sets (the Quranpedia books are about 2 GB) ask first.
    if (todo.length > 1) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          key: const ValueKey('confirm-download-all'),
          title: Text(l.downloadAllConfirmTitle(digits(todo.length))),
          content: Text(l.downloadAllConfirmBody(_size(total))),
          actions: [
            TextButton(
              autofocus: true,
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l.downloadAllConfirmOk),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    for (final i in todo) {
      unawaited(i.start());
    }
  }

  Widget _header(
    String title,
    String key, {
    List<TafsirDownloadItem>? all,
    double size = 15,
  }) {
    final l = AppLocalizations.of(context);
    final t = context.tokens.colors;
    final missing = all?.any((i) => !i.installed && !i.busy) ?? false;
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: TextStyle(
                  color: t.goldText,
                  fontWeight: FontWeight.w700,
                  fontSize: size,
                ),
              ),
            ),
          ),
          if (missing)
            TextButton.icon(
              key: ValueKey('downloads-all-$key'),
              onPressed: () => _downloadAll(all!),
              icon: const Icon(Icons.download_outlined, size: 18),
              label: Text(l.downloadAllGroup),
            ),
        ],
      ),
    );
  }

  Widget _row(TafsirDownloadItem item) {
    final l = AppLocalizations.of(context);
    final digits = NumberFormatter(Localizations.localeOf(context));
    final settings = ref.watch(settingsProvider);
    final p = item.progress;
    final author = item.author == null
        ? null
        : item.diedAh == null
        ? item.author!
        : l.tafsirLibraryAuthor(item.author!, digits(item.diedAh!));
    final size = _size(item.bytes);
    final status = switch (p.phase) {
      PackPhase.installed => [l.libraryFilterOnDevice, size].join(' · '),
      PackPhase.downloading => l.semanticPackDownloading(
        digits((p.fraction * 100).round()),
      ),
      PackPhase.verifying || PackPhase.installing => l.downloadInstalling,
      PackPhase.failed => l.downloadFailed(p.error ?? ''),
      PackPhase.idle => '${l.libraryFilterAvailable} · $size',
    };
    final coverage = item.coverage == null
        ? null
        : item.coverage! >= 6236
        ? l.tafsirCoverageFull
        : l.tafsirCoverage(
            digits.decimal((item.coverage! * 100 / 6236).toStringAsFixed(1)),
          );
    final showKey = item.showKey;
    return DownloadRow(
      key: ValueKey('tafsir-item-${item.id}'),
      title: item.title,
      status: [
        ?author,
        [status, ?coverage].join(' · '),
      ].join('\n'),
      fraction: item.busy
          ? (p.phase == PackPhase.downloading ? p.fraction : null)
          : (item.installed ? 1 : 0),
      done: !item.busy,
      actions: [
        if (widget.library && item.installed && showKey != null)
          Switch(
            value: !settings.hiddenBookTafsirs.contains(showKey),
            onChanged: (v) => ref
                .read(settingsProvider.notifier)
                .setBookTafsirShown(showKey, v),
          ),
        if (item.installed)
          IconButton(
            tooltip: l.tafsirPackDeleteLabel(item.title),
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _remove(item),
          )
        else if (item.busy)
          IconButton(
            tooltip: l.downloadCancelItem(item.title),
            icon: const Icon(Icons.close),
            onPressed: () =>
                ref.read(backgroundPacksProvider).cancel(item.pack),
          )
        else
          IconButton(
            tooltip: l.downloadItem(item.title),
            icon: Icon(
              p.phase == PackPhase.failed
                  ? Icons.refresh
                  : Icons.download_outlined,
            ),
            onPressed: () => unawaited(item.start()),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final digits = NumberFormatter(Localizations.localeOf(context));
    final all = ref.watch(tafsirDownloadItemsProvider);
    final shown = [
      for (final i in all)
        if (!widget.library || tafsirItemMatches(i, _query, _filter)) i,
    ];
    List<TafsirDownloadItem> of(TafsirDownloadGroup g) => [
      for (final i in shown)
        if (i.group == g) i,
    ];
    final tafsir = of(TafsirDownloadGroup.tafsir);
    final sciences = of(TafsirDownloadGroup.sciences);
    final translations = of(TafsirDownloadGroup.translations);
    final quranpedia = [
      for (final i in tafsir)
        if (i.quranpedia) i,
    ];

    final children = <Widget>[];
    if (widget.library) {
      children
        ..add(
          TextField(
            key: const ValueKey('tafsir-library-search'),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: l.librarySearchHint,
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        )
        ..add(const SizedBox(height: 8))
        ..add(
          Wrap(
            spacing: 8,
            children: [
              for (final (f, label) in [
                (TafsirLibraryFilter.all, l.libraryFilterAll),
                (TafsirLibraryFilter.onDevice, l.libraryFilterOnDevice),
                (TafsirLibraryFilter.available, l.libraryFilterAvailable),
              ])
                ChoiceChip(
                  key: ValueKey('tafsir-library-filter-${f.name}'),
                  label: Text(label),
                  selected: _filter == f,
                  onSelected: (_) => setState(() => _filter = f),
                ),
            ],
          ),
        )
        ..add(const SizedBox(height: 8));
    }
    if (tafsir.isNotEmpty) {
      children.add(
        _header(
          l.downloadsGroupTafsir,
          'tafsir',
          // «تنزيل الكل» here takes the Quranpedia books (with their total
          // size) and the rest of the group.
          all: tafsir,
        ),
      );
      int? century;
      for (final i in tafsir) {
        if (i.quranpedia && quranpedia.length > 1) {
          final c = (i.diedAh! - 1) ~/ 100 + 1;
          if (c != century) {
            century = c;
            children.add(
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 4, top: 4),
                child: Semantics(
                  header: true,
                  child: Text(
                    l.downloadsCentury(digits(c)),
                    style: TextStyle(
                      fontSize: 13,
                      color: context.tokens.colors.muted,
                    ),
                  ),
                ),
              ),
            );
          }
        }
        children.add(_row(i));
      }
    }
    if (sciences.isNotEmpty) {
      children
        ..add(_header(l.downloadsGroupSciences, 'sciences', all: sciences))
        ..addAll(sciences.map(_row));
    }
    if (translations.isNotEmpty) {
      children
        ..add(
          _header(
            l.downloadsGroupTranslations,
            'translations',
            all: translations,
          ),
        )
        ..addAll(translations.map(_row));
    }
    if (widget.library && shown.isEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(l.libraryNoMatch, textAlign: TextAlign.center),
        ),
      );
    }
    return Column(
      key: const ValueKey('tafsir-downloads-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}
