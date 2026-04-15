//
//  RenderingAndDiffTests.swift
//  minimarkTests
//

import Foundation
import JavaScriptCore
import Testing
@testable import minimark

@Suite(.serialized)
struct RenderingAndDiffTests {
    private struct InlineDiffMaskResult: Decodable {
        let tokens: [String]
        let removedKinds: [String?]
    }

    private struct InlineDiffNode: Decodable {
        let tagName: String?
        let className: String?
        let textContent: String?
        let style: [String: String]?
        let children: [InlineDiffNode]?
    }

    private func inlineDiffMask(previous: String, current: String) throws -> InlineDiffMaskResult {
        let context = try #require(JSContext())
        context.exceptionHandler = { _, exception in
            let message = exception?.toString() ?? "unknown"
            Issue.record("JavaScript exception: \(message)")
        }

        context.evaluateScript(ReaderBundledAssetLoader.inlineDiffRuntimeJavaScript)
        context.setObject(previous, forKeyedSubscript: "__previous" as NSString)
        context.setObject(current, forKeyedSubscript: "__current" as NSString)

        let jsonValue = try #require(
            context.evaluateScript("JSON.stringify(buildRemovedTokenMask(__previous, __current))")?.toString()
        )

        return try JSONDecoder().decode(InlineDiffMaskResult.self, from: Data(jsonValue.utf8))
    }

    private func removedKind(
        for token: String,
        in result: InlineDiffMaskResult
    ) -> String? {
        for (index, candidate) in result.tokens.enumerated() where candidate == token {
            return result.removedKinds[index]
        }

        return nil
    }

    private func extractedFunctionSource(
        named functionName: String,
        endingBefore nextFunctionName: String,
        in html: String
    ) throws -> String {
        let start = try #require(html.range(of: "function \(functionName)"))
        let end = try #require(html.range(of: "function \(nextFunctionName)", range: start.upperBound..<html.endIndex))
        return String(html[start.lowerBound..<end.lowerBound])
    }

    private func renderedDiffComparisonNode(previous: String, current: String) throws -> InlineDiffNode {
        let factory = ReaderCSSFactory()
        let html = factory.makeHTMLDocument(
            css: "",
            payloadBase64: "",
            runtimeAssets: ReaderRuntimeAssets(
                markdownItScriptPath: "markdown-it.min.js",
                highlightScriptPath: "highlight.min.js",
                taskListsScriptPath: nil,
                footnoteScriptPath: nil,
                attrsScriptPath: nil,
                deflistScriptPath: nil,
                calloutsScriptPath: nil,
                calloutsCSSPath: nil
            )
        )

        let functionSource = try extractedFunctionSource(
            named: "makeDiffComparisonColumn",
            endingBefore: "createInlineComparisonPanel",
            in: html
        )

        let context = try #require(JSContext())
        context.evaluateScript(
            """
            var document = {
              createElement: function(tagName) {
                return {
                  tagName: tagName,
                  className: "",
                  textContent: "",
                                    style: {},
                  children: [],
                  appendChild: function(child) {
                    this.children.push(child);
                    return child;
                  }
                };
              }
            };
            """
        )
        context.evaluateScript(ReaderBundledAssetLoader.inlineDiffRuntimeJavaScript)
        context.evaluateScript(functionSource)
        context.setObject(previous, forKeyedSubscript: "__previous" as NSString)
        context.setObject(current, forKeyedSubscript: "__current" as NSString)

        let jsonValue = try #require(
            context.evaluateScript(
                "JSON.stringify(makeDiffComparisonColumn('Previous', __previous, __current))"
            )?.toString()
        )

        return try JSONDecoder().decode(InlineDiffNode.self, from: Data(jsonValue.utf8))
    }

    private func firstNode(
        matching predicate: (InlineDiffNode) -> Bool,
        in node: InlineDiffNode
    ) -> InlineDiffNode? {
        if predicate(node) {
            return node
        }

        for child in node.children ?? [] {
            if let match = firstNode(matching: predicate, in: child) {
                return match
            }
        }

        return nil
    }

    @Test func markdownSourceHTMLRendererIncludesCodeMirrorBootstrap() {
        let html = MarkdownSourceHTMLRenderer.makeHTMLDocument(
            markdown: "# Heading\n\n- item",
            settings: .default,
            isEditable: false
        )

        #expect(html.contains("minimark-source-root"))
        #expect(html.contains("MinimarkCodeMirrorSourceView.bootstrap"))
        #expect(html.contains("codemirror-source-view.js"))
        #expect(html.contains("__minimarkSourceBootstrapStatus"))
    }

    @Test func htmlDocumentContainsContentSecurityPolicy() {
        let factory = ReaderCSSFactory()
        let html = factory.makeHTMLDocument(
            css: "",
            payloadBase64: "",
            runtimeAssets: ReaderRuntimeAssets(
                markdownItScriptPath: "markdown-it.min.js",
                highlightScriptPath: "highlight.min.js",
                taskListsScriptPath: nil,
                footnoteScriptPath: nil,
                attrsScriptPath: nil,
                deflistScriptPath: nil,
                calloutsScriptPath: nil,
                calloutsCSSPath: nil
            )
        )

        #expect(html.contains("Content-Security-Policy"))
        #expect(html.contains("default-src 'none'"))
        #expect(html.contains("script-src 'unsafe-inline' 'unsafe-eval' file:"))
        #expect(html.contains("img-src data: https:"))
    }

    @Test func htmlRuntimeEmbedsAndUpdatesRuntimeCSS() {
        let factory = ReaderCSSFactory()
        let html = factory.makeHTMLDocument(
            css: "body { color: red; }",
            payloadBase64: "payload",
            runtimeAssets: ReaderRuntimeAssets(
                markdownItScriptPath: "markdown-it.min.js",
                highlightScriptPath: "highlight.min.js",
                taskListsScriptPath: nil,
                footnoteScriptPath: nil,
                attrsScriptPath: nil,
                deflistScriptPath: nil,
                calloutsScriptPath: nil,
                calloutsCSSPath: nil
            )
        )

        #expect(html.contains("<meta name=\"minimark-runtime-css-base64\" content=\""))
        #expect(html.contains("<style id=\"minimark-runtime-style\">"))
        #expect(html.contains("function applyRuntimeCSS(cssBase64Value)"))
        #expect(html.contains("window.__minimarkApplyRuntimeCSS = function (cssBase64Value)"))
        #expect(html.contains("applyRuntimeCSS(runtimeCSSBase64);"))
    }

    @Test func htmlRuntimeExposesOverlayTopInsetSetter() {
        let factory = ReaderCSSFactory()
        let html = factory.makeHTMLDocument(
            css: "",
            payloadBase64: "",
            runtimeAssets: ReaderRuntimeAssets(
                markdownItScriptPath: "markdown-it.min.js",
                highlightScriptPath: "highlight.min.js",
                taskListsScriptPath: nil,
                footnoteScriptPath: nil,
                attrsScriptPath: nil,
                deflistScriptPath: nil,
                calloutsScriptPath: nil,
                calloutsCSSPath: nil
            )
        )

        #expect(html.contains("function setOverlayTopInset(value)"))
        #expect(html.contains("window.__minimarkSetOverlayTopInset = function (value)"))
    }

    @Test func htmlRuntimeChangedRegionNavigationUsesMutableOverlayInsetVariable() {
        let factory = ReaderCSSFactory()
        let html = factory.makeHTMLDocument(
            css: "",
            payloadBase64: "",
            runtimeAssets: ReaderRuntimeAssets(
                markdownItScriptPath: "markdown-it.min.js",
                highlightScriptPath: "highlight.min.js",
                taskListsScriptPath: nil,
                footnoteScriptPath: nil,
                attrsScriptPath: nil,
                deflistScriptPath: nil,
                calloutsScriptPath: nil,
                calloutsCSSPath: nil
            )
        )

        #expect(html.contains("overlayTopInset = Math.max(0, numericValue);"))
        #expect(html.contains("row.top - overlayTopInset"))
        #expect(html.contains("var probeTop = currentTop + overlayTopInset;"))
    }

    @Test func htmlRuntimeMeasuresChangedRegionMarkersWithExpandedPanelsStillMounted() {
        let factory = ReaderCSSFactory()
        let html = factory.makeHTMLDocument(
            css: "",
            payloadBase64: "",
            runtimeAssets: ReaderRuntimeAssets(
                markdownItScriptPath: "markdown-it.min.js",
                highlightScriptPath: "highlight.min.js",
                taskListsScriptPath: nil,
                footnoteScriptPath: nil,
                attrsScriptPath: nil,
                deflistScriptPath: nil,
                calloutsScriptPath: nil,
                calloutsCSSPath: nil
            )
        )

        let anchorIndexRange = html.range(of: "var anchorIndex = buildSourceLineAnchorIndex(root);")
        let reconcileRange = html.range(of: "reconcileInlineComparisonPanels(markers, root);")
        let earlyCleanupRange = html.range(of: "if (!root || !Array.isArray(regions) || regions.length === 0) {")

        #expect(html.contains("function removeStaleInlineComparisonPanels(root, validPanelIDs)"))
        #expect(html.contains("function reconcileInlineComparisonPanels(markers, root)"))
        #expect(html.contains("removeStaleInlineComparisonPanels(root, validPanelIDs);"))
        #expect(anchorIndexRange != nil)
        #expect(reconcileRange != nil)
        #expect(earlyCleanupRange != nil)

        if let anchorIndexRange, let reconcileRange {
            #expect(anchorIndexRange.lowerBound < reconcileRange.lowerBound)
        }
    }

    @Test func inlineDiffClassifierDistinguishesPureDeletionFromReplacement() throws {
        let deletedResult = try inlineDiffMask(
            previous: "the next word in this line will be deleted: thiswillbedeleted.",
            current: "the next word in this line will be deleted: ."
        )

        let replacedResult = try inlineDiffMask(
            previous: "the next word in this line will be changed: thiswillbechanged.",
            current: "the next word in this line will be changed: thiswaschanged."
        )

        #expect(removedKind(for: "thiswillbedeleted", in: deletedResult) == "deleted")
        #expect(removedKind(for: "thiswillbechanged", in: replacedResult) == "edited")
    }

    @Test func inlineDiffComparisonColumnUsesDifferentClassesForDeletedAndReplacedWords() throws {
        let deletedNode = try renderedDiffComparisonNode(
            previous: "the next word in this line will be deleted: thiswillbedeleted.",
            current: "the next word in this line will be deleted: ."
        )
        let replacedNode = try renderedDiffComparisonNode(
            previous: "the next word in this line will be changed: thiswillbechanged.",
            current: "the next word in this line will be changed: thiswaschanged."
        )

        let deletedToken = try #require(firstNode(matching: {
            $0.textContent == "thiswillbedeleted"
        }, in: deletedNode))
        let replacedToken = try #require(firstNode(matching: {
            $0.textContent == "thiswillbechanged"
        }, in: replacedNode))

        #expect(deletedToken.className == "reader-inline-diff-removed reader-inline-diff-removed-deleted")
        #expect(replacedToken.className == "reader-inline-diff-removed")
        #expect(deletedToken.style?["backgroundColor"] == "var(--reader-changed-deleted)")
        #expect(replacedToken.style?["backgroundColor"] == "var(--reader-changed-edited)")
    }

    @Test func inlineDiffComparisonColumnTreatsRemovedSmallWordAsDeleted() throws {
        let deletedNode = try renderedDiffComparisonNode(
            previous: "Blocking small, isolated fixes with process.",
            current: "Blocking isolated fixes with process."
        )

        let smallToken = try #require(firstNode(matching: {
            $0.textContent == "small"
        }, in: deletedNode))

        #expect(smallToken.className == "reader-inline-diff-removed reader-inline-diff-removed-deleted")
        #expect(smallToken.style?["backgroundColor"] == "var(--reader-changed-deleted)")
    }

    @Test func inlineDiffComparisonColumnTreatsRemovedWordWithOnlyWhitespaceChangeAsDeleted() throws {
        let deletedNode = try renderedDiffComparisonNode(
            previous: "Treat plan files as the default for anything beyond a very small change.",
            current: "Treat plan files as the default for anything beyond a very  change."
        )

        let smallToken = try #require(firstNode(matching: {
            $0.textContent == "small"
        }, in: deletedNode))

        #expect(smallToken.className == "reader-inline-diff-removed reader-inline-diff-removed-deleted")
        #expect(smallToken.style?["backgroundColor"] == "var(--reader-changed-deleted)")
    }

    @Test @MainActor func inlineDiffUsesDeletedStylingForRemovedSmallWordFromFullMarkdownFlow() throws {
        let oldMarkdown = """
        ---
        name: Planning Gatekeeper
        description: Use for large, risky, or ambiguous changes that need scope control, sequencing, or approval before implementation.
        argument-hint: Describe the risky or broad change, expected scope, and what needs approval.
        tools: [read, search, edit]
        user-invocable: false
        ---

        You create lightweight implementation plans.

        ## Focus

        - Clarify scope, assumptions, risks, and validation.
        - Split large work into small executable steps.
        - Turn those steps into a task list that can be updated as implementation progresses.
        - Treat plan files as the default for anything beyond a very small change.
        - Write the plan as a Markdown file under `.github/plans/` before implementation starts.
        - End with an explicit approval checkpoint and do not authorize implementation until the user approves the plan.

        ## Plan file

        - Create or update a single plan file in `.github/plans/` for the active task.
        - Use a short descriptive filename in kebab-case.
        - Include: goal, scope, assumptions, risks, a task list, implementation steps, and validation.
        - Format the task list as a Markdown checklist and update it immediately as each task is completed.
        - Do not mark multiple remaining items complete together at the end just to catch the checklist up.
        - If scope changes after review, update the plan file and request approval again.

        ## Avoid

        - Blocking small, isolated fixes with process.
        - Starting implementation for non-trivial work before the plan is approved.
        - Rewriting scope after approval unless requirements changed.

        ## Return

        - A concise execution plan.
        - An explicit approval checkpoint.
        - The plan file path.
        """

        let newMarkdown = oldMarkdown.replacingOccurrences(
            of: "- Blocking small, isolated fixes with process.",
            with: "- Blocking  isolated fixes with process."
        )

        let differ = ChangedRegionDiffer()
        let regions = differ.computeChangedRegions(oldMarkdown: oldMarkdown, newMarkdown: newMarkdown)
        let targetPreviousSnippet = "- Blocking small, isolated fixes with process."
        let editedRegion = try #require(regions.first(where: { region in
            guard region.kind == .edited else {
                return false
            }

            guard region.previousTextSnippet == targetPreviousSnippet else {
                return false
            }

            return region.currentTextSnippet?.contains("isolated fixes with process.") == true
        }))

        let deletedNode = try renderedDiffComparisonNode(
            previous: try #require(editedRegion.previousTextSnippet),
            current: try #require(editedRegion.currentTextSnippet)
        )

        let smallToken = try #require(firstNode(matching: {
            $0.textContent == "small"
        }, in: deletedNode))

        #expect(smallToken.className == "reader-inline-diff-removed reader-inline-diff-removed-deleted")
        #expect(smallToken.style?["backgroundColor"] == "var(--reader-changed-deleted)")
    }

    @Test func readerCSSUsesFullAvailableDocumentWidth() {
        let factory = ReaderCSSFactory()

        let css = factory.makeCSS(theme: ReaderThemeKind.blackOnWhite.themeDefinition, syntaxTheme: .default, baseFontSize: 16)

        #expect(css.contains("width: 100%;"))
        #expect(css.contains("margin: 0;"))
        #expect(css.contains("--reader-gutter-base-width: 32px;"))
        #expect(!css.contains("width: min(100%, 980px);"))
        #expect(!css.contains("margin: 0 auto;"))
    }

    @Test func htmlRuntimeLayersDeletedChangedRegionMarkersAboveOtherMarkers() {
        let factory = ReaderCSSFactory()
        let html = factory.makeHTMLDocument(
            css: "",
            payloadBase64: "",
            runtimeAssets: ReaderRuntimeAssets(
                markdownItScriptPath: "markdown-it.min.js",
                highlightScriptPath: "highlight.min.js",
                taskListsScriptPath: nil,
                footnoteScriptPath: nil,
                attrsScriptPath: nil,
                deflistScriptPath: nil,
                calloutsScriptPath: nil,
                calloutsCSSPath: nil
            )
        )

        #expect(html.contains("function changedRegionMarkerPaintRank(kind)"))
        #expect(html.contains("function assignMarkerLanes(markers)"))
        #expect(html.contains("function findClosestAnchorForRegion(anchorIndex, startLine, endLine)"))
        #expect(html.contains("if (row && row.kind === \"deleted\") {"))
        #expect(html.contains("function safeAnchorPlacement(region)"))
        #expect(html.contains("function inlineComparisonPanelFootprint(panelID)"))
        #expect(html.contains("function deletedMarkerBoundary(anchorIndex, region, anchors, regionKey)"))
        #expect(html.contains("var deletedMarkerThickness = 28;"))
        #expect(html.contains("var fallbackAnchor = findClosestAnchorForRegion(anchorIndex, startLine, endLine);"))
        #expect(html.contains("layout.style.setProperty(\"--reader-gutter-lane-count\", String(Math.max(1, laneCount)));"))
        #expect(html.contains("rowElement.style.left = String(row.laneOffset || 0) + \"px\";"))
        #expect(html.contains("rowElement.style.zIndex = String(changedRegionMarkerPaintRank(row.kind) + 1);"))
        #expect(html.contains("var markerRowWidth = 32;"))
        #expect(html.contains("marker.rowWidth = markerRowWidth;"))
        #expect(html.contains("marker.laneOffset = 0;"))
        #expect(!html.contains("marker.rowWidth = 34;"))
        #expect(!html.contains("marker.laneOffset = 1;"))
        #expect(html.contains("var placement = row.anchorPlacement === \"before\" ? \"beforebegin\" : \"afterend\";"))
        #expect(html.contains("panel.appendChild(makeComparisonColumn(\"Deleted\", row.previousTextSnippet));"))
    }

    @Test @MainActor func changedRegionDifferCreatesDeletedRegionForRemovedLine() {
        let differ = ChangedRegionDiffer()

        let regions = differ.computeChangedRegions(
            oldMarkdown: "# Demo\nRemove me\nKeep me",
            newMarkdown: "# Demo\nKeep me"
        )

        #expect(regions.contains { region in
            region.kind == .deleted
                && region.lineRange == 2...2
                && region.anchorPlacement == .before
                && region.deletedLineCount == 1
                && region.previousTextSnippet == "Remove me"
        })
    }

    @Test @MainActor func changedRegionDifferAnchorsTrailingDeletionAfterPreviousLine() {
        let differ = ChangedRegionDiffer()

        let regions = differ.computeChangedRegions(
            oldMarkdown: "# Demo\nKeep me\nRemove me",
            newMarkdown: "# Demo\nKeep me"
        )

        #expect(regions.contains { region in
            region.kind == .deleted
                && region.lineRange == 2...2
                && region.anchorPlacement == .after
                && region.deletedLineCount == 1
                && region.previousTextSnippet == "Remove me"
        })
    }

    @Test @MainActor func changedRegionDifferCreatesDeletedRegionForRemovedBlankLine() {
        let differ = ChangedRegionDiffer()

        let regions = differ.computeChangedRegions(
            oldMarkdown: "# Demo\n\nKeep me",
            newMarkdown: "# Demo\nKeep me"
        )

        #expect(regions.contains { region in
            region.kind == .deleted
                && region.lineRange == 2...2
                && region.deletedLineCount == 1
        })
    }

    @Test @MainActor func changedRegionDifferKeepsFullDeletedSnippetContent() {
        let differ = ChangedRegionDiffer()

        let deletedLines = (1...10).map { "Deleted line \($0)" }.joined(separator: "\n")
        let oldMarkdown = "# Demo\n\(deletedLines)\nKeep me"
        let newMarkdown = "# Demo\nKeep me"

        let regions = differ.computeChangedRegions(
            oldMarkdown: oldMarkdown,
            newMarkdown: newMarkdown
        )

        #expect(regions.contains { region in
            region.kind == .deleted
                && (region.previousTextSnippet?.contains("Deleted line 1") ?? false)
                && (region.previousTextSnippet?.contains("Deleted line 10") ?? false)
                && (region.previousTextSnippet?.contains("...") ?? true) == false
        })
    }

    @Test @MainActor func changedRegionDifferCreatesDeletedRegionForRemovedMarkdownSectionWithRepeatedSeparators() {
        let differ = ChangedRegionDiffer()

        let oldMarkdown = """
        # Markdown Demo

        ---

        ## Links & Images

        [Markdown Guide](https://www.markdownguide.org)

        ![Placeholder Image](https://via.placeholder.com/600x200)

        ---

        ## Code
        """

        let newMarkdown = """
        # Markdown Demo

        ---

        ## Code
        """

        let regions = differ.computeChangedRegions(
            oldMarkdown: oldMarkdown,
            newMarkdown: newMarkdown
        )

        #expect(regions.contains { region in
            region.kind == .deleted
                && (region.deletedLineCount ?? 0) >= 5
                && (region.previousTextSnippet?.contains("Links & Images") ?? false)
                && (region.previousTextSnippet?.contains("Markdown Guide") ?? false)
        })
    }

    @Test @MainActor func changedRegionDifferCreatesDeletedRegionForRemovedLinksAndImagesSection() {
        let differ = ChangedRegionDiffer()

        let oldMarkdown = """
        # Markdown Demo

        A short document demonstrating common **Markdown features** for preview screenshots.

        ---

        ## Task List

        - [x] Write demo
        - [x] Add formatting examples
        - [ ] Capture screenshot

        ---

        ## Links & Images

        [Markdown Guide](https://www.markdownguide.org)

        ![Placeholder Image](https://via.placeholder.com/600x200)

        ---

        ## Code
        """

        let newMarkdown = """
        # Markdown Demo

        A short document demonstrating common **Markdown features** for preview screenshots.

        ---

        ## Task List

        - [x] Write demo
        - [x] Add formatting examples
        - [ ] Capture screenshot

        ## Code
        """

        let regions = differ.computeChangedRegions(
            oldMarkdown: oldMarkdown,
            newMarkdown: newMarkdown
        )

        #expect(regions.contains { region in
            region.kind == .deleted
                && (region.deletedLineCount ?? 0) >= 5
                && (region.previousTextSnippet?.contains("Links & Images") ?? false)
                && (region.previousTextSnippet?.contains("Placeholder Image") ?? false)
        })
    }

    @Test @MainActor func changedRegionDifferCreatesDeletedRegionForRemovingOnlyLinksAndImagesContent() {
        let differ = ChangedRegionDiffer()

        let oldMarkdown = """
        # Markdown Demo

        A short document demonstrating common **Markdown features** for preview screenshots.

        ---

        ## Text Styles

        Regular text, **bold text**, *italic text*, ***bold italic***, ~~strikethrough~~, and `inline code`.

        > A blockquote can highlight important information or callouts.

        ---

        ## Lists

        ### Unordered

        - Item one
        - Item two
          - Nested item
          - Another nested item
        - Item three

        ### Ordered

        1. First step
        2. Second step
        3. Third step

        ---

        ## Task List

        - [x] Write demo
        - [x] Add formatting examples
        - [ ] Capture screenshot

        ---

        ## Links & Images

        [Markdown Guide](https://www.markdownguide.org)

        ![Placeholder Image](https://via.placeholder.com/600x200)

        ---

        ## Code
        """

        let newMarkdown = """
        # Markdown Demo

        A short document demonstrating common **Markdown features** for preview screenshots.

        ---

        ## Text Styles

        Regular text, **bold text**, *italic text*, ***bold italic***, ~~strikethrough~~, and `inline code`.

        > A blockquote can highlight important information or callouts.

        ---

        ## Lists

        ### Unordered

        - Item one
        - Item two
          - Nested item
          - Another nested item
        - Item three

        ### Ordered

        1. First step
        2. Second step
        3. Third step

        ---

        ## Task List

        - [x] Write demo
        - [x] Add formatting examples
        - [ ] Capture screenshot


        ---

        ## Code
        """

        let regions = differ.computeChangedRegions(
            oldMarkdown: oldMarkdown,
            newMarkdown: newMarkdown
        )

        let deletedRegions = regions.filter { $0.kind == .deleted }

        #expect(deletedRegions.count == 1)
        #expect(deletedRegions.contains { region in
            region.kind == .deleted
                && (region.deletedLineCount ?? 0) >= 5
                && (region.previousTextSnippet?.contains("Links & Images") ?? false)
                && (region.previousTextSnippet?.contains("Markdown Guide") ?? false)
        })
    }

    @Test @MainActor func changedRegionDifferDoesNotKeepDeletedMarkerWhenRestoringRemovedSection() {
        let differ = ChangedRegionDiffer()

        let restoredMarkdown = """
        ## UX defaults

        - Favor immediate clarity: the primary reading experience should stay visually dominant.
        - Default to fewer controls, fewer competing accents, and less persistent chrome.
        - In the main reader window, avoid adding sidebars, inspectors, bottom toolbars, or editor-style panels unless explicitly requested.
        - In settings, expose only controls that are directly relevant to reading and ensure preview feedback is immediate and useful.
        - Prefer native-feeling copy and interactions over clever or decorative UI.

        ## For open-ended UI requests

        - Start by identifying the UX problem, not just the missing component.
        - If the request is underspecified, briefly state the recommended direction and why before editing code.
        - Prefer the smallest change that materially improves usability.
        - If incremental additions are making the UI noisy or incoherent, recommend a focused cleanup or simplification.
        """

        let deletedMarkdown = """
        ## UX defaults

        ## For open-ended UI requests

        - Start by identifying the UX problem, not just the missing component.
        - If the request is underspecified, briefly state the recommended direction and why before editing code.
        - Prefer the smallest change that materially improves usability.
        - If incremental additions are making the UI noisy or incoherent, recommend a focused cleanup or simplification.
        """

        let regions = differ.computeChangedRegions(
            oldMarkdown: deletedMarkdown,
            newMarkdown: restoredMarkdown
        )

        #expect(regions.contains { $0.kind == .added || $0.kind == .edited })
        #expect(!regions.contains { $0.kind == .deleted })
    }

    // MARK: - Adjacent region coalescing (#234)

    @Test @MainActor func changedRegionDifferCoalescesConsecutiveEditedLinesIntoOneRegion() {
        let differ = ChangedRegionDiffer()

        let oldMarkdown = "# Title\n\nLine one\nLine two\nLine three\n\nEnd"
        let newMarkdown = "# Title\n\nLine one modified\nLine two modified\nLine three modified\n\nEnd"

        let regions = differ.computeChangedRegions(
            oldMarkdown: oldMarkdown,
            newMarkdown: newMarkdown
        )

        let editedRegions = regions.filter { $0.kind == .edited }
        #expect(editedRegions.count == 1)
        #expect(editedRegions.first?.lineRange == 3...5)
    }

    @Test @MainActor func changedRegionDifferCoalescesConsecutiveAddedLinesIntoOneRegion() {
        let differ = ChangedRegionDiffer()

        let oldMarkdown = "# Title\n\nEnd"
        let newMarkdown = "# Title\n\nNew line one\nNew line two\n\nEnd"

        let regions = differ.computeChangedRegions(
            oldMarkdown: oldMarkdown,
            newMarkdown: newMarkdown
        )

        let addedRegions = regions.filter { $0.kind == .added }
        #expect(addedRegions.count == 1)
        #expect(addedRegions.first?.lineRange == 3...4)
    }

    @Test @MainActor func changedRegionDifferKeepsSeparateRegionsForLinesSeparatedByBlankLine() {
        let differ = ChangedRegionDiffer()

        let oldMarkdown = "# Title\n\nParagraph one\n\nParagraph two"
        let newMarkdown = "# Title\n\nParagraph one modified\n\nParagraph two modified"

        let regions = differ.computeChangedRegions(
            oldMarkdown: oldMarkdown,
            newMarkdown: newMarkdown
        )

        let editedRegions = regions.filter { $0.kind == .edited }
        #expect(editedRegions.count == 2)
    }

    @Test @MainActor func changedRegionDifferDoesNotCoalesceDeletedWithEdited() {
        let differ = ChangedRegionDiffer()

        let oldMarkdown = "# Title\n\nRemove me\nKeep me\n\nEnd"
        let newMarkdown = "# Title\n\nKeep me modified\n\nEnd"

        let regions = differ.computeChangedRegions(
            oldMarkdown: oldMarkdown,
            newMarkdown: newMarkdown
        )

        let deletedRegions = regions.filter { $0.kind == .deleted }
        let editedRegions = regions.filter { $0.kind == .edited }
        #expect(deletedRegions.count + editedRegions.count >= 2)
        #expect(!deletedRegions.isEmpty)
        #expect(!editedRegions.isEmpty)
    }

    @Test @MainActor func changedRegionDifferSingleLineEditProducesOneRegion() {
        let differ = ChangedRegionDiffer()

        let oldMarkdown = "# Title\n\nOriginal line\n\nEnd"
        let newMarkdown = "# Title\n\nModified line\n\nEnd"

        let regions = differ.computeChangedRegions(
            oldMarkdown: oldMarkdown,
            newMarkdown: newMarkdown
        )

        let editedRegions = regions.filter { $0.kind == .edited }
        #expect(editedRegions.count == 1)
        #expect(editedRegions.first?.lineRange == 3...3)
    }

    // MARK: - Fenced code block changes (#269)

    @Test @MainActor func changedRegionDifferDetectsEditInsideFencedCodeBlock() {
        let differ = ChangedRegionDiffer()

        let oldMarkdown = "# Title\n\n```swift\nlet x = 1\nlet y = 2\nlet z = 3\n```\n\n- Next item"
        let newMarkdown = "# Title\n\n```swift\nlet x = 1\nlet y = 999\nlet z = 3\n```\n\n- Next item"

        let regions = differ.computeChangedRegions(
            oldMarkdown: oldMarkdown,
            newMarkdown: newMarkdown
        )

        let editedRegions = regions.filter { $0.kind == .edited }
        #expect(editedRegions.count == 1)
        #expect(editedRegions.first?.lineRange == 5...5)
    }

    @Test @MainActor func changedRegionDifferDoesNotMisattributeCodeBlockChangeToFollowingLine() {
        let differ = ChangedRegionDiffer()

        let oldMarkdown = "# Title\n\n```swift\nlet x = original\n```\n\n- Item after block"
        let newMarkdown = "# Title\n\n```swift\nlet x = changed\n```\n\n- Item after block"

        let regions = differ.computeChangedRegions(
            oldMarkdown: oldMarkdown,
            newMarkdown: newMarkdown
        )

        let editedRegions = regions.filter { $0.kind == .edited }
        #expect(editedRegions.count == 1)
        let region = editedRegions.first
        #expect(region?.lineRange == 4...4)
        #expect(region?.lineRange.contains(7) == false, "Changed region must not include lines after the code block")
    }
}
