(function () {
  var payload = decodePayload("__MINIMARK_PAYLOAD_BASE64__");
  var runtimeCSSBase64 = "__MINIMARK_CSS_BASE64__";
  var overlayTopInset = 56;

  function decodeBase64UTF8(base64Value) {
    var binary = atob(base64Value);
    var bytes = new Uint8Array(binary.length);
    for (var i = 0; i < binary.length; i += 1) {
      bytes[i] = binary.charCodeAt(i);
    }
    if (typeof TextDecoder !== "undefined") {
      return new TextDecoder("utf-8").decode(bytes);
    }
    var utf8 = "";
    for (var j = 0; j < bytes.length; j += 1) {
      utf8 += String.fromCharCode(bytes[j]);
    }
    return decodeURIComponent(escape(utf8));
  }

  function decodePayload(base64Value) {
    try {
      return JSON.parse(decodeBase64UTF8(base64Value));
    } catch (_) {
      return { markdown: "", changedRegions: [], unsavedChangedRegions: [] };
    }
  }

  function applyRuntimeCSS(cssBase64Value) {
    runtimeCSSBase64 = cssBase64Value || "";
    var styleElement = document.getElementById("minimark-runtime-style");
    if (!styleElement) {
      styleElement = document.createElement("style");
      styleElement.id = "minimark-runtime-style";
      document.head.appendChild(styleElement);
    }

    styleElement.textContent = runtimeCSSBase64 ? decodeBase64UTF8(runtimeCSSBase64) : "";

    var cssMeta = document.querySelector('meta[name="minimark-runtime-css-base64"]');
    if (cssMeta) {
      cssMeta.setAttribute("content", runtimeCSSBase64);
    }
  }

  function createMarkdownIt() {
    if (!window.markdownit || typeof window.markdownit !== "function") {
      return null;
    }

    var md = window.markdownit({
      html: true,
      linkify: true,
      typographer: false,
      breaks: false
    });

    configureURLSanitizer(md);
    registerPlugins(md);

    var defaultRenderToken = md.renderer.renderToken.bind(md.renderer);
    md.renderer.renderToken = function (tokens, idx, options) {
      var token = tokens[idx];
      sanitizeTokenAttributes(token);
      if (token.nesting === 1 && Array.isArray(token.map) && token.map.length === 2) {
        token.attrSet("data-src-line-start", String(token.map[0] + 1));
        token.attrSet("data-src-line-end", String(token.map[1]));
      }
      return defaultRenderToken(tokens, idx, options);
    };

    return md;
  }

  function registerPlugin(md, plugin, options) {
    if (typeof plugin !== "function") {
      return;
    }
    try {
      if (options) {
        md.use(plugin, options);
      } else {
        md.use(plugin);
      }
    } catch (_) {
      // Keep rendering available even if a plugin is incompatible.
    }
  }

  function registerPlugins(md) {
    installHeadingIDs(md);
    registerPlugin(md, window.markdownitTaskLists, {
      enabled: true,
      label: true,
      labelAfter: true
    });
    registerPlugin(md, window.markdownitFootnote);
    registerPlugin(md, window.markdownitDeflist);
    registerPlugin(md, window.markdownItAttrs);
  }

  function installHeadingIDs(md) {
    md.core.ruler.push("reader-heading-ids", function (state) {
      var usedIDs = Object.create(null);
      var tokens = state.tokens || [];

      for (var i = 0; i < tokens.length; i += 1) {
        var token = tokens[i];
        if (!token || token.type !== "heading_open") {
          continue;
        }

        var existingID = token.attrGet("id");
        if (existingID) {
          usedIDs[String(existingID).toLowerCase()] = true;
          continue;
        }

        var inlineToken = tokens[i + 1];
        var headingText = inlineToken && inlineToken.type === "inline"
          ? inlineToken.content
          : "";
        var slug = slugifyHeadingText(headingText);
        var uniqueSlug = makeUniqueHeadingSlug(slug, usedIDs);
        token.attrSet("id", uniqueSlug);
      }
    });
  }

  function slugifyHeadingText(textValue) {
    var normalized = String(textValue || "").toLowerCase().trim();
    normalized = normalized.replace(/[^a-z0-9\s-]/g, "");
    normalized = normalized.replace(/\s+/g, "-");
    normalized = normalized.replace(/-+/g, "-");
    normalized = normalized.replace(/^-+|-+$/g, "");
    return normalized || "section";
  }

  function makeUniqueHeadingSlug(baseSlug, usedIDs) {
    var slug = baseSlug;
    var suffix = 0;

    while (usedIDs[slug]) {
      suffix += 1;
      slug = baseSlug + "-" + String(suffix);
    }

    usedIDs[slug] = true;
    return slug;
  }

  function configureURLSanitizer(md) {
    var defaultValidateLink = md.validateLink;
    md.validateLink = function (urlValue) {
      if (!isSafeURL(urlValue)) {
        return false;
      }
      // data:image URIs are validated by isSafeURL — skip
      // the default markdown-it validator which blocks the data: scheme.
      if (typeof urlValue === "string") {
        var c = urlValue.trim().replace(/[\u0000-\u001F\u007F\s]+/g, "").toLowerCase();
        if (c.indexOf("data:") === 0) {
          return true;
        }
      }
      if (typeof defaultValidateLink === "function") {
        return defaultValidateLink(urlValue);
      }
      return true;
    };
  }

  function isSafeURL(urlValue) {
    if (typeof urlValue !== "string") {
      return false;
    }

    var trimmed = urlValue.trim();
    if (trimmed.length === 0) {
      return true;
    }

    var compact = trimmed.replace(/[\u0000-\u001F\u007F\s]+/g, "").toLowerCase();
    if (
      compact.indexOf("javascript:") === 0 ||
      compact.indexOf("vbscript:") === 0 ||
      compact.indexOf("file:") === 0
    ) {
      return false;
    }

    if (compact.indexOf("data:") === 0) {
      return /^data:image\/(?!svg\+xml)[a-z0-9.+-]+[;,]/.test(compact);
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

  function sanitizeURL(urlValue) {
    if (!isSafeURL(urlValue)) {
      return "#";
    }
    return urlValue;
  }

  function sanitizeRenderedHTML(rawHTML) {
    if (typeof rawHTML !== "string" || rawHTML.length === 0) {
      return "";
    }

    var template = document.createElement("template");
    template.innerHTML = rawHTML;

    var allowedTags = {
      "a": true,
      "blockquote": true,
      "br": true,
      "code": true,
      "dd": true,
      "del": true,
      "details": true,
      "div": true,
      "dl": true,
      "dt": true,
      "em": true,
      "h1": true,
      "h2": true,
      "h3": true,
      "h4": true,
      "h5": true,
      "h6": true,
      "hr": true,
      "img": true,
      "input": true,
      "li": true,
      "main": true,
      "mark": true,
      "ol": true,
      "p": true,
      "pre": true,
      "s": true,
      "span": true,
      "strong": true,
      "sub": true,
      "summary": true,
      "sup": true,
      "table": true,
      "tbody": true,
      "td": true,
      "th": true,
      "thead": true,
      "tr": true,
      "ul": true
    };

    function isAllowedHTMLAttribute(tagName, attrName) {
      var globalAllowed = {
        "align": true,
        "aria-label": true,
        "aria-hidden": true,
        "class": true,
        "colspan": true,
        "data-src-line-start": true,
        "data-src-line-end": true,
        "disabled": true,
        "height": true,
        "id": true,
        "open": true,
        "role": true,
        "rowspan": true,
        "title": true,
        "width": true
      };

      if (globalAllowed[attrName]) {
        return true;
      }

      if (attrName.indexOf("aria-") === 0) {
        return true;
      }

      var perTag = {
        "a": { "href": true, "name": true, "target": true, "rel": true },
        "img": { "src": true, "alt": true },
        "input": { "type": true, "checked": true }
      };

      return !!(perTag[tagName] && perTag[tagName][attrName]);
    }

    function sanitizeElement(node) {
      if (!node || node.nodeType !== Node.ELEMENT_NODE) {
        return;
      }

      var tagName = String(node.tagName || "").toLowerCase();
      if (!allowedTags[tagName]) {
        var parent = node.parentNode;
        if (!parent) {
          return;
        }
        while (node.firstChild) {
          parent.insertBefore(node.firstChild, node);
        }
        parent.removeChild(node);
        return;
      }

      var attributes = Array.prototype.slice.call(node.attributes || []);
      for (var i = 0; i < attributes.length; i += 1) {
        var attribute = attributes[i];
        var attrName = String(attribute.name || "").toLowerCase();
        var value = String(attribute.value || "");

        if (attrName.indexOf("on") === 0 || attrName === "style") {
          node.removeAttribute(attribute.name);
          continue;
        }

        if (!isAllowedHTMLAttribute(tagName, attrName)) {
          node.removeAttribute(attribute.name);
          continue;
        }

        if (attrName === "href" || attrName === "src") {
          if (!isSafeURL(value)) {
            node.setAttribute(attribute.name, "#");
          }
        }
      }

      if (tagName === "a") {
        var href = node.getAttribute("href");
        if (!href) {
          node.setAttribute("href", "#");
        }
        if (node.getAttribute("target") === "_blank") {
          node.setAttribute("rel", "noopener noreferrer nofollow");
        }
      }

      var children = Array.prototype.slice.call(node.childNodes || []);
      for (var childIndex = 0; childIndex < children.length; childIndex += 1) {
        var child = children[childIndex];
        if (child.nodeType === Node.ELEMENT_NODE) {
          sanitizeElement(child);
        } else if (child.nodeType === Node.COMMENT_NODE) {
          child.parentNode.removeChild(child);
        }
      }
    }

    var rootChildren = Array.prototype.slice.call(template.content.childNodes || []);
    for (var rootIndex = 0; rootIndex < rootChildren.length; rootIndex += 1) {
      var child = rootChildren[rootIndex];
      if (child.nodeType === Node.ELEMENT_NODE) {
        sanitizeElement(child);
      } else if (child.nodeType === Node.COMMENT_NODE) {
        child.parentNode.removeChild(child);
      }
    }

    return template.innerHTML;
  }

  function isAllowedAttribute(tagName, attrName) {
    var globalAllowed = {
      "id": true,
      "class": true,
      "align": true,
      "width": true,
      "height": true,
      "data-src-line-start": true,
      "data-src-line-end": true
    };

    if (globalAllowed[attrName]) {
      return true;
    }

    if (attrName.indexOf("aria-") === 0) {
      return true;
    }

    var perTag = {
      "a": { "href": true, "name": true, "target": true, "rel": true },
      "img": { "src": true, "alt": true, "title": true },
      "th": { "colspan": true, "rowspan": true },
      "td": { "colspan": true, "rowspan": true },
      "ol": { "start": true },
      "input": { "type": true, "checked": true, "disabled": true }
    };

    return !!(perTag[tagName] && perTag[tagName][attrName]);
  }

  function sanitizeTokenAttributes(token) {
    if (!token || !Array.isArray(token.attrs)) {
      return;
    }

    var tagName = String(token.tag || "").toLowerCase();
    var sanitized = [];

    for (var i = 0; i < token.attrs.length; i += 1) {
      var pair = token.attrs[i];
      if (!Array.isArray(pair) || pair.length < 2) {
        continue;
      }

      var rawName = String(pair[0] || "");
      var name = rawName.toLowerCase();
      var value = String(pair[1] || "");

      if (name.indexOf("on") === 0 || name === "style") {
        continue;
      }

      if (!isAllowedAttribute(tagName, name)) {
        continue;
      }

      if (name === "href" || name === "src") {
        value = sanitizeURL(value);
      }

      sanitized.push([name, value]);
    }

    token.attrs = sanitized.length > 0 ? sanitized : null;

    if (tagName === "a") {
      var href = token.attrGet("href");
      if (!href) {
        token.attrSet("href", "#");
      }
      if (token.attrGet("target") === "_blank") {
        token.attrSet("rel", "noopener noreferrer nofollow");
      }
    }
  }

  function overlaps(startA, endA, startB, endB) {
    return startA <= endB && startB <= endA;
  }

  function isListContainerElement(element) {
    var tagName = String(element && element.tagName || "").toUpperCase();
    return tagName === "UL" || tagName === "OL";
  }

  function getElementDepthWithinRoot(element, root) {
    var depth = 0;
    var node = element;
    while (node && node !== root) {
      depth += 1;
      node = node.parentElement;
    }
    return depth;
  }

  function chooseNarrowerAnchor(currentBest, candidate) {
    if (!currentBest) {
      return candidate;
    }

    if (candidate.span !== currentBest.span) {
      return candidate.span < currentBest.span ? candidate : currentBest;
    }

    var currentIsListContainer = currentBest.isListContainer;
    var candidateIsListContainer = candidate.isListContainer;
    if (currentIsListContainer !== candidateIsListContainer) {
      return candidateIsListContainer ? currentBest : candidate;
    }

    if (candidate.depth !== currentBest.depth) {
      return candidate.depth > currentBest.depth ? candidate : currentBest;
    }

    return currentBest;
  }

  function findNarrowestAnchorForLine(anchorIndex, lineNumber) {
    var best = null;
    for (var i = 0; i < anchorIndex.length; i += 1) {
      var candidate = anchorIndex[i];
      if (!overlaps(candidate.lineStart, candidate.lineEnd, lineNumber, lineNumber)) {
        continue;
      }
      best = chooseNarrowerAnchor(best, candidate);
    }
    return best;
  }

  var expandedComparisonRows = Object.create(null);
  var activeNavigatedChangedRegionKey = null;
  var latestChangedRegionRenderState = {
    root: null,
    gutter: null,
    regions: [],
    markers: []
  };
  var changedRegionRenderScheduled = false;
  var changedRegionLayoutObserversInstalled = false;

  function clampMarkerTop(top, maxTop) {
    if (!Number.isFinite(top)) {
      return 0;
    }
    if (top < 0) {
      return 0;
    }
    if (top > maxTop) {
      return maxTop;
    }
    return top;
  }

  function parsePixelNumber(value, fallback) {
    var number = Number.parseFloat(value);
    return Number.isFinite(number) ? number : fallback;
  }

  function computeGutterIconTop(row) {
    var iconSize = 18;
    var rowHeight = Number(row && row.height) || 0;
    var maxTop = Math.max(0, rowHeight - iconSize);
    var anchorElement = row && row.anchorElement;

    if (row && row.kind === "deleted") {
      return clampMarkerTop(Math.max(0, (rowHeight - iconSize) / 2), maxTop);
    }

    if (!anchorElement) {
      return Math.min(2, maxTop);
    }

    var style = window.getComputedStyle(anchorElement);
    var fontSize = parsePixelNumber(style.fontSize, 13);
    var lineHeight = parsePixelNumber(style.lineHeight, fontSize * 1.45);
    var paddingTop = parsePixelNumber(style.paddingTop, 0);

    var top = paddingTop + Math.max(0, (lineHeight - iconSize) / 2);
    return clampMarkerTop(top, maxTop);
  }

  function buildChangedRegionTooltip(region) {
    if (!region || typeof region.kind !== "string") {
      return "Edited";
    }

    if (region.kind === "added") {
      return "Added";
    }

    if (region.kind === "deleted") {
      var deletedLineCount = Number(region.deletedLineCount);
      if (!Number.isFinite(deletedLineCount) || deletedLineCount <= 0) {
        return "Deleted";
      }
      return deletedLineCount === 1
        ? "Deleted 1 line"
        : "Deleted " + String(deletedLineCount) + " lines";
    }

    return "Edited";
  }

  function buildChangedRegionActionLabel(region, isExpanded) {
    var tooltip = buildChangedRegionTooltip(region);
    return tooltip + (isExpanded ? ". Collapse comparison" : ". Expand comparison");
  }

  function supportsInlineComparison(region) {
    if (!region || (region.kind !== "edited" && region.kind !== "deleted")) {
      return false;
    }

    return typeof region.previousTextSnippet === "string" && region.previousTextSnippet.length > 0;
  }

  function safeAnchorPlacement(region) {
    if (!region || region.kind !== "deleted") {
      return null;
    }

    if (region.anchorPlacement === "before") {
      return "before";
    }

    if (region.anchorPlacement === "after") {
      return "after";
    }

    return null;
  }

  function inlineComparisonPanelFootprint(panelID) {
    if (!panelID) {
      return 0;
    }

    var panel = document.getElementById(panelID);
    if (!panel) {
      return 0;
    }

    var style = window.getComputedStyle(panel);
    var marginTop = parsePixelNumber(style.marginTop, 0);
    var marginBottom = parsePixelNumber(style.marginBottom, 0);
    return Math.max(0, panel.offsetHeight + marginTop + marginBottom);
  }

  function safeRegionKind(kind) {
    if (kind === "added" || kind === "deleted") {
      return kind;
    }
    return "edited";
  }

  function changedRegionMarkerPaintRank(kind) {
    if (kind === "deleted") {
      return 2;
    }

    if (kind === "edited") {
      return 1;
    }

    return 0;
  }

  function applyChangedRegionLaneCount(root, laneCount) {
    var layout = root && root.parentElement;
    if (!layout) {
      return;
    }

    layout.style.setProperty("--reader-gutter-lane-count", String(Math.max(1, laneCount)));
  }

  function assignMarkerLanes(markers) {
    if (!Array.isArray(markers) || markers.length === 0) {
      return 1;
    }

    var markerRowWidth = 32;

    for (var markerIndex = 0; markerIndex < markers.length; markerIndex += 1) {
      var marker = markers[markerIndex];
      marker.lane = 0;
      marker.rowWidth = markerRowWidth;
      marker.laneOffset = 0;
    }

    return 1;
  }

  function closeChangedRegionMarkerGaps(markers) {
    if (!Array.isArray(markers) || markers.length < 2) {
      return;
    }

    var sortedMarkers = markers.slice().sort(function (lhs, rhs) {
      if (lhs.lineStart !== rhs.lineStart) {
        return lhs.lineStart - rhs.lineStart;
      }

      if (lhs.top !== rhs.top) {
        return lhs.top - rhs.top;
      }

      return changedRegionMarkerPaintRank(rhs.kind) - changedRegionMarkerPaintRank(lhs.kind);
    });

    for (var i = 0; i < sortedMarkers.length - 1; i += 1) {
      var currentMarker = sortedMarkers[i];
      var nextMarker = sortedMarkers[i + 1];

      if (!currentMarker || !nextMarker) {
        continue;
      }

      if (currentMarker.kind !== nextMarker.kind) {
        continue;
      }

      if (currentMarker.kind !== "added" && currentMarker.kind !== "edited") {
        continue;
      }

      if (nextMarker.lineStart > currentMarker.lineEnd + 2) {
        continue;
      }

      var currentBottom = currentMarker.top + currentMarker.height;
      if (nextMarker.top <= currentBottom) {
        currentMarker.lineEnd = Math.max(currentMarker.lineEnd, nextMarker.lineEnd);
        continue;
      }

      currentMarker.height = Math.max(currentMarker.height, nextMarker.top - currentMarker.top);
      currentMarker.lineEnd = Math.max(currentMarker.lineEnd, nextMarker.lineEnd);
    }
  }

  function makeRegionKey(region, index) {
    return [
      safeRegionKind(region && region.kind),
      Number(region && region.lineStart) || 0,
      Number(region && region.lineEnd) || 0,
      Number(region && region.blockIndex) || 0,
      index
    ].join(":");
  }

  function makeInlinePanelID(regionKey) {
    return "reader-inline-compare-" + String(regionKey).replace(/[^a-zA-Z0-9_-]/g, "-");
  }

  function buildSourceLineAnchorIndex(root) {
    if (!root) {
      return [];
    }

    var rootRect = root.getBoundingClientRect();
    var candidateNodes = root.querySelectorAll("[data-src-line-start][data-src-line-end]");
    var anchors = [];
    for (var i = 0; i < candidateNodes.length; i += 1) {
      var candidateElement = candidateNodes[i];
      var lineStart = Number(candidateElement.getAttribute("data-src-line-start"));
      var lineEnd = Number(candidateElement.getAttribute("data-src-line-end"));
      if (!Number.isFinite(lineStart) || !Number.isFinite(lineEnd) || lineEnd < lineStart) {
        continue;
      }

      var rect = candidateElement.getBoundingClientRect();
      var top = rect.top - rootRect.top + root.scrollTop;
      var bottom = rect.bottom - rootRect.top + root.scrollTop;
      if (!Number.isFinite(top) || !Number.isFinite(bottom)) {
        continue;
      }

      if (bottom <= top) {
        bottom = top + Math.max(candidateElement.offsetHeight, 1);
      }

      anchors.push({
        lineStart: lineStart,
        lineEnd: lineEnd,
        span: lineEnd - lineStart,
        depth: getElementDepthWithinRoot(candidateElement, root),
        isListContainer: isListContainerElement(candidateElement),
        element: candidateElement,
        top: top,
        bottom: bottom
      });
    }

    return anchors;
  }

  function collectAnchorsForRegion(anchorIndex, region) {
    var selectedAnchors = [];
    if (!region) {
      return selectedAnchors;
    }

    var startLine = Number(region.lineStart);
    var endLine = Number(region.lineEnd);
    if (!Number.isFinite(startLine) || !Number.isFinite(endLine) || endLine < startLine) {
      return selectedAnchors;
    }

    for (var lineNumber = startLine; lineNumber <= endLine; lineNumber += 1) {
      var anchor = findNarrowestAnchorForLine(anchorIndex, lineNumber);
      if (!anchor || selectedAnchors.indexOf(anchor) !== -1) {
        continue;
      }
      selectedAnchors.push(anchor);
    }

    if (selectedAnchors.length === 0) {
      var fallbackAnchor = findClosestAnchorForRegion(anchorIndex, startLine, endLine);
      if (fallbackAnchor) {
        selectedAnchors.push(fallbackAnchor);
      }
    }

    return selectedAnchors;
  }

  function findClosestAnchorForRegion(anchorIndex, startLine, endLine) {
    var nextAnchor = null;
    var previousAnchor = null;

    for (var i = 0; i < anchorIndex.length; i += 1) {
      var anchor = anchorIndex[i];
      if (!anchor) {
        continue;
      }

      if (anchor.lineStart > endLine) {
        if (!nextAnchor || anchor.lineStart < nextAnchor.lineStart) {
          nextAnchor = anchor;
        }
        continue;
      }

      if (anchor.lineEnd < startLine) {
        if (!previousAnchor || anchor.lineEnd > previousAnchor.lineEnd) {
          previousAnchor = anchor;
        }
      }
    }

    return nextAnchor || previousAnchor;
  }

  function findPreviousAnchorBeforeLine(anchorIndex, lineNumber) {
    var previousAnchor = null;

    for (var i = 0; i < anchorIndex.length; i += 1) {
      var anchor = anchorIndex[i];
      if (!anchor || anchor.lineEnd >= lineNumber) {
        continue;
      }

      if (!previousAnchor || anchor.lineEnd > previousAnchor.lineEnd) {
        previousAnchor = anchor;
      }
    }

    return previousAnchor;
  }

  function findNextAnchorAtOrAfterLine(anchorIndex, lineNumber) {
    var nextAnchor = null;

    for (var i = 0; i < anchorIndex.length; i += 1) {
      var anchor = anchorIndex[i];
      if (!anchor || anchor.lineStart < lineNumber) {
        continue;
      }

      if (!nextAnchor || anchor.lineStart < nextAnchor.lineStart) {
        nextAnchor = anchor;
      }
    }

    return nextAnchor;
  }

  function deletedMarkerBoundary(anchorIndex, region, anchors, regionKey) {
    if (!region || !Array.isArray(anchors) || anchors.length === 0) {
      return null;
    }

    var anchorPlacement = safeAnchorPlacement(region);
    var lineStart = Number(region.lineStart) || 0;
    var anchorElement = anchors[0];
    var panelFootprint = inlineComparisonPanelFootprint(makeInlinePanelID(regionKey));

    if (anchorPlacement === "before") {
      var previousAnchor = findPreviousAnchorBeforeLine(anchorIndex, lineStart);
      var anchorTop = Number.isFinite(anchorElement.top)
        ? Math.max(0, anchorElement.top - panelFootprint)
        : anchorElement.top;
      if (previousAnchor && Number.isFinite(previousAnchor.bottom) && Number.isFinite(anchorTop)) {
        return (previousAnchor.bottom + anchorTop) / 2;
      }
      return anchorTop;
    }

    if (anchorPlacement === "after") {
      if (Number.isFinite(anchorElement.bottom)) {
        return anchorElement.bottom;
      }

      var nextAnchor = findNextAnchorAtOrAfterLine(anchorIndex, lineStart + 1);
      if (nextAnchor && Number.isFinite(nextAnchor.top) && Number.isFinite(anchorElement.bottom)) {
        return (anchorElement.bottom + nextAnchor.top) / 2;
      }
    }

    return null;
  }

  function buildDeletedPlaceholderRectMap(root) {
    var map = Object.create(null);
    if (!root) {
      return map;
    }
    var placeholders = root.querySelectorAll(".reader-deleted-placeholder[data-deleted-region-index]");
    if (placeholders.length === 0) {
      return map;
    }
    var rootRect = root.getBoundingClientRect();
    for (var pi = 0; pi < placeholders.length; pi += 1) {
      var el = placeholders[pi];
      var idx = el.getAttribute("data-deleted-region-index");
      if (idx === null) {
        continue;
      }
      var rect = el.getBoundingClientRect();
      var t = rect.top - rootRect.top + root.scrollTop;
      var b = rect.bottom - rootRect.top + root.scrollTop;
      if (Number.isFinite(t) && Number.isFinite(b) && b > t) {
        map[idx] = { top: t, bottom: b };
      }
    }
    return map;
  }

  function normalizeChangedRegionsToMarkerRows(anchorIndex, regions, rootHeight, root) {
    var markers = [];
    var maxTop = Math.max(0, rootHeight - 1);
    var deletedMarkerThickness = 28;
    var placeholderRects = buildDeletedPlaceholderRectMap(root);

    for (var i = 0; i < regions.length; i += 1) {
      var region = regions[i];
      var regionKey = makeRegionKey(region, i);
      var anchors = collectAnchorsForRegion(anchorIndex, region);
      if (anchors.length === 0) {
        continue;
      }

      var top = anchors[0].top;
      var bottom = anchors[0].bottom;
      if (safeRegionKind(region.kind) === "deleted") {
        var phRect = placeholderRects[String(i)];
        if (phRect) {
          top = phRect.top;
          bottom = phRect.bottom;
        } else {
          var boundary = deletedMarkerBoundary(anchorIndex, region, anchors, regionKey);
          if (Number.isFinite(boundary)) {
            top = boundary - (deletedMarkerThickness / 2);
            bottom = boundary + (deletedMarkerThickness / 2);
          }
        }
      } else {
        for (var anchorIndexValue = 1; anchorIndexValue < anchors.length; anchorIndexValue += 1) {
          var anchor = anchors[anchorIndexValue];
          top = Math.min(top, anchor.top);
          bottom = Math.max(bottom, anchor.bottom);
        }
      }

      top = clampMarkerTop(top, maxTop);
      bottom = clampMarkerTop(bottom, rootHeight);
      if (bottom <= top) {
        bottom = Math.min(rootHeight, top + (safeRegionKind(region.kind) === "deleted" ? deletedMarkerThickness : 10));
      }

      markers.push({
        key: regionKey,
        kind: safeRegionKind(region.kind),
        top: top,
        height: Math.max(10, bottom - top),
        tooltip: buildChangedRegionTooltip(region),
        lineStart: Number(region.lineStart) || 0,
        lineEnd: Number(region.lineEnd) || 0,
        anchorPlacement: safeAnchorPlacement(region),
        deletedLineCount: Number(region.deletedLineCount) || 0,
        previousTextSnippet: typeof region.previousTextSnippet === "string" ? region.previousTextSnippet : "",
        currentTextSnippet: typeof region.currentTextSnippet === "string" ? region.currentTextSnippet : "",
        supportsToggle: supportsInlineComparison(region),
        anchorElement: anchors[0].element
      });
    }

    closeChangedRegionMarkerGaps(markers);

    return markers;
  }

  function removeInlineComparisonPanels(root) {
    if (!root) {
      return;
    }

    var panels = root.querySelectorAll(".reader-inline-compare");
    for (var i = 0; i < panels.length; i += 1) {
      var panel = panels[i];
      if (panel && panel.parentNode) {
        panel.parentNode.removeChild(panel);
      }
    }
  }

  function removeStaleInlineComparisonPanels(root, validPanelIDs) {
    if (!root) {
      return;
    }

    var allowedPanelIDs = validPanelIDs || Object.create(null);
    var panels = root.querySelectorAll(".reader-inline-compare");
    for (var i = 0; i < panels.length; i += 1) {
      var panel = panels[i];
      if (!panel) {
        continue;
      }

      if (allowedPanelIDs[panel.id]) {
        continue;
      }

      if (panel.parentNode) {
        panel.parentNode.removeChild(panel);
      }
    }
  }

  function getScrollContainer() {
    return document.scrollingElement || document.documentElement || document.body;
  }

  function getRootDocumentTop(root) {
    if (!root) {
      return 0;
    }

    var scrollContainer = getScrollContainer();
    var scrollTop = scrollContainer ? scrollContainer.scrollTop || 0 : 0;
    return root.getBoundingClientRect().top + scrollTop;
  }

  function targetScrollTopForChangedRegion(row, root) {
    if (!row || !root) {
      return 0;
    }

    var scrollContainer = getScrollContainer();
    if (!scrollContainer) {
      return 0;
    }

    var maxScrollTop = Math.max(0, scrollContainer.scrollHeight - window.innerHeight);
    var rootDocumentTop = getRootDocumentTop(root);
    return clampMarkerTop(rootDocumentTop + row.top - overlayTopInset, maxScrollTop);
  }

  function scrollToChangedRegion(row, root) {
    if (!row || !root) {
      return false;
    }

    activeNavigatedChangedRegionKey = row.key;
    scheduleChangedRegionRender();
    window.scrollTo({
      top: targetScrollTopForChangedRegion(row, root),
      behavior: "smooth"
    });
    return true;
  }

  function findMarkerIndexByKey(markers, key) {
    if (!Array.isArray(markers) || !key) {
      return -1;
    }

    for (var i = 0; i < markers.length; i += 1) {
      if (markers[i] && markers[i].key === key) {
        return i;
      }
    }

    return -1;
  }

  function findMarkerIndexNearScrollPosition(markers, currentTop) {
    if (!Array.isArray(markers) || markers.length === 0) {
      return -1;
    }

    var probeTop = currentTop + overlayTopInset;
    var selectedIndex = -1;

    for (var i = 0; i < markers.length; i += 1) {
      if (markers[i].top <= probeTop) {
        selectedIndex = i;
        continue;
      }
      break;
    }

    if (selectedIndex >= 0) {
      return selectedIndex;
    }

    return 0;
  }

  function navigateChangedRegion(direction) {
    var root = latestChangedRegionRenderState.root;
    var markers = latestChangedRegionRenderState.markers;
    var scrollContainer = getScrollContainer();
    if (!root || !Array.isArray(markers) || markers.length === 0) {
      return false;
    }

    if (!scrollContainer) {
      return false;
    }

    var currentTop = Math.max(0, (scrollContainer.scrollTop || 0) - getRootDocumentTop(root));
    var activeIndex = findMarkerIndexByKey(markers, activeNavigatedChangedRegionKey);
    if (activeIndex < 0) {
      activeIndex = findMarkerIndexNearScrollPosition(markers, currentTop);
    }

    var targetIndex;
    if (direction === "previous") {
      targetIndex = activeIndex <= 0 ? markers.length - 1 : activeIndex - 1;
    } else {
      targetIndex = activeIndex >= markers.length - 1 ? 0 : activeIndex + 1;
    }

    var targetRow = markers[targetIndex];

    return scrollToChangedRegion(targetRow, root);
  }

  window.__minimarkNavigateChangedRegion = navigateChangedRegion;

  function makeGutterRowElement(row) {
    var rowElement;
    if (row.supportsToggle) {
      rowElement = document.createElement("button");
      rowElement.type = "button";
      rowElement.className = "reader-gutter-row reader-gutter-row-" + row.kind;
    } else {
      rowElement = document.createElement("div");
      rowElement.className = "reader-gutter-row reader-gutter-row-static reader-gutter-row-" + row.kind;
    }

    rowElement.style.top = String(row.top) + "px";
    rowElement.style.left = String(row.laneOffset || 0) + "px";
    rowElement.style.width = String(row.rowWidth || 32) + "px";
    rowElement.style.height = String(row.height) + "px";
    rowElement.style.zIndex = String(changedRegionMarkerPaintRank(row.kind) + 1);
    rowElement.setAttribute("title", row.tooltip);
    rowElement.style.setProperty(
      "--reader-gutter-icon-top",
      String(computeGutterIconTop(row)) + "px"
    );
    rowElement.classList.toggle("reader-gutter-row-active", row.key === activeNavigatedChangedRegionKey);

    var pillElement = document.createElement("span");
    pillElement.className = "reader-gutter-pill";
    var accentElement = document.createElement("span");
    accentElement.className = "reader-gutter-pill-accent";
    pillElement.appendChild(accentElement);
    rowElement.appendChild(pillElement);

    if (row.supportsToggle) {
      var panelID = makeInlinePanelID(row.key);
      rowElement.setAttribute("aria-controls", panelID);

      var iconElement = document.createElement("span");
      iconElement.className = "reader-gutter-icon";
      iconElement.setAttribute("aria-hidden", "true");
      rowElement.appendChild(iconElement);

      setGutterRowExpandedState(rowElement, row, !!expandedComparisonRows[row.key]);

      rowElement.addEventListener("click", function () {
        var isExpanded = !expandedComparisonRows[row.key];
        expandedComparisonRows[row.key] = isExpanded;
        setGutterRowExpandedState(rowElement, row, isExpanded);
        renderInlineComparisonPanel(row, latestChangedRegionRenderState.root);
        scheduleChangedRegionRender();
      });
    }

    return rowElement;
  }

  function setGutterRowExpandedState(rowElement, row, isExpanded) {
    if (!rowElement) {
      return;
    }

    rowElement.setAttribute("aria-expanded", isExpanded ? "true" : "false");
    rowElement.setAttribute("aria-label", buildChangedRegionActionLabel(row, isExpanded));

    var icon = rowElement.querySelector(".reader-gutter-icon");
    if (icon) {
      icon.textContent = isExpanded ? "\u2039" : "\u203A";
    }
  }

  function makeComparisonColumn(labelText, contentText) {
    var column = document.createElement("div");
    var label = document.createElement("p");
    label.className = "reader-inline-compare-column-label";
    label.textContent = labelText;

    var content = document.createElement("pre");
    content.textContent = contentText || "";

    column.appendChild(label);
    column.appendChild(content);
    return column;
  }

  function makeDiffComparisonColumn(labelText, previousText, currentText) {
    var column = document.createElement("div");
    var label = document.createElement("p");
    label.className = "reader-inline-compare-column-label";
    label.textContent = labelText;
    column.appendChild(label);

    var content = document.createElement("pre");
    content.className = "reader-inline-diff";

    var diffResult = buildRemovedTokenMask(previousText, currentText);
    for (var tokenIndex = 0; tokenIndex < diffResult.tokens.length; tokenIndex += 1) {
      var token = diffResult.tokens[tokenIndex];
      var isWhitespace = /^\s+$/.test(token);

      var removedKind = diffResult.removedKinds[tokenIndex];

      if (!removedKind || isWhitespace) {
        var unchangedSpan = document.createElement("span");
        unchangedSpan.className = "reader-inline-diff-unchanged";
        unchangedSpan.textContent = token;
        content.appendChild(unchangedSpan);
        continue;
      }

      var removedSpan = document.createElement("span");
      removedSpan.className = removedKind === "deleted"
        ? "reader-inline-diff-removed reader-inline-diff-removed-deleted"
        : "reader-inline-diff-removed";
      applyInlineDiffRemovedStyle(removedSpan, removedKind);
      removedSpan.textContent = token;
      content.appendChild(removedSpan);
    }

    column.appendChild(content);
    return column;
  }

  function createInlineComparisonPanel(row) {
    var panel = document.createElement("section");
    panel.id = makeInlinePanelID(row.key);
    panel.className = "reader-inline-compare reader-inline-compare-" + row.kind;
    panel.setAttribute("role", "region");
    panel.setAttribute("aria-label", buildChangedRegionTooltip(row) + " comparison");

    var header = document.createElement("p");
    header.className = "reader-inline-compare-header";
    header.textContent = buildChangedRegionTooltip(row) + " around line " + String(row.lineStart);
    panel.appendChild(header);

    if (row.kind === "edited") {
      panel.appendChild(
        makeDiffComparisonColumn("Previous", row.previousTextSnippet, row.currentTextSnippet)
      );
    } else {
      panel.appendChild(makeComparisonColumn("Deleted", row.previousTextSnippet));
    }

    return panel;
  }

  function renderInlineComparisonPanel(row, root) {
    if (!root || !row || !row.supportsToggle) {
      return;
    }

    var panelID = makeInlinePanelID(row.key);
    var existingPanel = document.getElementById(panelID);
    if (existingPanel && existingPanel.parentNode) {
      existingPanel.parentNode.removeChild(existingPanel);
    }

    if (!expandedComparisonRows[row.key]) {
      return;
    }

    if (!row.anchorElement || !row.anchorElement.parentNode) {
      return;
    }

    var panel = createInlineComparisonPanel(row);
    var placement = row.anchorPlacement === "before" ? "beforebegin" : "afterend";
    row.anchorElement.insertAdjacentElement(placement, panel);
  }

  function reconcileInlineComparisonPanels(markers, root) {
    if (!root) {
      return;
    }

    var rows = Array.isArray(markers) ? markers : [];
    var validPanelIDs = Object.create(null);

    for (var i = 0; i < rows.length; i += 1) {
      var row = rows[i];
      if (!row || !row.supportsToggle || !expandedComparisonRows[row.key]) {
        continue;
      }

      validPanelIDs[makeInlinePanelID(row.key)] = true;
    }

    removeStaleInlineComparisonPanels(root, validPanelIDs);

    for (var rowIndex = 0; rowIndex < rows.length; rowIndex += 1) {
      renderInlineComparisonPanel(rows[rowIndex], root);
    }
  }

  function scheduleChangedRegionRender() {
    if (changedRegionRenderScheduled) {
      return;
    }

    changedRegionRenderScheduled = true;
    window.requestAnimationFrame(function () {
      changedRegionRenderScheduled = false;
      renderChangedRegionGutter(
        latestChangedRegionRenderState.root,
        latestChangedRegionRenderState.gutter,
        latestChangedRegionRenderState.regions
      );
    });
  }

  function installChangedRegionLayoutObservers(root) {
    if (changedRegionLayoutObserversInstalled || !root) {
      return;
    }

    changedRegionLayoutObserversInstalled = true;

    window.addEventListener("resize", function () {
      scheduleChangedRegionRender();
    });

    root.addEventListener("load", function () {
      scheduleChangedRegionRender();
    }, true);

    if (typeof ResizeObserver === "function") {
      var resizeObserver = new ResizeObserver(function () {
        scheduleChangedRegionRender();
      });
      resizeObserver.observe(root);
    }
  }

  function clearContentHighlights(root) {
    if (!root) {
      return;
    }
    var nodes = root.querySelectorAll(
      ".reader-content-highlight-added, .reader-content-highlight-edited, .reader-content-highlight-deleted"
    );
    for (var ni = 0; ni < nodes.length; ni += 1) {
      var cl = nodes[ni].classList;
      cl.remove("reader-content-highlight-added", "reader-content-highlight-edited", "reader-content-highlight-deleted");
    }
  }

  function applyContentHighlights(root, anchorIndex, regions) {
    clearContentHighlights(root);
    if (!root || !Array.isArray(regions) || regions.length === 0) {
      return;
    }

    for (var i = 0; i < regions.length; i += 1) {
      var region = regions[i];
      var kind = safeRegionKind(region.kind);
      if (kind === "deleted") {
        continue;
      }
      var anchors = collectAnchorsForRegion(anchorIndex, region);
      var highlightClass = "reader-content-highlight-" + kind;
      for (var ai = 0; ai < anchors.length; ai += 1) {
        if (anchors[ai].element) {
          anchors[ai].element.classList.add(highlightClass);
        }
      }
    }
  }

  function removeDeletedPlaceholders(root) {
    if (!root) {
      return;
    }
    var placeholders = root.querySelectorAll(".reader-deleted-placeholder");
    for (var i = 0; i < placeholders.length; i += 1) {
      if (placeholders[i].parentNode) {
        placeholders[i].parentNode.removeChild(placeholders[i]);
      }
    }
  }

  function renderDeletedPlaceholders(root, anchorIndex, regions) {
    removeDeletedPlaceholders(root);
    if (!root || !Array.isArray(regions) || regions.length === 0) {
      return;
    }

    for (var i = 0; i < regions.length; i += 1) {
      var region = regions[i];
      if (safeRegionKind(region.kind) !== "deleted") {
        continue;
      }
      var anchors = collectAnchorsForRegion(anchorIndex, region);
      if (anchors.length === 0) {
        continue;
      }
      var anchorEl = anchors[0].element;
      if (!anchorEl || !anchorEl.parentNode) {
        continue;
      }
      var lineCount = Number(region.deletedLineCount) || 0;
      var label = lineCount === 1
        ? "1 line removed"
        : (lineCount > 1 ? lineCount + " lines removed" : "Content removed");
      var placeholder = document.createElement("div");
      placeholder.className = "reader-deleted-placeholder";
      placeholder.setAttribute("data-deleted-region-index", String(i));
      placeholder.setAttribute("role", "status");
      placeholder.textContent = label;

      var insertTarget = anchorEl;
      var parentTag = anchorEl.parentNode && anchorEl.parentNode.tagName;
      if (parentTag === "UL" || parentTag === "OL" || parentTag === "TABLE" || parentTag === "TBODY") {
        insertTarget = anchorEl.parentNode;
      }
      var placement = safeAnchorPlacement(region);
      if (placement === "before") {
        insertTarget.insertAdjacentElement("beforebegin", placeholder);
      } else {
        insertTarget.insertAdjacentElement("afterend", placeholder);
      }
    }
  }

  function renderChangedRegionGutter(root, gutter, regions) {
    if (!gutter) {
      return;
    }

    latestChangedRegionRenderState.root = root;
    latestChangedRegionRenderState.gutter = gutter;
    latestChangedRegionRenderState.regions = Array.isArray(regions) ? regions : [];
    latestChangedRegionRenderState.markers = [];

    gutter.innerHTML = "";
    if (!root || !Array.isArray(regions) || regions.length === 0) {
      applyChangedRegionLaneCount(root, 1);
      clearContentHighlights(root);
      removeDeletedPlaceholders(root);
      if (root) {
        removeInlineComparisonPanels(root);
      }
      return;
    }

    installChangedRegionLayoutObservers(root);

    var anchorIndex = buildSourceLineAnchorIndex(root);
    if (anchorIndex.length === 0) {
      applyChangedRegionLaneCount(root, 1);
      clearContentHighlights(root);
      removeDeletedPlaceholders(root);
      removeInlineComparisonPanels(root);
      return;
    }

    applyContentHighlights(root, anchorIndex, regions);
    renderDeletedPlaceholders(root, anchorIndex, regions);

    var hasDeletedPlaceholders = false;
    for (var di = 0; di < regions.length; di += 1) {
      if (safeRegionKind(regions[di].kind) === "deleted") {
        hasDeletedPlaceholders = true;
        break;
      }
    }
    var markerAnchorIndex = hasDeletedPlaceholders ? buildSourceLineAnchorIndex(root) : anchorIndex;
    var markers = normalizeChangedRegionsToMarkerRows(markerAnchorIndex, regions, root.scrollHeight, root);

    // Reconcile expanded comparison panels BEFORE final position measurement.
    // Panels inserted into the content push elements below them down, so gutter
    // positions must account for them.
    reconcileInlineComparisonPanels(markers, root);

    var hasExpandedPanels = false;
    for (var ep = 0; ep < markers.length; ep += 1) {
      if (markers[ep].supportsToggle && expandedComparisonRows[markers[ep].key]) {
        hasExpandedPanels = true;
        break;
      }
    }

    if (hasExpandedPanels) {
      var panelAnchorIndex = buildSourceLineAnchorIndex(root);
      markers = normalizeChangedRegionsToMarkerRows(panelAnchorIndex, regions, root.scrollHeight, root);
    }

    var laneCount = assignMarkerLanes(markers);
    applyChangedRegionLaneCount(root, laneCount);
    latestChangedRegionRenderState.markers = markers;
    if (activeNavigatedChangedRegionKey) {
      var hasActiveMarker = false;
      for (var markerIndex = 0; markerIndex < markers.length; markerIndex += 1) {
        if (markers[markerIndex].key === activeNavigatedChangedRegionKey) {
          hasActiveMarker = true;
          break;
        }
      }

      if (!hasActiveMarker) {
        activeNavigatedChangedRegionKey = null;
      }
    }

    for (var i = 0; i < markers.length; i += 1) {
      var row = markers[i];
      var rowElement = makeGutterRowElement(row);
      gutter.appendChild(rowElement);
    }
  }

  function clearUnsavedDraftHighlights(root) {
    if (!root) {
      return;
    }

    var highlightedNodes = root.querySelectorAll(".reader-unsaved-change");
    for (var i = 0; i < highlightedNodes.length; i += 1) {
      highlightedNodes[i].classList.remove("reader-unsaved-change");
    }
  }

  function renderUnsavedDraftHighlights(root, regions) {
    clearUnsavedDraftHighlights(root);
    if (!root || !Array.isArray(regions) || regions.length === 0) {
      return;
    }

    var lineAnchors = root.querySelectorAll("[data-src-line-start][data-src-line-end]");
    for (var i = 0; i < lineAnchors.length; i += 1) {
      var element = lineAnchors[i];
      var startLine = Number(element.getAttribute("data-src-line-start")) || 0;
      var endLine = Number(element.getAttribute("data-src-line-end")) || startLine;

      for (var regionIndex = 0; regionIndex < regions.length; regionIndex += 1) {
        var region = regions[regionIndex];
        var regionStart = Number(region.lineStart) || 0;
        var regionEnd = Number(region.lineEnd) || regionStart;
        if (startLine <= regionEnd && regionStart <= endLine) {
          element.classList.add("reader-unsaved-change");
          break;
        }
      }
    }
  }

  function runHighlighting() {
    try {
      if (!window.hljs || typeof window.hljs.highlightAll !== "function") return;
      window.hljs.highlightAll();
    } catch (_) {
      // Graceful fallback keeps readable code blocks via app CSS.
    }
  }

  function typesetMath(root, completion) {
    if (!window.MathJax || typeof window.MathJax.typesetPromise !== "function") {
      if (typeof completion === "function") {
        completion();
      }
      return;
    }

    window.MathJax.typesetPromise([root]).then(function () {
      if (typeof completion === "function") {
        completion();
      }
    }).catch(function () {
      if (typeof completion === "function") {
        completion();
      }
    });
  }

  function applyScrollProgress(progressValue) {
    if (typeof progressValue !== "number" || !isFinite(progressValue)) {
      return;
    }

    var clampedProgress = Math.max(0, Math.min(1, progressValue));
    var scrollContainer = document.scrollingElement || document.documentElement || document.body;
    if (!scrollContainer) {
      return;
    }

    var maxScrollTop = Math.max(0, scrollContainer.scrollHeight - window.innerHeight);
    var target = Math.max(0, Math.min(maxScrollTop, clampedProgress * maxScrollTop));
    window.scrollTo(0, target);
  }

  var lastExtractedHeadingsJSON = "";

  function extractHeadings() {
    try {
      var headings = document.querySelectorAll("h1, h2, h3");
      var result = [];
      for (var i = 0; i < headings.length; i += 1) {
        var el = headings[i];
        result.push({
          id: el.id || "",
          level: parseInt(el.tagName.charAt(1), 10),
          title: (el.textContent || "").trim(),
          sourceLine: parseInt(el.getAttribute("data-src-line-start"), 10) || null
        });
      }
      var json = JSON.stringify(result);
      if (json !== lastExtractedHeadingsJSON) {
        lastExtractedHeadingsJSON = json;
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.minimarkTOC) {
          window.webkit.messageHandlers.minimarkTOC.postMessage(result);
        }
      }
    } catch (_) {}
  }

  function renderMarkdown(scrollAnchorProgress) {
    var root = document.getElementById("reader-root");
    var gutter = document.getElementById("reader-change-gutter");
    if (!root) {
      return;
    }

    var md = createMarkdownIt();
    if (!md) {
      root.innerHTML = "<p>Markdown runtime unavailable.</p>";
      return;
    }

    var rawHTML = md.render(payload.markdown || "");
    var safeHTML = sanitizeRenderedHTML(rawHTML);
    root.innerHTML = safeHTML;
    runHighlighting();
    typesetMath(root, function () {
      renderUnsavedDraftHighlights(root, payload.unsavedChangedRegions || []);
      renderChangedRegionGutter(root, gutter, payload.changedRegions || []);
      applyScrollProgress(scrollAnchorProgress);

      // Auto-expand the first edited gutter pill (screenshot automation)
      var autoExpandMeta = document.querySelector('meta[name="minimark-auto-expand-first-edit"]');
      if (autoExpandMeta && autoExpandMeta.getAttribute("content") === "true") {
        var editedButton = gutter.querySelector(".reader-gutter-row-edited");
        if (editedButton) {
          editedButton.click();
          autoExpandMeta.setAttribute("content", "done");
        }
      }
      extractHeadings();
    });
  }

  window.__minimarkUpdateRenderedMarkdown = function (payloadBase64Value, scrollAnchorProgress) {
    payload = decodePayload(payloadBase64Value);
    renderMarkdown(scrollAnchorProgress);
    return true;
  };

  window.__minimarkOverlayTopInset = overlayTopInset;

  window.__minimarkExtractHeadings = function () {
    extractHeadings();
    return true;
  };

  window.__minimarkApplyRuntimeCSS = function (cssBase64Value) {
    applyRuntimeCSS(cssBase64Value);
    return true;
  };

  applyRuntimeCSS(runtimeCSSBase64);

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", function () {
      renderMarkdown(null);
    }, { once: true });
  } else {
    renderMarkdown(null);
  }
})();
