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
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.util.Log

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
    private var toneTried = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            finish()
            return START_NOT_STICKY
        }
        val files = intent?.getStringArrayListExtra("files") ?: arrayListOf()
        val title = intent?.getStringExtra("title") ?: ""
        val body = intent?.getStringExtra("body") ?: ""
        val payload = intent?.getStringExtra("payload") ?: ""
        preview = intent?.getBooleanExtra("preview", false) ?: false
        toneTried = false
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
        releasePlayer()
        // An alert with nothing on the device still sounds: the tone.
        queue = if (files.isEmpty()) listOf(TONE) else files
        index = 0
        startSession(title)
        listenScreenOff()
        playCurrent()
        onPlaying?.invoke(true)
        return START_NOT_STICKY
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
                    getString(R.string.adhan_stop),
                    stop,
                ).build(),
            )
            .build()
    }

    private fun startSession(title: String) {
        session?.release()
        session = MediaSession(this, "TibyanAdhan").apply {
            setPlaybackState(
                PlaybackState.Builder()
                    .setActions(PlaybackState.ACTION_STOP)
                    .setState(PlaybackState.STATE_PLAYING, 0, 1f)
                    .build(),
            )
            setCallback(object : MediaSession.Callback() {
                // Headset or media buttons stop it; the volume keys only
                // change the volume (the system does that for the session).
                override fun onStop() = finish()
                override fun onPause() = finish()
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
            override fun onReceive(context: Context, intent: Intent) = finish()
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
                    .setUsage(AudioAttributes.USAGE_MEDIA)
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
            p.setOnPreparedListener { it.start() }
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
        screenOff?.let {
            try {
                unregisterReceiver(it)
            } catch (_: Exception) {
            }
        }
        screenOff = null
        session?.release()
        session = null
        onPlaying?.invoke(false)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    override fun onDestroy() {
        releasePlayer()
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
        private const val TAG = "TibyanAdhan"
        private const val TONE = "tone:"

        /** Told when the adhan starts and stops (the app's screen). */
        var onPlaying: ((Boolean) -> Unit)? = null

        fun start(
            ctx: Context,
            files: List<String>,
            title: String,
            body: String,
            payload: String,
            preview: Boolean = false,
        ) {
            val i = Intent(ctx, AdhanService::class.java)
                .putExtra("preview", preview)
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
