import Foundation
import Testing
@testable import minimark

@Suite
struct SidebarRowStateTests {
    @Test func derivesRowStateFromReaderStoreProperties() {
        let state = SidebarRowState(
            id: UUID(),
            title: "README.md",
            lastModified: Date(timeIntervalSince1970: 1000),
            isFileMissing: false,
            indicatorState: .none
        )

        #expect(state.title == "README.md")
        #expect(state.lastModified == Date(timeIntervalSince1970: 1000))
        #expect(state.isFileMissing == false)
        #expect(state.indicatorState == .none)
    }

    @Test func equatableSkipsIdenticalState() {
        let id = UUID()
        let date = Date()
        let a = SidebarRowState(id: id, title: "A.md", lastModified: date, isFileMissing: false, indicatorState: .none)
        let b = SidebarRowState(id: id, title: "A.md", lastModified: date, isFileMissing: false, indicatorState: .none)
        #expect(a == b)
    }

    @Test func equatableDetectsChangedTitle() {
        let id = UUID()
        let a = SidebarRowState(id: id, title: "A.md", lastModified: nil, isFileMissing: false, indicatorState: .none)
        let b = SidebarRowState(id: id, title: "B.md", lastModified: nil, isFileMissing: false, indicatorState: .none)
        #expect(a != b)
    }

    @Test func equatableDetectsChangedIndicator() {
        let id = UUID()
        let a = SidebarRowState(id: id, title: "A.md", lastModified: nil, isFileMissing: false, indicatorState: .none)
        let b = SidebarRowState(id: id, title: "A.md", lastModified: nil, isFileMissing: false, indicatorState: .externalChange)
        #expect(a != b)
    }
}
