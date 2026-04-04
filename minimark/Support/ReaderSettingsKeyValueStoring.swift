import Foundation

protocol ReaderSettingsKeyValueStoring: AnyObject {
    func data(forKey defaultName: String) -> Data?
    func set(_ value: Any?, forKey defaultName: String)
}

extension UserDefaults: ReaderSettingsKeyValueStoring {}
