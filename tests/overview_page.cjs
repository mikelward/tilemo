// Runs the overview's bundled script (tests/overview_test.lua writes it to
// the file named on the command line) against a small fake DOM, and checks
// tide.update() draws the groups and cards, typing filters them, and the
// choices go back to tide.

const fs = require("fs");
const vm = require("vm");
const assert = require("assert");

class Element {
  constructor(tag) {
    this.tag = tag;
    this.children = [];
    this.className = "";
    this.textContent = "";
    this.attrs = {};
    this.listeners = {};
    const classes = new Set();
    this.classList = {
      toggle: (c, on) => (on ? classes.add(c) : classes.delete(c)),
      contains: (c) => classes.has(c),
    };
  }
  append(...xs) {
    for (const x of xs) this.children.push(x);
  }
  replaceChildren() {
    this.children = [];
  }
  addEventListener(type, fn) {
    this.listeners[type] = fn;
  }
}

const ids = {};
const docListeners = {};
let sent = [];
const sandbox = {
  document: {
    createElement: (tag) => new Element(tag),
    getElementById: (id) => (ids[id] ??= new Element(id)),
    addEventListener: (type, fn) => (docListeners[type] = fn),
  },
  Math,
  Number,
  String,
  Object,
  Array,
  Error,
  Map,
  Set,
};
sandbox.window = sandbox;
sandbox.webkit = { messageHandlers: { tide: { postMessage: (m) => sent.push(m) } } };
vm.createContext(sandbox);
vm.runInContext(fs.readFileSync(process.argv[2], "utf8"), sandbox);

// The messages come from the page's own realm, so compare them as JSON.
const took = () => {
  const out = JSON.stringify(sent);
  sent = [];
  return out;
};
const key = (k) => docListeners.keydown({ key: k, preventDefault() {} });
const groups = () => ids.groups.children.filter((c) => c.className === "group");
const cardsOf = (g) => g.children.find((c) => c.className === "cards").children;
const allCards = () => groups().flatMap(cardsOf);
const titles = () => allCards().map((c) => c.children[1].children[0].textContent);
const selected = () => allCards().filter((c) => c.classList.contains("selected")).map((c) => c.title);

const state = {
  scope: "all",
  focused: 2,
  icons: { "com.apple.Notes": "data:image/png;base64,AAAA" },
  groups: [
    {
      name: "web",
      current: true,
      windows: [
        { id: 5, app: "Chrome", bundle: "com.google.Chrome", title: "Docs", mine: false },
        { id: 2, app: "Mail", bundle: "com.apple.mail", title: "Inbox", mine: false },
      ],
    },
    {
      name: "in",
      current: false,
      windows: [
        { id: 1, app: "Notes", bundle: "com.apple.Notes", title: "Shopping", mine: false },
        { id: 3, app: "kitty", bundle: "net.kovidgoyal.kitty", title: "~", mine: true },
      ],
    },
  ],
};
sandbox.tide.update(state);

// Each group headed by its name, the current one marked, in tide's order.
assert.deepStrictEqual(groups().map((g) => g.children[0].textContent), ["web", "in"]);
assert.ok(groups()[0].classList.contains("current"));
assert.ok(!groups()[1].classList.contains("current"));
assert.deepStrictEqual(titles(), ["Docs", "Inbox", "Shopping", "~"]);
// An app's icon from the data URL, and a blank square for one with none.
const notes = cardsOf(groups()[1])[0];
assert.strictEqual(notes.children[0].tag, "img");
assert.strictEqual(notes.children[0].src, "data:image/png;base64,AAAA");
assert.ok(cardsOf(groups()[0])[0].children[0].className.includes("blank"));
// The app's name under the title, and a window you minimized marked.
assert.strictEqual(notes.children[1].children[1].textContent, "Notes");
const kitty = cardsOf(groups()[1])[1];
assert.strictEqual(kitty.children[1].children[1].textContent, "kitty · minimized");
assert.ok(kitty.classList.contains("minimized"));

// The selection starts on the focused window; arrows step, and stop at the
// ends; Return activates it.
assert.deepStrictEqual(selected(), ["Inbox"]);
key("ArrowRight");
key("ArrowDown");
key("ArrowDown");
key("ArrowDown");
assert.deepStrictEqual(selected(), ["~"]);
key("ArrowLeft");
key("Enter");
assert.strictEqual(took(), JSON.stringify([{ activate: 1 }]));

// A click on a card activates it, on a header shows its workspace, and on
// empty space closes the overview; so does Esc.
let stopped = 0;
const click = { stopPropagation: () => stopped++ };
cardsOf(groups()[0])[0].listeners.click(click);
groups()[1].children[0].listeners.click(click);
assert.strictEqual(stopped, 2, "a card's or header's click isn't also a click on empty space");
docListeners.click({});
key("Escape");
assert.strictEqual(took(), JSON.stringify([{ activate: 5 }, { show: "in" }, { close: true }, { close: true }]));

// Typing filters by title and app name, fuzzily, and drops a group left
// with nothing; the selection moves to the first card left.
key("s");
key("h");
assert.deepStrictEqual(titles(), ["Shopping"]);
assert.deepStrictEqual(groups().map((g) => g.children[0].textContent), ["in"]);
assert.strictEqual(ids.filter.textContent, "sh");
assert.deepStrictEqual(selected(), ["Shopping"]);
key("Backspace");
key("Backspace");
for (const c of "mail") key(c);
assert.deepStrictEqual(titles(), ["Inbox"], "by app name too");
key("q");
assert.deepStrictEqual(titles(), []);
assert.ok(ids.groups.children.some((c) => c.className === "note" && c.textContent === "No windows match"));
key("Enter");
assert.strictEqual(took(), "[]", "nothing to activate");
// Command and Control chords aren't typing.
docListeners.keydown({ key: "a", metaKey: true, preventDefault() {} });
assert.strictEqual(ids.filter.textContent, "mailq");

// An update in the same scope keeps the filter; the other scope starts
// afresh, on the focused window. The current workspace with no windows
// still shows, saying so.
sandbox.tide.update(state);
assert.strictEqual(ids.filter.textContent, "mailq");
sandbox.tide.update({ scope: "current", focused: null, icons: [], groups: [{ name: "oc", current: true, windows: [] }] });
assert.strictEqual(ids.filter.textContent, "");
assert.deepStrictEqual(groups().map((g) => g.children[0].textContent), ["oc"]);
assert.strictEqual(groups()[0].children[1].textContent, "No windows on this workspace");
key("Enter");
assert.strictEqual(took(), "[]");

// Lua's JSON can send an empty list as an object: an empty workspace's
// windows, or no groups at all.
sandbox.tide.update({ scope: "all", focused: null, icons: {}, groups: [{ name: "oc", current: true, windows: {} }] });
assert.strictEqual(groups()[0].children[1].textContent, "No windows on this workspace");
sandbox.tide.update({ scope: "current", focused: null, icons: {}, groups: {} });
assert.deepStrictEqual(groups(), []);
console.log("overview page: ok");
