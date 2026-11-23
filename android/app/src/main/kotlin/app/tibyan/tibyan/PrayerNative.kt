package app.tibyan.tibyan

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.net.Uri
import android.os.Build
import android.os.CancellationSignal
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

/**
 * «مواقيت الصلاة»'s native side (`app.tibyan/prayer`): one coarse
 * position, the adhan player (the [AdhanService]), and the adhan alarms.
 *
 * An adhan is an exact alarm ([AlarmManager.setExactAndAllowWhileIdle]):
 * an app may start a foreground service from an exact alarm, so the
 * adhan plays with the screen off. Without the exact-alarm permission the
 * Dart side schedules a plain notification with the tone instead.
 */
class PrayerNative(
    private val activity: Activity,
    messenger: BinaryMessenger,
) {
    val channel = MethodChannel(messenger, "app.tibyan/prayer")
    private var pendingLocate: MethodChannel.Result? = null
    private var inApp: android.media.MediaPlayer? = null

    /** Plays [files] one after the other in the app's own process. */
    private fun playInApp(files: List<String>, volume: Double, index: Int = 0) {
        stopInApp(notify = false)
        if (index >= files.size) {
            channel.invokeMethod("playing", false)
            return
        }
        try {
            val v = volume.toFloat().coerceIn(0f, 1f)
            inApp = android.media.MediaPlayer().apply {
                setAudioAttributes(
                    android.media.AudioAttributes.Builder()
                        .setUsage(android.media.AudioAttributes.USAGE_MEDIA)
                        .setContentType(android.media.AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build(),
                )
                setDataSource(files[index])
                setVolume(v, v)
                setOnCompletionListener { playInApp(files, volume, index + 1) }
                setOnErrorListener { _, _, _ -> stopInApp(); true }
                prepare()
                start()
            }
        } catch (_: Exception) {
            stopInApp()
        }
    }

    private fun stopInApp(notify: Boolean = true) {
        val p = inApp ?: return
        inApp = null
        try { p.stop() } catch (_: Exception) {}
        p.release()
        if (notify) channel.invokeMethod("playing", false)
    }

    init {
        channel.setMethodCallHandler { call, result ->
            val ctx = activity.applicationContext
            when (call.method) {
                "locate" -> locate(result)
                "play" -> {
                    val files = call.argument<List<String>>("files") ?: emptyList()
                    if (call.argument<Boolean>("preview") == true) {
                        // The library's preview: in the app only, no
                        // service and so no notification.
                        AdhanService.stop(ctx)
                        playInApp(files, call.argument<Double>("volume") ?: AlarmVolume.DEFAULT)
                        result.success(null)
                        return@setMethodCallHandler
                    }
                    stopInApp(notify = false)
                    AdhanService.start(
                        ctx,
                        files,
                        call.argument<String>("title") ?: "",
                        call.argument<String>("body") ?: "",
                        call.argument<String>("payload") ?: "",
                        call.argument<Boolean>("preview") ?: false,
                        call.argument<Double>("volume") ?: AlarmVolume.DEFAULT,
                        call.argument<String>("stopLabel"),
                        // From the app: the reader's own action.
                        manual = true,
                    )
                    result.success(null)
                }
                "stop" -> {
                    stopInApp(notify = false)
                    AdhanService.stop(ctx)
                    result.success(null)
                }
                "schedule" -> {
                    val alerts = call.argument<List<Map<String, Any?>>>("alerts") ?: emptyList()
                    AdhanAlarms.replace(ctx, alerts)
                    result.success(null)
                }
                "test" -> {
                    // «جرّب الأذان»: the same exact alarm and service as a
                    // real alert, a few seconds from now.
                    AdhanAlarms.test(ctx, call.arguments as Map<String, Any?>)
                    result.success(null)
                }
                "leaveLockScreen" -> {
                    (activity as? MainActivity)?.leaveLockScreen(call.argument<Boolean>("open") ?: false)
                    result.success(null)
                }
                "canExact" -> result.success(AdhanAlarms.canExact(ctx))
                "requestExact" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        activity.startActivity(
                            Intent(
                                Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                                Uri.fromParts("package", activity.packageName, null),
                            ),
                        )
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        AdhanService.onPlaying = { playing ->
            activity.runOnUiThread { channel.invokeMethod("playing", playing) }
        }
    }

    private fun locate(result: MethodChannel.Result) {
        if (activity.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            pendingLocate?.success(null)
            pendingLocate = result
            activity.requestPermissions(
                arrayOf(Manifest.permission.ACCESS_COARSE_LOCATION),
                LOCATION_REQUEST,
            )
            return
        }
        fix(result)
    }

    /** Called from the activity's permission result. */
    fun onPermissionResult(requestCode: Int, granted: Boolean): Boolean {
        if (requestCode != LOCATION_REQUEST) return false
        val r = pendingLocate ?: return true
        pendingLocate = null
        if (granted) fix(r) else r.success(null)
        return true
    }

    /** One network fix (coarse); the last known one when it is recent. */
    @SuppressLint("MissingPermission")
    private fun fix(result: MethodChannel.Result) {
        val lm = activity.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        var answered = false
        fun answer(l: Location?) {
            if (answered) return
            answered = true
            activity.runOnUiThread {
                result.success(l?.let { mapOf("lat" to it.latitude, "lon" to it.longitude) })
            }
        }
        try {
            val provider = when {
                lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER) ->
                    LocationManager.NETWORK_PROVIDER
                lm.isProviderEnabled(LocationManager.PASSIVE_PROVIDER) ->
                    LocationManager.PASSIVE_PROVIDER
                else -> null
            }
            if (provider == null) {
                answer(null)
                return
            }
            val last = lm.getLastKnownLocation(provider)
            if (last != null &&
                System.currentTimeMillis() - last.time < 6 * 60 * 60 * 1000L
            ) {
                answer(last)
                return
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                lm.getCurrentLocation(provider, CancellationSignal(), activity.mainExecutor) {
                    answer(it ?: last)
                }
            } else {
                @Suppress("DEPRECATION")
                lm.requestSingleUpdate(provider, { answer(it) }, activity.mainLooper)
            }
            // No answer in 20 s: the last known position, or none.
            activity.window.decorView.postDelayed({ answer(last) }, 20_000)
        } catch (e: Exception) {
            answer(null)
        }
    }

    companion object {
        const val LOCATION_REQUEST = 7302
    }
}

/** The adhan alarms, kept in preferences so they survive a reboot. */
object AdhanAlarms {
    private const val PREFS = "tibyan_adhan_alarms"
    private const val KEY = "alerts"

    fun canExact(ctx: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        return am.canScheduleExactAlarms()
    }

    private fun intent(ctx: Context, id: Int, alert: JSONObject?): PendingIntent {
        val i = Intent(ctx, AdhanAlarmReceiver::class.java).setAction("app.tibyan.ADHAN.$id")
        if (alert != null) i.putExtra("alert", alert.toString())
        return PendingIntent.getBroadcast(
            ctx,
            id,
            i,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    fun replace(ctx: Context, alerts: List<Map<String, Any?>>) {
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val old = JSONArray(prefs.getString(KEY, "[]"))
        for (i in 0 until old.length()) {
            am.cancel(intent(ctx, old.getJSONObject(i).getInt("id"), null))
        }
        val now = JSONArray()
        for (a in alerts) {
            val o = JSONObject()
            o.put("id", (a["id"] as Number).toInt())
            o.put("at", (a["at"] as Number).toLong())
            o.put("title", a["title"] as? String ?: "")
            o.put("body", a["body"] as? String ?: "")
            o.put("payload", a["payload"] as? String ?: "")
            o.put("volume", (a["volume"] as? Number)?.toDouble() ?: AlarmVolume.DEFAULT)
            o.put("stopLabel", a["stopLabel"] as? String ?: "")
            o.put("files", JSONArray((a["files"] as? List<*>) ?: emptyList<String>()))
            o.put("shortFiles", JSONArray((a["shortFiles"] as? List<*>) ?: emptyList<String>()))
            o.put("prayerAt", (a["prayerAt"] as? Number)?.toLong() ?: o.getLong("at"))
            o.put("inUse", a["inUse"] as? String ?: AdhanPolicy.IN_USE_NOTIFY)
            o.put("playLabel", a["playLabel"] as? String ?: "")
            // Not an adhan (the salawat reminder): no full-screen adhan.
            o.put("quiet", a["quiet"] as? Boolean ?: false)
            // Already fired (or stopped): a reschedule never re-arms it.
            if (AdhanGate.hasFired(ctx, o.getLong("prayerAt"))) continue
            now.put(o)
        }
        prefs.edit().putString(KEY, now.toString()).apply()
        arm(ctx, now)
    }

    const val TEST_ID = 9399

    fun test(ctx: Context, alert: Map<String, Any?>) {
        val o = JSONObject()
        o.put("id", TEST_ID)
        o.put("at", (alert["at"] as Number).toLong())
        o.put("title", alert["title"] as? String ?: "")
        o.put("body", alert["body"] as? String ?: "")
        o.put("payload", alert["payload"] as? String ?: "")
        o.put("volume", (alert["volume"] as? Number)?.toDouble() ?: AlarmVolume.DEFAULT)
        o.put("stopLabel", alert["stopLabel"] as? String ?: "")
        o.put("files", JSONArray((alert["files"] as? List<*>) ?: emptyList<String>()))
        o.put("test", true)
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        if (canExact(ctx)) {
            am.setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                o.getLong("at"),
                intent(ctx, TEST_ID, o),
            )
        } else {
            // No exact alarms: the app is in front, so start it directly.
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                val files = o.getJSONArray("files")
                AdhanService.start(
                    ctx,
                    (0 until files.length()).map { files.getString(it) },
                    o.optString("title"),
                    o.optString("body"),
                    o.optString("payload"),
                    volume = o.optDouble("volume", AlarmVolume.DEFAULT),
                    stopLabel = o.optString("stopLabel").ifEmpty { null },
                    manual = true,
                )
            }, (o.getLong("at") - System.currentTimeMillis()).coerceAtLeast(0))
        }
    }

    /** Sets every stored alarm still to come (after a reboot too). */
    fun arm(ctx: Context, alerts: JSONArray? = null) {
        val list = alerts ?: JSONArray(
            ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, "[]"),
        )
        if (!canExact(ctx)) return
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val now = System.currentTimeMillis()
        for (i in 0 until list.length()) {
            val o = list.getJSONObject(i)
            val at = o.getLong("at")
            if (at <= now) continue
            if (AdhanGate.hasFired(ctx, o.optLong("prayerAt", at))) continue
            try {
                am.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    at,
                    intent(ctx, o.getInt("id"), o),
                )
            } catch (_: SecurityException) {
                return
            }
        }
    }
}

