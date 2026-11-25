import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/db/content_database.dart';
import '../../../core/downloads/background_downloads.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/interface_style.dart';
import '../../../core/ui/app_toast.dart';
import '../../../core/ui/confirm_delete_download.dart';
import '../../../core/ui/look_kit.dart';
import '../../../core/ui/meta_separator.dart';
import '../../../core/ui/responsive.dart';
import '../../../l10n/app_localizations.dart';
import '../../audio/background_recitations.dart';
import '../../audio/player_bar.dart';
import '../../audio/recitation.dart';
import '../../audio/reciter_avatar.dart';
import '../../content_extras/tafsir_downloads_section.dart';
import '../../onboarding/background_downloads.dart';
import '../../prayer/data/adhan_catalog.dart';
import '../../prayer/data/adhan_downloads.dart';
import '../../prayer/presentation/adhan_library_screen.dart' show MuezzinAvatar;
import '../../prayer/services/prayer_runtime.dart' show prayerNativeProvider;
import '../../search/semantic/meaning_providers.dart';
import '../../tasmee/data/background_model_download.dart';
import '../../tasmee/data/tasmee_backend.dart';
import '../../tasmee/presentation/tasmee_settings_screen.dart'
    show tasmeeModelInfoProvider;
import '../data/page_pack.dart';
import '../mushaf_providers.dart';
import 'background_downloads_list.dart';
import 'widgets/illuminated_frame.dart';

/// The Downloads Center's sections; their names are the `?section=`
/// values of `/downloads` that open one directly.
enum DownloadsSection { mushaf, recitations, tafsir, adhan, resources }

extension on DownloadsSection {
  String title(AppLocalizations l) => switch (this) {
    DownloadsSection.mushaf => l.downloadsSectionMushaf,
    DownloadsSection.recitations => l.downloadsSectionRecitations,
    DownloadsSection.tafsir => l.downloadsSectionTafsir,
    DownloadsSection.adhan => l.downloadsSectionAdhan,
    DownloadsSection.resources => l.downloadsSectionTools,
  };

  IconData get icon => switch (this) {
    DownloadsSection.mushaf => Icons.menu_book_outlined,
    DownloadsSection.recitations => Icons.headphones_outlined,
    DownloadsSection.tafsir => Icons.auto_stories_outlined,
    DownloadsSection.adhan => Icons.mosque_outlined,
    DownloadsSection.resources => Icons.handyman_outlined,
  };
}

/// One downloadable thing of a section, as the hub, the search and the
/// section lists see it. [row] draws it with its actions; null for the
/// tafsir books (drawn by [TafsirDownloadsSection]) and for a reciter
/// downloading now (drawn by [BackgroundDownloadsList]).
class _Item {
  const _Item({
    required this.section,
    required this.id,
    required this.title,
    required this.installed,
    this.search = '',
    this.bytes = 0,
    this.busy = false,
    this.fraction,
    this.row,
  });

  final DownloadsSection section;
  final String id;
  final String title;
  final String search;
  final bool installed;

  /// Its size on the device (0 when not there).
  final int bytes;
  final bool busy;

  /// Its progress while [busy], when known.
  final double? fraction;
  final WidgetBuilder? row;

  bool matches(String q) =>
      q.isEmpty || title.contains(q) || search.toLowerCase().contains(q);
}

typedef _Catalog = Map<DownloadsSection, List<_Item>>;

String _query(String raw) => raw.trim().toLowerCase();

/// [bytes] in megabytes, or gigabytes from one gigabyte.
String _size(BuildContext context, int bytes) {
  if (bytes < 1e9) return downloadSizeLabel(context, bytes);
  final digits = NumberFormatter(Localizations.localeOf(context));
  return AppLocalizations.of(context)
      .downloadsSizeGb(digits.decimal((bytes / 1e9).toStringAsFixed(1)));
}

/// The Downloads Center: a hub with the storage on the device, a search
/// over everything, the running downloads and a tile per section; each
/// section lists what is on the device and what can be downloaded.
/// Opening it never starts a download, and leaving it leaves every
/// download running in the background. [section] opens that section
/// directly (`/downloads?section=adhan`).
class DownloadsCenterScreen extends ConsumerWidget {
  const DownloadsCenterScreen({super.key, this.section});

  final DownloadsSection? section;

  /// [name] as a section, or null.
  static DownloadsSection? sectionNamed(String? name) =>
      DownloadsSection.values.asNameMap()[name];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = section;
    return _LeaveNotice(
      child: s == null ? const _Hub() : DownloadsSectionScreen(section: s),
    );
  }
}

/// Tells the reader, on leaving, that the downloads go on.
class _LeaveNotice extends ConsumerWidget {
  const _LeaveNotice({required this.child});

