import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/downloads/background_downloads.dart';
import 'adhan_catalog.dart';

/// Whether this platform takes the PCM cut as its notification sound.
bool get isApplePlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS);

/// Whether [file] exists and its SHA-256 is [hex].
Future<bool> fileMatches(File file, String hex) async {
  if (!await file.exists()) return false;
  final digest = await sha256.bind(file.openRead()).first;
  return digest.toString() == hex.toLowerCase();
}

/// Where a muezzin stands on this device.
enum AdhanPhase { idle, downloading, paused, failed, installed }

@immutable
class AdhanState {
  const AdhanState(this.phase, {this.progress = 0, this.bytes = 0});

  final AdhanPhase phase;

  /// 0…1 while downloading or paused.
  final double progress;

  /// On the device, once installed.
  final int bytes;
}

/// The adhan recordings, downloaded by the app's one background downloader
/// like the recitations and the mushaf packs: the Wi‑Fi‑only policy and
/// its banner, the notification while they run, pause / resume / retry,
/// and «مركز التحميلات» all apply. Each file is one task and is kept only
/// when its SHA-256 matches the server's `SHA256SUMS`.
class AdhanDownloads implements DownloadHandler {
  AdhanDownloads({
    required BackgroundDownloads downloads,
    Future<Directory> Function()? supportDir,
    Future<String> Function(Uri url)? fetchText,
    bool? apple,
  }) : _downloads = downloads,
       _supportDir = supportDir ?? getApplicationSupportDirectory,
       _fetchText = fetchText ?? _httpText,
       apple = apple ?? isApplePlatform {
    downloads.register(this);
  }

  static const kGroup = 'adhan-download';
  static const folder = 'adhan-downloads';

  /// The notification title, in the interface language.
  static String displayName = 'الأذان';

  final BackgroundDownloads _downloads;
  final Future<Directory> Function() _supportDir;
  final Future<String> Function(Uri url) _fetchText;
  final bool apple;

  /// Bumped when a recording is installed or deleted.
  final changes = ValueNotifier<int>(0);

  /// Slugs whose last download failed its checksum or the network.
  final failed = <String>{};

  Map<String, String>? _sums;
  final _installed = <String, int>{};
  final _placing = <String>{};

