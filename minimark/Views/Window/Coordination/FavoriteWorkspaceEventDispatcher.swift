/// Persists favorite-workspace state changes. Merges the current locked
/// appearance into the new state before writing to the settings store.
@MainActor
final class FavoriteWorkspaceEventDispatcher {
    private let favoriteWorkspaceControllerProvider: () -> FavoriteWorkspaceController?
    private let appearanceControllerProvider: () -> WindowAppearanceController?
    private let settingsStore: SettingsStore

    init(
        favoriteWorkspaceControllerProvider: @escaping () -> FavoriteWorkspaceController?,
        appearanceControllerProvider: @escaping () -> WindowAppearanceController?,
        settingsStore: SettingsStore
    ) {
        self.favoriteWorkspaceControllerProvider = favoriteWorkspaceControllerProvider
        self.appearanceControllerProvider = appearanceControllerProvider
        self.settingsStore = settingsStore
    }

    func handleFavoriteWorkspaceStateChange(_ newState: FavoriteWorkspaceState?) {
        guard let favoriteID = favoriteWorkspaceControllerProvider()?.activeFavoriteID,
              var state = newState else { return }
        state.lockedAppearance = appearanceControllerProvider()?.lockedAppearance
        settingsStore.updateFavoriteWorkspaceState(id: favoriteID, workspaceState: state)
    }
}
