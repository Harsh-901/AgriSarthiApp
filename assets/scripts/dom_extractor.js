(function () {
  "use strict";

  // ─── Helpers ────────────────────────────────────────────────────────────────

  /**
   * Resolve the human-readable label for a form element.
   * Strategy order:
   *  1. <label for="id">
   *  2. aria-label attribute
   *  3. placeholder attribute
   *  4. nearest ancestor <label>
   *  5. closest preceding sibling text node
   *  6. title attribute
   */
  function resolveLabel(el) {
    // 1. Explicit <label for="...">
    if (el.id) {
      var labelEl = document.querySelector('label[for="' + el.id + '"]');
      if (labelEl) return labelEl.innerText.trim();
    }

    // 2. aria-label
    var ariaLabel = el.getAttribute("aria-label");
    if (ariaLabel) return ariaLabel.trim();

    // 3. aria-labelledby
    var labelledBy = el.getAttribute("aria-labelledby");
    if (labelledBy) {
      var refEl = document.getElementById(labelledBy);
      if (refEl) return refEl.innerText.trim();
    }

    // 4. Ancestor <label>
    var parent = el.parentElement;
    while (parent) {
      if (parent.tagName === "LABEL") return parent.innerText.trim();
      parent = parent.parentElement;
    }

    // 5. Placeholder fallback
    if (el.placeholder) return el.placeholder.trim();

    // 6. Title attribute
    if (el.title) return el.title.trim();

    // 7. name attribute as last resort
    return el.name || el.id || "";
  }

  /**
   * Normalise field type to a small set: text, number, date, tel, email,
   * select, textarea, checkbox, radio, hidden.
   */
  function normaliseType(el) {
    if (el.tagName === "SELECT") return "select";
    if (el.tagName === "TEXTAREA") return "textarea";
    var t = (el.type || "text").toLowerCase();
    if (["number", "date", "tel", "email", "checkbox", "radio", "hidden"].includes(t)) return t;
    return "text";
  }

  // ─── Main extraction ────────────────────────────────────────────────────────

  var results = [];
  var seen = new Set();

  var elements = document.querySelectorAll(
    'input:not([type="submit"]):not([type="button"]):not([type="reset"]):not([type="image"]), select, textarea'
  );


  elements.forEach(function (el) {
    // Skip elements we can't meaningfully fill
    if (el.disabled || el.readOnly) return;

    var key = el.id || el.name;
    if (!key) return;           // nothing to key on — skip
    if (seen.has(key)) return;  // deduplicate
    seen.add(key);

    var type = normaliseType(el);
    if (type === "hidden") return; // don't expose hidden fields

    var options = [];
    if (type === "select") {
      el.querySelectorAll("option").forEach(function (opt) {
        if (opt.value) options.push({ value: opt.value, text: opt.innerText.trim() });
      });
    }

    var field = {
      id:    el.id    || "",
      name:  el.name  || "",
      label: resolveLabel(el),
      type:  type,
    };
    if (options.length) field.options = options;

    results.push(field);
  });

  // Post back to Flutter
  if (typeof AutofillChannel !== "undefined") {
    AutofillChannel.postMessage(JSON.stringify(results));
  } else {
    console.warn("[AutoFill] AutofillChannel not available");
  }

  // Return value (also captured by evaluateJavascript)
  return JSON.stringify(results);
})();