  static Future<String> _httpText(Uri url) async {
    final r = await http.get(url).timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) throw HttpException('${r.statusCode}', uri: url);
    return utf8.decode(r.bodyBytes);
  }

  @override
  String get group => kGroup;

  @override
  get notifications => (
    running: TaskNotification(displayName, '{displayName}'),
    complete: TaskNotification(displayName, '{displayName}'),
    error: TaskNotification(displayName, '{displayName}'),
    paused: TaskNotification(displayName, '{displayName}'),
    groupNotificationId: kGroup,
  );

  List<String> filesOf(String slug) => switch (slug) {
    duaSlug => duaFilesFor(apple: apple),
    salawatSlug => salawatFilesFor(apple: apple),
    _ => adhanFilesFor(apple: apple),
  };

  Future<Directory> dirOf(String slug) async => Directory(
    p.join((await _supportDir()).path, 'adhan', adhanFolderOf(slug)),
  );

  Future<File> fileOf(String slug, String name) async =>
      File(p.join((await dirOf(slug)).path, name));

  static String taskIdFor(String slug, String file) => 'adhan-$slug-$file';

  static ({String slug, String file, String hash})? decode(Task task) {
    try {
      final j = jsonDecode(task.metaData) as Map<String, dynamic>;
      return (
        slug: j['s'] as String,
        file: j['f'] as String,
        hash: j['h'] as String,
      );
    } catch (_) {
      return null;
    }
  }

  /// Reads which recordings are on the device (at startup and after a
  /// change); every file must be present.
  Future<void> refresh() async {
    _installed.clear();
    for (final slug in [...muezzins.map((m) => m.slug), duaSlug, salawatSlug]) {
      var bytes = 0;
      var all = true;
      for (final f in filesOf(slug)) {
        final file = await fileOf(slug, f);
        if (!await file.exists()) {
          all = false;
          break;
        }
        bytes += await file.length();
      }
      if (all) _installed[slug] = bytes;
    }
    changes.value++;
  }

  bool isInstalled(String slug) => _installed.containsKey(slug);

  Iterable<TaskRecord> _records(String slug) => _downloads.tasks.value.values
      .where((r) => r.group == kGroup && decode(r.task)?.slug == slug);

  AdhanState stateOf(String slug) {
    final bytes = _installed[slug];
    if (bytes != null) return AdhanState(AdhanPhase.installed, bytes: bytes);
    final records = _records(slug).toList();
    if (records.isEmpty) {
      return AdhanState(
        failed.contains(slug) ? AdhanPhase.failed : AdhanPhase.idle,
      );
    }
    final n = filesOf(slug).length;
    final done = n - records.length;
    var sum = done.toDouble();
    var paused = false;
    var bad = false;
    for (final r in records) {
      sum += r.progress.clamp(0.0, 1.0);
      if (r.status == TaskStatus.paused) paused = true;
      if (r.status == TaskStatus.failed || r.status == TaskStatus.notFound) {
        bad = true;
      }
    }
    final progress = (sum / n).clamp(0.0, 1.0);
    if (bad) return AdhanState(AdhanPhase.failed, progress: progress);
    return AdhanState(
      paused ? AdhanPhase.paused : AdhanPhase.downloading,
      progress: progress,
    );
  }

  Future<Map<String, String>> _checksums() async => _sums ??= parseSums(
    await _fetchText(Uri.parse('$adhanBaseUrl/SHA256SUMS')),
  );

  /// Queues every missing file of [slug]. False when the checksums could
  /// not be read (offline).
  Future<bool> download(String slug, {String? label}) async {
    failed.remove(slug);
    final Map<String, String> sums;
    try {
      sums = await _checksums();
    } catch (_) {
      failed.add(slug);
      changes.value++;
      return false;
    }
    for (final f in filesOf(slug)) {
      final hash = sums['${adhanFolderOf(slug)}/$f'];
      if (hash == null) continue;
      final target = await fileOf(slug, f);
      if (await fileMatches(target, hash)) continue;
      final id = taskIdFor(slug, f);
      final record = _downloads.tasks.value[id];
      if (record != null) {
        if (record.status == TaskStatus.paused) {
          if (await _downloads.resume(id)) continue;
        }
        await _downloads.forget(id);
      }
      await _downloads.enqueue(
        DownloadTask(
          taskId: id,
          url: '$adhanBaseUrl/${adhanFolderOf(slug)}/$f',
          filename: '$slug-$f',
          directory: folder,
          baseDirectory: BaseDirectory.applicationSupport,
          group: kGroup,
          updates: Updates.statusAndProgress,
          allowPause: true,
          retries: 3,
          displayName: label ?? slug,
          metaData: jsonEncode({'s': slug, 'f': f, 'h': hash}),
          transferHints: {TransferHint.userInitiated},
        ),
      );
    }
    await refresh();
    return true;
  }

  Future<void> pause(String slug) async {
    for (final r in _records(slug).toList()) {
      await _downloads.pause(r.taskId);
    }
  }

  Future<void> resume(String slug) async {
    var all = true;
    for (final r in _records(slug).toList()) {
      if (!await _downloads.resume(r.taskId)) all = false;
    }
    if (!all) await download(slug);
  }

  Future<void> cancel(String slug) async {
    await _downloads.cancel(_records(slug).map((r) => r.taskId).toList());
    changes.value++;
  }

  /// Removes [slug]'s recordings from the device.
  Future<void> delete(String slug) async {
    await cancel(slug);
    // Only its own files: the dua and the salawat share a folder.
    for (final f in filesOf(slug)) {
      final file = await fileOf(slug, f);
      if (await file.exists()) await file.delete();
    }
    final dir = await dirOf(slug);
    if (await dir.exists()) {
      final left = await dir.list().toList();
      if (left.whereType<File>().isEmpty) await dir.delete(recursive: true);
    }
    await refresh();
  }

  @override
  Future<void> onUpdate(TaskUpdate update) async {
    final task = update.task;
    if (task is! DownloadTask) return;
    if (update case TaskStatusUpdate(:final status)) {
      if (status == TaskStatus.complete) {
        await _place(task);
      } else if (status == TaskStatus.failed || status == TaskStatus.notFound) {
        final d = decode(task);
        if (d != null) failed.add(d.slug);
      }
    }
    changes.value++;
  }

  @override
  Future<void> onFinishedWhileAway(DownloadTask task) => _place(task);

  /// Checks a finished file's SHA-256 and moves it into its muezzin's
  /// folder; a file that does not match is deleted and the download marked
  /// failed (the reader retries it).
  Future<void> _place(DownloadTask task) async {
    final d = decode(task);
    if (d == null || !_placing.add(task.taskId)) return;
    try {
      final tmp = File(
        p.join((await _supportDir()).path, folder, task.filename),
      );
      final target = await fileOf(d.slug, d.file);
      if (!await fileMatches(tmp, d.hash)) {
        if (await tmp.exists()) await tmp.delete();
        failed.add(d.slug);
      } else {
        await target.parent.create(recursive: true);
        if (await target.exists()) await target.delete();
        try {
          await tmp.rename(target.path);
        } on FileSystemException {
          await tmp.copy(target.path);
          await tmp.delete();
        }
      }
      await _downloads.forget(task.taskId);
      await refresh();
    } catch (_) {
      failed.add(d.slug);
    } finally {
      _placing.remove(task.taskId);
    }
  }
}

/// The app's one [AdhanDownloads].
final adhanDownloadsProvider = Provider<AdhanDownloads>((ref) {
  final a = AdhanDownloads(downloads: ref.watch(backgroundDownloadsProvider));
  unawaited(a.refresh().catchError((_) {}));
  return a;
});
