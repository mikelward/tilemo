// Runs the dashboard launcher's bundled script (tests/launcherpage_test.lua
// writes it, and the feed, to the files named on the command line) against
// a small fake DOM: tileco's launcher page, unchanged, on tide's stand-ins
// for Chrome. Checks it lists tide's rows in each scope, searches them, and
// sends tide what was chosen.

const fs = require("fs");
const vm = require("vm");
const assert = require("assert");

class Element {
  constructor(tag) {
    this.tag = tag;
    this.children = [];
    this.className = "";
    this.textContent = "";
    this.value = "";
    this.placeholder = "";
    this.hidden = false;
    this.style = {};
    this.attrs = {};
    this.dataset = {};
    this.listeners = {};
    const classes = new Set();
    this.classList = {
      add: (c) => classes.add(c),
      toggle: (c, on) => (on ? classes.add(c) : classes.delete(c)),
      contains: (c) => classes.has(c),
    };
  }
  append(...xs) {
    for (const x of xs) this.children.push(typeof x === "string" ? { text: x } : x);
  }
  replaceChildren(...xs) {
    this.children = [];
    this.append(...xs);
  }
  setAttribute(k, v) {
    this.attrs[k] = String(v);
  }
  getAttribute(k) {
    return this.attrs[k] ?? null;
  }
  // Every listener for each event, as a real element keeps them.
  addEventListener(type, fn) {
    (this.listeners[type] ??= []).push(fn);
  }
  fire(type, e = {}) {
    for (const fn of this.listeners[type] ?? []) fn(e);
  }
  click() {
    this.fire("click", { preventDefault() {} });
  }
  contains() {
    return false;
  }
  querySelector() {
    return null;
  }
  focus() {}
  select() {}
  scrollIntoView() {}
}

const ids = {};
for (const id of ["clock-detail", "extras"]) {
  ids[id] = new Element(id);
  ids[id].hidden = true;
}
const chips = ["launch", "tabs", "workspaces", "actions"].map((s) => {
  const b = new Element("button");
  b.dataset.scope = s;
  return b;
});
// Every listener for each event, in the order they were added, as a real
// document keeps them: the page's Esc handler and the clock's both hear Esc.
const docListeners = {};
const fire = (type, e) => (docListeners[type] ?? []).forEach((fn) => fn(e));
const winListeners = {};
const sent = [];
const sandbox = {
  document: {
    createElement: (tag) => new Element(tag),
    getElementById: (id) => (ids[id] ??= new Element(id)),
    querySelectorAll: (sel) => {
      assert.strictEqual(sel, ".scopes button");
      return chips;
    },
    addEventListener: (type, fn) => (docListeners[type] ??= []).push(fn),
    dispatchEvent: (e) => fire(e.type, e),
    body: new Element("body"),
    activeElement: null,
  },
  location: { search: "" },
  setInterval: () => 0,
  console,
  Intl,
  Date,
  Math,
  JSON,
  Number,
  String,
  Object,
  Array,
  Error,
  Map,
  Set,
  Promise,
  RegExp,
  URL,
  URLSearchParams,
};
sandbox.window = sandbox;
// A key event, as the page makes one for tide.escape().
sandbox.KeyboardEvent = class {
  constructor(type, init) {
    Object.assign(this, init, { type });
  }
  preventDefault() {}
};
// A frame, as WebKit paints one: after the work queued before it.
sandbox.requestAnimationFrame = (fn) => setTimeout(fn, 0);
sandbox.globalThis = sandbox;
sandbox.addEventListener = (type, fn) => (winListeners[type] = fn);
sandbox.webkit = { messageHandlers: { tide: { postMessage: (m) => sent.push(JSON.parse(JSON.stringify(m))) } } };
vm.createContext(sandbox);
vm.runInContext(fs.readFileSync(process.argv[2], "utf8"), sandbox);
const feed = JSON.parse(fs.readFileSync(process.argv[3], "utf8"));

// The page's work is promises; a turn of the event loop settles them.
const settle = () => new Promise((resolve) => setTimeout(resolve, 0));
const rows = () => ids.results.children.map((li) => li.children[1].textContent);
const details = () => ids.results.children.map((li) => li.children[2].textContent);
const keys = () => ids.results.children.map((li) => li.children[3].textContent);
const press = (key, extra = {}) => ids.query.fire("keydown", { key, preventDefault() {}, ...extra });
const type = async (text) => {
  ids.query.value = text;
  ids.query.fire("input");
  await settle();
};
const choices = () => sent.filter((m) => !m.goodClocks && !m.clockErrors && m.typed === undefined);
const typedSaid = () => sent.filter((m) => m.typed !== undefined).map((m) => m.typed);

