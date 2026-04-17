import Testing
import CoreGraphics
@testable import minimark

struct ReaderWindowResizeTests {
    @Test func sidebarShownWidensWindowByRequestedAmount() {
        let windowFrame = CGRect(x: 100, y: 100, width: 800, height: 1000)
        let screenFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        let result = WindowDefaults.sidebarResizedFrame(
            windowFrame: windowFrame,
            screenVisibleFrame: screenFrame,
            sidebarDelta: 250
        )

        #expect(result.width == 1050)
        #expect(result.height == 1000)
        #expect(result.origin.x == 100)
        #expect(result.origin.y == 100)
    }

    @Test func sidebarHiddenNarrowsWindowByRequestedAmount() {
        let windowFrame = CGRect(x: 100, y: 100, width: 1050, height: 1000)
        let screenFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        let result = WindowDefaults.sidebarResizedFrame(
            windowFrame: windowFrame,
            screenVisibleFrame: screenFrame,
            sidebarDelta: -250
        )

        #expect(result.width == 800)
        #expect(result.height == 1000)
        #expect(result.origin.x == 100)
    }

    @Test func sidebarShownClampsToScreenWidthWhenNoRoomRight() {
        let windowFrame = CGRect(x: 1700, y: 100, width: 800, height: 1000)
        let screenFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        let result = WindowDefaults.sidebarResizedFrame(
            windowFrame: windowFrame,
            screenVisibleFrame: screenFrame,
            sidebarDelta: 250
        )

        // Window should shift left to fit
        #expect(result.width == 1050)
        #expect(result.maxX <= screenFrame.maxX)
        #expect(result.origin.x >= screenFrame.origin.x)
    }

    @Test func sidebarShownClampsWidthWhenDeltaExceedsScreen() {
        let windowFrame = CGRect(x: 0, y: 100, width: 800, height: 1000)
        let screenFrame = CGRect(x: 0, y: 0, width: 900, height: 1080)

        let result = WindowDefaults.sidebarResizedFrame(
            windowFrame: windowFrame,
            screenVisibleFrame: screenFrame,
            sidebarDelta: 250
        )

        // Cannot exceed screen width
        #expect(result.width == 900)
        #expect(result.origin.x == 0)
    }

    @Test func sidebarHiddenDoesNotNarrowBelowMinimumUsableWidth() {
        let windowFrame = CGRect(x: 100, y: 100, width: 700, height: 1000)
        let screenFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        let result = WindowDefaults.sidebarResizedFrame(
            windowFrame: windowFrame,
            screenVisibleFrame: screenFrame,
            sidebarDelta: -250
        )

        #expect(result.width >= WindowDefaults.minimumUsableWidth)
    }

    @Test func sidebarShownRespectsNonZeroScreenOrigin() {
        let windowFrame = CGRect(x: 2600, y: 125, width: 800, height: 1000)
        let screenFrame = CGRect(x: 1920, y: 25, width: 1920, height: 1055)

        let result = WindowDefaults.sidebarResizedFrame(
            windowFrame: windowFrame,
            screenVisibleFrame: screenFrame,
            sidebarDelta: 250
        )

        #expect(result.width == 1050)
        #expect(result.origin.x == 2600)
        #expect(result.origin.x >= screenFrame.origin.x)
        #expect(result.maxX <= screenFrame.maxX)
    }
}
