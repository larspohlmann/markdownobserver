import { EditorState } from "@codemirror/state";
import { EditorView, drawSelection, lineNumbers } from "@codemirror/view";
import { markdown } from "@codemirror/lang-markdown";
import { HighlightStyle, syntaxHighlighting } from "@codemirror/language";
import { tags } from "@lezer/highlight";

function decodeBase64UTF8(input) {
  const binary = window.atob(input);
  const bytes = Uint8Array.from(binary, (char) => char.charCodeAt(0));
  return new TextDecoder().decode(bytes);
}

function buildEditorTheme(payload) {
  return EditorView.theme(
    {
      "&": {
        height: "100%",
        backgroundColor: payload.backgroundHex,
        color: payload.foregroundHex,
        fontFamily:
          "SFMono-Regular, Menlo, Monaco, Consolas, 'Liberation Mono', 'Courier New', monospace",
        fontSize: `${payload.baseFontSize}px`
      },
      ".cm-scroller": {
        overflow: "auto",
        fontFamily: "inherit",
        lineHeight: "1.55"
      },
      ".cm-content": {
        minHeight: "100%",
        padding: "14px 16px 32px",
        caretColor: payload.linkHex
      },
      ".cm-line": {
        padding: "0"
      },
      ".cm-gutters": {
        backgroundColor: payload.backgroundHex,
        color: payload.secondaryForegroundHex,
        borderRight: `1px solid ${payload.borderHex}`,
        paddingRight: "8px"
      },
      ".cm-lineNumbers .cm-gutterElement": {
        padding: "0 10px 0 12px",
        minWidth: "2.5em"
      },
      ".cm-selectionBackground, ::selection": {
        backgroundColor: payload.selectionHex
      },
      ".cm-focused .cm-selectionBackground": {
        backgroundColor: payload.selectionHex
      },
      ".cm-cursor, .cm-dropCursor": {
        borderLeftColor: payload.linkHex
      },
      ".cm-activeLine, .cm-activeLineGutter": {
        backgroundColor: "transparent"
      }
    },
    { dark: payload.isDark }
  );
}

function buildHighlightTheme(payload) {
  return HighlightStyle.define([
    { tag: tags.heading, color: payload.linkHex, fontWeight: "700" },
    { tag: [tags.processingInstruction, tags.meta, tags.comment], color: payload.secondaryForegroundHex },
    { tag: [tags.list, tags.quote, tags.contentSeparator], color: payload.secondaryForegroundHex },
    { tag: [tags.emphasis], fontStyle: "italic" },
    { tag: [tags.strong], fontWeight: "700" },
    { tag: [tags.link, tags.url], color: payload.linkHex, textDecoration: "underline" },
    {
      tag: [tags.monospace],
      color: payload.foregroundHex,
      backgroundColor: payload.codeBackgroundHex,
      border: `1px solid ${payload.borderHex}`,
      borderRadius: "4px"
    },
    { tag: [tags.atom, tags.bool, tags.number, tags.labelName], color: payload.accentHex },
    { tag: [tags.string, tags.inserted], color: payload.stringHex },
    { tag: [tags.deleted], color: payload.deletedHex },
    { tag: [tags.escape, tags.special(tags.string)], color: payload.accentHex }
  ]);
}

function removeExistingEditor(root) {
  if (root.__minimarkCodeMirrorView) {
    root.__minimarkCodeMirrorView.destroy();
    root.__minimarkCodeMirrorView = null;
  }
}

function bootstrap(base64Payload) {
  const root = document.getElementById("minimark-source-root");
  if (!root || !base64Payload) {
    return;
  }

  const payload = JSON.parse(decodeBase64UTF8(base64Payload));
  removeExistingEditor(root);
  root.textContent = "";

  const view = new EditorView({
    state: EditorState.create({
      doc: payload.markdown || "",
      extensions: [
        lineNumbers(),
        drawSelection(),
        EditorView.lineWrapping,
        EditorState.readOnly.of(true),
        EditorView.editable.of(false),
        EditorView.contentAttributes.of({
          "aria-label": "Markdown source",
          spellcheck: "false"
        }),
        markdown(),
        buildEditorTheme(payload),
        syntaxHighlighting(buildHighlightTheme(payload))
      ]
    }),
    parent: root
  });

  root.__minimarkCodeMirrorView = view;
}

window.MinimarkCodeMirrorSourceView = { bootstrap };