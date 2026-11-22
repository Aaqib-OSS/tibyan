import 'package:http/http.dart' as http;

/// Tibyan's own server. Both hosts serve the same static paths (`/mirror/`,
/// `/win/`, `/downloads/`, `/timing/`) with identical files.
const primaryServerHost = 'altibyan.app';

/// The old host, kept as an automatic fallback for [primaryServerHost].
const fallbackServerHost = 'tibyan.ahmedhelal.dev';

/// The base every Tibyan download and update URL is built on.
const serverBase = 'https://$primaryServerHost';

/// [url] with the host swapped to [fallbackServerHost] when it points at
/// [primaryServerHost]; null otherwise.
Uri? fallbackUrl(Uri url) => url.host == primaryServerHost
    ? url.replace(host: fallbackServerHost)
    : null;

/// Whether [url] is on either of Tibyan's hosts.
bool isServerUrl(Uri url) =>
    url.host == primaryServerHost || url.host == fallbackServerHost;

/// An HTTP client that retries a request to [primaryServerHost] on
/// [fallbackServerHost] when the first try throws or answers with a 5xx.
/// Requests to any other host pass through unchanged. Only plain
/// [http.Request]s can be retried (their body is copied); other request
/// kinds are sent once.
class FallbackClient extends http.BaseClient {
  FallbackClient([http.Client? inner]) : _inner = inner ?? http.Client();

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final alt = fallbackUrl(request.url);
    if (alt == null || request is! http.Request) return _inner.send(request);
    final retry = _copy(request, alt);
    try {
      final response = await _inner.send(request);
      if (response.statusCode < 500) return response;
      // Drain the failed body so the connection is freed.
      await response.stream.drain<void>().catchError((_) {});
    } on Exception {
      // Fall through to the old host.
    }
    return _inner.send(retry);
  }

  static http.Request _copy(http.Request r, Uri url) =>
      http.Request(r.method, url)
        ..headers.addAll(r.headers)
        ..followRedirects = r.followRedirects
        ..maxRedirects = r.maxRedirects
        ..persistentConnection = r.persistentConnection
        ..bodyBytes = r.bodyBytes;

  @override
  void close() => _inner.close();
}
