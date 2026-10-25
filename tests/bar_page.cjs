// Runs the bar's bundled script (tests/bar_test.lua writes it to the file
// named on the command line) against a small fake DOM, and checks
// timo.update() draws the chips, title, clocks and icons, and what clicks
// and scrolls send back.

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
    // As the DOM's: without a second argument, or with undefined, it flips.
    this.classList = {
      toggle: (c, on) => {
        const add = on === undefined ? !classes.has(c) : on;
        if (add) classes.add(c);
        else classes.delete(c);
        return add;
      },
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
const sent = [];
const sandbox = {
  document: {
    createElement: (tag) => new Element(tag),
    getElementById: (id) => (ids[id] ??= new Element(id)),
    addEventListener: () => {},
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
for (let n = 1; n <= 9; n++) ws.push({ n, current: n === 2, elsewhere: n === 3, occupied: n === 5, urgent: n === 5 });
sandbox.timo.update({
  uuid: "B",
  workspaces: ws,
  title: "Chat (1)",
  icons: {
    wifi: { on: true, bars: 2, name: "home" },
    volume: { level: "mute", muted: true },
    battery: { percent: 15, charging: false, text: "15%" },
  },
});

const chips = ids.workspaces.children;
assert.strictEqual(chips.map((b) => b.textContent).join(" "), "2 3 5", "only showing or occupied workspaces");
assert.ok(chips[0].classList.contains("current"));
assert.ok(chips[1].classList.contains("elsewhere"));
assert.ok(chips[2].classList.contains("urgent"));
assert.strictEqual(ids.title.textContent, "Chat (1)");
assert.ok(ids.clocks.children.length >= 1, "the clocks row");

const icons = ids.icons.children;
assert.deepStrictEqual(icons.map((b) => b.className), ["icon wifi", "icon volume", "icon battery"]);
assert.strictEqual(icons[0].children.filter((s) => s.className === "lit").length, 2, "two of three Wi-Fi bars");
assert.strictEqual(icons[0].attrs.title, "home");
assert.strictEqual(icons[1].textContent, "🔇");
assert.ok(icons[2].classList.contains("low"), "a low battery");
assert.strictEqual(icons[2].children[0].children[0].style.width, "15%");

// No sizes in the fake DOM, so nothing counts as crowded.
assert.strictEqual(ids.clocks.classList.contains("compact"), false);

chips[2].listeners.click();
icons[0].listeners.click();
ids.clocks.listeners.click();
const wheel = (deltaY) => ids.workspaces.listeners.wheel({ deltaY, preventDefault() {} });
wheel(20);
wheel(40);
wheel(-60);
assert.strictEqual(
  JSON.stringify(sent),
  JSON.stringify([
    { uuid: "B", show: 5 },
    { uuid: "B", open: "wifi" },
    { uuid: "B", dashboard: true },
    { uuid: "B", step: 1 },
    { uuid: "B", step: -1 },
  ]),
  "every message names this bar's display",
);

// The title keeps 200 px or the clocks shrink to local time.
const { crowded } = vm.runInContext('modules["./bar.js"]', sandbox);
assert.strictEqual(crowded(1920, 300, 500), false);
assert.strictEqual(crowded(1200, 300, 500), true);

// A long title is held to the room between the chips and the right side,
// centered, so it can't run over either.
Object.assign(ids.bar, { clientWidth: 1200 });
Object.assign(ids.workspaces, { offsetWidth: 300 });
Object.assign(ids.right, { offsetWidth: 500 });
sandbox.timo.update({ uuid: "B", workspaces: ws, title: "x".repeat(500), icons: {} });
const room = parseFloat(ids.title.style.maxWidth);
assert.strictEqual(room, 1200 - 2 * 500 - 2 * 24);
assert.ok(1200 / 2 - room / 2 >= 300, "clear of the chips");
assert.ok(1200 / 2 + room / 2 <= 1200 - 500, "clear of the clocks and icons");
assert.ok(ids.clocks.classList.contains("compact"), "and the clocks shrank");

// Off, Wi-Fi shows its bars dimmed and no name.
sandbox.timo.update({ uuid: "B", workspaces: ws, title: "", icons: { wifi: { on: false, bars: 0 } } });
assert.ok(ids.icons.children[0].classList.contains("off"));
assert.strictEqual(ids.icons.children[0].attrs.title, "Wi-Fi off");
// Lua's JSON leaves out a field that's nil: a chip that's only occupied
// mustn't come out urgent or elsewhere.
sandbox.timo.update({ uuid: "B", workspaces: [{ n: 4, occupied: true }], title: "", icons: {} });
const only = ids.workspaces.children[0];
assert.ok(only.classList.contains("occupied"));
for (const k of ["current", "elsewhere", "urgent"]) assert.ok(!only.classList.contains(k), `not ${k}`);
console.log("bar page: ok");