/** An adhan's time: starts the adhan service. */
class AdhanAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED,
            -> {
                AdhanAlarms.arm(context)
                return
            }
        }
        val o = JSONObject(intent.getStringExtra("alert") ?: return)
        val now = System.currentTimeMillis()
        // Late by more than five minutes (the phone was off): no adhan.
        if (now - o.getLong("at") > 5 * 60 * 1000L) return
        // «جرّب الأذان»: always heard (the reader is waiting for it).
        val test = o.optBoolean("test", false)
        if (!test) {
            // Each prayer's adhan once: a duplicate or re-armed alarm is
            // ignored, and so is one right after the reader stopped one.
            if (!AdhanGate.markFired(context, o.optLong("prayerAt", o.getLong("at")))) return
            if (AdhanGate.heldByStop(context, manual = false)) return
        }
        val playback = AdhanPolicy.decide(
            inCall = AdhanGate.inCall(context),
            inUse = !test && AdhanGate.inUse(context),
            choice = o.optString("inUse", AdhanPolicy.IN_USE_NOTIFY),
        )
        when (playback) {
            AdhanPolicy.Playback.NOTICE,
            AdhanPolicy.Playback.SILENT_NOTICE,
            -> {
                AdhanGate.postNotice(
                    context,
                    o,
                    silent = playback == AdhanPolicy.Playback.SILENT_NOTICE,
                )
                return
            }
            else -> {}
        }
        fun list(key: String): List<String> {
            val a = o.optJSONArray(key) ?: return emptyList()
            return (0 until a.length()).map { a.getString(it) }
        }
        val short = list("shortFiles")
        val files = if (playback == AdhanPolicy.Playback.SHORT && short.isNotEmpty()) short else list("files")
        AdhanService.start(
            context,
            files,
            o.optString("title"),
            o.optString("body"),
            o.optString("payload"),
            volume = o.optDouble("volume", AlarmVolume.DEFAULT),
            stopLabel = o.optString("stopLabel").ifEmpty { null },
            manual = test,
            alert = o,
        )
    }
}
