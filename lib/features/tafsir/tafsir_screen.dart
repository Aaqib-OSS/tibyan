import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/ui/app_toast.dart';

import '../../core/ui/look_kit.dart';
import '../../core/ui/share_text.dart';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/content_database.dart';
import '../../core/flags/feature_flags.dart';
import '../../core/settings/app_settings.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/mushaf_digits.dart';
import '../../l10n/app_localizations.dart';
import '../audio/player_bar.dart';
import '../audio/recitation.dart';
import '../books/books_providers.dart';
import '../books/data/book_pack.dart';
import '../books/presentation/asbab_section.dart';
import '../content_extras/english_tafsir.dart';
import '../content_extras/tafsir_library.dart';
import '../content_extras/tafsir_audio_button.dart';
import '../content_extras/verse_audio_index.dart';
import '../books/presentation/book_section.dart';
import '../mushaf/data/mushaf_repository.dart';
import '../mushaf/mushaf_providers.dart';
import '../mushaf/presentation/index_screen.dart';
import '../mushaf/presentation/mushaf_screen.dart';
import '../mushaf/presentation/navigation.dart';
import '../mushaf/presentation/widgets/illuminated_frame.dart';
import '../mushaf/presentation/widgets/mushaf_page.dart';
import 'kashida_text.dart';
import '../../core/ui/meta_separator.dart';

final commentaryEditionsProvider = FutureProvider<List<CommentaryEditionRow>>(
  (ref) => ref.watch(mushafRepositoryProvider).commentaryEditions(),
);

final verseCommentaryProvider =
    FutureProvider.family<Map<int, CommentaryRow>, VerseKey>(
      (ref, v) =>
          ref.watch(mushafRepositoryProvider).commentary(v.surah, v.ayah),
    );

/// Opens the tafsir from the mushaf in a half sheet that can be dragged
/// up to the full height, so the page stays in sight; while a recitation
/// plays, the sheet follows the verse being recited.
Future<void> showTafsirSheet(
  BuildContext context, {
  required int surah,
  required int ayah,
  Riwaya? riwaya,
  int? riwayaAyah,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  barrierColor: Colors.black26,
  builder: (_) => LookTheme(
    child: DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      minChildSize: 0.3,
      snap: true,
      snapSizes: const [0.55],
      builder: (context, controller) => TafsirScreen(
        surah: surah,
        ayah: ayah,
        riwaya: riwaya,
        riwayaAyah: riwayaAyah,
        sheetController: controller,
      ),
    ),
  ),
);

/// The tafsir settings: font, size and the texts shown.
Future<void> showTafsirSettings(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => LookTheme(
        child: Builder(builder: (_) => const _TafsirSettingsSheet()),
      ),
    );

/// Tafsir and translations of one verse; swipe or use the arrows to move
/// through the surah and on to the next one. Every text is shown exactly
/// as its source has it, with the source's credit under it.
class TafsirScreen extends ConsumerStatefulWidget {
  const TafsirScreen({
    super.key,
    required this.surah,
    required this.ayah,
    this.riwaya,
    this.riwayaAyah,
    this.sheetController,
  });

  /// The verse in Hafs numbers: tafsir and translations are keyed by them.
  final int surah;
  final int ayah;

  /// Opened from a riwaya edition: the riwaya and the verse's number
  /// there, named above the texts with the Hafs verses it matches.
  final Riwaya? riwaya;
  final int? riwayaAyah;

  /// Shown in the mushaf's half sheet ([showTafsirSheet]): the sheet's
  /// scroll controller. The sheet follows the recitation.
  final ScrollController? sheetController;

  @override
  ConsumerState<TafsirScreen> createState() => _TafsirScreenState();
}

class _TafsirScreenState extends ConsumerState<TafsirScreen> {
  late int _surah = widget.surah;
  late int _ayah = widget.ayah;
  late PageController _pages = PageController(initialPage: _pageOf(_ayah));

  /// A page before the first verse (from the second surah on) and one
  /// after the last (up to the 113th): landing there moves to the
  /// neighbouring surah.
  /// Opens the index to choose a verse; the choice stays in the tafsir.
  Future<void> _openIndex() async {
    final picked = await Navigator.of(context).push<(int, int)>(
      MaterialPageRoute(
        builder: (context) => IndexPickScope(
          onPick: (s, a) => Navigator.of(context).pop((s, a)),
          child: LookTheme(child: IndexScreen(surah: _surah)),
        ),
      ),
    );
    if (picked != null && mounted) _show(picked.$1, picked.$2);
  }

  int get _lead => _surah > 1 ? 1 : 0;
  late final _dragger = _PageDragger(() => _pages);
  int _pageOf(int ayah) => ayah - 1 + _lead;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  /// Leaving the tafsir: a tafsir read aloud from here stops with it, so
  /// no player is left over the mushaf.
  void _stopTafsirAudio() {
    final s = ref.read(recitationProvider);
    final clip = s.clip;
    if (s.active &&
        clip != null &&
        clip.standalone &&
        clip.kind == VerseAudioKind.tafsir) {
      ref.read(recitationProvider.notifier).stop();
    }
  }

