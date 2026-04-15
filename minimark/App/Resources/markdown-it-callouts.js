/**
 * markdown-it-callouts
 *
 * A markdown-it plugin that transforms blockquotes with [!TYPE] markers
 * into styled callout blocks, compatible with GitHub and Obsidian syntax.
 *
 * Usage:
 *   md.use(markdownitCallouts);
 *
 * Input:
 *   > [!WARNING] Watch out
 *   > This will break things.
 *
 * Output:
 *   <blockquote class="callout callout-warning" data-callout="warning">
 *     <p><strong class="callout-title">Watch out</strong></p>
 *     <p>This will break things.</p>
 *   </blockquote>
 */
(function () {
  "use strict";

  // GitHub-native callout types: type -> { cssClass, defaultTitle }
  var GITHUB_TYPES = {
    NOTE:      { cssClass: "note",      defaultTitle: "Note" },
    TIP:       { cssClass: "tip",       defaultTitle: "Tip" },
    IMPORTANT: { cssClass: "important", defaultTitle: "Important" },
    WARNING:   { cssClass: "warning",   defaultTitle: "Warning" },
    CAUTION:   { cssClass: "caution",   defaultTitle: "Caution" }
  };

  // Obsidian aliases: type -> { cssClass, defaultTitle }
  var OBSIDIAN_ALIASES = {
    INFO:     { cssClass: "note",    defaultTitle: "Note" },
    QUESTION: { cssClass: "note",    defaultTitle: "Question" },
    EXAMPLE:  { cssClass: "tip",     defaultTitle: "Example" },
    BUG:      { cssClass: "warning", defaultTitle: "Bug" },
    DANGER:   { cssClass: "caution", defaultTitle: "Danger" },
    ABSTRACT: { cssClass: "note",    defaultTitle: "Abstract" },
    SUMMARY:  { cssClass: "note",    defaultTitle: "Summary" },
    TLDR:     { cssClass: "note",    defaultTitle: "TL;DR" },
    SUCCESS:  { cssClass: "tip",     defaultTitle: "Success" },
    CHECK:    { cssClass: "tip",     defaultTitle: "Check" },
    DONE:     { cssClass: "tip",     defaultTitle: "Done" },
    FAILURE:  { cssClass: "caution", defaultTitle: "Failure" },
    FAIL:     { cssClass: "caution", defaultTitle: "Fail" },
    MISSING:  { cssClass: "caution", defaultTitle: "Missing" },
    QUOTE:    { cssClass: "note",    defaultTitle: "Quote" },
    CITE:     { cssClass: "note",    defaultTitle: "Cite" }
  };

  // Merged lookup table (all uppercase keys)
  var CALLOUT_TYPES = {};
  var key;
  for (key in GITHUB_TYPES) {
    if (GITHUB_TYPES.hasOwnProperty(key)) {
      CALLOUT_TYPES[key] = GITHUB_TYPES[key];
    }
  }
  for (key in OBSIDIAN_ALIASES) {
    if (OBSIDIAN_ALIASES.hasOwnProperty(key)) {
      CALLOUT_TYPES[key] = OBSIDIAN_ALIASES[key];
    }
  }

  // Pattern: [!TYPE] optionally followed by a space and title text
  var CALLOUT_RE = /^\[!([A-Za-z]+)\](?:\s+(.+))?$/;

  /**
   * Find the blockquote_open token that owns the given paragraph_open token.
   * Walks backward through the token array looking for the nearest
   * blockquote_open at one nesting level above the paragraph.
   */
  function findBlockquoteOpen(tokens, paragraphIdx) {
    var targetLevel = tokens[paragraphIdx].level - 1;
    for (var i = paragraphIdx - 1; i >= 0; i--) {
      if (tokens[i].type === "blockquote_open" && tokens[i].level === targetLevel) {
        return i;
      }
    }
    return -1;
  }

  /**
   * Check whether the paragraph at pIdx is the FIRST child of the
   * blockquote at bqIdx. In markdown-it's token stream, the first
   * paragraph_open follows immediately after blockquote_open.
   */
  function isFirstChild(tokens, bqIdx, pIdx) {
    return bqIdx + 1 === pIdx;
  }

  /**
   * Join a value onto a token's attribute, appending with a space if it
   * already exists (like classList.add). Creates the attribute when absent.
   */
  function attrJoin(token, name, value) {
    var idx = token.attrIndex(name);
    if (idx < 0) {
      token.attrPush([name, value]);
    } else {
      token.attrs[idx][1] = token.attrs[idx][1] + " " + value;
    }
  }

  /**
   * Set an attribute on a token, creating or updating as needed.
   */
  function setAttr(token, name, value) {
    var idx = token.attrIndex(name);
    if (idx < 0) {
      token.attrPush([name, value]);
    } else {
      token.attrs[idx][1] = value;
    }
  }

  /**
   * Extract the callout marker from the first inline token's content.
   * Returns null if no marker is found, or an object with:
   *   { type: "WARNING", match: matchArray }
   */
  function extractCalloutMarker(inlineToken) {
    if (!inlineToken || inlineToken.type !== "inline" || !inlineToken.children) {
      return null;
    }

    // The first text child holds the raw content
    var firstChild = inlineToken.children[0];
    if (!firstChild || firstChild.type !== "text") {
      return null;
    }

    // In markdown-it, each line of a blockquote paragraph is a separate
    // text child separated by softbreak tokens. The first text child
    // holds the first line, which is where the [!TYPE] marker lives.
    var match = CALLOUT_RE.exec(firstChild.content);
    if (!match) {
      return null;
    }

    var typeName = match[1].toUpperCase();
    if (!CALLOUT_TYPES.hasOwnProperty(typeName)) {
      return null;
    }

    return { type: typeName, match: match };
  }

  /**
   * Transform the inline token's children to strip the [!TYPE] marker
   * and wrap the title text in a <strong class="callout-title"> element.
   *
   * If the first paragraph contains additional lines (softbreaks), those
   * lines are preserved after the title.
   */
  function transformInlineContent(inlineToken, calloutInfo, Token) {
    var typeInfo = CALLOUT_TYPES[calloutInfo.type];
    var customTitle = calloutInfo.match[2]; // text after [!TYPE], may be undefined
    var titleText = customTitle ? customTitle.trim() : typeInfo.defaultTitle;

    // Build title tokens: <strong class="callout-title">titleText</strong>
    var strongOpen = new Token("html_inline", "", 0);
    strongOpen.content = '<strong class="callout-title">';

    var titleContent = new Token("text", "", 0);
    titleContent.content = titleText;

    var strongClose = new Token("html_inline", "", 0);
    strongClose.content = "</strong>";

    var titleTokens = [strongOpen, titleContent, strongClose];

    // Preserve any children after the first text node (softbreaks, more text, etc.)
    var remaining = inlineToken.children.slice(1);

    inlineToken.children = titleTokens.concat(remaining);
    inlineToken.content = "";
  }

  /**
   * The core ruler function. Walks the token stream after inline parsing
   * and transforms blockquotes with [!TYPE] markers.
   */
  function calloutCoreRule(state) {
    var tokens = state.tokens;
    var i, token, inlineToken, bqIdx, calloutInfo, typeInfo;

    for (i = 0; i < tokens.length; i++) {
      token = tokens[i];

      // Look for paragraph_open inside a blockquote
      if (token.type !== "paragraph_open") {
        continue;
      }

      // The inline content follows the paragraph_open
      if (i + 1 >= tokens.length) {
        continue;
      }
      inlineToken = tokens[i + 1];

      // Try to extract a callout marker
      calloutInfo = extractCalloutMarker(inlineToken);
      if (!calloutInfo) {
        continue;
      }

      // Find the parent blockquote
      bqIdx = findBlockquoteOpen(tokens, i);
      if (bqIdx < 0) {
        continue;
      }

      // Only transform if this paragraph is the FIRST content in the blockquote
      if (!isFirstChild(tokens, bqIdx, i)) {
        continue;
      }

      typeInfo = CALLOUT_TYPES[calloutInfo.type];

      // Add class and data-callout attributes to the blockquote.
      // Use attrJoin for class to preserve any existing classes (e.g. from markdown-it-attrs).
      attrJoin(tokens[bqIdx], "class", "callout callout-" + typeInfo.cssClass);
      setAttr(tokens[bqIdx], "data-callout", typeInfo.cssClass);

      // Transform the inline content to show the title
      transformInlineContent(inlineToken, calloutInfo, state.Token);
    }
  }

  /**
   * The plugin entry point. Registers the core ruler.
   */
  function calloutPlugin(md) {
    md.core.ruler.after("inline", "callouts", calloutCoreRule);
  }

  // UMD export
  if (typeof module !== "undefined" && module.exports) {
    module.exports = calloutPlugin;
  } else {
    window.markdownitCallouts = calloutPlugin;
  }
})();
