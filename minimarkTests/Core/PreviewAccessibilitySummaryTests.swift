import Foundation
import Testing
@testable import minimark

@Suite
struct PreviewAccessibilitySummaryTests {

    @Test func descriptionMatchesLegacyFormat() {
        let summary = PreviewAccessibilitySummary(
            fileName: "notes.md",
            regionCount: 3,
            mode: .split
        )

        #expect(summary.description == "file=notes.md|regions=3|mode=split|surface=preview")
    }

    @Test func descriptionEscapesNothingForPlainFilenames() {
        let summary = PreviewAccessibilitySummary(
            fileName: "none",
            regionCount: 0,
            mode: .preview
        )

        #expect(summary.description == "file=none|regions=0|mode=preview|surface=preview")
    }

    @Test func roundTripRecoversOriginalValue() {
        let original = PreviewAccessibilitySummary(
            fileName: "auto-open.md",
            regionCount: 7,
            mode: .source
        )

        let parsed = PreviewAccessibilitySummary(rawValue: original.description)

        #expect(parsed == original)
    }

    @Test func parsesEachSupportedMode() {
        for mode in DocumentViewMode.allCases {
            let raw = "file=x.md|regions=0|mode=\(mode.rawValue)|surface=preview"
            let parsed = PreviewAccessibilitySummary(rawValue: raw)

            #expect(parsed?.mode == mode, "failed for \(mode)")
        }
    }

    @Test func parsesFilenameContainingSpaces() {
        let parsed = PreviewAccessibilitySummary(
            rawValue: "file=my notes.md|regions=2|mode=preview|surface=preview"
        )

        #expect(parsed?.fileName == "my notes.md")
        #expect(parsed?.regionCount == 2)
    }

    @Test func rejectsMissingKey() {
        let parsed = PreviewAccessibilitySummary(
            rawValue: "file=x.md|regions=0|surface=preview"
        )

        #expect(parsed == nil)
    }

    @Test func rejectsUnknownMode() {
        let parsed = PreviewAccessibilitySummary(
            rawValue: "file=x.md|regions=0|mode=banana|surface=preview"
        )

        #expect(parsed == nil)
    }

    @Test func rejectsNonIntegerRegionCount() {
        let parsed = PreviewAccessibilitySummary(
            rawValue: "file=x.md|regions=many|mode=preview|surface=preview"
        )

        #expect(parsed == nil)
    }

    @Test func rejectsUnknownSurface() {
        let parsed = PreviewAccessibilitySummary(
            rawValue: "file=x.md|regions=0|mode=preview|surface=mystery"
        )

        #expect(parsed == nil)
    }
}
