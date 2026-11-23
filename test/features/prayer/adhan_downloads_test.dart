import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tibyan/core/downloads/background_downloads.dart';
import 'package:tibyan/core/downloads/cellular_policy.dart';
import 'package:tibyan/features/prayer/data/adhan_catalog.dart';
import 'package:tibyan/features/prayer/data/adhan_downloads.dart';
import 'package:tibyan/features/prayer/domain/prayer_settings.dart';
import 'package:tibyan/features/prayer/services/prayer_alarms.dart';
import 'package:tibyan/features/prayer/services/prayer_native.dart';

import '../../downloads/background_downloads_test.dart' show FakeDownloader;

String hex(List<int> bytes) => sha256.convert(bytes).toString();

void main() {
  late Directory support;
  late FakeDownloader fake;
  late BackgroundDownloads downloads;
  late Map<String, List<int>> server;
  var offline = false;

  AdhanDownloads make({bool apple = false}) => AdhanDownloads(
    downloads: downloads,
    supportDir: () async => support,
    apple: apple,
    fetchText: (url) async {
      if (offline) throw const SocketException('offline');
      expect(url.toString(), '$adhanBaseUrl/SHA256SUMS');
      return [for (final e in server.entries) '${hex(e.value)}  ${e.key}']
          .join('\n');
    },
  );

  /// The system finished [task]: its file arrives with [bytes].
  Future<void> finish(DownloadTask task, List<int> bytes) async {
    final f = File(p.join(support.path, AdhanDownloads.folder, task.filename));
    await f.parent.create(recursive: true);
    await f.writeAsBytes(bytes);
    fake.send(TaskStatusUpdate(task, TaskStatus.complete));
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  setUp(() async {
    offline = false;
    support = await Directory.systemTemp.createTemp('adhan');
    fake = FakeDownloader();
    downloads = BackgroundDownloads(downloader: fake);
    server = {
      for (final f in ['full.m4a', 'short.m4a', 'short.caf', 'photo.jpg'])
        'refaat/$f': utf8.encode('refaat $f'),
      'extras/dua_shaarawy.m4a': utf8.encode('dua'),
      'extras/dua_shaarawy.caf': utf8.encode('dua caf'),
    };
  });

  tearDown(() => support.delete(recursive: true));

  test('the catalog: thirteen muezzins, Refaat first', () {
    expect(muezzins, hasLength(13));
    expect(muezzins.first.slug, 'refaat');
    expect(muezzins.map((m) => m.slug).toSet(), hasLength(13));
    expect(muezzinOf('nope').slug, 'refaat');
  });

  test('parses SHA256SUMS', () {
    final sums = parseSums(
      '${'a' * 64}  refaat/full.m4a\n${'B' * 64} *extras/dua.m4a\nbroken\n',
    );
    expect(sums['refaat/full.m4a'], 'a' * 64);
    expect(sums['extras/dua.m4a'], 'b' * 64);
    expect(sums, hasLength(2));
  });

  test('queues each file in the shared downloader, in its own group', () async {
    final a = make();
    await downloads.start();
    expect(await a.download('refaat', label: 'محمد رفعت'), isTrue);
    expect(fake.enqueued.map((t) => t.url), [
      '$adhanBaseUrl/refaat/full.m4a',
      '$adhanBaseUrl/refaat/short.m4a',
      '$adhanBaseUrl/refaat/photo.jpg',
    ]);
    expect(
      fake.enqueued.every((t) => t.group == AdhanDownloads.kGroup),
      isTrue,
    );
    expect(fake.enqueued.first.displayName, 'محمد رفعت');
    expect(a.stateOf('refaat').phase, AdhanPhase.downloading);
  });

  test('Apple platforms also fetch the PCM cut for the notification', () async {
    final a = make(apple: true);
    await downloads.start();
    await a.download('refaat');
    expect(fake.enqueued.map((t) => p.basename(t.url)), contains('short.caf'));
  });

  test('a file is kept only when its SHA-256 matches', () async {
    final a = make();
    await downloads.start();
    await a.download('refaat');
    final tasks = [...fake.enqueued];
    // A corrupted full.m4a is deleted and the download marked failed.
    await finish(tasks[0], utf8.encode('tampered'));
    expect(await (await a.fileOf('refaat', 'full.m4a')).exists(), isFalse);
    expect(a.failed, contains('refaat'));
    // The right bytes: placed, and once all are in, installed.
    await a.download('refaat');
    final again = fake.enqueued.where((t) => t.filename.endsWith('full.m4a'));
    await finish(again.last, server['refaat/full.m4a']!);
    await finish(tasks[1], server['refaat/short.m4a']!);
    await finish(tasks[2], server['refaat/photo.jpg']!);
    expect(a.isInstalled('refaat'), isTrue);
    expect(a.stateOf('refaat').phase, AdhanPhase.installed);
  });

  test('offline: nothing queued, the state says failed', () async {
    offline = true;
    final a = make();
    await downloads.start();
    expect(await a.download('refaat'), isFalse);
    expect(fake.enqueued, isEmpty);
    expect(a.stateOf('refaat').phase, AdhanPhase.failed);
  });

  test('delete removes the recordings', () async {
    final a = make();
    final dir = await a.dirOf('refaat');
    await dir.create(recursive: true);
    for (final f in adhanFilesFor(apple: false)) {
      await File(p.join(dir.path, f)).writeAsString('x');
    }
    await a.refresh();
    expect(a.isInstalled('refaat'), isTrue);
    await a.delete('refaat');
    expect(a.isInstalled('refaat'), isFalse);
    expect(await dir.exists(), isFalse);
  });

  group('download policy (shared with every other download)', () {
    test(
      'adhan downloads count as pending for the mobile-data banner',
      () async {
        final a = make();
        await downloads.start();
        await a.download('refaat');
        final pending = pendingOf(downloads.tasks.value.values);
        expect(pending.count, 3);
        expect(
          showCellularBanner(
            applies: true,
            state: const CellularState(net: NetKind.cellular),
            alwaysAllowed: false,
            pending: pending.count,
          ),
          isTrue,
        );
      },
    );

    test('they wait for Wi‑Fi unless mobile data is allowed', () {
      expect(wifiOnly(alwaysAllowed: false, allowedForNow: false), isTrue);
      expect(wifiOnly(alwaysAllowed: false, allowedForNow: true), isFalse);
      expect(wifiOnly(alwaysAllowed: true, allowedForNow: false), isFalse);
    });

    test('a paused adhan download is not pending', () async {
      final a = make();
      await downloads.start();
      await a.download('refaat');
      for (final t in [...fake.enqueued]) {
        fake.send(TaskStatusUpdate(t, TaskStatus.paused));
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(pendingOf(downloads.tasks.value.values).count, 0);
      expect(a.stateOf('refaat').phase, AdhanPhase.paused);
    });
  });

  test('alerts get downloaded file paths, never server links', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final a = make();
    final dir = await a.dirOf('refaat');
    await dir.create(recursive: true);
    for (final f in adhanFilesFor(apple: false)) {
      await File(p.join(dir.path, f)).writeAsString('x');
    }
    await a.refresh();
    final alarms = PrayerAlarms(
      plugin: () async => null,
      native: PrayerNative(),
      adhan: a,
    );
    // Ali Mahmoud chosen but not downloaded: Refaat's file plays.
    final files = await alarms.adhanFiles(
      const PrayerSettings(muezzin: 'ali_mahmoud'),
    );
    expect(files, [p.join(dir.path, 'full.m4a')]);
    expect(files.every((f) => !f.startsWith('http')), isTrue);
    final short = await alarms.adhanFiles(
      const PrayerSettings(length: AdhanLength.short),
    );
    expect(short.single, endsWith('short.m4a'));
    // Nothing on the device: no files (the tone).
    await a.delete('refaat');
    expect(await alarms.adhanFiles(const PrayerSettings()), isEmpty);
  });

  test('each prayer gets its own files, with the fallback chain', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final a = make();
    Future<Directory> install(String slug) async {
      final dir = await a.dirOf(slug);
      await dir.create(recursive: true);
      for (final f in adhanFilesFor(apple: false)) {
        await File(p.join(dir.path, f)).writeAsString('x');
      }
      return dir;
    }

    final refaat = await install('refaat');
    final minshawi = await install('minshawi');
    await a.refresh();
    final alarms = PrayerAlarms(
      plugin: () async => null,
      native: PrayerNative(),
      adhan: a,
    );
    const s = PrayerSettings(
      muezzin: 'refaat',
      custom: {
        PrayerKind.fajr: PrayerAdhan(
          muezzin: 'minshawi',
          length: AdhanLength.short,
          volume: 0.3,
        ),
        PrayerKind.isha: PrayerAdhan(muezzin: 'ali_mahmoud'),
      },
    );
    expect(await alarms.adhanFiles(s, prayer: PrayerKind.fajr), [
      p.join(minshawi.path, 'short.m4a'),
    ]);
    expect(s.forPrayer(PrayerKind.fajr).adhanVolume, 0.3);
    // Others follow the general settings.
    expect(await alarms.adhanFiles(s, prayer: PrayerKind.dhuhr), [
      p.join(refaat.path, 'full.m4a'),
    ]);
    expect(s.forPrayer(PrayerKind.dhuhr).adhanVolume, 0.7);
    // Its own muezzin not downloaded: the general one.
    expect(alarms.slugFor(s, PrayerKind.isha), 'refaat');
    // The general one gone too: the default, then nothing (the tone).
    await a.delete('refaat');
    const s2 = PrayerSettings(
      muezzin: 'minshawi',
      custom: {PrayerKind.isha: PrayerAdhan(muezzin: 'ali_mahmoud')},
    );
    expect(alarms.slugFor(s2, PrayerKind.isha), 'minshawi');
    await a.delete('minshawi');
    expect(await alarms.adhanFiles(s2, prayer: PrayerKind.isha), isEmpty);
  });
}