  int _countOf(int surah) =>
      ref.read(surahsProvider).value?[surah - 1].ayahCount ?? 0;

  /// Shows [ayah] of [surah] (Hafs numbers).
  void _show(int surah, int ayah) {
    if (surah < 1 || surah > 114 || ayah < 1) return;
    if (surah == _surah) {
      if (!_pages.hasClients) return;
      final page = _pageOf(ayah);
      if ((ayah - _ayah).abs() == 1) {
        _pages.animateToPage(
          page,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      } else {
        _pages.jumpToPage(page);
      }
      setState(() => _ayah = ayah);
      return;
    }
    final old = _pages;
    setState(() {
      _surah = surah;
      _ayah = ayah;
      _pages = PageController(initialPage: _pageOf(ayah));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  void _next(int count) =>
      _ayah < count ? _show(_surah, _ayah + 1) : _show(_surah + 1, 1);

  void _previous() => _ayah > 1
      ? _show(_surah, _ayah - 1)
      : _show(_surah - 1, _countOf(_surah - 1));

  /// A swipe that settled on the page past either end of the surah.
  bool _onScrollEnd(ScrollEndNotification n, int count) {
    if (n.depth != 0 || n.metrics.axis != Axis.horizontal) return false;
    final page = _pages.hasClients ? _pages.page?.round() : null;
    if (page == null) return false;
    if (_lead == 1 && page == 0) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _show(_surah - 1, _countOf(_surah - 1)),
      );
    } else if (page == count + _lead) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _show(_surah + 1, 1));
    }
    return false;
  }

