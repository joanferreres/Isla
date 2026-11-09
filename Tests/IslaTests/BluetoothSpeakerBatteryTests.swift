import XCTest
@testable import Isla

final class BluetoothSpeakerBatteryTests: XCTestCase {
    func testUsesOnlyBatteryFromTheMatchingConnectedAudioDevice() {
        let data = Data("""
        {"SPBluetoothDataType":[{"device_connected":[
          {"Speaker":{"device_address":"AA:BB:CC:DD:EE:FF","device_batteryLevelMain":"72%"}},
          {"Speaker":{"device_address":"01:02:03:04:05:06","device_batteryLevelMain":"20%"}}
        ],"device_not_connected":[{"Offline":{"device_batteryLevelMain":"90%"}}]}]}
        """.utf8)
        XCTAssertEqual(BluetoothAudioRoute(uid: "AABBCCDD-EEFF:output", name: "Speaker").battery(in: data), 72)
        XCTAssertNil(BluetoothAudioRoute(uid: "unknown", name: "Speaker").battery(in: data))
        XCTAssertNil(BluetoothAudioRoute(uid: "unknown", name: "Offline").battery(in: data))
    }
}
