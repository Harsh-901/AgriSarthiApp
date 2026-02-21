(function (mapping) {
  "use strict";

  var filled      = 0;
  var skipped     = 0;
  var skippedKeys = [];

  // ─── React / framework compatibility ────────────────────────────────────────
  //
  // Plain `el.value = x` doesn't work with React 16+ controlled components.
  // React stores its own internal "last known value" on the fiber. When you
  // set el.value directly, React's next reconciliation resets it back to the
  // fiber value. The fix: call the *native* HTMLInputElement/HTMLTextAreaElement
  // prototype setter, which bypasses React's override and triggers its internal
  // change listener correctly.

  var nativeInputSetter = Object.getOwnPropertyDescriptor(
    window.HTMLInputElement.prototype, "value"
  ) && Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, "value").set;

  var nativeTextareaSetter = Object.getOwnPropertyDescriptor(
    window.HTMLTextAreaElement.prototype, "value"
  ) && Object.getOwnPropertyDescriptor(window.HTMLTextAreaElement.prototype, "value").set;

  /**
   * Set value using native prototype setter (React-safe), then dispatch
   * both InputEvent and Event so all frameworks (React, Vue, Angular) detect it.
   */
  function setNativeValue(el, value) {
    var tag = el.tagName.toUpperCase();
    try {
      if (tag === "TEXTAREA" && nativeTextareaSetter) {
        nativeTextareaSetter.call(el, value);
      } else if (nativeInputSetter) {
        nativeInputSetter.call(el, value);
      } else {
        el.value = value; // fallback for non-React pages
      }
    } catch (e) {
      el.value = value; // last-resort fallback
    }
    dispatchEvents(el);
  }

  /**
   * Dispatch InputEvent (React 17+ needs this) + plain Event for older setups.
   * bubbles: true is required for React's event delegation.
   */
  function dispatchEvents(el) {
    // InputEvent: preferred; carries the new value in React's handler
    try {
      el.dispatchEvent(new InputEvent("input",  { bubbles: true, cancelable: true }));
    } catch (e) {
      el.dispatchEvent(new Event("input", { bubbles: true, cancelable: true }));
    }
    el.dispatchEvent(new Event("change", { bubbles: true, cancelable: true }));
  }

  /**
   * Find a form element by id first, then by name, then by data-testid.
   */
  function findEl(key) {
    var el = document.getElementById(key);
    if (el) return el;
    el = document.querySelector('[name="' + key + '"]');
    if (el) return el;
    el = document.querySelector('[data-testid="' + key + '"]');
    return el || null;
  }

  /**
   * Fill a <select> by matching option value or visible text (case-insensitive).
   * Also triggers a React-compatible change event.
   */
  function fillSelect(el, value) {
    var lc = value.toString().toLowerCase().trim();
    for (var i = 0; i < el.options.length; i++) {
      var opt = el.options[i];
      if (
        opt.value.toLowerCase().trim() === lc ||
        opt.text.toLowerCase().trim() === lc ||
        opt.text.toLowerCase().trim().includes(lc) ||
        lc.includes(opt.value.toLowerCase().trim())
      ) {
        // Use native setter on select for React compatibility
        var nativeSelectSetter = Object.getOwnPropertyDescriptor(
          window.HTMLSelectElement.prototype, "value"
        );
        if (nativeSelectSetter && nativeSelectSetter.set) {
          nativeSelectSetter.set.call(el, opt.value);
        } else {
          el.selectedIndex = i;
        }
        dispatchEvents(el);
        return true;
      }
    }
    return false;
  }

  // ─── Main fill loop ──────────────────────────────────────────────────────────

  Object.keys(mapping).forEach(function (key) {
    var value = mapping[key];
    if (value === null || value === undefined || value === "") {
      skipped++;
      skippedKeys.push(key);
      return;
    }

    var el = findEl(key);
    if (!el) {
      // Field not found on current page — may be on a different step/page
      skipped++;
      // Don't add to skippedKeys — it's not a *missing data* problem
      return;
    }

    var tag  = el.tagName.toUpperCase();
    var type = (el.type || "").toLowerCase();

    if (tag === "SELECT") {
      var ok = fillSelect(el, value);
      if (!ok) { skipped++; skippedKeys.push(key); }
      else { filled++; }

    } else if (type === "checkbox") {
      var checked = (value === true || value === "true" || value === "1" || value === "yes");
      el.checked = checked;
      dispatchEvents(el);
      filled++;

    } else if (type === "radio") {
      var radios = document.querySelectorAll('[name="' + key + '"]');
      var radioFilled = false;
      radios.forEach(function (r) {
        if (r.value.toLowerCase() === value.toString().toLowerCase()) {
          r.checked = true;
          dispatchEvents(r);
          radioFilled = true;
        }
      });
      if (radioFilled) filled++;
      else { skipped++; skippedKeys.push(key); }

    } else {
      // text / number / date / tel / email / textarea
      setNativeValue(el, value);
      filled++;
    }
  });

  return JSON.stringify({ filled: filled, skipped: skipped, skippedKeys: skippedKeys });
})(MAPPING_JSON); // MAPPING_JSON is replaced at runtime by Dart before injection
