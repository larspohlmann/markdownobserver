import XCTest
@testable import minimark

@MainActor
final class ReaderAutoOpenSettlerTests: XCTestCase {

    func test_makePendingContext_returns_nil_for_manual_origin() {
        let settler = ReaderAutoOpenSettler(settlingInterval: 1.0)
        let result = settler.makePendingContext(
            origin: .manual,
            initialDiffBaselineMarkdown: nil,
            loadedMarkdown: "# Hello",
            now: Date()
        )
        XCTAssertNil(result)
    }

    func test_makePendingContext_returns_context_for_folder_watch_auto_open() {
        let settler = ReaderAutoOpenSettler(settlingInterval: 1.0)
        let now = Date()
        let result = settler.makePendingContext(
            origin: .folderWatchAutoOpen,
            initialDiffBaselineMarkdown: "# Old",
            loadedMarkdown: "# New",
            now: now
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.loadedMarkdown, "# New")
        XCTAssertEqual(result?.diffBaselineMarkdown, "# Old")
        XCTAssertFalse(result?.showsLoadingOverlay ?? true)
        XCTAssertNotNil(result?.expiresAt)
    }

    func test_makePendingContext_shows_loading_for_empty_new_file() {
        let settler = ReaderAutoOpenSettler(settlingInterval: 1.0)
        let result = settler.makePendingContext(
            origin: .folderWatchAutoOpen,
            initialDiffBaselineMarkdown: nil,
            loadedMarkdown: "",
            now: Date()
        )
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.showsLoadingOverlay ?? false)
        XCTAssertNil(result?.expiresAt)
    }

    func test_makePendingContext_returns_context_for_initial_batch_auto_open() {
        let settler = ReaderAutoOpenSettler(settlingInterval: 1.0)
        let result = settler.makePendingContext(
            origin: .folderWatchInitialBatchAutoOpen,
            initialDiffBaselineMarkdown: nil,
            loadedMarkdown: "# Content",
            now: Date()
        )
        XCTAssertNotNil(result)
        XCTAssertFalse(result?.showsLoadingOverlay ?? true)
    }

    func test_beginSettling_nil_clears_state() {
        let settler = makeConfiguredSettler()

        let context = PendingAutoOpenSettlingContext(
            loadedMarkdown: "# Test",
            diffBaselineMarkdown: nil,
            expiresAt: Date().addingTimeInterval(10),
            showsLoadingOverlay: false
        )
        settler.beginSettling(context)
        XCTAssertNotNil(settler.pendingContext)

        settler.beginSettling(nil)
        XCTAssertNil(settler.pendingContext)
    }

    func test_beginSettling_sets_load_state_to_settling_when_loading_overlay() {
        var loadStates: [ReaderDocumentLoadState] = []
        let settler = makeConfiguredSettler(onLoadStateChanged: { loadStates.append($0) })

        let context = PendingAutoOpenSettlingContext(
            loadedMarkdown: "",
            diffBaselineMarkdown: nil,
            expiresAt: nil,
            showsLoadingOverlay: true
        )
        settler.beginSettling(context)
        XCTAssertEqual(loadStates.last, .settlingAutoOpen)
    }

    func test_clearSettling_resets_state() {
        var loadStates: [ReaderDocumentLoadState] = []
        let settler = makeConfiguredSettler(onLoadStateChanged: { loadStates.append($0) })

        let context = PendingAutoOpenSettlingContext(
            loadedMarkdown: "# Test",
            diffBaselineMarkdown: nil,
            expiresAt: Date().addingTimeInterval(10),
            showsLoadingOverlay: true
        )
        settler.beginSettling(context)
        settler.clearSettling()
        XCTAssertNil(settler.pendingContext)
        XCTAssertEqual(loadStates.last, .ready)
    }

    func test_handleChangeIfNeeded_returns_false_without_context() {
        let settler = ReaderAutoOpenSettler(settlingInterval: 1.0)
        let url = URL(fileURLWithPath: "/tmp/test.md")
        let result = settler.handleChangeIfNeeded(fileURL: url) { _ in
            ("# Hello", Date())
        }
        XCTAssertFalse(result)
    }

    func test_handleChangeIfNeeded_detects_content_change_and_settles() {
        var settledCalls: [(markdown: String, fileURL: URL)] = []
        let settler = makeConfiguredSettler(
            onDocumentSettled: { loaded, fileURL, _ in
                settledCalls.append((loaded.markdown, fileURL))
            }
        )

        let context = PendingAutoOpenSettlingContext(
            loadedMarkdown: "# Old",
            diffBaselineMarkdown: nil,
            expiresAt: Date().addingTimeInterval(10),
            showsLoadingOverlay: false
        )
        settler.beginSettling(context)

        let url = URL(fileURLWithPath: "/tmp/test.md")
        let result = settler.handleChangeIfNeeded(fileURL: url) { _ in
            ("# New", Date())
        }

        XCTAssertTrue(result)
        XCTAssertEqual(settledCalls.count, 1)
        XCTAssertEqual(settledCalls.first?.markdown, "# New")
        XCTAssertNil(settler.pendingContext)
    }

    func test_handleChangeIfNeeded_returns_handled_when_content_unchanged() {
        let settler = makeConfiguredSettler()

        let context = PendingAutoOpenSettlingContext(
            loadedMarkdown: "# Same",
            diffBaselineMarkdown: nil,
            expiresAt: Date().addingTimeInterval(10),
            showsLoadingOverlay: false
        )
        settler.beginSettling(context)

        let url = URL(fileURLWithPath: "/tmp/test.md")
        let result = settler.handleChangeIfNeeded(fileURL: url) { _ in
            ("# Same", Date())
        }

        XCTAssertTrue(result)
        XCTAssertNil(settler.pendingContext)
    }

    func test_handleChangeIfNeeded_clears_when_expired() {
        let settler = makeConfiguredSettler()

        let context = PendingAutoOpenSettlingContext(
            loadedMarkdown: "# Old",
            diffBaselineMarkdown: nil,
            expiresAt: Date().addingTimeInterval(-1),
            showsLoadingOverlay: false
        )
        settler.beginSettling(context)

        let url = URL(fileURLWithPath: "/tmp/test.md")
        let result = settler.handleChangeIfNeeded(fileURL: url) { _ in
            ("# Whatever", Date())
        }

        XCTAssertFalse(result)
        XCTAssertNil(settler.pendingContext)
    }

    func test_handleChangeIfNeeded_passes_diff_baseline_on_settle() {
        var settledDiffBaseline: String?
        let settler = makeConfiguredSettler(
            onDocumentSettled: { _, _, diffBaseline in
                settledDiffBaseline = diffBaseline
            }
        )

        let context = PendingAutoOpenSettlingContext(
            loadedMarkdown: "# Old",
            diffBaselineMarkdown: "# Baseline",
            expiresAt: Date().addingTimeInterval(10),
            showsLoadingOverlay: false
        )
        settler.beginSettling(context)

        let url = URL(fileURLWithPath: "/tmp/test.md")
        _ = settler.handleChangeIfNeeded(fileURL: url) { _ in
            ("# New", Date())
        }

        XCTAssertEqual(settledDiffBaseline, "# Baseline")
    }

    func test_handleChangeIfNeeded_returns_false_when_loader_throws() {
        let settler = makeConfiguredSettler()

        let context = PendingAutoOpenSettlingContext(
            loadedMarkdown: "# Old",
            diffBaselineMarkdown: nil,
            expiresAt: Date().addingTimeInterval(10),
            showsLoadingOverlay: false
        )
        settler.beginSettling(context)

        let url = URL(fileURLWithPath: "/tmp/test.md")
        let result = settler.handleChangeIfNeeded(fileURL: url) { _ in
            throw NSError(domain: "test", code: 0)
        }

        XCTAssertFalse(result)
        XCTAssertNotNil(settler.pendingContext)
    }

    // MARK: - Helpers

    private func makeConfiguredSettler(
        currentFileURL: @escaping () -> URL? = { nil },
        loadFile: @escaping (URL) throws -> (markdown: String, modificationDate: Date) = { _ in throw NSError(domain: "test", code: 0) },
        onDocumentSettled: @escaping ((markdown: String, modificationDate: Date), URL, String?) -> Void = { _, _, _ in },
        onLoadStateChanged: @escaping (ReaderDocumentLoadState) -> Void = { _ in }
    ) -> ReaderAutoOpenSettler {
        let settler = ReaderAutoOpenSettler(settlingInterval: 1.0)
        settler.configure(
            currentFileURL: currentFileURL,
            loadFile: loadFile,
            onDocumentSettled: onDocumentSettled,
            onLoadStateChanged: onLoadStateChanged
        )
        return settler
    }
}
