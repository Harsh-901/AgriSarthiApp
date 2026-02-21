/**
 * field_highlighter.js
 * Highlights unfillable form fields with a pulsing yellow border so the
 * farmer can see exactly which fields need manual input.
 *
 * Called by Dart as:
 *   js = template.replaceFirst('HIGHLIGHT_JSON', jsonEncode(fieldKeys));
 *   webViewController.runJavaScript(js);
 *
 * HIGHLIGHT_JSON is replaced at runtime with a JSON array of field id/name strings.
 */
(function (fieldKeys) {
  "use strict";

  var STYLE_ID = "__autofill_highlight_style__";
  var ATTR     = "data-autofill-highlight";

  // ── Inject CSS once ────────────────────────────────────────────────────────
  if (!document.getElementById(STYLE_ID)) {
    var style = document.createElement("style");
    style.id = STYLE_ID;
    style.textContent = [
      "@keyframes autofill-pulse {",
      "  0%   { box-shadow: 0 0 0 2px rgba(245, 158, 11, 0.9); }",
      "  50%  { box-shadow: 0 0 0 6px rgba(245, 158, 11, 0.3); }",
      "  100% { box-shadow: 0 0 0 2px rgba(245, 158, 11, 0.9); }",
      "}",
      "[" + ATTR + "] {",
      "  outline: 2px solid #F59E0B !important;",
      "  outline-offset: 2px !important;",
      "  border-radius: 4px !important;",
      "  animation: autofill-pulse 1.5s ease-in-out infinite !important;",
      "  background-color: rgba(254, 243, 199, 0.35) !important;",
      "}",
    ].join("\n");
    document.head.appendChild(style);
  }

  // ── Clear any previous highlighting ───────────────────────────────────────
  document.querySelectorAll("[" + ATTR + "]").forEach(function (el) {
    el.removeAttribute(ATTR);
  });

  if (!Array.isArray(fieldKeys) || fieldKeys.length === 0) {
    return JSON.stringify({ highlighted: 0 });
  }

  // ── Apply highlight to each key ───────────────────────────────────────────
  var highlighted = 0;
  var firstEl = null;

  fieldKeys.forEach(function (key) {
    var el = document.getElementById(key);
    if (!el) el = document.querySelector("[name=\"" + key + "\"]");
    if (!el) return;

    el.setAttribute(ATTR, "1");
    highlighted++;
    if (!firstEl) firstEl = el;
  });

  // Scroll the first highlighted field into view smoothly
  if (firstEl) {
    firstEl.scrollIntoView({ behavior: "smooth", block: "center" });
  }

  return JSON.stringify({ highlighted: highlighted });
})(HIGHLIGHT_JSON);
