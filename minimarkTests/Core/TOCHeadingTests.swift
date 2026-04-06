import Foundation
import Testing
@testable import minimark

@Suite
struct TOCHeadingTests {
    @Test func initializesWithAllProperties() {
        let heading = TOCHeading(elementID: "introduction", level: 1, title: "Introduction", sourceLine: 3, index: 0)
        #expect(heading.elementID == "introduction")
        #expect(heading.level == 1)
        #expect(heading.title == "Introduction")
        #expect(heading.sourceLine == 3)
        #expect(heading.index == 0)
    }

    @Test func sourceLineCanBeNil() {
        let heading = TOCHeading(elementID: "setup", level: 2, title: "Setup", sourceLine: nil, index: 0)
        #expect(heading.sourceLine == nil)
    }

    @Test func equatableComparesAllFields() {
        let a = TOCHeading(elementID: "a", level: 1, title: "A", sourceLine: 1, index: 0)
        let b = TOCHeading(elementID: "a", level: 1, title: "A", sourceLine: 1, index: 0)
        let c = TOCHeading(elementID: "a", level: 2, title: "A", sourceLine: 1, index: 0)
        #expect(a == b)
        #expect(a != c)
    }

    @Test func identifiableUsesIndex() {
        let h1 = TOCHeading(elementID: "intro", level: 1, title: "Intro", sourceLine: 1, index: 0)
        let h2 = TOCHeading(elementID: "intro", level: 1, title: "Intro", sourceLine: 1, index: 1)
        #expect(h1.id != h2.id)
    }

    @Test func duplicateHeadingsGetDistinctIDs() {
        let payload: [[String: Any]] = [
            ["id": "setup", "level": 2, "title": "Setup", "sourceLine": NSNull()],
            ["id": "setup", "level": 2, "title": "Setup", "sourceLine": NSNull()]
        ]
        let headings = TOCHeading.fromJavaScriptPayload(payload)
        #expect(headings.count == 2)
        #expect(headings[0].id != headings[1].id)
    }

    @Test func parsesFromJavaScriptPayload() {
        let payload: [[String: Any]] = [
            ["id": "getting-started", "level": 2, "title": "Getting Started", "sourceLine": 10],
            ["id": "installation", "level": 3, "title": "Installation", "sourceLine": 15],
            ["id": "", "level": 1, "title": "Source Only", "sourceLine": 1]
        ]
        let headings = TOCHeading.fromJavaScriptPayload(payload)
        #expect(headings.count == 3)
        #expect(headings[0].elementID == "getting-started")
        #expect(headings[0].level == 2)
        #expect(headings[0].title == "Getting Started")
        #expect(headings[0].sourceLine == 10)
        #expect(headings[0].index == 0)
        #expect(headings[2].elementID == "")
        #expect(headings[2].sourceLine == 1)
        #expect(headings[2].index == 2)
    }

    @Test func parsesFromJavaScriptPayloadSkipsInvalidEntries() {
        let payload: [[String: Any]] = [
            ["id": "ok", "level": 1, "title": "OK", "sourceLine": 1],
            ["level": 2, "title": "Missing ID"],
            ["id": "ok2", "level": 1, "title": "OK2", "sourceLine": 3]
        ]
        let headings = TOCHeading.fromJavaScriptPayload(payload)
        #expect(headings.count == 2)
        #expect(headings[0].title == "OK")
        #expect(headings[1].title == "OK2")
    }

    @Test func parsesNullSourceLineAsNil() {
        let payload: [[String: Any]] = [
            ["id": "test", "level": 1, "title": "Test", "sourceLine": NSNull()]
        ]
        let headings = TOCHeading.fromJavaScriptPayload(payload)
        #expect(headings.count == 1)
        #expect(headings[0].sourceLine == nil)
    }
}
