import Foundation
import Observation

@MainActor
@Observable
final class ReaderTOCController {
    var headings: [TOCHeading] = []
    var isVisible: Bool = false
    var scrollRequest: TOCScrollRequest?
    private(set) var scrollRequestCounter: Int = 0

    func updateHeadings(_ headings: [TOCHeading]) {
        guard self.headings != headings else { return }
        self.headings = headings
        if headings.isEmpty {
            isVisible = false
        }
    }

    func toggle() {
        guard !headings.isEmpty else { return }
        isVisible.toggle()
    }

    func scrollTo(_ heading: TOCHeading) {
        scrollRequestCounter += 1
        scrollRequest = TOCScrollRequest(heading: heading, requestID: scrollRequestCounter)
        isVisible = false
    }

    func clear() {
        headings = []
        isVisible = false
        scrollRequest = nil
        scrollRequestCounter = 0
    }
}
