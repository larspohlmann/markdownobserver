import CoreGraphics
import Testing
@testable import minimark

struct ThemeSelectorLayoutAndPreviewTests {
    @Test
    func themeSelectorUsesExpectedMinimumColumnWidths() {
        #expect(ThemeSelectorColumnWidths.readerMin == 180)
        #expect(ThemeSelectorColumnWidths.syntaxMin == 180)
        #expect(ThemeSelectorColumnWidths.previewMin == 320)
    }

    @Test
    func previewReaderTextExamplesIncludeKeyReaderColors() {
        let readerSamples = ThemePreviewReaderTextExamples.reader(theme: Theme.theme(for: .monokai))

        #expect(readerSamples.count == 4)
        #expect(readerSamples.contains(where: { $0.role == .body && $0.hex == "#F8F8F2" }))
        #expect(readerSamples.contains(where: { $0.role == .secondary && $0.hex == "#CFCFC2" }))
        #expect(readerSamples.contains(where: { $0.role == .link && $0.hex == "#A6E22E" }))
    }
}
