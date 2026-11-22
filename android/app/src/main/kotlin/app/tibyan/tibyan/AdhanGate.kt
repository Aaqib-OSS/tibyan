package app.tibyan.tibyan

import android.app.KeyguardManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import org.json.JSONObject

/**
 * What the phone is doing when an adhan comes, what already fired or was
 * stopped (kept in preferences: the alarm may come in a fresh process),
 * and the adhan's notice: «حان وقت أذان …» with «تشغيل الأذان» instead of
 * the sound.
 */
object AdhanGate {
    private const val PREFS = "tibyan_adhan_state"
    private const val FIRED = "fired"
    private const val LAST_STOP = "lastStop"
    const val NOTICE_ID = 7401
    private const val NOTICE_CHANNEL = "app.tibyan.adhan.notice"
    private const val SILENT_CHANNEL = "app.tibyan.adhan.notice.silent"

    /** A call (cellular or VoIP) is active. */
    fun inCall(ctx: Context): Boolean {
        val am = ctx.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        return am.mode == AudioManager.MODE_IN_CALL ||
            am.mode == AudioManager.MODE_IN_COMMUNICATION
    }

    /** The screen is on and unlocked, or other media is playing. */
    fun inUse(ctx: Context): Boolean {
        val am = ctx.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        if (am.isMusicActive) return true
        val pm = ctx.getSystemService(Context.POWER_SERVICE) as PowerManager
        val km = ctx.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        return pm.isInteractive && !km.isKeyguardLocked
    }

    private fun prefs(ctx: Context) = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** Records the alert of [prayerAt] as fired; false when it already was. */
    @Synchronized
    fun markFired(ctx: Context, prayerAt: Long): Boolean {
        val p = prefs(ctx)
        val log = AdhanPolicy.FiredLog(p.getString(FIRED, null))
        val first = log.record(prayerAt, System.currentTimeMillis())
        p.edit().putString(FIRED, log.toJson()).commit()
        return first
    }

    fun hasFired(ctx: Context, prayerAt: Long): Boolean =
        AdhanPolicy.FiredLog(prefs(ctx).getString(FIRED, null)).has(prayerAt)

    fun markStopped(ctx: Context) {
        prefs(ctx).edit().putLong(LAST_STOP, System.currentTimeMillis()).commit()
    }

    fun heldByStop(ctx: Context, manual: Boolean): Boolean = AdhanPolicy.heldByStop(
        prefs(ctx).getLong(LAST_STOP, 0L),
        System.currentTimeMillis(),
        manual,
    )

    /** The adhan's notice: [silent] during a call, a light sound otherwise. */
    fun postNotice(ctx: Context, alert: JSONObject, silent: Boolean) {
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = if (silent) SILENT_CHANNEL else NOTICE_CHANNEL
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(
                channel,
                ctx.getString(
                    if (silent) R.string.adhan_silent_channel_name else R.string.adhan_notice_channel_name,
                ),
                if (silent) NotificationManager.IMPORTANCE_LOW else NotificationManager.IMPORTANCE_DEFAULT,
            )
            if (silent) ch.setSound(null, null)
            nm.createNotificationChannel(ch)
        }
        // Opens the prayer times (over home: the app's link handling).
        val open = Intent(ctx, MainActivity::class.java)
            .setAction(Intent.ACTION_VIEW)
            .setData(Uri.parse("tibyan://prayer"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val content = PendingIntent.getActivity(
            ctx,
            3,
            open,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val playIntent = Intent(ctx, AdhanService::class.java)
            .setAction(AdhanService.ACTION_PLAY)
            .putExtra("alert", alert.toString())
        val play = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            PendingIntent.getForegroundService(
                ctx,
                4,
                playIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        } else {
            PendingIntent.getService(
                ctx,
                4,
                playIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
        val b = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(ctx, channel)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(ctx)
        }
        val label = alert.optString("playLabel").ifEmpty { ctx.getString(R.string.adhan_play) }
        nm.notify(
            NOTICE_ID,
            b.setSmallIcon(R.drawable.ic_stat_tibyan)
                .setContentTitle(alert.optString("title"))
                .setContentText(alert.optString("body"))
                .setColor(0xFF0F6660.toInt())
                .setCategory(Notification.CATEGORY_REMINDER)
                .setAutoCancel(true)
                .setContentIntent(content)
                .addAction(Notification.Action.Builder(null, label, play).build())
                .apply {
                    prayedAction(ctx, alert.optString("payload"), 5)?.let { addAction(it) }
                }
                .build(),
        )
    }

    /**
     * «صليت»: opens «صلواتي» asking about the alert's prayer (the app's
     * link handling puts it over home). Null when the payload names none.
     */
    fun prayedAction(ctx: Context, payload: String, requestCode: Int): Notification.Action? {
        val prayer = try {
            Uri.parse(payload).getQueryParameter("p")
        } catch (_: Exception) {
            null
        } ?: return null
        val i = Intent(ctx, MainActivity::class.java)
            .setAction(Intent.ACTION_VIEW)
            .setData(Uri.parse("tibyan://prayer/log?p=$prayer"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val pi = PendingIntent.getActivity(
            ctx,
            requestCode,
            i,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return Notification.Action.Builder(null, ctx.getString(R.string.adhan_prayed), pi).build()
    }

    fun cancelNotice(ctx: Context) {
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel(NOTICE_ID)
    }
}
