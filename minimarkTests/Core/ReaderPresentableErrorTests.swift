import Foundation
import Testing
@testable import minimark

struct ReaderPresentableErrorTests {
    @Test func fileReadErrorClassifiesCorrectly() {
        let error = ReaderPresentableError(from: ReaderError.fileReadFailed(
            URL(fileURLWithPath: "/test.md"),
            underlying: NSError(domain: "test", code: 1)
        ))
        #expect(error.kind == .fileRead)
        #expect(error.message.contains("Failed to read"))
    }

    @Test func fileWriteErrorClassifiesCorrectly() {
        let error = ReaderPresentableError(from: ReaderError.fileWriteFailed(
            URL(fileURLWithPath: "/test.md"),
            underlying: NSError(domain: "test", code: 1)
        ))
        #expect(error.kind == .fileWrite)
    }

    @Test func renderingErrorClassifiesCorrectly() {
        let error = ReaderPresentableError(from: ReaderError.renderingFailed(
            underlying: NSError(domain: "test", code: 1)
        ))
        #expect(error.kind == .rendering)
    }

    @Test func applicationErrorClassifiesCorrectly() {
        let error = ReaderPresentableError(from: ReaderError.noRegisteredApplications(
            URL(fileURLWithPath: "/test.md")
        ))
        #expect(error.kind == .application)
    }

    @Test func genericNSErrorClassifiesAsGeneral() {
        let error = ReaderPresentableError(from: NSError(domain: "test", code: 42, userInfo: [
            NSLocalizedDescriptionKey: "Something went wrong"
        ]))
        #expect(error.kind == .general)
        #expect(error.message == "Something went wrong")
    }

    @Test func equalityBasedOnKindAndMessage() {
        let a = ReaderPresentableError(from: ReaderError.fileNotReachable(URL(fileURLWithPath: "/a.md")))
        let b = ReaderPresentableError(from: ReaderError.fileNotReachable(URL(fileURLWithPath: "/a.md")))
        let c = ReaderPresentableError(from: ReaderError.fileNotReachable(URL(fileURLWithPath: "/b.md")))
        #expect(a == b)
        #expect(a != c)
    }

    @Test func fileMissingKindFromFileNotReachable() {
        let error = ReaderPresentableError(from: ReaderError.fileNotReachable(
            URL(fileURLWithPath: "/missing.md")
        ))
        #expect(error.kind == .fileMissing)
    }
}
