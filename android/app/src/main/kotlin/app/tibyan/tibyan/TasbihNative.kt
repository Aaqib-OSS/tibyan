package app.tibyan.tibyan

import android.content.Context
import android.media.AudioAttributes
import android.media.SoundPool
import io.flutter.FlutterInjector
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * «المسبحة»'s channel (`app.tibyan/tasbih`): the bead's sounds through a
 * SoundPool (no delay, mixes with other sound) and counting with the
 * volume buttons while the app is open.
 */
class TasbihNative(private val context: Context, messenger: BinaryMessenger) {
  val channel = MethodChannel(messenger, "app.tibyan/tasbih")

  /** The volume buttons count instead of changing the volume. */
  var volumeKeys = false
    private set

  private var pool: SoundPool? = null

  /** Each sound's id in the pool, by its asset; and the ids loaded. */
  private val ids = HashMap<String, Int>()
  private val ready = HashSet<Int>()

  /** A sound asked for before it had loaded: played as soon as it has. */
  private var waiting = 0

  init {
    channel.setMethodCallHandler { call, result ->
      try {
        when (call.method) {
          "click" -> {
            play(CLICK)
            result.success(null)
          }
          "play" -> {
            (call.arguments as? String)?.let { play(it) }
            result.success(null)
          }
          "preload" -> {
            (call.arguments as? List<*>)?.forEach { (it as? String)?.let { a -> load(a) } }
            result.success(null)
          }
          "setVolumeKeys" -> {
            volumeKeys = call.arguments as? Boolean ?: false
            result.success(null)
          }
          else -> result.notImplemented()
        }
      } catch (e: Throwable) {
        result.success(null)
      }
    }
  }

  /** A volume button press, while [volumeKeys] is on. */
  fun volumeKey() {
    try {
      channel.invokeMethod("volumeKey", null)
    } catch (e: Throwable) {}
  }

  /** Plays a bundled sound; one not loaded yet plays once it has. */
  private fun play(asset: String) {
    try {
      val id = load(asset) ?: return
      if (id in ready) {
        pool?.play(id, 1f, 1f, 1, 0, 1f)
      } else {
        waiting = id
      }
    } catch (e: Throwable) {}
  }

  private fun pool(): SoundPool {
    pool?.let { return it }
    val p = SoundPool.Builder()
        .setMaxStreams(4)
        .setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build(),
        )
        .build()
    p.setOnLoadCompleteListener { pool, id, status ->
      try {
        if (status == 0) {
          ready.add(id)
          if (waiting == id) {
            waiting = 0
            pool.play(id, 1f, 1f, 1, 0, 1f)
          }
        }
      } catch (e: Throwable) {}
    }
    pool = p
    return p
  }

  /** The sound's id in the pool, loading it on first use. */
  private fun load(asset: String): Int? =
      try {
        ids[asset] ?: run {
          // Only the misbaha's own bundled sounds.
          if (!asset.startsWith("assets/tasbih/") || asset.contains("..")) return null
          // Flutter's assets may be compressed in the APK: copy the sound
          // out once, then load it from the file.
          val name = if (asset == CLICK) "tasbih_click.wav"
              else "tasbih_" + asset.substringAfterLast('/')
          val file = File(context.cacheDir, name)
          if (!file.exists()) {
            val key = FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(asset)
            context.assets.open(key).use { input ->
              file.outputStream().use { input.copyTo(it) }
            }
          }
          val id = pool().load(file.path, 1)
          ids[asset] = id
          id
        }
      } catch (e: Throwable) {
        null
      }

  fun dispose() {
    try {
      pool?.release()
    } catch (e: Throwable) {}
    pool = null
    ids.clear()
    ready.clear()
  }

  private companion object {
    const val CLICK = "assets/tasbih/click.wav"
  }
}
