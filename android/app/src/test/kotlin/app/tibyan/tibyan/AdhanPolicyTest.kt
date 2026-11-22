package app.tibyan.tibyan

import app.tibyan.tibyan.AdhanPolicy.Playback
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AdhanPolicyTest {
    @Test
    fun aCallAlwaysGetsASilentNotice() {
        for (choice in listOf("notify", "short", "full", null)) {
            assertEquals(Playback.SILENT_NOTICE, AdhanPolicy.decide(true, true, choice))
            assertEquals(Playback.SILENT_NOTICE, AdhanPolicy.decide(true, false, choice))
            assertEquals(Playback.SILENT_NOTICE, AdhanPolicy.decide(true, false, choice, manual = true))
        }
    }

    @Test
    fun inUseFollowsTheChoice() {
        assertEquals(Playback.NOTICE, AdhanPolicy.decide(false, true, "notify"))
        assertEquals(Playback.NOTICE, AdhanPolicy.decide(false, true, null))
        assertEquals(Playback.SHORT, AdhanPolicy.decide(false, true, "short"))
        assertEquals(Playback.FULL, AdhanPolicy.decide(false, true, "full"))
        assertEquals(Playback.FULL, AdhanPolicy.decide(false, true, "notify", manual = true))
    }

    @Test
    fun idlePlaysInFull() {
        for (choice in listOf("notify", "short", "full")) {
            assertEquals(Playback.FULL, AdhanPolicy.decide(false, false, choice))
        }
    }

    @Test
    fun aStopHoldsForTwoMinutesUnlessAskedFor() {
        val stop = 1_000_000L
        assertTrue(AdhanPolicy.heldByStop(stop, stop + 1_000, manual = false))
        assertTrue(AdhanPolicy.heldByStop(stop, stop + 119_000, manual = false))
        assertFalse(AdhanPolicy.heldByStop(stop, stop + 121_000, manual = false))
        assertFalse(AdhanPolicy.heldByStop(stop, stop + 1_000, manual = true))
        assertFalse(AdhanPolicy.heldByStop(0, stop, manual = false))
    }

    @Test
    fun anAlertFiresOnceEvenAfterAReschedule() {
        val log = AdhanPolicy.FiredLog(null)
        assertTrue(log.record(500L, 1_000L))
        // Saved and read back (the receiver runs in a new process).
        val again = AdhanPolicy.FiredLog(log.toJson())
        assertTrue(again.has(500L))
        assertFalse(again.record(500L, 2_000L))
        assertTrue(again.record(600L, 2_000L))
    }

    @Test
    fun firedAlertsAreForgottenAfterADay() {
        val log = AdhanPolicy.FiredLog(null)
        log.record(500L, 0L)
        log.prune(AdhanPolicy.FIRED_KEEP_MS + 1)
        assertFalse(log.has(500L))
        assertFalse(AdhanPolicy.FiredLog("not json").has(1L))
    }
}
