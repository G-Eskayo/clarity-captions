import XCTest
@testable import CaptionCore

/// Which microphone joins the call on the Mac (#172, owner 2026-10-28 ~10 a.m.):
/// headphones with a mic → their mic (the call is private, no room); no headphones → the room through the Mac's mic,
/// echo cancelled; headphones without a mic → the call only.
final class RoomMicChoiceTests: XCTestCase {
    private let speakers = AudioDeviceInfo(id: 1, transport: .builtIn, isHeadphoneJack: false)
    private let internalMic = AudioDeviceInfo(id: 2, transport: .builtIn, isHeadphoneJack: false)
    private let airPodsMax = AudioDeviceInfo(id: 9, transport: .bluetooth, isHeadphoneJack: false)

    private func choose(output: AudioDeviceInfo?, input: AudioDeviceInfo?) -> RoomMicChoice {
        RoomMicChoice.choose(output: output, input: input)
    }

    func testNoHeadphonesUsesTheRoomWithEchoCancelled() {
        XCTAssertEqual(choose(output: speakers, input: internalMic), .room)
    }

    func testAirPodsWithTheirMicUseTheHeadsetNotTheRoom() {
        XCTAssertEqual(choose(output: airPodsMax, input: airPodsMax), .headset)
    }

    func testBluetoothHeadphonesWhileTheMacMicIsStillTheInputCaptionTheCallOnly() {
        // Headphones with no mic of their own (or one the person turned off): never fall back to the room.
        XCTAssertEqual(choose(output: airPodsMax, input: internalMic), .none)
    }

    func testWiredHeadphonesInTheJackWithoutAMicCaptionTheCallOnly() {
        let jack = AudioDeviceInfo(id: 1, transport: .builtIn, isHeadphoneJack: true)
        XCTAssertEqual(choose(output: jack, input: internalMic), .none)
    }

    func testAWiredHeadsetMicInTheJackIsTheHeadset() {
        let jack = AudioDeviceInfo(id: 1, transport: .builtIn, isHeadphoneJack: true)
        let headsetMic = AudioDeviceInfo(id: 3, transport: .builtIn, isHeadphoneJack: true)
        XCTAssertEqual(choose(output: jack, input: headsetMic), .headset)
    }

    func testAUSBHeadsetIsOneDeviceForBothWays() {
        let usbHeadset = AudioDeviceInfo(id: 7, transport: .usb, isHeadphoneJack: false)
        XCTAssertEqual(choose(output: usbHeadset, input: usbHeadset), .headset)
    }

    func testUSBSpeakersWithTheMacMicAreTheRoom() {
        let usbSpeakers = AudioDeviceInfo(id: 7, transport: .usb, isHeadphoneJack: false)
        XCTAssertEqual(choose(output: usbSpeakers, input: internalMic), .room)
    }

    func testTVOrDisplaySpeakersAreTheRoom() {
        let hdmi = AudioDeviceInfo(id: 5, transport: .other, isHeadphoneJack: false)
        XCTAssertEqual(choose(output: hdmi, input: internalMic), .room)
    }

    func testNoInputAtAllCaptionsTheCallOnly() {
        XCTAssertEqual(choose(output: speakers, input: nil), .none)
        XCTAssertEqual(choose(output: airPodsMax, input: nil), .none)
    }

    func testNoOutputKnownStillUsesTheRoomMic() {
        XCTAssertEqual(choose(output: nil, input: internalMic), .room)
    }
}
