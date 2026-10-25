// Runs the dashboard's bundled script (tests/dashboard_test.lua writes it
// to the file named on the command line) against a small fake DOM, and
// checks timo.update() draws the bar and the clock panel.

const fs = require("fs");
const vm = require("vm");
const assert = require("assert");

class Element {
  constructor(tag) {
    this.tag = tag;
    this.children = [];
    this.className = "";
    this.textContent = "";
    this.style = {};
    this.attrs = {};
    this.listeners = {};
    const classes = new Set();
    this.classList = {
      toggle: (c, on) => (on ? classes.add(c) : classes.delete(c)),
      contains: (c) => classes.has(c),
    };
  }
  append(...xs) {
    for (const x of xs) this.children.push(typeof x === "string" ? { text: x } : x);
  }
  replaceChildren() {
    this.children = [];
  }
  setAttribute(k, v) {
    this.attrs[k] = v;
  }
  addEventListener(type, fn) {
    this.listeners[type] = fn;
  }
}

const ids = {};
const docListeners = {};
const sent = [];
const sandbox = {
  document: {
    createElement: (tag) => new Element(tag),
    getElementById: (id) => (ids[id] ??= new Element(id)),
    addEventListener: (type, fn) => (docListeners[type] = fn),
  },
  setInterval: () => 0,
  Intl,
  Date,
  Math,
  Number,
  String,
  Object,
  Error,
  Map,
  Set,
};
sandbox.window = sandbox;
sandbox.webkit = { messageHandlers: { timo: { postMessage: (m) => sent.push(m) } } };
vm.createContext(sandbox);
vm.runInContext(fs.readFileSync(process.argv[2], "utf8"), sandbox);

const ws = [];
for (let n = 1; n <= 9; n++) ws.push({ n, current: n === 2, elsewhere: false, occupied: n === 5, urgent: n === 5 });
sandbox.timo.update({ workspaces: ws, title: "Chat (1)" });

const chips = ids.workspaces.children;
assert.strictEqual(chips.map((b) => b.textContent).join(" "), "2 5", "only showing or occupied workspaces");
assert.ok(chips[0].classList.contains("current"));
assert.ok(chips[1].classList.contains("urgent"));
assert.strictEqual(ids.title.textContent, "Chat (1)");
assert.ok(ids.clocks.children.length >= 1, "the clocks row");
assert.ok(ids["clock-detail"].children.some((c) => c.className === "calendar"), "the calendar");

chips[1].listeners.click();
docListeners.keydown({ key: "7" });
docListeners.keydown({ key: "Escape" });
// The messages come from the page's own realm, so compare them as JSON.
assert.strictEqual(JSON.stringify(sent), JSON.stringify([{ show: 5 }, { show: 7 }, { close: true }]));
console.log("dashboard page: ok");