  /// «اذهب لآية»: a verse of the current surah.
  Future<void> _pickVerse(int count) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => LookTheme(
        child: _VersePicker(count: count, current: _ayah),
      ),
    );
    if (picked != null && mounted) _show(_surah, picked);
  }

  /// The sheet follows the verse being recited (in the edition's numbers,
  /// so a riwaya's verse goes to the first Hafs verse it covers).
  void _follow(RecitationState? prev, RecitationState s) {
    final a = s.ayah;
    if (!s.active || s.foreign || a == null) return;
    if (s.clip?.standalone ?? false) return;
    if (prev != null && prev.surah == s.surah && prev.ayah == a) return;
    final h = hafsKeyOf(ref.read(riwayaDataProvider).value, (
      surah: s.surah,
      ayah: a,
    ));
    if (h.surah != _surah || h.ayah != _ayah) _show(h.surah, h.ayah);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens.colors;
    final digits = NumberFormatter(Localizations.localeOf(context));
    final sheet = widget.sheetController;
    if (sheet != null) ref.listen(recitationProvider, _follow);
    final surah = ref.watch(surahsProvider).value?[_surah - 1];
    final ayahs = ref.watch(surahAyahsProvider(_surah)).value;
    final count = surah?.ayahCount ?? 0;
    final atStart = _surah == 1 && _ayah == 1;
    final atEnd = _surah == 114 && _ayah >= count;

    final bottomBar = SafeArea(
      top: false,
      child: Row(
        children: [
          IconButton(
            tooltip: l.previousVerse,
            onPressed: atStart || count == 0 ? null : _previous,
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Center(
              heightFactor: 1,
              child: Semantics(
                button: true,
                liveRegion: true,
                label: l.verseCounter(digits(_ayah), digits(count)),
                hint: l.tafsirGoToVerse,
                excludeSemantics: true,
                child: InkWell(
                  key: const ValueKey('tafsir-verse-counter'),
                  borderRadius: BorderRadius.circular(24),
                  onTap: count == 0 ? null : () => _pickVerse(count),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: 48,
                      minWidth: 48,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Center(
                        widthFactor: 1,
                        heightFactor: 1,
                        child: MushafDigitsText(
                          '${digits(_ayah)} / ${digits(count)}',
                          style: TextStyle(color: t.muted),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: l.nextVerse,
            onPressed: atEnd || count == 0 ? null : () => _next(count),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );

    final topBar = LookTopBar(
      back: sheet == null,
      titleWidget: surah == null
          ? Text(l.tafsirTitle)
          : Semantics(
              button: true,
              label: l.tafsirOpenIndex,
              excludeSemantics: true,
              child: InkWell(
                key: const ValueKey('tafsir-title-index'),
                borderRadius: BorderRadius.circular(8),
                onTap: _openIndex,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(railIcon(RailItem.mushaf), size: 20),
                        const SizedBox(width: 6),
                        Flexible(
                          child: MushafDigitsText(
                            '${l.surahWord(surahName(context, surah))} | ${digits(_ayah)}',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
      actions: [
        IconButton(
          tooltip: l.tafsirSettings,
          icon: const Icon(Icons.tune),
          onPressed: () => showTafsirSettings(context),
        ),
      ],
    );

    final lead = _lead;
    final trail = _surah < 114 ? 1 : 0;
    final body = ayahs == null
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              if (widget.riwaya != null &&
                  widget.riwayaAyah != null &&
                  _surah == widget.surah)
                _RiwayaNote(
                  riwaya: widget.riwaya!,
                  surah: widget.surah,
                  ayah: widget.riwayaAyah!,
                ),
              Expanded(
                child: NotificationListener<ScrollEndNotification>(
                  onNotification: (n) => _onScrollEnd(n, ayahs.length),
                  child: PageView.builder(
                    key: ValueKey('tafsir-surah-$_surah'),
                    controller: _pages,
                    itemCount: lead + ayahs.length + trail,
                    onPageChanged: (i) {
                      final a = i - lead + 1;
                      if (a >= 1 && a <= ayahs.length) {
                        setState(() => _ayah = a);
                      }
                    },
                    itemBuilder: (context, i) {
                      final a = i - lead;
                      if (a < 0 || a >= ayahs.length) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final v = ayahs[a];
                      return _VersePage(
                        key: ValueKey('tafsir-verse-${v.surah}:${v.number}'),
                        pages: _dragger,
                        ayah: v,
                        onShow: _show,
                      );
                    },
                  ),
                ),
              ),
            ],
          );

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _stopTafsirAudio();
      },
      child: sheet != null
          ? Column(
              children: [
                // Dragging the handle or the title bar resizes the sheet.
                ListView(
                  controller: sheet,
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  children: [
                    Center(
                      child: Container(
                        width: 32,
                        height: 4,
                        margin: const EdgeInsets.only(top: 10, bottom: 2),
                        decoration: BoxDecoration(
                          color: t.muted.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    topBar,
                  ],
                ),
                Expanded(child: body),
                // The mushaf's player is under the sheet: its controls
                // come along while a recitation is on.
                if (ref.watch(recitationProvider.select((s) => s.active)))
                  const Padding(
                    padding: EdgeInsets.fromLTRB(12, 4, 12, 0),
                    child: PlayerBar(),
                  ),
                bottomBar,
              ],
            )
          : LookScaffold(
              bottomNavigationBar: bottomBar,
              body: SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    topBar,
                    Expanded(child: body),
                  ],
                ),
              ),
            ),
    );
  }
}

/// «اذهب لآية»: the verse numbers of the surah, 48dp each at least.
class _VersePicker extends StatelessWidget {
  const _VersePicker({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens.colors;
    final digits = NumberFormatter(Localizations.localeOf(context));
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              header: true,
              child: Text(
                l.tafsirGoToVerse,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Flexible(
              child: GridView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.all(16),
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 64 * scale,
                  mainAxisExtent: 48 * scale < 48 ? 48 : 48 * scale,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                itemCount: count,
                itemBuilder: (context, i) {
                  final n = i + 1;
                  final here = n == current;
                  return Semantics(
                    selected: here,
                    child: TextButton(
                      key: ValueKey('verse-pick-$n'),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        padding: EdgeInsets.zero,
                        backgroundColor: here
                            ? t.marker.withValues(alpha: 0.18)
                            : null,
                      ),
                      onPressed: () => Navigator.of(context).pop(n),
                      child: MushafDigitsText(digits(n)),
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

/// Opened from a riwaya edition: the verse as read there (number and the
/// riwaya's KFGQPC text) and the Hafs verses its tafsir is shown for.
class _RiwayaNote extends ConsumerWidget {
  const _RiwayaNote({
    required this.riwaya,
    required this.surah,
    required this.ayah,
  });

  final Riwaya riwaya;
  final int surah;
  final int ayah;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = context.tokens.colors;
    final digits = NumberFormatter(Localizations.localeOf(context));
    final data = ref.watch(riwayaDataProvider).value;
    final surahs = ref.watch(surahsProvider).value;
    final verse = data?.id == riwaya.name ? data!.verse(surah, ayah) : null;
    final hafs = verse?.hafs ?? const [];
    final hafsText = hafs.isEmpty
        ? l.riwayaNoHafs
        : hafs.length == 1
        ? l.hafsVerseOne(digits(hafs.first.ayah))
        : l.hafsVerseRange(digits(hafs.first.ayah), digits(hafs.last.ayah));
    final name = riwayaName(l, riwaya);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.marker.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (verse != null)
            Semantics(
              label: l.riwayaVerseText(name),
              child: Text(
                verse.text,
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: riwayaFontFamily(riwaya),
                  fontFamilyFallback: const ['UthmanicHafs'],
                  fontSize: 22,
                  height: 1.9,
                  color: t.ink,
                ),
              ),
            ),
          const SizedBox(height: 6),
          Text(
            l.riwayaTafsirNote(
              digits(ayah),
              surahs == null ? '$surah' : surahs[surah - 1].nameAr,
              name,
              hafsText,
            ),
            style: TextStyle(fontSize: 13, height: 1.5, color: t.muted),
          ),
        ],
      ),
    );
  }
}

class _VersePage extends ConsumerWidget {
  const _VersePage({
    super.key,
    required this.ayah,
    required this.pages,
    this.onShow,
  });

  final AyahRow ayah;

  /// Goes to another verse (Hafs numbers).
  final void Function(int surah, int ayah)? onShow;

  /// Turns the pages on a touch swipe over the texts.
  final _PageDragger pages;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = context.tokens.colors;
    final settings = ref.watch(settingsProvider);
    final editions = ref.watch(commentaryEditionsProvider).value;
    final languageCode = Localizations.localeOf(context).languageCode;
    final entries = ref
        .watch(verseCommentaryProvider((surah: ayah.surah, ayah: ayah.number)))
        .value;
    final sources = {
      for (final s in ref.watch(sourcesProvider).value ?? <SourceRow>[])
        s.id: s,
    };
    if (editions == null || entries == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final shown = [
      for (final e in editions)
        if (settings.isCommentaryShown(
              e.sourceId,
              defaultShown: commentaryDefaultShown(
                kind: e.kind,
                contentLanguageCode: e.language,
                languageCode: languageCode,
              ),
            ) &&
            entries[e.sourceId] != null)
          e,
    ];
    // Book tafsirs from installed reviewed packs: more choices beside the
    // ones above, each shown only when it has a passage for this verse.
    final books = [
      for (final b in ref.watch(installedBookSourcesProvider(BookKind.tafsir)))
        if (!settings.hiddenBookTafsirs.contains(b.key) &&
            ref
                .watch(
                  bookEntriesProvider((
                    spec: BookSectionSpec.tafsir,
                    surah: ayah.surah,
                    ayah: ayah.number,
                    source: b.key,
                    word: null,
                  )),
                )
                .isNotEmpty)
          b,
    ];
    // Downloaded tafsir packs (the tafsir library), under the same rule.
    // A pack without a passage for this verse (a sparse tafsir) still
    // has its chip, dimmed, so the reader does not think it is missing.
    final packs = [
      for (final i in ref.watch(installedTafsirPacksProvider))
        if (!settings.hiddenBookTafsirs.contains(tafsirPackKey(i.spec))) i,
    ];
    bool covers(InstalledTafsirPack i) =>
        i.pack.entry(ayah.surah, ayah.number) != null;
    final arabicUi = languageCode == 'ar';
    // Each shown text is a chip: (settings key, name, card).
    final items = <(String, String, Widget)>[
      for (final e in shown)
        (
          'c:${e.sourceId}',
          arabicUi ? e.nameAr : e.nameEn,
          _CommentaryCard(
            key: ValueKey('commentary-${e.sourceId}'),
            edition: e,
            entry: entries[e.sourceId]!,
            source: sources[e.sourceId],
          ),
        ),
      for (final b in books)
        (
          'b:${b.key}',
          b.title,
          BookSection(
            key: ValueKey('book-tafsir-${b.key}'),
            spec: BookSectionSpec.tafsir,
            surah: ayah.surah,
            ayah: ayah.number,
            source: b.key,
            title: b.title,
            titleSize: 14,
          ),
        ),
      for (final i in packs)
        (
          tafsirPackKey(i.spec),
          i.pack.title,
          covers(i)
              ? TafsirPackCard(
                  key: ValueKey('tafsir-pack-${i.spec.id}'),
                  pack: i.pack,
                  surah: ayah.surah,
                  ayah: ayah.number,
                )
              : _NotCoveredCard(
                  key: ValueKey('tafsir-pack-none-${i.spec.id}'),
                  pack: i.pack,
                  surah: ayah.surah,
                  ayah: ayah.number,
                  onShow: onShow,
                ),
        ),
    ];
    final dimmed = {
      for (final i in packs)
        if (!covers(i)) tafsirPackKey(i.spec),
    };
    final controller = ref.read(settingsProvider.notifier);
    // «قارن» shows them all; otherwise the last one chosen, else the first.
    final compare = settings.tafsirCompare && items.length > 1;
    final chosen = items.isEmpty
        ? null
        : items.firstWhere(
            (i) => i.$1 == settings.tafsirChoice,
            orElse: () => items.firstWhere(
              (i) => !dimmed.contains(i.$1),
              orElse: () => items.first,
            ),
          );
    final cards = compare
        ? [
            for (final i in items)
              if (!dimmed.contains(i.$1)) i.$3,
          ]
        : [?chosen?.$3];

    // On Android the text selection would take horizontal touch drags
    // first; this detector sits under it, so it wins them and turns the
    // page. Long-press selection and mouse drags still select.
    return SelectionArea(
      child: GestureDetector(
        supportedDevices: const {
          PointerDeviceKind.touch,
          PointerDeviceKind.stylus,
          PointerDeviceKind.invertedStylus,
          PointerDeviceKind.trackpad,
        },
        onHorizontalDragStart: pages.start,
        onHorizontalDragUpdate: pages.update,
        onHorizontalDragEnd: pages.end,
        onHorizontalDragCancel: pages.cancel,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Wide screens show the texts side by side for comparison.
            final wide = constraints.maxWidth >= 720 && cards.length > 1;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                if (items.length > 1) ...[
                  Semantics(
                    container: true,
                    label: l.tafsirChoices,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          FilterChip(
                            key: const ValueKey('tafsir-compare'),
                            label: Text(l.tafsirCompare),
                            tooltip: l.tafsirCompareHint,
                            selected: compare,
                            materialTapTargetSize: MaterialTapTargetSize.padded,
                            onSelected: controller.setTafsirCompare,
                          ),
                          if (!compare)
                            for (final i in items)
                              Padding(
                                padding: const EdgeInsetsDirectional.only(
                                  start: 8,
                                ),
                                child: ChoiceChip(
                                  key: ValueKey('tafsir-chip-${i.$1}'),
                                  label: Opacity(
                                    opacity: dimmed.contains(i.$1) ? 0.5 : 1,
                                    child: Text(i.$2),
                                  ),
                                  selected: i.$1 == chosen?.$1,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.padded,
                                  onSelected: (_) =>
                                      controller.setTafsirChoice(i.$1),
                                ),
                              ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                _VerseCard(ayah: ayah),
                const SizedBox(height: 16),
                // «استمع للتفسير» (flag tafsir_audio), when a recording has
                // the verse; nothing otherwise.
                TafsirAudioButtons(surah: ayah.surah, ayah: ayah.number),
                if (cards.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Text(
                          l.tafsirNoneShown,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: t.muted),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.tonalIcon(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(48, 48),
                          ),
                          onPressed: () => showTafsirSettings(context),
                          icon: const Icon(Icons.tune),
                          label: Text(l.tafsirChooseTexts),
                        ),
                      ],
                    ),
                  )
                else if (wide)
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (i, c) in cards.indexed) ...[
                          if (i > 0) const SizedBox(width: 12),
                          Expanded(child: c),
                        ],
                      ],
                    ),
                  )
                else
                  for (final (i, c) in cards.indexed) ...[
                    if (i > 0) const SizedBox(height: 12),
                    c,
                  ],
                // The English tafsir pack (flag english_tafsir), English
                // interface only; nothing otherwise.
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: EnglishTafsirSection(
                    surah: ayah.surah,
                    ayah: ayah.number,
                  ),
                ),
                // Reviewed occasions of revelation, when the feature is on
                // and a pack has some for this verse; nothing otherwise.
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: AsbabSection(surah: ayah.surah, ayah: ayah.number),
                ),
                // Reviewed munasabat, under the same conditions.
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: BookSection(
                    spec: BookSectionSpec.munasabat,
                    surah: ayah.surah,
                    ayah: ayah.number,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CommentaryCard extends ConsumerStatefulWidget {
  const _CommentaryCard({
    super.key,
    required this.edition,
    required this.entry,
    required this.source,
  });

  final CommentaryEditionRow edition;
  final CommentaryRow entry;
  final SourceRow? source;

  @override
  ConsumerState<_CommentaryCard> createState() => _CommentaryCardState();
}

class _CommentaryCardState extends ConsumerState<_CommentaryCard> {
  /// A long text shows this many lines until «اقرأ المزيد».
  static const _collapsedLines = 8;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final edition = widget.edition;
    final entry = widget.entry;
    final l = AppLocalizations.of(context);
    final t = context.tokens.colors;
    final settings = ref.watch(settingsProvider);
    final arabicUi = Localizations.localeOf(context).languageCode == 'ar';
    final rtl = edition.direction == 'rtl';
    final family = !rtl
        ? 'IBMPlexSans'
        : settings.tafsirFont == TafsirFont.naskh
        ? 'UthmanTahaNaskh'
        : settings.uiFont.family;
    final size = (rtl ? 19.0 : 16.0) * settings.tafsirFontScale;
    final dir = rtl ? TextDirection.rtl : TextDirection.ltr;
    final bodyStyle = TextStyle(
      fontFamily: family,
      fontSize: size,
      height: rtl ? 1.9 : 1.6,
      color: t.ink,
    );
    final s = widget.source;
    final credit = s == null
        ? null
        : [
            s.attribution,
            // The version is shown once, even when the credit names it.
            if (s.version == null)
              l.sourceRetrieved(s.retrievedAt)
            else if (!s.attribution.contains(s.version!))
              l.sourceVersion(s.version!),
          ].join(' · ');

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
                child: Text(
                  arabicUi ? edition.nameAr : edition.nameEn,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: t.ink,
                  ),
                ),
              ),
              IconButton(
                tooltip: l.copyText,
                icon: Icon(Icons.copy, size: 18, color: t.muted),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: entry.body));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context)
                      .showSnackBar(appToast(content: Text(l.copied)));
                },
              ),
              // The text as it is, with the source's name and credit.
              IconButton(
                tooltip: l.tafsirShareText,
                icon: Icon(Icons.share_outlined, size: 18, color: t.muted),
                onPressed: () => ref.read(shareTextProvider)(
                  [
                    entry.body,
                    '',
                    arabicUi ? edition.nameAr : edition.nameEn,
                    ?credit,
                  ].join('\n'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          LayoutBuilder(
            builder: (context, constraints) {
              final text = rtl && settings.tafsirKashida
                  // Selection would copy the added tatweels; the copy
                  // button gives the original text instead.
                  ? SelectionContainer.disabled(
                      child: KashidaText(entry.body, style: bodyStyle),
                    )
                  : Text(
                      entry.body,
                      textDirection: dir,
                      textAlign: TextAlign.justify,
                      style: bodyStyle,
                    );
              final painter = TextPainter(
                text: TextSpan(text: entry.body, style: bodyStyle),
                textDirection: dir,
                textScaler: MediaQuery.textScalerOf(context),
                maxLines: _collapsedLines,
              )..layout(maxWidth: constraints.maxWidth);
              final long = painter.didExceedMaxLines;
              final height = painter.height;
              painter.dispose();
              if (!long) return text;
              // Collapsed, the whole text is still there (selection,
              // screen readers); only the first lines are in sight.
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_expanded)
                    text
                  else
                    SizedBox(
                      height: height,
                      child: ClipRect(
                        child: OverflowBox(
                          alignment: Alignment.topCenter,
                          minHeight: 0,
                          maxHeight: double.infinity,
                          child: text,
                        ),
                      ),
                    ),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      key: const ValueKey('tafsir-read-more'),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                      onPressed: () => setState(() => _expanded = !_expanded),
                      child: Text(
                        _expanded ? l.tafsirShowLess : l.tafsirReadMore,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          if (entry.footnotes != null) ...[
            const SizedBox(height: 10),
            Text(
              l.tafsirFootnotes,
              style: TextStyle(fontSize: 12, color: t.muted),
            ),
            const SizedBox(height: 4),
            Text(
              entry.footnotes!,
              textDirection: dir,
              style: TextStyle(
                fontFamily: family,
                fontSize: size * 0.8,
                height: 1.5,
                color: t.muted,
              ),
            ),
          ],
          if (credit != null) ...[
            const SizedBox(height: 10),
            MetaText(
              credit,
              textDirection: dir,
              style: TextStyle(fontSize: 11, color: t.muted),
            ),
          ],
        ],
      ),
    );
  }
}

class _TafsirSettingsSheet extends ConsumerWidget {
  const _TafsirSettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);
    final editions = ref.watch(commentaryEditionsProvider).value ?? const [];
    final books = ref.watch(installedBookSourcesProvider(BookKind.tafsir));
    final languageCode = Localizations.localeOf(context).languageCode;
    final arabicUi = languageCode == 'ar';
    final flags = ref.watch(featureFlagsProvider);
    final englishTafsirSpecs = ref.watch(englishTafsirSpecsProvider);
    final packs = ref.watch(installedTafsirPacksProvider);
    final englishTafsirOn =
        englishTafsirSpecs.isNotEmpty && flags.isOn(Feature.englishTafsir);
    final tafsirEditions = [
      for (final e in editions)
        if (e.kind == 'tafsir' && e.language == 'ar') e,
    ];
    final translations = [
      for (final e in editions)
        if (!(e.kind == 'tafsir' && e.language == 'ar')) e,
    ];
    bool editionShown(CommentaryEditionRow e) => settings.isCommentaryShown(
      e.sourceId,
      defaultShown: commentaryDefaultShown(
        kind: e.kind,
        contentLanguageCode: e.language,
        languageCode: languageCode,
      ),
    );
    // How many texts are shown: the last one cannot be hidden.
    final shownCount = [
      for (final e in editions) editionShown(e),
      for (final b in books) !settings.hiddenBookTafsirs.contains(b.key),
      for (final i in packs)
        !settings.hiddenBookTafsirs.contains(tafsirPackKey(i.spec)),
      if (englishTafsirOn) settings.isEnglishTafsirShown(languageCode),
    ].where((v) => v).length;

    Widget guardedSwitch({
      required Key key,
      required String title,
      String? subtitle,
      required bool value,
      required ValueChanged<bool> onChanged,
    }) {
      final last = value && shownCount <= 1;
      return SwitchListTile(
        key: key,
        contentPadding: EdgeInsets.zero,
        title: Text(title),
        subtitle: last
            ? Text(l.tafsirKeepOne)
            : subtitle == null
            ? null
            : Text(subtitle),
        value: value,
        onChanged: last ? null : onChanged,
      );
    }

    Widget editionSwitch(CommentaryEditionRow e) => guardedSwitch(
      key: ValueKey('tafsir-shown-c:${e.sourceId}'),
      title: arabicUi ? e.nameAr : e.nameEn,
      value: editionShown(e),
      onChanged: (v) => controller.setCommentaryShown(e.sourceId, v),
    );

    Widget keyedSwitch({
      required String key,
      required String title,
      String? subtitle,
    }) => guardedSwitch(
      key: ValueKey('tafsir-shown-$key'),
      title: title,
      subtitle: subtitle,
      value: !settings.hiddenBookTafsirs.contains(key),
      onChanged: (v) => controller.setBookTafsirShown(key, v),
    );

    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Semantics(
            header: true,
            child: Text(
              l.tafsirFontLabel,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<TafsirFont>(
            segments: [
              ButtonSegment(
                value: TafsirFont.naskh,
                label: Text(l.tafsirFontNaskh),
              ),
              ButtonSegment(
                value: TafsirFont.interface,
                label: Text(l.tafsirFontInterface),
              ),
            ],
            selected: {settings.tafsirFont},
            onSelectionChanged: (v) => controller.setTafsirFont(v.first),
          ),
          const SizedBox(height: 16),
          Semantics(
            header: true,
            child: Text(
              l.tafsirTextSize,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          Slider(
            value: settings.tafsirFontScale,
            semanticFormatterCallback: (v) => '${(v * 100).round()}%',
            min: 0.8,
            max: 1.8,
            divisions: 10,
            onChanged: controller.setTafsirFontScale,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l.tafsirKashida),
            subtitle: Text(l.tafsirKashidaHint),
            value: settings.tafsirKashida,
            onChanged: controller.setTafsirKashida,
          ),
          Text(l.tafsirShown, style: Theme.of(context).textTheme.titleSmall),
          _SectionLabel(l.tafsirSectionTafsirs),
          for (final e in tafsirEditions) editionSwitch(e),
          for (final b in books)
            keyedSwitch(key: b.key, title: b.title, subtitle: b.author),
          for (final i in packs)
            keyedSwitch(
              key: tafsirPackKey(i.spec),
              title: i.pack.title,
              subtitle: i.spec.author,
            ),
          ListTile(
            key: const ValueKey('tafsir-library-open'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.library_books_outlined),
            title: Text(l.tafsirLibrary),
            subtitle: Text(l.tafsirLibraryHint),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showTafsirLibrary(context),
          ),
          if (translations.isNotEmpty || englishTafsirOn) ...[
            _SectionLabel(l.tafsirSectionTranslations),
            for (final e in translations) editionSwitch(e),
            if (englishTafsirOn)
              guardedSwitch(
                key: const ValueKey('tafsir-shown-english'),
                title: l.englishTafsirVisibilityLabel,
                value: settings.isEnglishTafsirShown(languageCode),
                onChanged: controller.setEnglishTafsirShown,
              ),
          ],
        ],
      ),
    );
  }
}

/// A group label in the tafsir settings.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 4),
    child: Semantics(
      header: true,
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge
            ?.copyWith(color: context.tokens.colors.muted),
      ),
    ),
  );
}

