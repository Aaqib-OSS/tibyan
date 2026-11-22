package app.tibyan.tibyan

/**
 * «مستوى صوت الأذان» on Android: the adhan plays on the alarm stream at the
 * user's level. The stream's own level is saved when the adhan starts and
 * put back when it ends (finished, stopped, failed or destroyed). It is set
 * once only: a volume key pressed during the adhan is not fought back.
 * Do-Not-Disturb is left alone (no policy access): if it silences alarms,
 * so be it.
 */
class AlarmVolume(private val stream: Stream) {
    /** The alarm stream, as the service sees it (a fake in tests). */
    interface Stream {
        val max: Int
        var level: Int
    }

    private var saved: Int? = null

    /**
     * Saves the current level and sets [fraction] (0…1) of the maximum,
     * once per adhan: a later file in the queue (the dua) does not set it
     * again, so a volume key pressed meanwhile is kept.
     */
    fun apply(fraction: Double) {
        if (saved != null) return
        saved = stream.level
        stream.level = indexFor(fraction, stream.max)
    }

    /** Puts the saved level back (once). */
    fun restore() {
        val s = saved ?: return
        saved = null
        stream.level = s
    }

    companion object {
        /**
         * What a key does while the adhan plays: +1 (raise), -1 (lower) or
         * 0 (not a volume key).
         */
        fun keyDirection(keyCode: Int): Int = when (keyCode) {
            KEYCODE_VOLUME_UP -> 1
            KEYCODE_VOLUME_DOWN -> -1
            else -> 0
        }

        // android.view.KeyEvent's codes (kept here for plain JVM tests).
        const val KEYCODE_VOLUME_UP = 24
        const val KEYCODE_VOLUME_DOWN = 25

        /** The stream index for [fraction]: at least 1, never above [max]. */
        fun indexFor(fraction: Double, max: Int): Int {
            if (max <= 0) return 0
            val f = if (fraction.isNaN()) DEFAULT else fraction.coerceIn(0.0, 1.0)
            return Math.round(f * max).toInt().coerceIn(1, max)
        }

        const val DEFAULT = 0.7
    }
}
