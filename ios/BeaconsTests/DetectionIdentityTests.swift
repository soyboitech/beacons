import XCTest
@testable import Beacons

/// Row identity (`Detection.id`) for body cams that share one address.
///
/// WHY THIS EXISTS. On 2026-11-14 (nov142026.log) four Axon cams sent their 0xFE6B advert from one
/// fixed private address, and the Log showed them as ONE body cam row. The board now sends each
/// cam's serial in `id` when the MAC is on no known block (ble-protocol.md, `id`), and the row
/// keys on it the way a drone keys on its UAS ID. A body cam with no `id` keeps the MAC key.
/// TWIN: Android DetectionIdentityTest.
final class DetectionIdentityTests: XCTestCase {
    private func cam(id: String?) throws -> Detection {
        let idField = id.map { #","id":"\#($0)""# } ?? ""
        let json = #"{"t":3,"s":0,"meth":8,"c":75,"mac":"20:70:3a:00:00:01","rssi":-87,"#
            + #""det":"Axon Bluetooth ID","n":1\#(idField)}"#
        return try Detection.decodeWireJSON(Data(json.utf8))
    }

    func testCamsOnOneAddressWithDifferentSerialsAreDifferentRows() throws {
        let a = try cam(id: "X705F22R5"), b = try cam(id: "X705F22QW")
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertEqual(a.id, "3:X705F22R5")
        XCTAssertEqual(a.id, try cam(id: "X705F22R5").id, "one serial stays one row")
    }

    func testCamWithoutSerialKeepsTheMacKey() throws {
        XCTAssertEqual(try cam(id: nil).id, "3:20:70:3a:00:00:01")
        XCTAssertEqual(try cam(id: "").id, "3:20:70:3a:00:00:01")
    }

    func testOtherTypesIgnoreId() throws {
        let json = #"{"t":5,"s":0,"meth":3,"c":85,"mac":"f3:00:00:00:00:01","rssi":-60,"id":"X","n":1}"#
        XCTAssertEqual(try Detection.decodeWireJSON(Data(json.utf8)).id, "5:f3:00:00:00:00:01")
    }
}
