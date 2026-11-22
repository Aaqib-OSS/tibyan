package app.tibyan.tibyan

import org.junit.Assert.assertEquals
import org.junit.Test

class AlarmVolumeTest {
    private class FakeStream(override val max: Int, override var level: Int) :
        AlarmVolume.Stream

    @Test
    fun setsTheLevelAndRestoresTheSavedOne() {
        val s = FakeStream(max = 7, level = 2)
        val v = AlarmVolume(s)
        v.apply(0.7)
        assertEquals(5, s.level)
        v.restore()
        assertEquals(2, s.level)
    }

    @Test
    fun restoresOnceAndKeepsTheFirstSavedLevel() {
        val s = FakeStream(max = 10, level = 3)
        val v = AlarmVolume(s)
        v.apply(1.0)
        v.apply(0.5) // a second file (the dua): the original stays saved
        v.restore()
        assertEquals(3, s.level)
        s.level = 6
        v.restore() // nothing saved any more
        assertEquals(6, s.level)
    }

    @Test
    fun aVolumeKeyDuringTheAdhanIsNotFoughtBack() {
        val s = FakeStream(max = 7, level = 4)
        val v = AlarmVolume(s)
        v.apply(1.0)
        s.level = 2 // the user lowered it
        assertEquals(2, s.level)
        v.restore()
        assertEquals(4, s.level)
    }

    @Test
    fun indexIsClampedAndNeverZero() {
        assertEquals(1, AlarmVolume.indexFor(0.0, 7))
        assertEquals(7, AlarmVolume.indexFor(2.0, 7))
        assertEquals(5, AlarmVolume.indexFor(Double.NaN, 7))
        assertEquals(0, AlarmVolume.indexFor(0.5, 0))
    }
}
