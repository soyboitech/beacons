package tech.acab.app.model

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The staged suggestion to charge the beacon: its thresholds, its re-arm margin, its three
 * sentences and the rule that picks a stage from a status frame's battery fields.
 *
 * FAILS IF a threshold, the margin or a sentence changes on this side alone (the iOS app shows the
 * same stages at the same levels in the same words); if a stage starts showing while the board is
 * charging or reports no battery; if a worsening level waits for anything; if a showing stage eases
 * before the level is the margin above its own threshold, or holds past that; or if the status
 * parse stops handing the rule the board's "bat" and "chg".
 *
 * Every expectation is a literal, never a constant compared with itself.
 *
 * TWIN: iOS BatteryAdviceTests, which pins the same numbers, sentences and table.
 */
class BatteryAdviceTest {

    private fun status(json: String) = DeviceStatus.fromJson(JSONObject(json))

    @Test
    fun `thresholds and the re-arm margin`() {
        assertEquals(20, BATTERY_ADVICE_LOW_PERCENT)
        assertEquals(10, BATTERY_ADVICE_SOON_PERCENT)
        assertEquals(5, BATTERY_ADVICE_NOW_PERCENT)
        assertEquals(7, BATTERY_ADVICE_REARM_MARGIN)
        // What the rule reads is the stage's own threshold, so pin the wiring too.
        assertEquals(listOf(20, 10, 5), BatteryAdvice.entries.map { it.threshold })
    }

    @Test
    fun `the three sentences, as the notice draws them`() {
        assertEquals(
            "beacon battery is getting low. charge it when you get the chance.",
            BATTERY_ADVICE_LOW_MESSAGE,
        )
        assertEquals(
            "beacon battery is low. charge it soon, or detection will stop.",
            BATTERY_ADVICE_SOON_MESSAGE,
        )
        assertEquals(
            "beacon battery is almost empty. plug it in now to keep detecting.",
            BATTERY_ADVICE_NOW_MESSAGE,
        )
        // The notice draws the stage's message, so each stage has to carry its own sentence.
        assertEquals(
            listOf(
                "beacon battery is getting low. charge it when you get the chance.",
                "beacon battery is low. charge it soon, or detection will stop.",
                "beacon battery is almost empty. plug it in now to keep detecting.",
            ),
            listOf(BatteryAdvice.LOW, BatteryAdvice.CHARGE_SOON, BatteryAdvice.CHARGE_NOW).map { it.message },
        )
    }

    private data class Case(
        val percent: Int?,
        val charging: Boolean,
        val previous: BatteryAdvice?,
        val expected: BatteryAdvice?,
    )

    @Test
    fun `the rule, case by case`() {
        val low = BatteryAdvice.LOW
        val soon = BatteryAdvice.CHARGE_SOON
        val now = BatteryAdvice.CHARGE_NOW
        val cases = listOf(
            // nothing showing: the most severe stage the level is at or under
            Case(null, false, null, null),
            Case(82, false, null, null),
            Case(21, false, null, null),
            Case(20, false, null, low),
            Case(11, false, null, low),
            Case(10, false, null, soon),
            Case(6, false, null, soon),
            Case(5, false, null, now),
            Case(0, false, null, now),
            // charging: none, whatever the level and whatever was showing
            Case(5, true, now, null),
            Case(20, true, null, null),
            // a showing stage eases only once the level is 7 above its own threshold
            Case(22, false, low, low),
            Case(26, false, low, low),
            Case(27, false, low, null),
            Case(18, false, low, low),
            Case(12, false, soon, soon),
            Case(16, false, soon, soon),
            Case(17, false, soon, low),
            Case(7, false, now, now),
            Case(11, false, now, now),
            Case(12, false, now, low),
            Case(30, false, now, null),
            // worsening is immediate
            Case(8, false, low, soon),
            Case(3, false, soon, now),
        )
        for (c in cases) {
            assertEquals("$c", c.expected, batteryAdvice(c.percent, c.charging, c.previous))
        }
    }

    @Test
    fun `the status parse hands the rule bat and chg`() {
        val draining = status("""{"fw":"beacon board 2.2.4","bat":18}""")
        assertEquals(18, draining.battery)
        assertFalse("an absent chg is not charging", draining.charging)
        assertEquals(BatteryAdvice.LOW, batteryAdvice(draining.battery, draining.charging, null))

        val charging = status("""{"fw":"beacon board 2.2.4","bat":18,"chg":true}""")
        assertEquals(18, charging.battery)
        assertTrue(charging.charging)
        assertNull(batteryAdvice(charging.battery, charging.charging, BatteryAdvice.LOW))

        // No "bat" key is a board with no battery to report, never 0 percent.
        val none = status("""{"fw":"beacon board 2.2.4"}""")
        assertNull(none.battery)
        assertNull(batteryAdvice(none.battery, none.charging, null))
    }

    /** The fold AcabBleManager.installStatus runs for each status it installs, over two parsed
     *  frames: the level bounces from 20 up to 22 and the stage holds. The manager's own line is
     *  not run here (nothing in this suite can construct an AcabBleManager), only the expression
     *  it evaluates. */
    @Test
    fun `two frames, 20 then 22, leave the advice at low`() {
        var advice: BatteryAdvice? = null
        for (json in listOf("""{"fw":"x","bat":20}""", """{"fw":"x","bat":22}""")) {
            val s = status(json)
            advice = batteryAdvice(s.battery, s.charging, advice)
        }
        assertEquals(BatteryAdvice.LOW, advice)
    }
}
