// When the app may ask the engine for a picture of a widget (toImage,
// toImageSync).
//
// GlitchTip issues 14 and 15 (Huawei JLN-LX1 / NAM-LX9, OPPO CPH2631):
// SIGSEGV in libflutter.so, symbolicated to
//   DlDeferredImageGPUImpeller::SnapshotDisplayList
//   → Rasterizer::MakeImpellerSnapshotSync
//   → AndroidSurfaceGLImpeller::CreateSnapshotSurface
//   → ContentContext → BlitCopyBufferToTextureCommandGLES::Encode.
// A toImageSync() whose picture the raster thread draws while Android
// releases (on stop) or has not yet given back (on recreate) the window's
// surface: Impeller's OpenGL backend then builds an off-screen context and
// crashes in it. The picture is drawn later than the call, so asking at
// «inactive» is already too late: only a resumed app may ask, and not in
// its first moments back (onResume comes before the new surface; one
// crash came 15 ms after «resumed»).
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// How long after coming back to the front pictures still wait.
const rasterSettle = Duration(milliseconds: 800);

DateTime? _resumedAt;
AppLifecycleListener? _listener;

/// Starts noting when the app comes back to the front (main()).
void installRasterGuard() {
  _listener ??= AppLifecycleListener(
    onResume: () => _resumedAt = DateTime.now(),
  );
}

/// Whether a picture of a widget may be taken now: always off Android, and
/// on Android only while the app is resumed (its surface is there) and has
/// been for [rasterSettle].
bool canRasterizeNow({
  TargetPlatform? platform,
  AppLifecycleState? state,
  DateTime? now,
}) {
  if (kIsWeb) return true;
  if ((platform ?? defaultTargetPlatform) != TargetPlatform.android) {
    return true;
  }
  final s = state ?? WidgetsBinding.instance.lifecycleState;
  // Null before the first lifecycle message: the app is starting in front.
  if (s != null && s != AppLifecycleState.resumed) return false;
  final back = _resumedAt;
  return back == null ||
      (now ?? DateTime.now()).difference(back) >= rasterSettle;
}

/// Test hook: when the app last came back to the front.
@visibleForTesting
set debugResumedAt(DateTime? t) => _resumedAt = t;
