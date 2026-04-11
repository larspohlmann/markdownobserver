# Security Audit: MarkdownObserver

**Date:** April 2026
**Method:** Code-first static analysis (no runtime penetration testing)
**Classification:** Critical / High / Medium / Low / Informational

---

## Summary

The overall security posture is **moderate**. The app has significant defense mechanisms in place — a comprehensive HTML sanitizer in the JavaScript runtime, proper OSLog privacy annotations, minimal sandbox entitlements, and correct security-scoped resource token management. However, the **lack of a Content Security Policy** and the use of **markdown-it's `html: true` mode** create an elevated XSS risk surface with no browser-level defense-in-depth. Several medium-severity findings around file access and JS injection patterns warrant attention.

All findings are code-backed hypotheses. No runtime exploitation was attempted.

---

## Well-Implemented Defenses (Positive)

1. **HTML Sanitization (`sanitizeRenderedHTML`)** — The runtime sanitizer in `markdownobserver-runtime.js` is comprehensive: tag whitelist, attribute whitelist per tag, `on*` event handler removal, `style` attribute removal, URL scheme validation, comment node removal, `data:image/svg+xml` blocking, and `rel="noopener noreferrer nofollow"` on `_blank` links.
2. **JavaScript String Escaping** — `MarkdownWebView.javaScriptStringLiteral()` uses `JSONSerialization` for proper escaping.
3. **HTML Escaping** — `escapeHTML()` in `MarkdownWebView.swift:835-842` properly escapes `&`, `<`, `>`, `"`, `'`.
4. **URL Sanitization in JS** — `isSafeURL()` blocks `javascript:`, `vbscript:`, `file:`, protocol-relative `//`, and limits `data:` to non-SVG image types.
5. **Path Normalization** — Consistent use of `normalizedFileURL` via `standardizedFileURL.resolvingSymlinksInPath()`.
6. **OSLog Privacy** — Error descriptions use `privacy: .private`; custom `redactedPathText()` hashes full paths.
7. **Minimal Sandbox Entitlements** — Only `com.apple.security.files.user-selected.read-write` is declared.
8. **File Type Validation** — Uses `UTType(filenameExtension:)` for type detection, preventing bypass via unusual extensions.
9. **Token-Based Security Scope Management** — Access tokens are properly ended before starting new ones.
10. **Navigation Policy** — `WKNavigationDelegate` properly handles link clicks with fragment scrolling, external browser opening, and unsupported scheme cancellation.

---

## Findings

### S-1: No Content Security Policy (HIGH)

- **Files:** `minimark/Support/ReaderCSSFactory.swift:31-56`, `minimark/Support/MarkdownSourceHTMLRenderer.swift:197-252`
- **Description:** Neither `makeHTMLDocument` method includes a `<meta http-equiv="Content-Security-Policy">` tag. The WKWebView has no CSP restrictions as a defense-in-depth layer. Combined with markdown-it's `html: true` configuration, raw HTML from markdown is rendered with only application-level JavaScript sanitization.
- **Impact:** If any bypass is found in `sanitizeRenderedHTML()`, there is no secondary browser-level defense. Inline scripts, `eval()`-style constructs, and external resource loading are unrestricted.
- **Fix:** Add a strict CSP: `default-src 'none'; script-src 'unsafe-inline' 'unsafe-eval'; style-src 'unsafe-inline'; img-src data: blob:; font-src data:; connect-src 'none'`
- **Validation:** Inspect generated HTML for CSP meta tag; test XSS payloads in markdown files.

### S-2: markdown-it `html: true` with Application-Level-Only Sanitization (HIGH)

- **File:** `minimark/App/Resources/markdownobserver-runtime.js:71`
- **Description:** The markdown-it parser is configured with `html: true`, allowing raw HTML in markdown files. The rendered HTML is passed through `sanitizeRenderedHTML()` which whitelists ~30 safe tags, removes `on*` event handlers and `style` attributes, validates URLs via `isSafeURL()`, and blocks dangerous schemes.
- **Mitigations in place:** The sanitizer is thorough — it removes `<script>`, `<iframe>`, `<object>`, `<embed>`, `<form>`, `<meta>`, `<link>`, `<svg>`, `<math>`, strips event handlers, and validates URLs.
- **Risk:** The sanitizer runs as JavaScript in the web view. A parser edge case or novel bypass could execute arbitrary JS. Without CSP (S-1), there is no fallback.
- **Fix:** Consider setting `html: false` if raw HTML support is not required. If required, add CSP (S-1) as defense-in-depth.

