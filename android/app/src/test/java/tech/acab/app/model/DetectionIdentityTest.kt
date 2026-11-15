package tech.acab.app.model

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

/**
 * Row identity ([Detection.id]) for body cams that share one address.
 *
 * On 2026-11-14 (nov142026.log) four Axon cams sent their 0xFE6B advert from one fixed private
 * address, and the Log showed them as ONE body cam row. The board now sends each cam's serial in
 * `id` when the MAC is on no known block (ble-protocol.md, `id`), and the row keys on it the way a
 * drone keys on its UAS ID. A body cam with no `id` keeps the MAC key.
 * TWIN: iOS DetectionIdentityTests.
 */
class DetectionIdentityTest {
    private fun cam(id: String?): Detection {
        val idField = id?.let { ""","id":"$it"""" } ?: ""
        val json = """{"t":3,"s":0,"meth":8,"c":75,"mac":"20:70:3a:00:00:01","rssi":-87,""" +
            """"det":"Axon Bluetooth ID","n":1$idField}"""
        return Detection.fromWireJson(json, JSONObject(json))
    }

    @Test fun camsOnOneAddressWithDifferentSerials_areDifferentRows() {
        assertNotEquals(cam("X705F22R5").id, cam("X705F22QW").id)
        assertEquals("3:X705F22R5", cam("X705F22R5").id)
        assertEquals("one serial stays one row", cam("X705F22R5").id, cam("X705F22R5").id)
    }

    @Test fun camWithoutSerial_keepsTheMacKey() {
        assertEquals("3:20:70:3a:00:00:01", cam(null).id)
        assertEquals("3:20:70:3a:00:00:01", cam("").id)
    }

    @Test fun otherTypes_ignoreId() {
        val json = """{"t":5,"s":0,"meth":3,"c":85,"mac":"f3:00:00:00:00:01","rssi":-60,"id":"X","n":1}"""
        assertEquals("5:f3:00:00:00:00:01", Detection.fromWireJson(json, JSONObject(json)).id)
    }
}
