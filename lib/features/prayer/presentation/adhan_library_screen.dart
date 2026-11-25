import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/look_kit.dart';
import '../../../core/ui/responsive.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/ui/app_toast.dart';
import '../../../core/ui/confirm_delete_download.dart';
import '../../mushaf/presentation/widgets/illuminated_frame.dart'
    show NumberFormatter;
import '../data/adhan_catalog.dart';
import '../data/adhan_downloads.dart';
import '../prayer_providers.dart';
import '../services/prayer_native.dart';
import '../services/prayer_runtime.dart';

/// The muezzin's photo, always: the downloaded file when his recordings
/// are on the device, otherwise fetched from the server and cached. The
/// first letter of the name only while it loads or when offline.
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
          child: ValueListenableBuilder<int>(
            valueListenable: adhan.changes,
            builder: (context, _, _) => FutureBuilder<File?>(
              future: adhan.photoOf(muezzin.slug),
              builder: (context, snap) => snap.data == null
                  ? Center(child: letter)
                  : Image.file(
                      snap.data!,
                      key: ValueKey('muezzin-photo-${muezzin.slug}'),
                      fit: BoxFit.cover,
                      cacheWidth: (size * 3).round(),
                      errorBuilder: (_, _, _) => Center(child: letter),
                    ),
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

  /// The muezzin whose play was pressed before his recordings were on the
  /// device: they are downloading, and play when they arrive.
  String? _waiting;

  /// Read once: `ref` must not be used in [dispose] (the element is
  /// already unmounting then).
  late final PrayerNative _native = ref.read(prayerNativeProvider);

  @override
  void initState() {
    super.initState();
    _native.playing.addListener(_onPlaying);
    _adhan.changes.addListener(_onAdhanChange);
  }

  late final AdhanDownloads _adhan = ref.read(adhanDownloadsProvider);

  void _onAdhanChange() {
    final slug = _waiting;
    if (slug == null || !mounted) return;
    switch (_adhan.stateOf(slug).phase) {
      case AdhanPhase.installed:
        setState(() => _waiting = null);
        unawaited(_play(muezzinOf(slug)));
      case AdhanPhase.failed:
        setState(() => _waiting = null);
        _failed(muezzinOf(slug));
      default:
        break;
    }
  }

  void _failed(Muezzin m) {
    final l = AppLocalizations.of(context);
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        appToast(
          content: Text(l.downloadFailedOne(m.name(l.localeName == 'ar'))),
          action: SnackBarAction(
            label: l.downloadRetry,
            onPressed: () => _preview(m),
          ),
        ),
      );
  }

  /// The row shows «stop» from the real playing state (see build), so a
  /// late «stopped» from the previous sound can't leave a wrong icon.
  void _onPlaying() {
    if (mounted) setState(() {});
  }

  bool _isPreviewing(String slug) =>
      _previewing == slug && _native.playing.value;

  @override
  void dispose() {
    _native.playing.removeListener(_onPlaying);
    _adhan.changes.removeListener(_onAdhanChange);
    if (_previewing != null) unawaited(_native.stop());
    super.dispose();
  }

  /// Plays [m]'s full recording; one not on the device is downloaded
  /// first (kept afterwards) and then plays. A second tap stops the
  /// playback or cancels the download.
  Future<void> _preview(Muezzin m) async {
    final native = ref.read(prayerNativeProvider);
    if (_isPreviewing(m.slug)) {
      setState(() => _previewing = null);
      await native.stop();
      return;
    }
    if (_waiting == m.slug) {
      setState(() => _waiting = null);
      await _adhan.cancel(m.slug);
      return;
    }
    if (_adhan.isInstalled(m.slug)) return _play(m);
    final l = AppLocalizations.of(context);
    setState(() => _waiting = m.slug);
    final ok = await _adhan.download(
      m.slug,
      label: m.name(l.localeName == 'ar'),
      quiet: true,
    );
    if (!mounted || _waiting != m.slug) return;
    if (!ok) {
      setState(() => _waiting = null);
      _failed(m);
    } else {
      _onAdhanChange();
    }
  }

  Future<void> _play(Muezzin m) async {
    final native = ref.read(prayerNativeProvider);
    final src = (await _adhan.fileOf(m.slug, 'full.m4a')).path;
    if (!mounted) return;
    final l = AppLocalizations.of(context);
    if (_previewing != null) await native.stop();
    if (!mounted) return;
    setState(() => _previewing = m.slug);
    // In the app only: a preview posts no notification.
    await native.play(
      [src],
      title: l.adhanPreview(m.name(l.localeName == 'ar')),
      preview: true,
    );
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
                          previewing: _isPreviewing(m.slug),
                          waiting: _waiting == m.slug,
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
    this.waiting = false,
    this.onPreview,
  });

  final Muezzin muezzin;
  final bool previewing;

  /// Play was pressed before the recordings were on the device: the
  /// button shows the download's progress and cancels it.
  final bool waiting;
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
        name: name,
        bytes: state.bytes,
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
              key: ValueKey('adhan-play-${muezzin.slug}'),
              tooltip: waiting
                  ? l.downloadCancelItem(name)
                  : l.adhanPreview(name),
              onPressed: onPreview,
              icon: waiting
                  ? Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox.square(
                          dimension: 28,
                          child: CircularProgressIndicator(
                            value:
                                state.phase == AdhanPhase.downloading &&
                                    state.progress > 0
                                ? state.progress
                                : null,
                            strokeWidth: 2.5,
                          ),
                        ),
                        const Icon(Icons.close, size: 16),
                      ],
                    )
                  : Icon(previewing ? Icons.stop : Icons.play_arrow),
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
