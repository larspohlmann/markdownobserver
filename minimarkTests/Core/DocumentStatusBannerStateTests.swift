import Testing
@testable import minimark

struct DocumentStatusBannerStateTests {
    @Test
    func equatableReflectsAllFields() {
        let a = DocumentStatusBannerState(
            isCurrentFileMissing: false,
            fileDisplayName: "x",
            errorMessage: nil,
            needsImageDirectoryAccess: false
        )
        let b = DocumentStatusBannerState(
            isCurrentFileMissing: true,
            fileDisplayName: "x",
            errorMessage: nil,
            needsImageDirectoryAccess: false
        )
        #expect(a != b)
    }

    @Test
    func fieldsRoundTrip() {
        let state = DocumentStatusBannerState(
            isCurrentFileMissing: true,
            fileDisplayName: "README.md",
            errorMessage: "File no longer exists",
            needsImageDirectoryAccess: true
        )

        #expect(state.isCurrentFileMissing)
        #expect(state.fileDisplayName == "README.md")
        #expect(state.errorMessage == "File no longer exists")
        #expect(state.needsImageDirectoryAccess)
    }
}
