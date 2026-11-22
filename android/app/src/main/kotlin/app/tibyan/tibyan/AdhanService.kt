package app.tibyan.tibyan

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.util.Log
import org.json.JSONObject

/**
 * Plays the adhan (then the dua, when chosen) as a media-playback
 * foreground service: an ongoing notification with «إيقاف», and a
 * MediaSession so the volume keys change the adhan's volume and nothing
 * else. Turning the screen off (the power key) stops it.
 */
class AdhanService : Service() {
    private var player: MediaPlayer? = null
    private var session: MediaSession? = null
    private var queue: List<String> = emptyList()
    private var index = 0
    private var screenOff: BroadcastReceiver? = null
    private var preview = false
    private var quiet = false
    private var stopLabel = ""
    private var volume = AlarmVolume.DEFAULT
    private val alarmVolume by lazy {
        val am = getSystemService(AUDIO_SERVICE) as android.media.AudioManager
        AlarmVolume(object : AlarmVolume.Stream {
            override val max get() = am.getStreamMaxVolume(android.media.AudioManager.STREAM_ALARM)
            override var level: Int
                get() = am.getStreamVolume(android.media.AudioManager.STREAM_ALARM)
                set(v) {
                    try {
                        am.setStreamVolume(android.media.AudioManager.STREAM_ALARM, v, 0)
                    } catch (e: SecurityException) {
                        // Do-Not-Disturb owns the alarm stream: respected.
                        Log.w(TAG, "alarm volume not changed", e)
                    }
                }
        })
    }
    private var toneTried = false
    private var focus: AudioFocusRequest? = null
    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        // A call (or another app) takes the sound: the adhan ends, and
        // never comes back by itself when the focus returns.
        if (change == AudioManager.AUDIOFOCUS_LOSS ||
            change == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT
        ) {
            finish()
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            userStop()
            return START_NOT_STICKY
        }
        val alertJson = intent?.getStringExtra("alert")
        val alert = alertJson?.let {
            try {
                JSONObject(it)
            } catch (_: Exception) {
                null
            }
        }
        // «تشغيل الأذان» on the notice: the full adhan, asked for.
        val manual = intent?.action == ACTION_PLAY ||
            (intent?.getBooleanExtra("manual", false) ?: false)
        if (intent?.action == ACTION_PLAY) AdhanGate.cancelNotice(this)
        val files = if (intent?.action == ACTION_PLAY && alert != null) {
            alert.optJSONArray("files")?.let { a -> (0 until a.length()).map { a.getString(it) } }
                ?: emptyList()
        } else {
            intent?.getStringArrayListExtra("files") ?: arrayListOf()
        }
        val title = intent?.getStringExtra("title") ?: alert?.optString("title") ?: ""
        val body = intent?.getStringExtra("body") ?: alert?.optString("body") ?: ""
        val payload = intent?.getStringExtra("payload") ?: alert?.optString("payload") ?: ""
        preview = intent?.getBooleanExtra("preview", false) ?: false
        quiet = alert?.optBoolean("quiet", false) ?: false
        volume = if (intent?.hasExtra("volume") == true) {
            intent.getDoubleExtra("volume", AlarmVolume.DEFAULT)
        } else {
            alert?.optDouble("volume", AlarmVolume.DEFAULT) ?: AlarmVolume.DEFAULT
        }
        toneTried = false
        // In the app's language (the system's may differ).
        stopLabel = intent?.getStringExtra("stopLabel")
            ?: alert?.optString("stopLabel")?.ifEmpty { null }
            ?: getString(R.string.adhan_stop)
        val notification = notification(title, body, payload)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        // The foreground notice is up (required); now whether to sound.
        if (!preview && !manual && AdhanGate.heldByStop(this, manual = false)) {
            // Stopped moments ago: a duplicate alarm or a re-sent start.
            finish()
            return START_NOT_STICKY
        }
        if (!preview && AdhanGate.inCall(this)) {
            finish()
            alert?.let { AdhanGate.postNotice(this, it, silent = true) }
            return START_NOT_STICKY
        }
        if (!requestFocus()) {
            finish()
            if (!preview) alert?.let { AdhanGate.postNotice(this, it, silent = true) }
            return START_NOT_STICKY
        }
        releasePlayer()
        // An alert with nothing on the device still sounds: the tone.
        queue = if (files.isEmpty()) listOf(TONE) else files
        index = 0
        startSession(title)
        listenScreenOff()
        playCurrent()
        playing = true
        onPlaying?.invoke(true)
        return START_NOT_STICKY
    }

    private fun requestFocus(): Boolean {
        val am = getSystemService(AUDIO_SERVICE) as AudioManager
        val granted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build(),
                )
                .setOnAudioFocusChangeListener(focusListener)
                .build()
            focus = req
            am.requestAudioFocus(req)
        } else {
            @Suppress("DEPRECATION")
            am.requestAudioFocus(
                focusListener,
                AudioManager.STREAM_ALARM,
                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT,
            )
        }
        return granted == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
    }

    private fun abandonFocus() {
        val am = getSystemService(AUDIO_SERVICE) as AudioManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            focus?.let { am.abandonAudioFocusRequest(it) }
        } else {
            @Suppress("DEPRECATION")
            am.abandonAudioFocus(focusListener)
        }
        focus = null
    }

    /** The reader stopped it: it does not start again for a while. */
    private fun userStop() {
        AdhanGate.markStopped(this)
        finish()
    }

    private fun notification(title: String, body: String, payload: String): Notification {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(
                CHANNEL,
                getString(R.string.adhan_channel_name),
                NotificationManager.IMPORTANCE_HIGH,
            )
            // The adhan itself is the sound.
            ch.setSound(null, null)
            nm.createNotificationChannel(ch)
        }
        val open = Intent(this, MainActivity::class.java)
            .setAction(Intent.ACTION_VIEW)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        if (payload.isNotEmpty()) open.data = Uri.parse(payload)
        val content = PendingIntent.getActivity(
            this,
            0,
            open,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val stop = PendingIntent.getService(
            this,
            1,
            Intent(this, AdhanService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val b = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this).setPriority(Notification.PRIORITY_HIGH)
        }
        // The full-screen adhan build only: the app's own (Flutter)
        // full-screen adhan, shown over the lock screen.
        if (!quiet && fullScreenAllowed(nm)) {
            val lock = Intent(this, MainActivity::class.java)
                .setAction(Intent.ACTION_VIEW)
                .putExtra(MainActivity.EXTRA_LOCK_SCREEN, true)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            if (payload.isNotEmpty()) lock.data = Uri.parse(payload)
            val full = PendingIntent.getActivity(
                this,
                2,
                lock,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            b.setFullScreenIntent(full, true)
        }
        return b.setSmallIcon(R.drawable.ic_stat_tibyan)
            .setContentTitle(title)
            .setContentText(body)
            .setColor(0xFF0F6660.toInt())
            .setCategory(Notification.CATEGORY_ALARM)
            .setOngoing(true)
            .setContentIntent(content)
            .setDeleteIntent(stop)
            .addAction(
                Notification.Action.Builder(
                    null,
                    stopLabel,
                    stop,
                ).build(),
            )
            .build()
    }

    /** Declared (FULLSCREEN_ADHAN build) and, on Android 14+, allowed. */
    private fun fullScreenAllowed(nm: NotificationManager): Boolean {
        val declared = try {
            packageManager.getPackageInfo(packageName, android.content.pm.PackageManager.GET_PERMISSIONS)
                .requestedPermissions?.contains("android.permission.USE_FULL_SCREEN_INTENT") == true
        } catch (_: Exception) {
            false
        }
        if (!declared) return false
        return Build.VERSION.SDK_INT < 34 || nm.canUseFullScreenIntent()
    }

    private fun startSession(title: String) {
        session?.release()
        session = MediaSession(this, "TibyanAdhan").apply {
            // Local playback on the alarm stream: the volume keys change
            // the adhan's level even with the screen locked or another
            // app in front.
            setPlaybackToLocal(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build(),
            )
            setPlaybackState(
                PlaybackState.Builder()
                    .setActions(PlaybackState.ACTION_STOP)
                    .setState(PlaybackState.STATE_PLAYING, 0, 1f)
                    .build(),
            )
            setCallback(object : MediaSession.Callback() {
                // Headset or media buttons stop it; the volume keys only
                // change the volume (the system does that for the session).
                override fun onStop() = userStop()
                override fun onPause() = userStop()
            })
            isActive = true
        }
        session?.setMetadata(
            android.media.MediaMetadata.Builder()
                .putString(android.media.MediaMetadata.METADATA_KEY_TITLE, title)
                .build(),
        )
    }

    private fun listenScreenOff() {
        if (screenOff != null) return
        screenOff = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) = userStop()
        }
        val filter = IntentFilter(Intent.ACTION_SCREEN_OFF)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(screenOff, filter, RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(screenOff, filter)
        }
    }

    private fun playCurrent() {
        val src = queue.getOrNull(index) ?: return finish()
        if (src == TONE) return playTone()
        // Alerts play downloaded files only; a link (or a missing file)
        // falls back to the tone. The library's preview may stream.
        val remote = src.startsWith("http://") || src.startsWith("https://")
        if ((remote && !preview) || (!remote && !java.io.File(src).isFile)) {
            Log.w(TAG, "adhan source not playable: $src")
            return if (index == 0) playTone() else finish()
        }
        start(src, isTone = false)
    }

    private fun playTone() {
        if (toneTried) return finish()
        toneTried = true
        val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            ?: return finish()
        queue = listOf(TONE)
        index = 0
        start(uri.toString(), isTone = true)
    }

    private fun start(src: String, isTone: Boolean) {
        releasePlayer()
        try {
            val p = MediaPlayer()
            p.setAudioAttributes(
                AudioAttributes.Builder()
                    // The alarm stream: heard with the ringer or media muted.
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build(),
            )
            if (isTone) {
                p.setDataSource(this, Uri.parse(src))
            } else {
                // A path or (preview) an http link: never through the
                // ContentResolver.
                p.setDataSource(src)
            }
            p.setOnCompletionListener {
                index++
                releasePlayer()
                if (!isTone && index < queue.size) playCurrent() else finish()
            }
            p.setOnErrorListener { _, what, extra ->
                Log.e(TAG, "adhan playback error $what/$extra: $src")
                if (isTone || preview) finish() else playTone()
                true
            }
            p.setOnPreparedListener {
                alarmVolume.apply(volume)
                it.start()
            }
            player = p
            p.prepareAsync()
        } catch (e: Exception) {
            Log.e(TAG, "adhan source failed: $src", e)
            if (isTone || preview) finish() else playTone()
        }
    }

    private fun releasePlayer() {
        player?.let {
            try {
                it.stop()
            } catch (_: Exception) {
            }
            it.release()
        }
        player = null
    }

    private fun finish() {
        releasePlayer()
        abandonFocus()
        alarmVolume.restore()
        screenOff?.let {
            try {
                unregisterReceiver(it)
            } catch (_: Exception) {
            }
        }
        screenOff = null
        session?.release()
        session = null
        playing = false
        onPlaying?.invoke(false)
        onFinished?.invoke()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    override fun onDestroy() {
        playing = false
        releasePlayer()
        abandonFocus()
        alarmVolume.restore()
        screenOff?.let {
            try {
                unregisterReceiver(it)
            } catch (_: Exception) {
            }
        }
        session?.release()
        super.onDestroy()
    }

    companion object {
        const val CHANNEL = "app.tibyan.adhan"
        const val NOTIFICATION_ID = 7400
        const val ACTION_STOP = "app.tibyan.ADHAN_STOP"
        const val ACTION_PLAY = "app.tibyan.ADHAN_PLAY"
        private const val TAG = "TibyanAdhan"
        private const val TONE = "tone:"

        /** Whether the adhan sounds now (the activity's volume keys). */
        @Volatile
        var playing = false

        /** Told when the adhan starts and stops (the app's screen). */
        var onPlaying: ((Boolean) -> Unit)? = null

        /** Told when the adhan ends (closes the full-screen adhan). */
        var onFinished: (() -> Unit)? = null

        fun start(
            ctx: Context,
            files: List<String>,
            title: String,
            body: String,
            payload: String,
            preview: Boolean = false,
            volume: Double = AlarmVolume.DEFAULT,
            stopLabel: String? = null,
            manual: Boolean = false,
            alert: JSONObject? = null,
        ) {
            val i = Intent(ctx, AdhanService::class.java)
                .putExtra("manual", manual)
                .putExtra("alert", alert?.toString())
                .putExtra("preview", preview)
                .putExtra("volume", volume)
                .putExtra("stopLabel", stopLabel)
                .putStringArrayListExtra("files", ArrayList(files))
                .putExtra("title", title)
                .putExtra("body", body)
                .putExtra("payload", payload)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ctx.startForegroundService(i)
            } else {
                ctx.startService(i)
            }
        }

        fun stop(ctx: Context) {
            try {
                ctx.startService(Intent(ctx, AdhanService::class.java).setAction(ACTION_STOP))
            } catch (_: Exception) {
                // Not running and the app in the background: nothing to stop.
            }
        }
    }
}
