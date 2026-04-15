import Testing
@testable import minimark

@Suite
struct SyntaxThemeMermaidCSSVariableTests {
    private let requiredVariables = [
        "--reader-syntax-text",
        "--reader-syntax-bg",
        "--reader-syntax-border",
        "--reader-syntax-string",
        "--reader-syntax-number",
        "--reader-syntax-title",
        "--reader-syntax-builtin",
        "--reader-syntax-comment",
    ]

    @Test(arguments: SyntaxThemeKind.allCases)
    func themeEmitsMermaidCSSVariables(theme: SyntaxThemeKind) {
        let css = theme.css
        for variable in requiredVariables {
            #expect(css.contains(variable), "Theme \(theme) missing CSS variable \(variable)")
        }
    }

    @Test func monokaiCSSVariablesHaveCorrectValues() {
        let css = SyntaxThemeKind.monokai.css
        #expect(css.contains("--reader-syntax-text: #F8F8F2"))
        #expect(css.contains("--reader-syntax-bg: #272822"))
        #expect(css.contains("--reader-syntax-border: #3A3C33"))
        #expect(css.contains("--reader-syntax-keyword: #F92672"))
        #expect(css.contains("--reader-syntax-string: #E6DB74"))
        #expect(css.contains("--reader-syntax-number: #AE81FF"))
        #expect(css.contains("--reader-syntax-title: #A6E22E"))
        #expect(css.contains("--reader-syntax-builtin: #66D9EF"))
        #expect(css.contains("--reader-syntax-comment: #75715E"))
    }
}