/// A horizontal drag handed to the pages' scroll position, as the
/// PageView's own Scrollable would do it.
class _PageDragger {
  _PageDragger(this._controller);

  final PageController Function() _controller;
  Drag? _drag;

  void start(DragStartDetails d) {
    final c = _controller();
    if (!c.hasClients) return;
    _drag = c.position.drag(d, () => _drag = null);
  }

  void update(DragUpdateDetails d) => _drag?.update(d);
  void end(DragEndDetails d) => _drag?.end(d);
  void cancel() => _drag?.cancel();
}

/// The verse over its tafsir: a soft card between two mosaic bands, the
/// surah and verse between two markers, the verse, then «استمع للآية»,
/// which plays this verse only and stops at its end (on and on when the
/// reader turned «كرّر» on).
class _VerseCard extends ConsumerStatefulWidget {
  const _VerseCard({required this.ayah});

  final AyahRow ayah;

  @override
  ConsumerState<_VerseCard> createState() => _VerseCardState();
}

class _VerseCardState extends ConsumerState<_VerseCard> {
  bool _repeat = false;

  /// The verse as the recitation counts it (the edition's numbering).
  ({int surah, int ayah}) _key() {
    final k = editionKeyOf(
      ref.read(riwayaDataProvider).value,
      widget.ayah.surah,
      widget.ayah.number,
    );
    return (surah: k.surah, ayah: k.ayah);
  }

