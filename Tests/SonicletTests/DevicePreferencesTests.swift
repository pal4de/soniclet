import Foundation
import CoreAudio

@main
struct DevicePreferencesTests {
    private static func fixture() -> (UserDefaults, DevicePreferences) {
        // Unique suite keeps tests completely separate from the app's preferences.
        let defaults = UserDefaults(suiteName: "Soniclet.tests.\(UUID().uuidString)")!
        return (defaults, DevicePreferences(defaults: defaults))
    }
    private static func device(uid: String = "usb-yeti", direction: AudioDirection = .output,
                        objectID: UInt32 = 10, name: String = "Yeti Nano") -> AudioDevice {
        AudioDevice(objectID: objectID, key: DeviceKey(uid: uid, direction: direction),
                    name: name, symbol: "speaker.wave.2.fill", isBuiltIn: false)
    }
    static func testNewDevicesAreVisibleByDefault() {
        let (_, store) = fixture()
        let first = device()
        expectTrue(store.isVisible(first.key))
        store.synchronize([first])
        expectTrue(store.isVisible(first.key))
    }
    static func testHidingOutputDoesNotHideInputWithSameUID() {
        let (_, store) = fixture()
        let output = device()
        let input = device(direction: .input)
        store.synchronize([output, input])
        store.setVisible(false, for: output.key)
        expectFalse(store.isVisible(output.key))
        expectTrue(store.isVisible(input.key))
    }
    static func testVisibilitySurvivesReconnectWithNewObjectIDAndName() {
        let (_, store) = fixture()
        let original = device()
        store.synchronize([original])
        store.setVisible(false, for: original.key)
        store.synchronize([])
        expectEqual(store.devices.count, 1, "Keep disconnected devices editable")
        store.synchronize([device(objectID: 99, name: "Renamed USB Device")])
        expectEqual(store.devices.count, 1)
        expectEqual(store.devices.first?.name, "Renamed USB Device")
        expectFalse(store.isVisible(original.key))
    }
    static func testVisibilitySurvivesRestartAndCanBeRestored() {
        let (defaults, store) = fixture()
        let item = device()
        store.synchronize([item])
        store.setVisible(false, for: item.key)
        let relaunched = DevicePreferences(defaults: defaults)
        expectFalse(relaunched.isVisible(item.key))
        relaunched.setVisible(true, for: item.key)
        expectTrue(DevicePreferences(defaults: defaults).isVisible(item.key))
    }
    static func testNewDeviceDoesNotInheritAnOldDevicePreference() {
        let (_, store) = fixture()
        let old = device(uid: "old")
        let new = device(uid: "new")
        store.synchronize([old])
        store.setVisible(false, for: old.key)
        store.synchronize([old, new])
        expectTrue(store.isVisible(new.key))
    }
    static func testMalformedPreferencesRecoverToVisibleDefaults() {
        let (defaults, _) = fixture()
        defaults.set(Data("invalid".utf8), forKey: "devicePreferences.v1")
        let store = DevicePreferences(defaults: defaults)
        store.synchronize([device()])
        expectTrue(store.isVisible(device().key))
    }
    static func testSessionAirPlayRoutesDisappearWhenDisconnected() {
        let (_, store) = fixture()
        let route = AudioDevice(objectID: 500, key: DeviceKey(uid: "airplay-session-1", direction: .output),
                                name: "AirPlay", symbol: "airplay.audio", isBuiltIn: false,
                                transport: kAudioDeviceTransportTypeAirPlay)
        let usb = device()
        store.synchronize([usb, route])
        store.setVisible(false, for: usb.key)
        store.synchronize([usb])
        expectEqual(store.devices.count, 1)
        expectFalse(store.isVisible(usb.key))
    }
    static func testLegacyPhantomAirPlayRecordsAreCleanedWithoutLosingUSBPreferences() {
        let (defaults, store) = fixture()
        let old = DevicePreference(key: DeviceKey(uid: "old-airplay", direction: .output),
                                   name: "AirPlay", symbol: "airplay.audio", isVisible: true)
        defaults.set(try! JSONEncoder().encode([old]), forKey: "devicePreferences.v1")
        let reloaded = DevicePreferences(defaults: defaults)
        reloaded.synchronize([device()])
        expectEqual(reloaded.devices.count, 1)
        expectTrue(reloaded.isVisible(device().key))
        _ = store
    }
    static func testDevelopmentBuildMigrationPreservesUserChoices() {
        let (defaults, _) = fixture()
        let domain = "Soniclet.legacy-tests.\(UUID().uuidString)"
        defer { defaults.removePersistentDomain(forName: domain) }
        let hidden = DevicePreference(key: device().key, name: "USB Device",
                                      symbol: "speaker.fill", isVisible: false)
        let data = try! JSONEncoder().encode([hidden])
        defaults.setPersistentDomain(["devicePreferences.v1": data, "unrelated": true], forName: domain)
        DevicePreferences.migrateLegacyPreferences(in: defaults, from: domain)
        expectFalse(DevicePreferences(defaults: defaults).isVisible(hidden.key))
        expectTrue(defaults.object(forKey: "unrelated") == nil, "Import only device visibility")
        let current = DevicePreferences(defaults: defaults)
        current.setVisible(true, for: hidden.key)
        DevicePreferences.migrateLegacyPreferences(in: defaults, from: domain)
        expectTrue(DevicePreferences(defaults: defaults).isVisible(hidden.key), "Never overwrite newer settings")
        defaults.removeObject(forKey: "devicePreferences.v1")
        defaults.setPersistentDomain(["devicePreferences.v1": Data("invalid".utf8)], forName: domain)
        DevicePreferences.migrateLegacyPreferences(in: defaults, from: domain)
        expectTrue(defaults.object(forKey: "devicePreferences.v1") == nil, "Ignore malformed legacy data")
    }
    private static func expectTrue(_ value: Bool, _ message: String = "Expected true") {
        if !value { fputs("FAIL: \(message)\n", stderr); exit(1) }
    }
    private static func expectFalse(_ value: Bool) { expectTrue(!value, "Expected false") }
    private static func expectEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "Values differ") {
        expectTrue(a == b, message)
    }
    static func main() {
        testNewDevicesAreVisibleByDefault()
        testHidingOutputDoesNotHideInputWithSameUID()
        testVisibilitySurvivesReconnectWithNewObjectIDAndName()
        testVisibilitySurvivesRestartAndCanBeRestored()
        testNewDeviceDoesNotInheritAnOldDevicePreference()
        testMalformedPreferencesRecoverToVisibleDefaults()
        testSessionAirPlayRoutesDisappearWhenDisconnected()
        testLegacyPhantomAirPlayRecordsAreCleanedWithoutLosingUSBPreferences()
        testDevelopmentBuildMigrationPreservesUserChoices()
        print("PASS: 9 device preference tests")
    }
}
