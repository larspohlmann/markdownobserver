//
//  KaTeXRuntimeAssetsTests.swift
//  minimarkTests
//

import Foundation
import Testing
@testable import minimark

@Suite
struct KaTeXRuntimeAssetsTests {
    @Test func katexAssetConstantsMatchFlattenedResourceLayout() {
        #expect(BundledAssets.katexScriptPath == "Contents/Resources/katex.min.js")
        #expect(BundledAssets.katexCSSPath == "Contents/Resources/katex.min.css")
        #expect(BundledAssets.markdownItKatexScriptPath == "Contents/Resources/markdown-it-katex.min.js")
    }

    @Test func katexScriptIsBundledAlongsideApp() {
        #expect(BundledAssets.availableKatexScriptPath() == BundledAssets.katexScriptPath)
    }

    @Test func katexStylesheetIsBundledAlongsideApp() {
        #expect(BundledAssets.availableKatexCSSPath() == BundledAssets.katexCSSPath)
    }

    @Test func markdownItKatexPluginIsBundledAlongsideApp() {
        #expect(BundledAssets.availableMarkdownItKatexScriptPath() == BundledAssets.markdownItKatexScriptPath)
    }

    @Test func katexCSSUsesFlatFontPathsToMatchBundleLayout() throws {
        let url = Bundle.main.bundleURL.appendingPathComponent(BundledAssets.katexCSSPath)
        let data = try Data(contentsOf: url)
        let css = String(decoding: data, as: UTF8.self)
        // The bundled CSS must not reference `fonts/…` — Xcode's synchronized
        // resource group flattens the Vendor/katex/fonts directory, so the
        // woff2 files land next to the CSS file.
        #expect(!css.contains("url(fonts/"))
        #expect(css.contains("KaTeX_Main-Regular.woff2"))
    }

    @Test func woff2FontsAreBundledForKatexCSS() {
        // Sample three representative fonts; if the resource group drops any,
        // missing ones will fail in the browser silently as 404s.
        let sampleFonts = [
            "KaTeX_Main-Regular.woff2",
            "KaTeX_Math-Italic.woff2",
            "KaTeX_Size2-Regular.woff2"
        ]
        for font in sampleFonts {
            let url = Bundle.main.bundleURL
                .appendingPathComponent("Contents/Resources/\(font)")
            #expect(FileManager.default.fileExists(atPath: url.path), "Missing bundled font: \(font)")
        }
    }
}

@Suite
struct KaTeXContentSecurityPolicyTests {
    @Test func htmlDocumentCSPAllowsLocalFontSources() {
        let factory = CSSFactory()
        let html = factory.makeHTMLDocument(
            css: "",
            payloadBase64: "",
            runtimeAssets: RuntimeAssets(
                markdownItScriptPath: "Contents/Resources/markdown-it.min.js",
                highlightScriptPath: nil,
                taskListsScriptPath: nil,
                footnoteScriptPath: nil,
                attrsScriptPath: nil,
                deflistScriptPath: nil,
                calloutsScriptPath: nil,
                calloutsCSSPath: nil
            )
        )
        #expect(html.contains("font-src file:"))
    }
}