  bool _isThis(RecitationState s, ({int surah, int ayah}) k) =>
      s.active &&
      s.clip == null &&
      s.surah == k.surah &&
      s.rangeFrom == k.ayah &&
      s.rangeTo == k.ayah;

  Future<void> _play() {
    final k = _key();
    // This verse only: a stretch of one verse, played once (or until
    // stopped with «كرّر»); the mushaf's own recitation is untouched.
    return ref
        .read(recitationProvider.notifier)
        .play(
          k.surah,
          from: k.ayah,
          to: k.ayah,
          repeat: _repeat ? 0 : 1,
          verseRepeat: 1,
        );
  }

  Future<void> _tap(RecitationState s) async {
    final k = _key();
    final mine = _isThis(s, k);
    if (mine && s.playing) {
      await ref.read(recitationProvider.notifier).toggle();
    } else {
      await _play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens.colors;
    final scheme = Theme.of(context).colorScheme;
    final ayah = widget.ayah;
    final digits = NumberFormatter(Localizations.localeOf(context));
    final s = ref.watch(recitationProvider);
    final surahRow = ref.watch(surahsProvider).value?[ayah.surah - 1];
    final k = _key();
    final playing = _isThis(s, k) && (s.playing || s.loading);
    final images = ref.watch(frameImagesProvider(t.artTint)).value;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    Widget band() => SizedBox(
      height: 22,
      child: images == null
          ? ColoredBox(color: t.border)
          : CustomPaint(painter: _MosaicBand(images)),
    );
    Widget marker() => ExcludeSemantics(
      child: Image.asset(
        'assets/ornaments/marker_16.png',
        width: 20,
        height: 20,
      ),
    );
    final words = ayah.displayBody.split(RegExp(r'\s+')).length;
    final word = playing ? s.word : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          key: const ValueKey('tafsir-verse'),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: t.bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: t.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              band(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        marker(),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            l.tafsirVerseHeader(
                              surahRow == null
                                  ? digits(ayah.surah)
                                  : l.surahWord(surahName(context, surahRow)),
                              digits(ayah.number),
                            ),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: scheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        marker(),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: '${ayah.displayBody} '),
                          TextSpan(
                            text: ayah.displayNumber,
                            style: TextStyle(color: t.marker),
                          ),
                        ],
                      ),
                      textDirection: TextDirection.rtl,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'UthmanicHafs',
                        fontSize: 24,
                        height: 2,
                        color: t.ink,
                      ),
                    ),
                  ],
                ),
              ),
              band(),
            ],
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const ValueKey('tafsir-play-verse'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          onPressed: () => _tap(s),
          icon: Icon(playing ? Icons.pause : Icons.play_arrow),
          label: Text(playing ? l.tafsirPauseVerse : l.tafsirPlayVerse),
        ),
        if (playing && (word != null || !reduceMotion))
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                minHeight: 3,
                value: word == null ? null : (word / words).clamp(0.0, 1.0),
              ),
            ),
          ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton.icon(
            key: const ValueKey('tafsir-repeat-verse'),
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: () {
              setState(() => _repeat = !_repeat);
              if (playing) unawaited(_play());
            },
            icon: Icon(_repeat ? Icons.repeat_on : Icons.repeat),
            label: Semantics(
              toggled: _repeat,
              child: Text(l.tafsirRepeatVerse),
            ),
          ),
        ),
      ],
    );
  }
}

