// tide's overview page (SPEC.md §6.9), in place of Mission Control: each
// workspace with windows as a group, headed by its name, and each window in
// it as a card with its app's icon, its title and its app's name. tide
// fills it with tide.update(state), state being overview.lua's: { scope,
// groups: [{ name, current, windows: [{ id, app, bundle, title, mine }] }],
// focused, icons: { bundle: data URL } }. It hears back through the
// "tide" message handler, as the dashboard does: { activate: id },
// { show: name } or { close: true }.

import { match } from "./tide-fuzzy.js";

const send = (msg) => window.webkit?.messageHandlers?.tide?.postMessage(msg);

let state = { scope: "all", groups: [], icons: {} };
let scope = null;
let query = "";
// The window whose card Return activates, and the cards showing, in order.
let selected = null;
let cards = [];

// Typing filters by title and app name with tide's fuzzy matcher, as the
// launcher's does.
function matches(w) {
  return query === "" || match(query, String(w.title)) !== null || match(query, String(w.app)) !== null;
}

function el(tag, className, text) {
  const e = document.createElement(tag);
  if (className) e.className = className;
  if (text !== undefined) e.textContent = text;
  return e;
}

// A click on a card or a header is that choice, not a click on empty
// space, which closes the overview.
function choose(e, msg) {
  e?.stopPropagation?.();
  send(msg);
}

function card(w) {
  const b = el("button", "card");
  b.type = "button";
  b.title = String(w.title);
  const icon = (state.icons || {})[w.bundle];
  if (icon) {
    const img = el("img", "icon");
    img.src = icon;
    img.alt = "";
    b.append(img);
  } else {
    b.append(el("span", "icon blank"));
  }
  const text = el("span", "text");
  text.append(el("span", "name", String(w.title) || String(w.app)));
  text.append(el("span", "app", w.mine ? `${w.app} · minimized` : String(w.app)));
  b.append(text);
  b.classList.toggle("minimized", !!w.mine);
  b.addEventListener("click", (e) => choose(e, { activate: w.id }));
  return b;
}

function render() {
  const main = document.getElementById("groups");
  main.replaceChildren();
  cards = [];
  for (const g of state.groups) {
    const shown = g.windows.filter(matches);
    if (shown.length === 0 && (query !== "" || !g.current)) continue;
    const section = el("section", "group");
    section.classList.toggle("current", !!g.current);
    const head = el("button", "header", String(g.name));
    head.type = "button";
    head.addEventListener("click", (e) => choose(e, { show: g.name }));
    section.append(head);
    if (shown.length === 0) {
      section.append(el("p", "note", "No windows on this workspace"));
    }
    const grid = el("div", "cards");
    for (const w of shown) {
      const b = card(w);
      cards.push({ id: w.id, el: b });
      grid.append(b);
    }
    section.append(grid);
    main.append(section);
  }
  if (cards.length === 0 && query !== "") {
    main.append(el("p", "note", "No windows match"));
  }
  if (!cards.some((c) => c.id === selected)) selected = cards.length > 0 ? cards[0].id : null;
  mark();
  document.getElementById("filter").textContent = query;
}

function mark() {
  for (const c of cards) {
    c.el.classList.toggle("selected", c.id === selected);
    if (c.id === selected) c.el.scrollIntoView?.({ block: "nearest" });
  }
}

function step(by) {
  const i = cards.findIndex((c) => c.id === selected);
  const next = cards[Math.min(cards.length - 1, Math.max(0, i + by))];
  if (next) {
    selected = next.id;
    mark();
  }
}

// Lua's JSON encoder can write an empty list as {}, so a list from tide
// is read as an array only if it is one.
const list = (v) => (Array.isArray(v) ? v : []);

window.tide = {
  update(next) {
    state = { ...next, groups: list(next.groups).map((g) => ({ ...g, windows: list(g.windows) })) };
    // A new overview, or the other key while it's open, starts on the
    // focused window; an update within the same scope keeps your place.
    if (next.scope !== scope) {
      scope = next.scope;
      query = "";
      selected = next.focused ?? null;
    }
    render();
  },
};

document.addEventListener("keydown", (e) => {
  const handled = () => e.preventDefault?.();
  if (e.key === "Escape") {
    handled();
    send({ close: true });
  } else if (e.key === "Enter") {
    handled();
    if (selected !== null) send({ activate: selected });
  } else if (e.key === "ArrowLeft" || e.key === "ArrowUp") {
    handled();
    step(-1);
  } else if (e.key === "ArrowRight" || e.key === "ArrowDown") {
    handled();
    step(1);
  } else if (e.key === "Backspace") {
    handled();
    query = Array.from(query).slice(0, -1).join("");
    render();
  } else if (Array.from(e.key).length === 1 && !e.metaKey && !e.ctrlKey && !e.altKey) {
    handled();
    query += e.key;
    render();
  }
});

// A click that no card or header took landed on empty space.
document.addEventListener("click", () => send({ close: true }));
