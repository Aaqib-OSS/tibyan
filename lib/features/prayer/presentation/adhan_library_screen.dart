import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/look_kit.dart';
import '../../../core/ui/responsive.dart';
import '../../../l10n/app_localizations.dart';
import '../../audio/audio_downloads_screen.dart' show confirmDeleteDownload;
import '../../mushaf/presentation/widgets/illuminated_frame.dart'
    show NumberFormatter;
import '../data/adhan_catalog.dart';
import '../data/adhan_downloads.dart';
import '../prayer_providers.dart';
import '../services/prayer_runtime.dart';

/// The muezzin's photo once downloaded; the first letter of the name
/// until then (nothing is bundled).
class MuezzinAvatar extends ConsumerWidget {
  const MuezzinAvatar({super.key, required this.muezzin, this.size = 44});

  final Muezzin muezzin;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens.colors;
    final adhan = ref.watch(adhanDownloadsProvider);
    final arabic = Localizations.localeOf(context).languageCode == 'ar';
    final letter = Text(
      muezzin.name(arabic).characters.first,
      style: TextStyle(color: t.goldText, fontWeight: FontWeight.w700),
    );
    return SizedBox.square(
      dimension: size,
      child: ClipOval(
        child: ColoredBox(
          color: t.control.withValues(alpha: .15),
          child: !adhan.isInstalled(muezzin.slug)
              ? Center(child: letter)
              : FutureBuilder<File>(
                  future: adhan.fileOf(muezzin.slug, 'photo.jpg'),
                  builder: (context, snap) => snap.data == null
                      ? Center(child: letter)
                      : Image.file(
                          snap.data!,
                          fit: BoxFit.cover,
                          cacheWidth: (size * 3).round(),
                          errorBuilder: (_, _, _) => Center(child: letter),
                        ),
                ),
        ),
      ),
    );
  }
}

/// «مكتبة الأذان»: every muezzin, with a preview before downloading,
/// download / pause / delete as for every other download, and the
/// licence line under each name.
class AdhanLibraryScreen extends ConsumerStatefulWidget {
  const AdhanLibraryScreen({super.key});

  @override
  ConsumerState<AdhanLibraryScreen> createState() => _AdhanLibraryScreenState();
}

class _AdhanLibraryScreenState extends ConsumerState<AdhanLibraryScreen> {
  String? _previewing;

  @override
  void dispose() {
    if (_previewing != null) unawaited(ref.read(prayerNativeProvider).stop());
    super.dispose();
  }