### S-3: Theme JavaScript Executed via `new Function()` — Eval Equivalent (MEDIUM)

- **Files:** `minimark/Support/ReaderJavaScriptLoader.swift:44`, `minimark/Views/MarkdownWebView.swift:296-301`
- **Description:** Theme JavaScript is base64-decoded and executed using `new Function(themeJS)()`, which is semantically equivalent to `eval()`. Currently only built-in themes provide `customJavaScript` (e.g., Green Terminal theme's canvas animation). `ThemeDefinition` is a struct with hardcoded cases — there is no external theme loading mechanism.
- **Risk:** If a future change allows user-supplied or externally-loaded themes, arbitrary JavaScript execution would be trivial.
- **Fix:** Document this as a security-sensitive boundary. If external themes are ever supported, add a signing/verification mechanism.

### S-4: `file://` URLs Allowed in External Link Navigation (MEDIUM)

- **File:** `minimark/Views/MarkdownWebView.swift:642-653`
- **Description:** `isSafeExternalURL()` allows `file://` scheme URLs to be opened via `NSWorkspace.shared.open(url)`. While the JS-side sanitizer blocks `file:` URLs in `href`/`src`, the native side would still allow them if a link bypasses the JS sanitizer.
- **Impact:** A user opening a malicious markdown file could be tricked into opening arbitrary local files in their default application.
- **Fix:** Remove `"file"` from the `isSafeExternalURL()` whitelist. File navigation should be handled by the app's own routing, not NSWorkspace.

### S-5: Image Resolver Reads Arbitrary Local Files via Absolute/`file://` Paths (MEDIUM)

- **File:** `minimark/Services/MarkdownImageResolver.swift:77-131`
- **Description:** `resolveImage()` accepts `file:///...` URLs (line 85-87), absolute paths starting with `/` (line 88-89), and relative paths that escape the document directory via `../` before `.standardized` resolves (line 97). A crafted markdown file like `![](file:///Users/secret/photo.png)` or `![](/etc/passwd)` causes the app to attempt reading those files. Mitigations: UTType image check, 2MB size limit, macOS sandbox, `isReadableFile` check.
- **Impact:** A crafted markdown file can probe the local filesystem for readable image files outside the document directory, embedded as base64 data URIs in the web view.
- **Fix:** Restrict image resolution to paths within the document directory. Reject `file://` and absolute paths. For relative paths, validate that the resolved path is within the document directory after `.standardized`.

### S-6: `baseURL: Bundle.main.bundleURL` Enables Relative URL Resolution from Bundle (MEDIUM)

- **File:** `minimark/Views/MarkdownWebView.swift:213,248`
- **Description:** HTML is loaded via `loadHTMLString(htmlDocument, baseURL: Bundle.main.bundleURL)`. Relative URLs in rendered content resolve against the app bundle directory. Any bypass in the JS sanitizer could allow loading resources relative to the bundle.
- **Fix:** Consider using `baseURL: nil` or a custom URL. Document this trade-off if the current approach is needed for bundled script loading.

### S-7: Payload Base64 Injected into JS String Literals with Minimal Escaping (MEDIUM)

- **Files:** `minimark/Support/ReaderCSSFactory.swift:103-121`, `minimark/Support/MarkdownSourceHTMLRenderer.swift:62,172,178`
- **Description:** Base64-encoded payloads are injected into JavaScript string literals using only `"` → `\"` escaping. Mitigation: base64 uses only `A-Za-z0-9+/=`, which are safe in JS string literals. The `"` and `\` characters never appear in base64 output.
- **Risk:** The pattern is fragile. If the encoding changes (e.g., raw JSON), this becomes a direct JS injection vector.
- **Fix:** Use `javaScriptStringLiteral()` (which uses `JSONSerialization`) consistently. Add a validation assertion that base64 strings match `[A-Za-z0-9+/=]+`.

### S-8: Security-Scoped Bookmark Data Stored in UserDefaults as Plain JSON (LOW)

- **Files:** `minimark/Stores/ReaderSettingsStore.swift:390-403`, `minimark/Models/ReaderRecentOpenedFile.swift`, `minimark/Models/ReaderRecentWatchedFolder.swift`, `minimark/Models/ReaderTrustedImageFolder.swift`, `minimark/Models/ReaderFavoriteWatchedFolder.swift`
- **Description:** Security-scoped bookmark data (created with `.withSecurityScope` option) is serialized as JSON and stored in `UserDefaults`. Any process running as the same user could read/modify these bookmarks.
- **Impact:** If an attacker gains code execution as the user, they could inject crafted bookmark data pointing to arbitrary file paths. On next app launch, the app would resolve these and potentially access files outside the intended scope.
- **Fix:** Consider using the Keychain for bookmark storage, which provides additional access controls. Validate bookmark resolution results against expected paths.

### S-9: File Names Logged in Cleartext (LOW)

- **File:** `minimark/Stores/ReaderStore.swift:702-711`
- **Description:** `redactedPathText(for:)` hashes full paths but includes the file name (last path component) in cleartext.
- **Impact:** File names of opened documents are visible in the system log.
- **Fix:** Acceptable for a viewer app. Consider fully redacting in production builds if desired.

### S-10: Error Messages May Include File Paths (LOW)

- **Files:** `minimark/Services/ReaderDocumentIOService.swift:21,33`, `minimark/Views/MarkdownWebView.swift:397,409`
- **Description:** Error messages include file URLs. Fallback HTML in `loadFallbackMessage` includes `error.localizedDescription` which may contain the file path. The HTML is properly escaped via `escapeHTML()`.
- **Fix:** Low risk. `escapeHTML()` prevents XSS. Consider redacting paths in user-facing error messages.

### S-11: `nonisolated(unsafe)` Static Mutable CSS Cache (LOW)

- **File:** `minimark/Support/ReaderCSSThemeGenerator.swift:5`
- **Description:** `private nonisolated(unsafe) static var cache` has no synchronization. All production callers are `@MainActor`.
- **Fix:** Consider using `@MainActor` isolation for the entire class.

### S-12: Script Tag `src` Paths Not Validated Against Bundle (LOW)

- **File:** `minimark/Support/ReaderCSSFactory.swift:77-80`
- **Description:** `makeScriptTag(for:)` only double-quote-escapes paths, but does not validate they are within the app bundle.
- **Fix:** Add a URL scheme/prefix check to ensure paths are relative or `file://` URLs within the bundle.

### S-13: Symlink Following Allows Reading Files Outside Expected Scope (LOW)

- **Files:** `minimark/Services/MarkdownImageResolver.swift:97`, `minimark/Services/FolderSnapshotDiffer.swift:379`, `minimark/Support/ReaderFileRouting.swift:13`
- **Description:** The app consistently resolves symlinks via `.standardized` and `.resolvingSymlinksInPath()`. A symlink within a watched folder could point to files outside the expected scope. The image resolver would follow symlinks to read image files from arbitrary locations.
- **Fix:** Limited by macOS sandbox. Document as expected behavior. The sandbox boundary is the primary defense.

### S-14: Arbitrary CSS Class Values Could Match Existing Selectors (LOW)

- **File:** `minimark/App/Resources/markdownobserver-runtime.js:359,459`
- **Description:** The sanitizer strips `style` attributes and `on*` event handlers, but allows arbitrary `class` attribute values. Combined with the extensive CSS in generated HTML, a crafted `class` value could match existing CSS selectors and alter visual presentation.
- **Fix:** Visual-only impact. Low risk. If desired, validate class values against a whitelist.

---

## Priority-Ordered Remediation

| Priority | ID | Finding | Effort |
| --- | --- | --- | --- |
| 1 | S-1 | No Content Security Policy | Low |
| 2 | S-2 | markdown-it `html: true` without browser-level defense | Low |
| 3 | S-4 | `file://` URLs in external link navigation | Low |
| 4 | S-5 | Image resolver reads arbitrary local files | Medium |
| 5 | S-7 | Payload injection with minimal escaping | Low |
| 6 | S-3 | Theme JS via `new Function()` boundary | Low (documentation) |
| 7 | S-6 | `baseURL: Bundle.main.bundleURL` | Medium |
| 8 | S-8 | Bookmarks in UserDefaults | Medium |
| 9 | S-12 | Script src path validation | Low |
| 10 | S-13 | Symlink following | Documentation |
| 11 | S-9, S-10 | Information leakage in logs/errors | Low |
| 12 | S-11, S-14 | Minor (concurrency, CSS class) | Low |

**Highest-impact single fix:** Adding a CSP header (S-1) addresses both S-1 and provides defense-in-depth for S-2, making it the single most valuable change.
