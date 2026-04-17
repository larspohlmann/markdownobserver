//
//  CheckboxCSSTests.swift
//  minimarkTests
//

import Testing
@testable import minimark

@Suite
struct CheckboxCSSTests {
    private let css = CSSFactory().makeCSS(
        theme: ThemeKind.blackOnWhite.themeDefinition,
        syntaxTheme: .default,
        baseFontSize: 16.0
    )

    @Test
    func checkboxUsesAppearanceNone() {
        #expect(css.contains("appearance: none"))
    }

    @Test
    func checkboxHasRoundedBorder() {
        #expect(css.contains("border-radius: 4px"))
        #expect(css.contains("border: 1.5px solid var(--reader-border)"))
    }

    @Test
    func checkedCheckboxFillsWithLinkColor() {
        #expect(css.contains("background-color: var(--reader-link)"))
        #expect(css.contains("border-color: var(--reader-link)"))
    }

    @Test
    func checkedCheckboxHasSVGCheckmark() {
        #expect(css.contains("background-image: url(\"data:image/svg+xml"))
    }

    @Test
    func checkedItemTextIsDimmed() {
        #expect(css.contains(".task-list-item:has(.task-list-item-checkbox:checked)"))
        #expect(css.contains("opacity: 0.55"))
    }

    @Test
    func checkboxIsNotInteractive() {
        #expect(css.contains("pointer-events: none"))
    }

    @Test
    func noAccentColorRemains() {
        #expect(!css.contains("accent-color"))
    }
}
