import Foundation

protocol SettingsKeyValueStoring: AnyObject {
    func data(forKey defaultName: String) -> Data?
    func set(_ value: Any?, forKey defaultName: String)
}

extension UserDefaults: SettingsKeyValueStoring {}
