import Foundation

enum SettingsStorageEnvironment {
    static let ephemeralDefaultsEnvironmentKey = "MINIMARK_EPHEMERAL_DEFAULTS"

    static func resolveStorage(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> SettingsKeyValueStoring {
        if let value = environment[ephemeralDefaultsEnvironmentKey],
           !value.isEmpty,
           value != "0" {
            return InMemorySettingsKeyValueStorage()
        }
        return UserDefaults.standard
    }
}

extension SettingsStore {
    @MainActor
    static func makeDefault() -> SettingsStore {
        SettingsStore(storage: SettingsStorageEnvironment.resolveStorage())
    }
}
