package app.tibyan.tibyan

import org.json.JSONObject

/**
 * The adhan's decisions, kept free of Android so they are unit-tested:
 * how an alert sounds for what the phone is doing, which alerts already
 * fired, and how long a stop holds.
 */
object AdhanPolicy {
    /** How an adhan alert plays. */
    enum class Playback {
        /** The adhan as chosen (full or short, then the dua). */
        FULL,

        /** The short cut only. */
        SHORT,

        /** A notification with a light sound and «تشغيل الأذان». */
        NOTICE,

        /** A silent notification with «تشغيل الأذان» (during a call). */
        SILENT_NOTICE,
    }

    /** «عندما يكون الهاتف قيد الاستخدام»: the setting's values. */
    const val IN_USE_NOTIFY = "notify"
    const val IN_USE_SHORT = "short"
    const val IN_USE_FULL = "full"

    /** How long a stop keeps the same adhan from starting again. */
    const val STOP_HOLD_MS = 2 * 60 * 1000L

    /** How long a fired alert is remembered. */
    const val FIRED_KEEP_MS = 24 * 60 * 60 * 1000L

    /**
     * [inCall]: a call is active (never loud over it). [inUse]: the
     * screen is on and unlocked, or other media plays. [manual]: the
     * reader asked for it («تشغيل الأذان», a preview), always full.
     */
    fun decide(
        inCall: Boolean,
        inUse: Boolean,
        choice: String?,
        manual: Boolean = false,
    ): Playback {
        if (inCall) return Playback.SILENT_NOTICE
        if (manual || !inUse) return Playback.FULL
        return when (choice) {
            IN_USE_FULL -> Playback.FULL
            IN_USE_SHORT -> Playback.SHORT
            else -> Playback.NOTICE
        }
    }

    /** Whether a start comes too soon after a stop (and is not asked for). */
    fun heldByStop(lastStopAt: Long, now: Long, manual: Boolean): Boolean =
        !manual && lastStopAt > 0 && now >= lastStopAt && now - lastStopAt < STOP_HOLD_MS

    /** The alerts that fired, by their prayer's time (ms) → when recorded. */
    class FiredLog(json: String?) {
        private val fired = mutableMapOf<Long, Long>()

        init {
            try {
                val o = JSONObject(json ?: "{}")
                for (k in o.keys()) fired[k.toLong()] = o.getLong(k)
            } catch (_: Exception) {
                // A broken record: start empty.
            }
        }

        fun has(prayerAt: Long) = fired.containsKey(prayerAt)

        /** Records [prayerAt]; false when it was already there. */
        fun record(prayerAt: Long, now: Long): Boolean {
            prune(now)
            if (fired.containsKey(prayerAt)) return false
            fired[prayerAt] = now
            return true
        }

        fun prune(now: Long) {
            fired.entries.removeAll { now - it.value > FIRED_KEEP_MS }
        }

        fun toJson(): String {
            val o = JSONObject()
            for ((k, v) in fired) o.put(k.toString(), v)
            return o.toString()
        }
    }
}
