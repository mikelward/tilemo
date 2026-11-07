// What tide calls on the dashboard launcher (SPEC.md §9.2), after tileco's
// page has started: tide.open(feed, scope) fills it, clears the search
// and turns to a scope, tide.update(feed) brings in what arrived since, as
// browser tabs, tide.press(scope) is a switcher key while it's open, which
// closes it on its own scope and otherwise turns to that one,
// tide.escape() is Esc with something typed, which tide hands here, and
// tide.turn(scope) turns to a scope as Tab does, for CI's smoke test. The
// page says { typed } as the search goes from empty to not, and back.

import { update } from "./launcher-chrome.js";

const send = (msg) => window.webkit?.messageHandlers?.tide?.postMessage(msg);

const chips = () => Array.from(document.querySelectorAll(".scopes button"));
const shown = () => chips().find((b) => b.getAttribute("aria-selected") === "true")?.dataset.scope ?? null;

// As a click on its chip does, so the page clears the selection and keeps
// the keyboard in the search field.
function turnTo(scope) {
  chips().find((b) => b.dataset.scope === scope)?.click();
}

// tide takes Esc while the launcher's open, so Esc closes it at once,
// however long WebKit takes to wake the page. To leave clearing the search
// to the page's own Esc, it needs to know whether there's anything there.
let typed = false;
function sayTyped() {
  const now = (document.getElementById("query")?.value ?? "") !== "";
  if (now !== typed) {
    typed = now;
    send({ typed });
  }
}
document.getElementById("query")?.addEventListener("input", sayTyped);

// When the page last heard Esc, by the clock, for CI's smoke test.
document.addEventListener(
  "keydown",
  (e) => {
    if (e.key === "Escape") window.tide.esc = Date.now();
  },
  true,
);

window.tide = {
  // The page is kept between opens, hidden, so each starts with an empty
  // search as a new page would.
  open(next, scope) {
    // When the page heard it, when this had run, and when the page had
    // painted after it, by the clock, for CI's smoke test: a hidden page
    // can be slow to wake. update() starts an asynchronous refresh, which
    // the second frame comes after.
    const heard = Date.now();
    const query = document.getElementById("query");
    if (query) query.value = "";
    // tide starts each open with nothing typed too.
    typed = false;
    update(next);
    turnTo(scope);
    const opened = { heard, ran: Date.now(), visibility: document.visibilityState };
    window.tide.opened = opened;
    requestAnimationFrame(() =>
      requestAnimationFrame(() => {
        opened.painted = Date.now();
      }),
    );
  },
  update,
  // Esc with something typed: the page's own Esc, which clears it.
  escape() {
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true, cancelable: true }));
    sayTyped();
  },
  press(scope) {
    if (shown() === scope) window.close();
    else turnTo(scope);
  },
  turn: turnTo,
  scope: shown,
};
