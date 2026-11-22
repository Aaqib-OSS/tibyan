import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tibyan/core/net/server.dart';
import 'package:tibyan/core/update/windows_updater.dart';

void main() {
  group('FallbackClient', () {
    test('primary answers: no retry', () async {
      final hosts = <String>[];
      final c = FallbackClient(
        MockClient((r) async {
          hosts.add(r.url.host);
          return http.Response('ok', 200);
        }),
      );
      final r = await c.get(Uri.parse('$serverBase/mirror/a.json'));
      expect(r.body, 'ok');
      expect(hosts, [primaryServerHost]);
    });

    test('5xx on primary retries the same path on the old host', () async {
      final urls = <Uri>[];
      final c = FallbackClient(
        MockClient((r) async {
          urls.add(r.url);
          return r.url.host == primaryServerHost
              ? http.Response('down', 503)
              : http.Response('ok', 200);
        }),
      );
      final r = await c.get(
        Uri.parse('$serverBase/mirror/a.json?x=1'),
        headers: {'Range': 'bytes=10-'},
      );
      expect(r.statusCode, 200);
      expect(
        urls.last.toString(),
        'https://$fallbackServerHost/mirror/a.json?x=1',
      );
    });

    test('headers are carried to the retry', () async {
      String? range;
      final c = FallbackClient(
        MockClient((r) async {
          if (r.url.host == primaryServerHost) {
            throw const SocketException('no route');
          }
          range = r.headers['Range'];
          return http.Response('ok', 206);
        }),
      );
      final r = await c.get(
        Uri.parse('$serverBase/win/x.exe'),
        headers: {'Range': 'bytes=10-'},
      );
      expect(r.statusCode, 206);
      expect(range, 'bytes=10-');
    });

    test('network error on primary retries on the old host', () async {
      final hosts = <String>[];
      final c = FallbackClient(
        MockClient((r) async {
          hosts.add(r.url.host);
          if (r.url.host == primaryServerHost) {
            throw http.ClientException('offline');
          }
          return http.Response('ok', 200);
        }),
      );
      expect((await c.get(Uri.parse('$serverBase/a'))).body, 'ok');
      expect(hosts, [primaryServerHost, fallbackServerHost]);
    });

    test('4xx is final: no retry', () async {
      var calls = 0;
      final c = FallbackClient(
        MockClient((r) async {
          calls++;
          return http.Response('', 404);
        }),
      );
      expect((await c.get(Uri.parse('$serverBase/a'))).statusCode, 404);
      expect(calls, 1);
    });

    test('other hosts pass through once', () async {
      var calls = 0;
      final c = FallbackClient(
        MockClient((r) async {
          calls++;
          return http.Response('', 500);
        }),
      );
      expect(
        (await c.get(Uri.parse('https://server8.mp3quran.net/a.mp3')))
            .statusCode,
        500,
      );
      expect(calls, 1);
    });

    test('both hosts down: the old host error surfaces', () async {
      final c = FallbackClient(
        MockClient((r) async => throw http.ClientException(r.url.host)),
      );
      expect(
        c.get(Uri.parse('$serverBase/a')),
        throwsA(
          isA<http.ClientException>().having(
            (e) => e.message,
            'message',
            fallbackServerHost,
          ),
        ),
      );
    });
  });

  test('installers accepted from both hosts only', () {
    expect(isWindowsInstallerUrl('$serverBase/win/a.exe'), isTrue);
    expect(
      isWindowsInstallerUrl('https://$fallbackServerHost/win/a.exe'),
      isTrue,
    );
    expect(isWindowsInstallerUrl('https://evil.example/win/a.exe'), isFalse);
    expect(
      isWindowsInstallerUrl('http://$primaryServerHost/win/a.exe'),
      isFalse,
    );
    expect(isWindowsInstallerUrl('$serverBase/mirror/a.exe'), isFalse);
  });
}