  Future<void> _preview(Muezzin m) async {
    final native = ref.read(prayerNativeProvider);
    if (_previewing == m.slug) {
      setState(() => _previewing = null);
      await native.stop();
      return;
    }
    final adhan = ref.read(adhanDownloadsProvider);
    final src = adhan.isInstalled(m.slug)
        ? (await adhan.fileOf(m.slug, 'full.m4a')).path
        : '$adhanBaseUrl/${m.slug}/full.m4a';
    if (!mounted) return;
    final l = AppLocalizations.of(context);
    setState(() => _previewing = m.slug);
    await native.play([
      src,
    ], title: l.adhanPreview(m.name(l.localeName == 'ar')));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens.colors;
    final adhan = ref.watch(adhanDownloadsProvider);
    final native = ref.watch(prayerNativeProvider);
    return LookScaffold(
      maxWidth: ContentWidth.text,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            LookTopBar(title: l.adhanLibraryTitle),
            Expanded(
              child: ListenableBuilder(
                listenable: Listenable.merge([adhan.changes, native.playing]),
                builder: (context, _) {
                  if (!native.playing.value && _previewing != null) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() => _previewing = null);
                    });
                  }
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    children: [
                      Text(
                        l.adhanLibraryIntro,
                        style: TextStyle(
                          color: t.muted,
                          fontSize: 13,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 12),
                      for (final m in muezzins)
                        AdhanLibraryRow(
                          key: ValueKey('adhan-row-${m.slug}'),
                          muezzin: m,
                          previewing: _previewing == m.slug,
                          onPreview: () => _preview(m),
                        ),
                    ],
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

/// One muezzin: photo, name, state and licence, preview, choose, and the
/// download's own actions.
class AdhanLibraryRow extends ConsumerWidget {
  const AdhanLibraryRow({
    super.key,
    required this.muezzin,
    this.previewing = false,
    this.onPreview,
  });

  final Muezzin muezzin;
  final bool previewing;
  final VoidCallback? onPreview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = context.tokens.colors;
    final arabic = l.localeName == 'ar';
    final digits = NumberFormatter(Localizations.localeOf(context));
    final adhan = ref.watch(adhanDownloadsProvider);
    final settings = ref.watch(prayerSettingsProvider);
    final selected = settings.muezzin == muezzin.slug;
    final state = adhan.stateOf(muezzin.slug);
    final name = muezzin.name(arabic);
    final label = name;
    String mb(int b) => digits.decimal((b / 1e6).toStringAsFixed(1));
    final status = switch (state.phase) {
      AdhanPhase.installed => '${l.adhanDownloaded} · ${mb(state.bytes)} MB',
      AdhanPhase.downloading => l.adhanDownloading(
        '${digits((state.progress * 100).round())}٪',
      ),
      AdhanPhase.paused => l.adhanPausedState,
      AdhanPhase.failed => l.adhanFailedState,
      AdhanPhase.idle => l.adhanNotDownloaded,
    };
    Future<void> download() => adhan.download(muezzin.slug, label: name);
    Future<void> delete() async {
      final ok = await confirmDeleteDownload(
        context,
        title: l.adhanDeleteTitle(name),
        body: l.adhanDeleteBody,
      );
      if (ok) await adhan.delete(muezzin.slug);
    }

    final Widget action = switch (state.phase) {
      AdhanPhase.installed => IconButton(
        key: ValueKey('adhan-delete-${muezzin.slug}'),
        tooltip: l.adhanDelete(name),
        onPressed: delete,
        icon: const Icon(Icons.delete_outline),
      ),
      AdhanPhase.downloading => IconButton(
        tooltip: l.pause,
        onPressed: () => adhan.pause(muezzin.slug),
        icon: const Icon(Icons.pause),
      ),
      AdhanPhase.paused => IconButton(
        tooltip: l.downloadResume,
        onPressed: () => adhan.resume(muezzin.slug),
        icon: const Icon(Icons.play_arrow),
      ),
      AdhanPhase.failed => IconButton(
        tooltip: l.downloadRetry,
        onPressed: download,
        icon: const Icon(Icons.refresh),
      ),
      AdhanPhase.idle => IconButton(
        key: ValueKey('adhan-download-${muezzin.slug}'),
        tooltip: l.adhanDownload(name),
        onPressed: download,
        icon: const Icon(Icons.download),
      ),
    };
    return Card(
      color: selected ? t.goldText.withValues(alpha: .08) : null,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(8, 8, 4, 8),
        child: Row(
          children: [
            IconButton(
              tooltip: l.adhanPreview(name),
              onPressed: onPreview,
              icon: Icon(previewing ? Icons.stop : Icons.play_arrow),
            ),
            MuezzinAvatar(muezzin: muezzin),
            const SizedBox(width: 10),
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: selected ? t.goldText : null,
                      ),
                    ),
                    Text(
                      status,
                      style: TextStyle(color: t.muted, fontSize: 12),
                    ),
                    Text(
                      l.adhanLicense(adhanLicense),
                      style: TextStyle(color: t.muted, fontSize: 11),
                    ),
                    if (state.phase == AdhanPhase.downloading ||
                        state.phase == AdhanPhase.paused) ...[
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: state.progress,
                        minHeight: 4,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (selected)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Chip(
                  label: Text(l.adhanSelected),
                  visualDensity: VisualDensity.compact,
                ),
              )
            else
              TextButton(
                key: ValueKey('adhan-select-${muezzin.slug}'),
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: () async {
                  await ref
                      .read(prayerSettingsProvider.notifier)
                      .update((s) => s.copyWith(muezzin: muezzin.slug));
                  if (!adhan.isInstalled(muezzin.slug)) await download();
                },
                child: Text(l.adhanSelect),
              ),
            action,
          ],
        ),
      ),
    );
  }
}
