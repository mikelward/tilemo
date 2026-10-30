// Runs the dashboard's bundled script (tests/dashboard_test.lua writes it
// to the file named on the command line) against a small fake DOM, and
// checks tilemo.update() draws the bar and the clock panel.

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
sandbox.webkit = { messageHandlers: { tilemo: { postMessage: (m) => sent.push(m) } } };
vm.createContext(sandbox);
vm.runInContext(fs.readFileSync(process.argv[2], "utf8"), sandbox);

const ws = [];
for (let n = 1; n <= 9; n++) ws.push({ n, current: n === 2, elsewhere: false, occupied: n === 5, urgent: n === 5 });
sandbox.tilemo.update({ workspaces: ws, title: "Chat (1)" });

const chips = ids.workspaces.children;
assert.strictEqual(chips.map((b) => b.textContent).join(" "), "2 5", "only showing or occupied workspaces");
assert.ok(chips[0].classList.contains("current"));
assert.ok(chips[1].classList.contains("urgent"));
assert.strictEqual(ids.title.textContent, "Chat (1)");
assert.ok(ids.clocks.children.length >= 1, "the clocks row");
assert.ok(ids["clock-detail"].children.some((c) => c.className === "calendar"), "the calendar");

// With no clocks files, SPEC.md §8's clocks; Dublin is local, so London's
// shows.
const labels = () => ids.clocks.children.map((li) => li.children[0].textContent).join(" ");
assert.match(labels(), /^SYD LAX NYC LON /);

// tide's clocks.local.json replaces the list, and "abbr" is the zone's
// abbreviation.
const local = JSON.stringify({ clocks: [{ zone: "Asia/Tokyo", label: "TYO" }, { zone: "America/Chicago", label: "abbr" }] });
sandbox.tilemo.update({ workspaces: ws, title: "", clockFiles: { local } });
assert.match(labels(), /^TYO C[DS]T /);

// An update while it's open keeps the month the calendar was moved to.
const month = () => ids["clock-detail"].children.find((c) => c.className === "calendar").children[0];
const thisMonth = month().children[1].textContent;
month().children[2].listeners.click();
const nextMonth = month().children[1].textContent;
assert.notStrictEqual(nextMonth, thisMonth);
sandbox.tilemo.update({ workspaces: ws, title: "", clockFiles: { local } });
assert.strictEqual(month().children[1].textContent, nextMonth);

// A file that's wrong keeps the clocks, and says so.
sandbox.tilemo.update({ workspaces: ws, title: "", clockFiles: { local: "[{" } });
assert.match(labels(), /^TYO C[DS]T /);
sandbox.tilemo.update({ workspaces: ws, title: "", clockFiles: { local: '[{"zone": "Mars/Base", "label": "M"}]' } });
assert.match(labels(), /^TYO C[DS]T /);

chips[1].listeners.click();
docListeners.keydown({ key: "7" });
docListeners.keydown({ key: "Escape" });
ids["edit-clocks"].listeners.click();
// The messages come from the page's own realm, so compare them as JSON.
assert.strictEqual(
  JSON.stringify(sent.filter((m) => !m.goodClocks)),
  JSON.stringify([
    { clockErrors: ['clocks.local.json: line 1: expected " before the end'] },
    { clockErrors: ['clocks.local.json: entry 1: unknown time zone "Mars/Base"'] },
    { show: 5 },
    { show: 7 },
    { close: true },
    { settings: true },
  ]),
);
// tilemo hears the clocks to keep each time they change, and only then:
// SPEC.md §8's, then the file's, kept through the two that are wrong.
assert.deepStrictEqual(
  JSON.parse(JSON.stringify(sent.filter((m) => m.goodClocks))).map((m) => m.goodClocks.map((c) => c.zone)),
  [
    ["Australia/Sydney", "America/Los_Angeles", "America/New_York", "Europe/London"],
    ["Asia/Tokyo", "America/Chicago"],
  ],
);

// A dashboard opened while a file is wrong shows the clocks tilemo kept from
// the pages before it, as the bar still does, not SPEC.md §8's.
const reopened = {};
const fresh = {
  ...sandbox,
  document: {
    createElement: (tag) => new Element(tag),
    getElementById: (id) => (reopened[id] ??= new Element(id)),
    addEventListener: () => {},
  },
};
fresh.window = fresh;
vm.createContext(fresh);
vm.runInContext(fs.readFileSync(process.argv[2], "utf8"), fresh);
fresh.tilemo.update({
  workspaces: ws,
  title: "",
  clockFiles: { local: "[{" },
  goodClocks: [{ zone: "Asia/Tokyo", label: "TYO" }],
});
assert.match(reopened.clocks.children.map((li) => li.children[0].textContent).join(" "), /^TYO /);
console.log("dashboard page: ok");