/// The mosaic repeated along a band.
class _MosaicBand extends CustomPainter {
  _MosaicBand(this.images);

  final FrameImages images;

  @override
  void paint(Canvas canvas, Size size) =>
      canvas.drawRect(Offset.zero & size, images.mosaicPaint());

  @override
  bool shouldRepaint(_MosaicBand old) => old.images != images;
}

/// A library tafsir with nothing on this verse: says so, with the way to
/// the nearest verses it does speak of.
class _NotCoveredCard extends StatelessWidget {
  const _NotCoveredCard({
    super.key,
    required this.pack,
    required this.surah,
    required this.ayah,
    this.onShow,
  });

  final TafsirTextPack pack;
  final int surah;
  final int ayah;
  final void Function(int surah, int ayah)? onShow;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens.colors;
    final before = pack.previousCovered(surah, ayah);
    final after = pack.nextCovered(surah, ayah);
    final go = onShow;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l.tafsirPackNotCovered(pack.title),
            textAlign: TextAlign.center,
            style: TextStyle(color: t.muted, height: 1.6),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            children: [
              if (before != null && go != null)
                OutlinedButton(
                  key: const ValueKey('tafsir-pack-previous-covered'),
                  onPressed: () => go(before.surah, before.ayah),
                  child: Text(l.tafsirPackPreviousCovered),
                ),
              if (after != null && go != null)
                OutlinedButton(
                  key: const ValueKey('tafsir-pack-next-covered'),
                  onPressed: () => go(after.surah, after.ayah),
                  child: Text(l.tafsirPackNextCovered),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
