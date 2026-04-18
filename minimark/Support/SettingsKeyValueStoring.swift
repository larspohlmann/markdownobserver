import Foundation

protocol SettingsKeyValueStoring: AnyObject {
    func data(forKey defaultName: String) -> Data?
    func set(_ value: Any?, forKey defaultName: String)
}

extension UserDefaults: SettingsKeyValueStoring {}

final class InMemorySettingsKeyValueStorage: SettingsKeyValueStoring {
    private var storedValues: [String: Data] = [:]

    func data(forKey defaultName: String) -> Data? {
        storedValues[defaultName]
    }

    func set(_ value: Any?, forKey defaultName: String) {
        storedValues[defaultName] = value as? Data
    }
}