(async () => {
  await settle();
  sandbox.tide.open(feed, "launch");
  await settle();

  // Launch: the Mac's apps, most recently used first, then Tide Settings.
  assert.strictEqual(sandbox.tide.scope(), "launch");
  assert.deepStrictEqual(rows(), ["Browser window", "Notes", "Safari", "Mouse settings", "Tide Settings"]);
  assert.strictEqual(keys()[0], "Super+G");
  assert.match(ids.keys.textContent, /^Enter to run · ↑ ↓ to choose · Tab to switch to Tabs · Esc to clear or close$/);

  // The bar: tide's workspaces, and the one showing.
  const bar = ids.workspaces.children.filter((b) => b.tag === "button");
  assert.strictEqual(bar[0].textContent, "in");
  assert.ok(bar[0].classList.contains("current"));
  assert.ok(ids.clocks.children.length >= 1, "the clocks");

  // A Tide Settings section turns up for a query, and opens the window there.
  await type("left-handed");
  assert.strictEqual(rows()[0], "Mouse");
  assert.strictEqual(details()[0], "Tide Settings");
  press("Enter");
  await settle();
  assert.deepStrictEqual(choices().at(-1), { settings: "mouse" });

  // An app runs as the switcher's row.
  await type("notes");
  press("Enter");
  await settle();
  assert.deepStrictEqual(choices().slice(-2), [{ command: "row:app:/System/Applications/Notes.app" }, { close: true }]);

  // Tab moves to Tabs: the windows, most recent first, then browser tabs.
  await type("");
  press("Tab");
  await settle();
  assert.strictEqual(sandbox.tide.scope(), "tabs");
  assert.deepStrictEqual(rows(), ["notes.txt", "Google Chrome", "Docs"]);
  assert.deepStrictEqual(details(), ["tab on in", "tab on re", "tab on re"]);
  // A window is found by its app.
  await type("chrome");
  assert.strictEqual(rows()[0], "Google Chrome");
  press("Enter");
  await settle();
  assert.deepStrictEqual(choices().slice(-2), [{ tabId: "window:1", windowId: "window:1" }, { close: true }]);

  // A switcher key while it's open turns to its scope, or closes it on its own.
  await type("");
  sandbox.tide.press("actions");
  await settle();
  assert.strictEqual(sandbox.tide.scope(), "actions");
  assert.deepStrictEqual(rows().slice(0, 3), ["Lock", "Log out", "Sleep"]);
  assert.ok(rows().includes("Layout: tile"), "tide's commands after the actions");
  assert.ok(!rows().some((r) => r.startsWith("Tide Settings:")), "no section rows as commands");
  const awake = rows().indexOf("Keep awake");
  assert.strictEqual(details()[awake], "off");
  sandbox.tide.press("actions");
  assert.deepStrictEqual(choices().at(-1), { close: true });

  // Workspaces: the bar's, and a new one by name.
  sandbox.tide.press("workspaces");
  await settle();
  assert.strictEqual(ids.query.placeholder, "Go to the workspace named");
  assert.strictEqual(rows()[0], "in");
  await type("web");
  assert.strictEqual(details()[0], "new workspace");
  press("Enter");
  await settle();
  assert.deepStrictEqual(choices().slice(-2), [{ workspace: "web" }, { close: true }]);

  // Browser tabs arriving later join the rows; keep awake's cup shows it.
  await type("");
  sandbox.tide.press("tabs");
  sandbox.tide.update({ tabs: [...feed.tabs, { id: "tab:x", windowId: "tab:x", title: "Later", url: "https://example.com/", lastAccessed: 0 }], keepAwake: true });
  await settle();
  assert.ok(rows().includes("Later"));
  assert.strictEqual(ids["keep-awake"].attrs["aria-pressed"], "true");

  // Esc with nothing typed closes it, and the page notes when it heard it;
  // the footer's Settings opens the window.
  const before = choices().length;
  fire("keydown", { key: "Escape", preventDefault() {} });
  await settle();
  assert.deepStrictEqual(choices().slice(before), [{ close: true }], "Esc itself closes it");
  assert.strictEqual(typeof sandbox.tide.esc, "number");
  ids["open-settings"].click();
  await settle();
  assert.deepStrictEqual(choices().slice(-2), [{ close: true }, { settings: true }]);

  // tide hears the clocks to keep, as from the dashboard.
  assert.ok(sent.some((m) => m.goodClocks));

  // The page is kept between opens: each starts with an empty search, on its
  // scope, as a new page would.
  await type("Safari");
  sandbox.tide.open(feed, "launch");
  await settle();
  assert.strictEqual(ids.query.value, "");
  assert.strictEqual(sandbox.tide.scope(), "launch");
  assert.deepStrictEqual(rows(), ["Browser window", "Notes", "Safari", "Mouse settings", "Tide Settings"]);

  // CI's turn keeps what's typed, as Tab does.
  await type("no");
  sandbox.tide.turn("tabs");
  await settle();
  assert.strictEqual(ids.query.value, "no");
  assert.strictEqual(sandbox.tide.scope(), "tabs");
  // tide takes Esc while it's open, so the page says when there's
  // something typed, once each way, and hands Esc back as tide.escape(),
  // which clears the search and leaves it open; with nothing typed it
  // closes.
  sandbox.tide.open(feed, "launch");
  await settle();
  const said = typedSaid().length;
  await type("sa");
  await type("saf");
  assert.deepStrictEqual(typedSaid().slice(said), [true], "said once as the search fills");
  let made = choices().length;
  sandbox.tide.escape();
  await settle();
  assert.strictEqual(ids.query.value, "");
  assert.deepStrictEqual(choices().slice(made), [], "clearing leaves it open");
  assert.deepStrictEqual(typedSaid().slice(said), [true, false]);
  made = choices().length;
  sandbox.tide.escape();
  await settle();
  assert.deepStrictEqual(choices().slice(made), [{ close: true }]);
  console.log("launcher page: ok");
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
