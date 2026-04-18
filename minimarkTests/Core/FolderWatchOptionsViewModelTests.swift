import XCTest
@testable import minimark

final class FolderWatchOptionsViewModelTests: XCTestCase {

    private func makeViewModel(
        folderURL: URL? = URL(fileURLWithPath: "/tmp/project"),
        scope: FolderWatchScope = .includeSubfolders,
        excludedPaths: [String] = [],
        subdirectoryCount: Int? = nil,
        allSubdirectoryPaths: [String] = [],
        isLoading: Bool = false,
        didExceedLimit: Bool = false
    ) -> FolderWatchOptionsViewModel {
        var vm = FolderWatchOptionsViewModel()
        vm.folderURL = folderURL
        vm.scope = scope
        vm.excludedSubdirectoryPaths = excludedPaths
        vm.subdirectoryCount = subdirectoryCount
        vm.allSubdirectoryPaths = allSubdirectoryPaths
        vm.isLoading = isLoading
        vm.didExceedSupportedSubdirectoryLimit = didExceedLimit
        return vm
    }

    // MARK: - requiresHardLimitRefusal

    func testRequiresHardLimitRefusalWhenExceedingLimit() {
        let vm = makeViewModel(
            scope: .includeSubfolders,
            didExceedLimit: true
        )

        XCTAssertTrue(vm.requiresHardLimitRefusal)
    }

    func testNoHardLimitRefusalWhenSelectedFolderOnly() {
        let vm = makeViewModel(
            scope: .selectedFolderOnly,
            didExceedLimit: true
        )

        XCTAssertFalse(vm.requiresHardLimitRefusal)
    }

    func testNoHardLimitRefusalWhenWithinLimit() {
        let vm = makeViewModel(
            scope: .includeSubfolders,
            subdirectoryCount: 100,
            didExceedLimit: false
        )

        XCTAssertFalse(vm.requiresHardLimitRefusal)
    }

    // MARK: - requiresExclusionSelectionBeforeStart

    func testRequiresExclusionAtThresholdBoundary() {
        let threshold = FolderWatchPerformancePolicy.exclusionPromptSubdirectoryThreshold
        let count = threshold + 1
        let paths = (0..<count).map { "/tmp/project/sub\($0)" }

        let vm = makeViewModel(
            scope: .includeSubfolders,
            subdirectoryCount: count,
            allSubdirectoryPaths: paths
        )

        XCTAssertTrue(vm.requiresExclusionSelectionBeforeStart)
    }

    func testNoExclusionRequiredAtExactThreshold() {
        let threshold = FolderWatchPerformancePolicy.exclusionPromptSubdirectoryThreshold
        let paths = (0..<threshold).map { "/tmp/project/sub\($0)" }

        let vm = makeViewModel(
            scope: .includeSubfolders,
            subdirectoryCount: threshold,
            allSubdirectoryPaths: paths
        )

        XCTAssertFalse(vm.requiresExclusionSelectionBeforeStart)
    }

    func testNoExclusionRequiredWhenSelectedFolderOnly() {
        let threshold = FolderWatchPerformancePolicy.exclusionPromptSubdirectoryThreshold
        let count = threshold + 100
        let paths = (0..<count).map { "/tmp/project/sub\($0)" }

        let vm = makeViewModel(
            scope: .selectedFolderOnly,
            subdirectoryCount: count,
            allSubdirectoryPaths: paths
        )

        XCTAssertFalse(vm.requiresExclusionSelectionBeforeStart)
    }

    func testExclusionNotRequiredWhenEnoughPathsExcluded() {
        let threshold = FolderWatchPerformancePolicy.exclusionPromptSubdirectoryThreshold
        let count = threshold + 2
        let paths = (0..<count).map { "/tmp/project/sub\($0)" }
        let excluded = Array(paths.suffix(2))

        let vm = makeViewModel(
            scope: .includeSubfolders,
            excludedPaths: excluded,
            subdirectoryCount: count,
            allSubdirectoryPaths: paths
        )

        XCTAssertFalse(vm.requiresExclusionSelectionBeforeStart)
    }

    func testExclusionNotRequiredWhenHardLimitRefusal() {
        let vm = makeViewModel(
            scope: .includeSubfolders,
            subdirectoryCount: 10_000,
            didExceedLimit: true
        )

        XCTAssertFalse(
            vm.requiresExclusionSelectionBeforeStart,
            "Hard limit refusal takes priority over exclusion requirement"
        )
    }