  final Widget child;

  static bool busy(WidgetRef ref) {
    if (ref.read(backgroundDownloadsProvider).tasks.value.isNotEmpty) {
      return true;
    }
    for (final e in MushafEdition.values) {
      final p = ref.read(editionDownloadProvider(e)).phase;
      if (p == PackPhase.downloading ||
          p == PackPhase.verifying ||
          p == PackPhase.installing) {
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && busy(ref)) {
          messenger?.showSnackBar(appToast(content: Text(l.downloadsGoesOn)));
        }
      },
      child: child,
    );
  }
}

Future<void> _openSection(
  BuildContext context,
  DownloadsSection section, {
  String query = '',
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => LookTheme(
      child: DownloadsSectionScreen(section: section, initialQuery: query),
    ),
  ),
);

/// A page of the center: its top bar and a centred, width-capped body.
class _Page extends StatelessWidget {
  const _Page({required this.title, required this.child, this.actions});

  final String title;
  final List<Widget>? actions;
  final Widget child;

  @override
  Widget build(BuildContext context) => LookScaffold(
    body: SafeArea(
      bottom: false,
      child: Column(
        children: [
          LookTopBar(title: title, actions: actions ?? const []),
          Expanded(
            child: SafeArea(
              top: false,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: ContentWidth.text,
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

// ───────────────────────────── hub ─────────────────────────────

class _Hub extends StatefulWidget {
  const _Hub();

  @override
  State<_Hub> createState() => _HubState();
}

class _HubState extends State<_Hub> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return _Page(
      title: l.downloadAllTitle,
      child: _CatalogBuilder(
        builder: (context, catalog) {
          final q = _query(_q);
          // The search field stays put while the hub scrolls under it.
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: TextField(
                  key: const ValueKey('downloads-search'),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: l.downloadsSearchAll,
                  ),
                  onChanged: (v) => setState(() => _q = v),
                ),
              ),
              Expanded(
                child: ListView(
                  key: const ValueKey('downloads-hub-list'),
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  children: [
                    _StorageCard(catalog: catalog),
                    const SizedBox(height: 12),
                    _ActiveBanner(catalog: catalog),
                    if (q.isEmpty)
                      _Tiles(catalog: catalog)
                    else
                      _Results(catalog: catalog, query: q),
                    const SizedBox(height: 16),
                    Text(
                      l.downloadInBackgroundNote,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: context.tokens.colors.muted,
                        fontSize: 13,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () {
                        if (context.canPop()) {
                          context.pop();
                        } else {
                          context.go('/mushaf');
                        }
                      },
                      child: Text(l.doneLabel),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The space the downloads take, by kind, with a segmented bar.
class _StorageCard extends StatelessWidget {
  const _StorageCard({required this.catalog});

  final _Catalog catalog;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final look = context.look;
    int sum(Iterable<DownloadsSection> of) =>
        [for (final s in of) ...catalog[s]!]
            .fold(0, (a, i) => a + (i.installed ? i.bytes : 0));
    final parts = [
      (
        l.downloadsSectionRecitations,
        sum([DownloadsSection.recitations]),
        look.accent,
      ),
      (l.downloadsSectionMushaf, sum([DownloadsSection.mushaf]), look.gold),
      (
        l.downloadsStorageOther,
        sum([
          DownloadsSection.tafsir,
          DownloadsSection.adhan,
          DownloadsSection.resources,
        ]),
        look.sub,
      ),
    ];
    final total = parts.fold(0, (a, p) => a + p.$2);
    return Container(
      key: const ValueKey('downloads-storage-card'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: look.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: look.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l.downloadsStorageTitle,
            style: TextStyle(color: look.sub, fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            l.downloadsStorageTotal(_size(context, total)),
            style: TextStyle(
              color: look.ink,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          ExcludeSemantics(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 10,
                child: Row(
                  children: [
                    if (total == 0)
                      Expanded(child: ColoredBox(color: look.line))
                    else
                      for (final p in parts)
                        if (p.$2 > 0)
                          Expanded(
                            // At least a sliver for a small part.
                            flex: (p.$2 * 1000 ~/ total).clamp(8, 1000),
                            child: ColoredBox(color: p.$3),
                          ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              for (final p in parts)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: p.$3,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '${p.$1} · ${_size(context, p.$2)}',
                        style: TextStyle(color: look.sub, fontSize: 13),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The running downloads: their count and overall progress.
class _ActiveBanner extends StatelessWidget {
  const _ActiveBanner({required this.catalog});

  final _Catalog catalog;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final look = context.look;
    final busy = [
      for (final s in catalog.values)
        for (final i in s)
          if (i.busy) i,
    ];
    if (busy.isEmpty) return const SizedBox.shrink();
    final known = [
      for (final i in busy)
        if (i.fraction != null) i.fraction!.clamp(0.0, 1.0),
    ];
    final digits = NumberFormatter(Localizations.localeOf(context));
    final arabic = l.localeName == 'ar';
    final pct = known.isEmpty
        ? 0
        : (known.reduce((a, b) => a + b) / known.length * 100).round();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        key: const ValueKey('downloads-active-banner'),
        padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 8, 8),
        decoration: BoxDecoration(
          color: look.accent.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: look.accent.withValues(alpha: .35)),
        ),
        child: Row(
          children: [
            Icon(Icons.downloading, color: look.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                l.downloadsActiveBanner(
                  digits(busy.length),
                  '${digits(pct)}${arabic ? '٪' : '%'}',
                ),
                style: TextStyle(color: look.ink, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              key: const ValueKey('downloads-active-show'),
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const LookTheme(child: _ActiveScreen()),
                ),
              ),
              child: Text(l.downloadsActiveShow),
            ),
          ],
        ),
      ),
    );
  }
}

/// The section tiles, two to a row (one with large text).
class _Tiles extends StatelessWidget {
  const _Tiles({required this.catalog});

  final _Catalog catalog;

  @override
  Widget build(BuildContext context) {
    final columns = MediaQuery.textScalerOf(context).scale(10) > 15 ? 1 : 2;
    const sections = DownloadsSection.values;
    final rows = <Widget>[];
    for (var i = 0; i < sections.length; i += columns) {
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var c = 0; c < columns; c++) ...[
                  if (c > 0) const SizedBox(width: 12),
                  Expanded(
                    child: i + c < sections.length
                        ? _Tile(
                            section: sections[i + c],
                            items: catalog[sections[i + c]]!,
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }
    return Column(children: rows);
  }
}

String _sectionStatus(BuildContext context, List<_Item> items) {
  final l = AppLocalizations.of(context);
  final digits = NumberFormatter(Localizations.localeOf(context));
  final here = items.where((i) => i.installed).toList();
  if (here.isEmpty) return l.downloadsTileNone(digits(items.length));
  final bytes = here.fold(0, (a, i) => a + i.bytes);
  return l.downloadsTileOnDevice(digits(here.length), _size(context, bytes));
}

class _Tile extends StatelessWidget {
  const _Tile({required this.section, required this.items});

  final DownloadsSection section;
  final List<_Item> items;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final look = context.look;
    final title = section.title(l);
    final status = _sectionStatus(context, items);
    return Semantics(
      button: true,
      label: '$title. $status',
      excludeSemantics: true,
      child: Material(
        color: look.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: look.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('downloads-tile-${section.name}'),
          onTap: () => _openSection(context, section),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _IconTile(section.icon),
                  const SizedBox(height: 10),
                  Text(
                    title,
                    style: TextStyle(
                      color: look.ink,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(status, style: TextStyle(color: look.sub, fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// An icon in a small rounded square: a section, a mushaf, a tool.
class _IconTile extends StatelessWidget {
  const _IconTile(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final look = context.look;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: look.accent.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: look.accent, size: 22),
    );
  }
}

/// The hub's search results, by section; each opens its section.
class _Results extends StatelessWidget {
  const _Results({required this.catalog, required this.query});

  final _Catalog catalog;
  final String query;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final look = context.look;
    final children = <Widget>[];
    for (final s in DownloadsSection.values) {
      final hits = catalog[s]!.where((i) => i.matches(query)).toList();
      if (hits.isEmpty) continue;
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 6),
          child: Semantics(
            header: true,
            child: Text(
              s.title(l),
              style: TextStyle(
                color: look.goldText,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ),
        ),
      );
      for (final i in hits) {
        children.add(
          Card(
            child: ListTile(
              key: ValueKey('downloads-result-${s.name}-${i.id}'),
              minTileHeight: 56,
              leading: Icon(i.installed ? Icons.check_circle : s.icon),
              title: Text(plainMeta(i.title)),
              subtitle: Text(
                i.installed
                    ? l.downloadsHeaderOnDevice
                    : l.downloadsHeaderAvailable,
              ),
              onTap: () => _openSection(context, s, query: i.title),
            ),
          ),
        );
      }
    }
    if (children.isEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(l.libraryNoMatch, textAlign: TextAlign.center),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

/// Everything downloading now, each with its pause / cancel.
class _ActiveScreen extends StatelessWidget {
  const _ActiveScreen();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return _Page(
      title: l.downloadsActiveTitle,
      child: _CatalogBuilder(
        builder: (context, catalog) {
          final rows = [
            for (final s in catalog.values)
              for (final i in s)
                if (i.busy &&
                    i.row != null &&
                    i.section != DownloadsSection.resources)
                  i,
          ];
          final anyBusy = catalog.values.any((s) => s.any((i) => i.busy));
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const BackgroundDownloadsList(),
              for (final i in rows) i.row!(context),
              // Semantic pack: a pack row, not a background task.
              for (final i in catalog[DownloadsSection.resources]!)
                if (i.busy && i.id == 'semantic') i.row!(context),
              TafsirDownloadsSection(where: (i) => i.busy),
              if (!anyBusy)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    l.downloadsActiveNone,
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────── a section ───────────────────────────

/// One section of the center: its search, «all» / «on my device», and
/// two lists under sticky headers (on the device, available).
class DownloadsSectionScreen extends ConsumerStatefulWidget {
  const DownloadsSectionScreen({
    super.key,
    required this.section,
    this.initialQuery = '',
  });

  final DownloadsSection section;
  final String initialQuery;

  @override
  ConsumerState<DownloadsSectionScreen> createState() =>
      _DownloadsSectionScreenState();
}

class _DownloadsSectionScreenState
    extends ConsumerState<DownloadsSectionScreen> {
  late final _search = TextEditingController(text: widget.initialQuery);
  bool _onDeviceOnly = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _downloadModel() async {
    final backend = ref.read(tasmeeBackendProvider);
    try {
      final m = await backend.fetchManifest();
      ref.read(tasmeeModelDownloadProvider.notifier).start(m);
    } catch (_) {
      // Offline: the button stays for another try.
    }
  }

  /// The section's «download all», when it has one and something is left.
  VoidCallback? _downloadAll(List<_Item> items) {
    final idle = [
      for (final i in items)
        if (!i.installed && !i.busy) i,
    ];
    if (idle.isEmpty) return null;
    switch (widget.section) {
      case DownloadsSection.mushaf:
        return () => ref.read(pageDownloadProvider.notifier).startAll();
      case DownloadsSection.resources:
        return () {
          for (final i in idle) {
            if (i.id == 'tasmee-model') unawaited(_downloadModel());
            if (i.id == 'semantic') {
              unawaited(ref.read(semanticDownloadProvider.notifier).start());
            }
          }
        };
      // No «download all» for the recitations (many gigabytes) or the
      // adhan; the tafsir groups have theirs in their lists.
      case DownloadsSection.recitations:
      case DownloadsSection.tafsir:
      case DownloadsSection.adhan:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final section = widget.section;
    final digits = NumberFormatter(Localizations.localeOf(context));
    return _CatalogBuilder(
      builder: (context, catalog) {
        final items = catalog[section]!;
        final q = _query(_search.text);
        final shown = [
          for (final i in items)
            if (i.matches(q) && (!_onDeviceOnly || i.installed)) i,
        ];
        final here = [
          for (final i in shown)
            if (i.installed) i,
        ];
        final there = [
          for (final i in shown)
            if (!i.installed) i,
        ];
        final installedCount = items.where((i) => i.installed).length;
        final downloadAll = _downloadAll(items);
        final scale = MediaQuery.textScalerOf(context);
        final headerExtent = scale.scale(15) + 24;
        bool tafsirMatch(TafsirDownloadItem i) =>
            shown.any((s) => s.id == i.id);
        // Running recitations / model downloads: their own rows.
        final runningList = switch (section) {
          DownloadsSection.recitations when items.any((i) => i.busy) =>
            const BackgroundDownloadsList(model: false),
          _ => null,
        };

        List<Widget> group(
          String title,
          String key,
          List<_Item> list, {
          Widget? lead,
          bool installed = false,
        }) {
          if (list.isEmpty && lead == null) return const [];
          return [
            SliverPersistentHeader(
              pinned: true,
              delegate: _StickyHeader(
                key: key,
                title: title,
                extent: headerExtent,
                color: context.look.bg,
                ink: context.look.goldText,
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList.list(
                children: [
                  ?lead,
                  if (section == DownloadsSection.tafsir)
                    TafsirDownloadsSection(
                      where: (i) => i.installed == installed && tafsirMatch(i),
                    )
                  else
                    for (final i in list)
                      if (i.row != null) i.row!(context),
                ],
              ),
            ),
          ];
        }

        return _Page(
          title: section.title(l),
          actions: [
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 12),
              child: Center(
                child: Text(
                  l.downloadsCountOf(
                    digits(installedCount),
                    digits(items.length),
                  ),
                  key: const ValueKey('downloads-section-count'),
                  maxLines: 1,
                  style: TextStyle(color: context.look.sub, fontSize: 13),
                ),
              ),
            ),
          ],
          // The search field stays put; the chips and lists scroll under it.
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: TextField(
                  key: const ValueKey('downloads-section-search'),
                  controller: _search,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: l.downloadsSearchSection,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              Expanded(
                child: CustomScrollView(
                  key: ValueKey('downloads-section-${section.name}'),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                ChoiceChip(
                                  key: const ValueKey('downloads-filter-all'),
                                  label: Text(l.libraryFilterAll),
                                  selected: !_onDeviceOnly,
                                  onSelected: (_) =>
                                      setState(() => _onDeviceOnly = false),
                                ),
                                ChoiceChip(
                                  key: const ValueKey(
                                    'downloads-filter-on-device',
                                  ),
                                  label: Text(l.downloadsFilterOnDevice),
                                  selected: _onDeviceOnly,
                                  onSelected: (_) =>
                                      setState(() => _onDeviceOnly = true),
                                ),
                                if (downloadAll != null)
                                  TextButton.icon(
                                    key: ValueKey(
                                      'downloads-all-${section.name}',
                                    ),
                                    style: TextButton.styleFrom(
                                      minimumSize: const Size(48, 48),
                                    ),
                                    onPressed: downloadAll,
                                    icon: const Icon(
                                      Icons.download_outlined,
                                      size: 18,
                                    ),
                                    label: Text(l.downloadAll),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    ...group(
                      l.downloadsHeaderOnDevice,
                      'on-device',
                      here,
                      installed: true,
                    ),
                    if (!_onDeviceOnly)
                      ...group(
                        l.downloadsHeaderAvailable,
                        'available',
                        there,
                        lead: q.isEmpty ? runningList : null,
                      ),
                    if (here.isEmpty && (_onDeviceOnly || there.isEmpty))
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            l.libraryNoMatch,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    const SliverToBoxAdapter(child: SizedBox(height: 24)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A list's header that stays at the top while its list scrolls.
class _StickyHeader extends SliverPersistentHeaderDelegate {
  _StickyHeader({
    required this.key,
    required this.title,
    required this.extent,
    required this.color,
    required this.ink,
  });

  final String key;
  final String title;
  final double extent;
  final Color color;
  final Color ink;

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      ColoredBox(
        key: ValueKey('downloads-header-$key'),
        color: color,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Semantics(
              header: true,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: ink,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ),
      );

  @override
  bool shouldRebuild(_StickyHeader old) =>
      old.title != title ||
      old.extent != extent ||
      old.color != color ||
      old.ink != ink;
}

// ─────────────────────────── the catalog ───────────────────────────

/// Builds every section's items from the download stores, and rebuilds
/// when any of them changes.
class _CatalogBuilder extends ConsumerWidget {
  const _CatalogBuilder({required this.builder});

  final Widget Function(BuildContext context, _Catalog catalog) builder;

  static double? _mean(Iterable<TaskRecord> records) {
    final p = [
      for (final r in records)
        if (r.progress >= 0) r.progress.clamp(0.0, 1.0),
    ];
    return p.isEmpty ? null : p.reduce((a, b) => a + b) / p.length;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final bg = ref.watch(backgroundRecitationsProvider);
    final downloads = ref.watch(backgroundDownloadsProvider);
    final reciters = ref.watch(recitersProvider).value ?? const <ReciterRow>[];
    final adhan = ref.watch(adhanDownloadsProvider);
    final model = ref.watch(backgroundModelDownloadProvider);
    final info = ref.watch(tasmeeModelInfoProvider).value;
    final semantic = ref.watch(semanticDownloadProvider);
    final tafsir = ref.watch(tafsirDownloadItemsProvider);
    final editions = {
      for (final e in MushafEdition.values)
        e: ref.watch(editionDownloadProvider(e)),
    };
    return ListenableBuilder(
      listenable: Listenable.merge([
        downloads.tasks,
        bg.files.changes,
        adhan.changes,
      ]),
      builder: (context, _) {
        final records = downloads.tasks.value.values;
        final digits = NumberFormatter(Localizations.localeOf(context));
        final arabic = l.localeName == 'ar';
        bool packBusy(PackPhase p) =>
            p == PackPhase.downloading ||
            p == PackPhase.verifying ||
            p == PackPhase.installing;

        // ── المصاحف
        final mushaf = [
          for (final MapEntry(key: e, value: p) in editions.entries)
            _Item(
              section: DownloadsSection.mushaf,
              id: e.name,
              title: editionName(l, e),
              installed: p.phase == PackPhase.installed,
              bytes: p.phase == PackPhase.installed
                  ? (p.total > 0 ? p.total : PagePackSpec.of(e).bytes)
                  : 0,
              busy: packBusy(p.phase),
              fraction: p.total > 0 ? p.received / p.total : null,
              row: (context) => _PackRow(
                key: ValueKey('downloads-edition-${e.name}'),
                leading: const _IconTile(Icons.menu_book_outlined),
                title: editionName(l, e),
                progress: p,
                bytes: PagePackSpec.of(e).bytes,
                onStart: ref.read(editionDownloadProvider(e).notifier).start,
                onPause: ref.read(editionDownloadProvider(e).notifier).pause,
              ),
            ),
        ];

        // ── القراءات الصوتية
        final byReciter = <int, List<TaskRecord>>{};
        for (final r in records) {
          if (r.group != BackgroundRecitations.kGroup) continue;
          final d = BackgroundRecitations.decode(r.task);
          if (d != null) (byReciter[d.reciter] ??= []).add(r);
        }
        Future<void> download(ReciterRow r) => bg.enqueueAll(
          r,
          urls: (s) => ref.read(audioHostsProvider.notifier).urls(r, s),
          displayName: plainMeta(reciterLabel(context, r)),
        );
        final recitations = <_Item>[];
        for (final r in reciters) {
          final have = bg.files.downloaded(r.id);
          var bytes = 0;
          for (final s in have) {
            try {
              bytes += bg.files.file(r.id, s).lengthSync();
            } on FileSystemException {
              // Removed meanwhile.
            }
          }
          final running = byReciter[r.id];
          final label = reciterLabel(context, r);
          recitations.add(
            _Item(
              section: DownloadsSection.recitations,
              id: '${r.id}',
              title: label,
              search: '${r.nameAr} ${r.nameEn}',
              installed: have.isNotEmpty,
              bytes: bytes,
              busy: running != null,
              fraction: running == null ? null : _mean(running),
              row: running != null
                  ? null
                  : (context) => DownloadRow(
                      key: ValueKey('downloads-reciter-${r.id}-idle'),
                      leading: ReciterAvatar(
                        id: r.id,
                        name: arabic ? r.nameAr : r.nameEn,
                      ),
                      title: label,
                      fraction: have.length / 114,
                      done: true,
                      status: have.isEmpty
                          ? l.downloadsAvailableShort
                          : l.downloadsReciterOnDevice(
                              digits(have.length),
                              digits(114),
                              _mb(context, bytes),
                            ),
                      actions: [
                        SizedBox(
                          width: 48,
                          child: Center(
                            child: have.length == 114
                                ? Icon(
                                    Icons.check_circle,
                                    color: context.tokens.colors.control,
                                    semanticLabel: l.downloadDone,
                                  )
                                : IconButton(
                                    tooltip: l.downloadStart,
                                    onPressed: () => download(r),
                                    icon: const Icon(Icons.download),
                                  ),
                          ),
                        ),
                      ],
                    ),
            ),
          );
        }
        // A running reciter is drawn by BackgroundDownloadsList: first.
        recitations.sort((a, b) => (b.busy ? 1 : 0).compareTo(a.busy ? 1 : 0));

        // ── التفاسير ومعاني القرآن
        final tafsirItems = [
          for (final i in tafsir)
            _Item(
              section: DownloadsSection.tafsir,
              id: i.id,
              title: i.title,
              search: i.author ?? '',
              installed: i.installed,
              bytes: i.installed ? i.bytes : 0,
              busy: i.busy,
              fraction: i.progress.total > 0
                  ? i.progress.received / i.progress.total
                  : null,
            ),
        ];

        // ── الأذان
        final adhanItems = [
          for (final (slug, muezzin) in [
            for (final m in muezzins) (m.slug, m),
            // «الصلاة على النبي»: the adhkar reminder's recording.
            (salawatSlug, null),
          ])
            _adhanItem(context, l, adhan, slug, muezzin, arabic, digits),
        ];

        // ── أدوات
        final modelBusy = model.active != null;
        final modelHere = info?.$1 != null;
        final resources = [
          _Item(
            section: DownloadsSection.resources,
            id: 'tasmee-model',
            title: l.tasmeeModelTitle,
            installed: modelHere,
            bytes: modelHere ? info!.$2 : 0,
            busy: modelBusy,
            fraction: modelBusy
                ? _mean([
                    for (final r in records)
                      if (r.group == BackgroundModelDownload.kGroup) r,
                  ])
                : null,
            row: (context) => modelBusy
                ? const BackgroundDownloadsList(recitations: false)
                : DownloadRow(
                    key: const ValueKey('downloads-tasmee-model-idle'),
                    leading: const _IconTile(Icons.mic_none),
                    title: l.tasmeeModelTitle,
                    fraction: modelHere ? 1 : 0,
                    done: true,
                    status: modelHere
                        ? l.downloadsOnDevice(_mb(context, info!.$2))
                        : l.downloadsAvailableShort,
                    actions: [
                      SizedBox(
                        width: 48,
                        child: Center(
                          child: modelHere
                              ? Icon(
                                  Icons.check_circle,
                                  color: context.tokens.colors.control,
                                  semanticLabel: l.downloadDone,
                                )
                              : IconButton(
                                  tooltip: l.downloadStart,
                                  onPressed: () async {
                                    final backend = ref.read(
                                      tasmeeBackendProvider,
                                    );
                                    try {
                                      final m = await backend.fetchManifest();
                                      ref
                                          .read(
                                            tasmeeModelDownloadProvider
                                                .notifier,
                                          )
                                          .start(m);
                                    } catch (_) {
                                      // Offline: the button stays.
                                    }
                                  },
                                  icon: const Icon(Icons.download),
                                ),
                        ),
                      ),
                    ],
                  ),
          ),
          _Item(
            section: DownloadsSection.resources,
            id: 'semantic',
            title: l.semanticPackName,
            installed: semantic.phase == PackPhase.installed,
            bytes: semantic.phase == PackPhase.installed
                ? (semantic.total > 0
                      ? semantic.total
                      : PagePackSpec.semantic.bytes)
                : 0,
            busy: packBusy(semantic.phase),
            fraction: semantic.total > 0
                ? semantic.received / semantic.total
                : null,
            row: (context) => _PackRow(
              key: const ValueKey('downloads-semantic'),
              leading: const _IconTile(Icons.manage_search),
              title: l.semanticPackName,
              progress: semantic,
              bytes: PagePackSpec.semantic.bytes,
              onStart: () => unawaited(
                ref.read(semanticDownloadProvider.notifier).start(),
              ),
            ),
          ),
        ];

        return builder(context, {
          DownloadsSection.mushaf: mushaf,
          DownloadsSection.recitations: recitations,
          DownloadsSection.tafsir: tafsirItems,
          DownloadsSection.adhan: adhanItems,
          DownloadsSection.resources: resources,
        });
      },
    );
  }
}

/// An adhan recording, with its muezzin's photo, downloaded, paused and
/// deleted as in the adhan library.
_Item _adhanItem(
  BuildContext context,
  AppLocalizations l,
  AdhanDownloads adhan,
  String slug,
  Muezzin? muezzin,
  bool arabic,
  NumberFormatter digits,
) {
  final st = adhan.stateOf(slug);
  final name = muezzin?.name(arabic) ?? l.salawatAudioName;
  return _Item(
    section: DownloadsSection.adhan,
    id: slug,
    title: name,
    search: muezzin == null ? '' : '${muezzin.arabic} ${muezzin.english}',
    installed: st.phase == AdhanPhase.installed,
    bytes: st.phase == AdhanPhase.installed ? st.bytes : 0,
    busy: st.phase == AdhanPhase.downloading,
    fraction: st.progress,
    row: (context) {
      final status = switch (st.phase) {
        AdhanPhase.installed => l.downloadsOnDevice(_mb(context, st.bytes)),
        AdhanPhase.downloading => l.adhanDownloading(
          '${digits((st.progress * 100).round())}٪',
        ),
        AdhanPhase.paused => l.adhanPausedState,
        AdhanPhase.failed => l.adhanFailedState,
        AdhanPhase.idle => l.downloadsAvailableShort,
      };
      final Widget action = switch (st.phase) {
        AdhanPhase.installed => IconButton(
          tooltip: l.adhanDelete(name),
          onPressed: () async {
            final ok = await confirmDeleteDownload(
              context,
              name: name,
              bytes: st.bytes,
            );
            if (ok) await adhan.delete(slug);
          },
          icon: const Icon(Icons.delete_outline),
        ),
        AdhanPhase.downloading => IconButton(
          tooltip: l.downloadPause,
          onPressed: () => adhan.pause(slug),
          icon: const Icon(Icons.pause),
        ),
        AdhanPhase.paused => IconButton(
          tooltip: l.downloadResume,
          onPressed: () => adhan.resume(slug),
          icon: const Icon(Icons.play_arrow),
        ),
        AdhanPhase.failed => IconButton(
          tooltip: l.downloadRetry,
          onPressed: () => adhan.download(slug, label: name),
          icon: const Icon(Icons.refresh),
        ),
        AdhanPhase.idle => IconButton(
          tooltip: l.adhanDownload(name),
          onPressed: () => adhan.download(slug, label: name),
          icon: const Icon(Icons.download),
        ),
      };
      return DownloadRow(
        key: ValueKey('downloads-adhan-$slug'),
        leading: muezzin == null
            ? const SizedBox.square(
                dimension: 40,
                child: Icon(Icons.graphic_eq),
              )
            : MuezzinAvatar(muezzin: muezzin, size: 40),
        title: name,
        status: '$status · ${l.adhanLicense(adhanLicense)}',
        fraction: st.progress,
        done:
            st.phase != AdhanPhase.downloading && st.phase != AdhanPhase.paused,
        actions: [
          if (muezzin != null && st.phase == AdhanPhase.installed)
            SizedBox(
              width: 48,
              child: Center(
                child: _AdhanPlayButton(muezzin: muezzin, name: name),
              ),
            ),
          SizedBox(width: 48, child: Center(child: action)),
        ],
      );
    },
  );
}

/// The muezzin whose recording the downloads center is playing.
final _adhanPlaying = ValueNotifier<String?>(null);

/// Play / stop for a downloaded muezzin, as in the adhan library: the
/// same button stops the adhan while it sounds.
class _AdhanPlayButton extends ConsumerWidget {
  const _AdhanPlayButton({required this.muezzin, required this.name});

  final Muezzin muezzin;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final native = ref.watch(prayerNativeProvider);
    final adhan = ref.watch(adhanDownloadsProvider);
    return ListenableBuilder(
      listenable: Listenable.merge([native.playing, _adhanPlaying]),
      builder: (context, _) {
        final playing =
            native.playing.value && _adhanPlaying.value == muezzin.slug;
        return IconButton(
          key: ValueKey('downloads-adhan-play-${muezzin.slug}'),
          tooltip: playing ? l.adhanStop : l.adhanPreview(name),
          onPressed: () async {
            if (playing) {
              _adhanPlaying.value = null;
              await native.stop();
              return;
            }
            final file = await adhan.fileOf(muezzin.slug, 'full.m4a');
            if (native.playing.value) await native.stop();
            _adhanPlaying.value = muezzin.slug;
            await native.play(
              [file.path],
              title: l.adhanPreview(name),
              preview: true,
            );
          },
          icon: Icon(
            playing ? Icons.stop_circle_outlined : Icons.play_circle_outline,
          ),
        );
      },
    );
  }
}

String _mb(BuildContext context, int bytes) =>
    NumberFormatter(Localizations.localeOf(context))
        .decimal((bytes / 1e6).toStringAsFixed(1));

/// A pack the system downloads (an edition, the meaning search).
class _PackRow extends StatelessWidget {
  const _PackRow({
    super.key,
    required this.title,
    required this.progress,
    required this.bytes,
    required this.onStart,
    this.onPause,
    this.leading,
  });

  final String title;
  final PackProgress progress;
  final int bytes;
  final VoidCallback onStart;
  final VoidCallback? onPause;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens.colors;
    final p = progress;
    final total = p.total > 0 ? p.total : bytes;
    String mb(int b) => _mb(context, b);
    final fraction = switch (p.phase) {
      PackPhase.downloading || PackPhase.idle => p.received / total,
      PackPhase.verifying || PackPhase.installing => null,
      PackPhase.installed => 1.0,
      PackPhase.failed => p.received / total,
    };
    final status = switch (p.phase) {
      PackPhase.idle when p.received == 0 => l.downloadsAvailable(mb(total)),
      PackPhase.idle ||
      PackPhase.downloading => l.downloadProgress(mb(p.received), mb(total)),
      PackPhase.verifying => l.downloadVerifying,
      PackPhase.installing => l.downloadInstalling,
      PackPhase.installed => l.downloadsOnDevice(mb(total)),
      PackPhase.failed => l.downloadFailed(p.error ?? ''),
    };
    final Widget? action = switch (p.phase) {
      PackPhase.installed => Icon(
        Icons.check_circle,
        color: t.control,
        semanticLabel: l.downloadDone,
      ),
      PackPhase.verifying || PackPhase.installing => null,
      PackPhase.downloading =>
        onPause == null
            ? const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : IconButton(
                tooltip: l.downloadPause,
                onPressed: onPause,
                icon: const Icon(Icons.pause),
              ),
      PackPhase.failed => IconButton(
        tooltip: l.downloadRetry,
        onPressed: onStart,
        icon: const Icon(Icons.refresh),
      ),
      PackPhase.idle => IconButton(
        tooltip: p.received > 0 ? l.downloadResume : l.downloadStart,
        onPressed: onStart,
        icon: Icon(p.received > 0 ? Icons.play_arrow : Icons.download),
      ),
    };
    return DownloadRow(
      leading: leading,
      title: title,
      status: status,
      fraction: fraction,
      done:
          p.phase == PackPhase.installed ||
          (p.phase == PackPhase.idle && p.received == 0),
      actions: [
        SizedBox(
          width: 48,
          child: Center(child: action ?? const SizedBox.shrink()),
        ),
      ],
    );
  }
}
