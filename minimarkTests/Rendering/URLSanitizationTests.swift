//
//  URLSanitizationTests.swift
//  minimarkTests
//

import Foundation
import JavaScriptCore
import Testing
@testable import minimark

@Suite(.serialized)
struct URLSanitizationTests {

    /// The isSafeURL function extracted from markdownobserver-runtime.js.
    /// This must be kept in sync with the source in markdownobserver-runtime.js.
    private static let isSafeURLSource = """
    function isSafeURL(urlValue) {
        if (typeof urlValue !== "string") {
            return false;
        }
        var trimmed = urlValue.trim();
        if (trimmed.length === 0) {
            return true;
        }
        var compact = trimmed.replace(/[\\u0000-\\u001F\\u007F\\s]+/g, "").toLowerCase();
        if (
            compact.indexOf("javascript:") === 0 ||
            compact.indexOf("vbscript:") === 0 ||
            compact.indexOf("file:") === 0
        ) {
            return false;
        }
        if (compact.indexOf("data:") === 0) {
            return /^data:image\\/(?!svg\\+xml)[a-z0-9.+-]+[;,]/.test(compact);
        }
        if (trimmed.indexOf("//") === 0) {
            return false;
        }
        if (
            trimmed.indexOf("#") === 0 ||
            trimmed.indexOf("/") === 0 ||
            trimmed.indexOf("./") === 0 ||
            trimmed.indexOf("../") === 0
        ) {
            return true;
        }
        var schemeMatch = /^[a-zA-Z][a-zA-Z0-9+.-]*:/.exec(trimmed);
        if (!schemeMatch) {
            return true;
        }
        var scheme = schemeMatch[0].toLowerCase();
        return (
            scheme === "http:" ||
            scheme === "https:" ||
            scheme === "mailto:" ||
            scheme === "tel:"
        );
    }
    """

    private func makeContext() throws -> JSContext {
        let context = try #require(JSContext())
        context.exceptionHandler = { _, exception in
            let message = exception?.toString() ?? "unknown"
            Issue.record("JavaScript exception: \(message)")
        }
        context.evaluateScript(Self.isSafeURLSource)
        return context
    }

    private func isSafeURL(_ url: String, context: JSContext) -> Bool {
        context.setObject(url, forKeyedSubscript: "__testURL" as NSString)
        return context.evaluateScript("isSafeURL(__testURL)")?.toBool() ?? false
    }

    // MARK: - Dangerous schemes must be blocked

    @Test func blocksJavaScriptURLs() throws {
        let ctx = try makeContext()
        #expect(!isSafeURL("javascript:alert(1)", context: ctx))
        #expect(!isSafeURL("JAVASCRIPT:alert(1)", context: ctx))
        #expect(!isSafeURL("  javascript:void(0)  ", context: ctx))
    }

    @Test func blocksVBScriptURLs() throws {
        let ctx = try makeContext()
        #expect(!isSafeURL("vbscript:MsgBox", context: ctx))
    }

    @Test func blocksFileURLs() throws {
        let ctx = try makeContext()
        #expect(!isSafeURL("file:///Users/lars/image.png", context: ctx))
        #expect(!isSafeURL("file:///path/to/document.md", context: ctx))
    }

    // MARK: - Data URIs

    @Test func allowsDataImagePNG() throws {
        let ctx = try makeContext()
        #expect(isSafeURL("data:image/png;base64,iVBORw0KGgo=", context: ctx))
    }

    @Test func allowsDataImageJPEG() throws {
        let ctx = try makeContext()
        #expect(isSafeURL("data:image/jpeg;base64,/9j/4AAQ", context: ctx))
    }

    @Test func allowsDataImageGIF() throws {
        let ctx = try makeContext()
        #expect(isSafeURL("data:image/gif;base64,R0lGODlh", context: ctx))
    }

    @Test func allowsDataImageWebP() throws {
        let ctx = try makeContext()
        #expect(isSafeURL("data:image/webp;base64,UklGR", context: ctx))
    }

    @Test func blocksDataImageSVG() throws {
        let ctx = try makeContext()
        #expect(!isSafeURL("data:image/svg+xml;base64,PHN2Zz4=", context: ctx))
        #expect(!isSafeURL("data:image/svg+xml,%3Csvg%3E", context: ctx))
    }

    @Test func blocksDataTextHTML() throws {
        let ctx = try makeContext()
        #expect(!isSafeURL("data:text/html,<script>alert(1)</script>", context: ctx))
    }

    @Test func blocksDataApplicationJavaScript() throws {
        let ctx = try makeContext()
        #expect(!isSafeURL("data:application/javascript,alert(1)", context: ctx))
    }

    @Test func blocksDataTextPlain() throws {
        let ctx = try makeContext()
        #expect(!isSafeURL("data:text/plain;base64,SGVsbG8=", context: ctx))
    }

    @Test func dataImageCaseInsensitive() throws {
        let ctx = try makeContext()
        #expect(isSafeURL("DATA:IMAGE/PNG;base64,iVBORw0KGgo=", context: ctx))
        #expect(isSafeURL("Data:Image/Jpeg;base64,/9j/4AAQ", context: ctx))
    }

    // MARK: - Safe schemes

    @Test func allowsHTTP() throws {
        let ctx = try makeContext()
        #expect(isSafeURL("http://example.com/image.png", context: ctx))
        #expect(isSafeURL("https://example.com/image.png", context: ctx))
    }

    @Test func allowsRelativePaths() throws {
        let ctx = try makeContext()
        #expect(isSafeURL("./image.png", context: ctx))
        #expect(isSafeURL("../assets/photo.jpg", context: ctx))
        #expect(isSafeURL("/absolute/path.png", context: ctx))
    }

    @Test func allowsFragments() throws {
        let ctx = try makeContext()
        #expect(isSafeURL("#section", context: ctx))
    }
}