    // MARK: - startActionStatusText

    func testStartActionStatusTextWhenRefused() {
        let vm = makeViewModel(
            scope: .includeSubfolders,
            didExceedLimit: true
        )

        XCTAssertEqual(vm.startActionStatusText, "Include Subfolders unavailable")
    }

    func testStartActionStatusTextWhenActionRequired() {
        let threshold = FolderWatchPerformancePolicy.exclusionPromptSubdirectoryThreshold
        let count = threshold + 10
        let paths = (0..<count).map { "/tmp/project/sub\($0)" }

        let vm = makeViewModel(
            scope: .includeSubfolders,
            subdirectoryCount: count,
            allSubdirectoryPaths: paths
        )

        XCTAssertEqual(vm.startActionStatusText, "Action required before watch can start")
    }

    func testStartActionStatusTextWhenReady() {
        let vm = makeViewModel(
            scope: .includeSubfolders,
            subdirectoryCount: 10,
            allSubdirectoryPaths: (0..<10).map { "/tmp/project/sub\($0)" }
        )

        XCTAssertEqual(vm.startActionStatusText, "Ready to start")
    }

    func testStartActionStatusTextWhenLargeTreeReviewed() {
        let threshold = FolderWatchPerformancePolicy.exclusionPromptSubdirectoryThreshold
        let count = threshold + 2
        let paths = (0..<count).map { "/tmp/project/sub\($0)" }
        let excluded = Array(paths.suffix(2))

        let vm = makeViewModel(
            scope: .includeSubfolders,
            excludedPaths: excluded,
            subdirectoryCount: count,
            allSubdirectoryPaths: paths
        )

        XCTAssertEqual(vm.startActionStatusText, "Large tree reviewed")
    }

    // MARK: - optimizationCardTone

    func testOptimizationCardToneNeutralWhenSelectedFolderOnly() {
        let vm = makeViewModel(scope: .selectedFolderOnly)

        XCTAssertEqual(vm.optimizationCardTone, .neutral)
    }

    func testOptimizationCardToneNeutralWhileLoading() {
        let vm = makeViewModel(
            scope: .includeSubfolders,
            isLoading: true
        )

        XCTAssertEqual(vm.optimizationCardTone, .neutral)
    }

    func testOptimizationCardToneWarningWhenHardLimitRefusal() {
        let vm = makeViewModel(
            scope: .includeSubfolders,
            didExceedLimit: true
        )

        XCTAssertEqual(vm.optimizationCardTone, .warning)
    }

    func testOptimizationCardToneWarningWhenAboveThreshold() {
        let threshold = FolderWatchPerformancePolicy.exclusionPromptSubdirectoryThreshold
        let count = threshold + 10
        let paths = (0..<count).map { "/tmp/project/sub\($0)" }

        let vm = makeViewModel(
            scope: .includeSubfolders,
            subdirectoryCount: count,
            allSubdirectoryPaths: paths
        )

        XCTAssertEqual(vm.optimizationCardTone, .warning)
    }

    func testOptimizationCardToneSuccessWhenBelowThreshold() {
        let vm = makeViewModel(
            scope: .includeSubfolders,
            subdirectoryCount: 10,
            allSubdirectoryPaths: (0..<10).map { "/tmp/project/sub\($0)" }
        )

        XCTAssertEqual(vm.optimizationCardTone, .success)
    }

    // MARK: - thresholdWarningVisible

    func testThresholdWarningNotVisibleWhenHardLimitRefusal() {
        let vm = makeViewModel(
            scope: .includeSubfolders,
            subdirectoryCount: 10_000,
            didExceedLimit: true
        )

        XCTAssertFalse(vm.thresholdWarningVisible)
    }

    func testThresholdWarningNotVisibleWhenNoSummary() {
        let vm = makeViewModel(
            scope: .includeSubfolders,
            subdirectoryCount: nil
        )

        XCTAssertFalse(vm.thresholdWarningVisible)
    }

    func testThresholdWarningVisibleWhenAboveThreshold() {
        let threshold = FolderWatchPerformancePolicy.exclusionPromptSubdirectoryThreshold
        let vm = makeViewModel(
            scope: .includeSubfolders,
            subdirectoryCount: threshold + 1
        )

        XCTAssertTrue(vm.thresholdWarningVisible)
    }
}
