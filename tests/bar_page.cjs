// Runs the bar's bundled script (tests/bar_test.lua writes it to the file
// named on the command line) against a small fake DOM, and checks
// tilemo.update() draws the chips, title, clocks and icons, and what clicks
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
    this.innerHTML = "";
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
sandbox.webkit = { messageHandlers: { tilemo: { postMessage: (m) => sent.push(m) } } };
vm.createContext(sandbox);
vm.runInContext(fs.readFileSync(process.argv[2], "utf8"), sandbox);

const ws = [
  { n: "in" },
  { n: "web", current: true },
  { n: "docs", elsewhere: true },
  {
    n: "ABC-123 fix the login page",
    occupied: true,
    urgent: true,
    apps: ["com.a", "com.b", "com.a", "com.c", "com.d"],
    wins: [11, 12, 13, 14, 15],
    more: 2,
  },
];
sandbox.tilemo.update({
  uuid: "B",
  workspaces: ws,
  title: "Chat (1)",
  app_icons: { "com.a": "data:image/png;base64,QQ==", "com.b": "data:image/png;base64,Qg==", "com.c": false },
  icons: {
    source: { label: "DVO", name: "Dvorak" },
    awake: { on: false },
    camera: { in_use: true },
    mic: { muted: false },
    wifi: { on: true, bars: 2, name: "home" },
    network: { kind: "wifi" },
    volume: { level: "mute", muted: true },
    battery: { percent: 15, charging: false, text: "15%", tip: "Battery 15%, 0:40 left" },
  },
});

const chips = ids.workspaces.children;
assert.strictEqual(
  chips.map((b) => b.children[0].textContent).join("|"),
  "in|web|docs|ABC-123 fix the …",
  "every workspace, by name, a long one cut",
);
assert.strictEqual(chips[3].title, "ABC-123 fix the login page", "the whole name on hover");
// A chip's name, then one icon per window wanting attention, then how many
// more.
const parts = chips[3].children;
assert.deepStrictEqual(
  parts.map((c) => c.tag + "." + c.className),
  ["span.n", "img.app", "img.app", "img.app", "span.app none", "span.app none", "span.more"],
);
assert.strictEqual(parts[1].src, "data:image/png;base64,QQ==");
assert.strictEqual(parts[3].src, parts[1].src, "one icon per window, so an app's second window repeats it");
assert.strictEqual(parts[6].textContent, "+2");
assert.strictEqual(chips[0].children.length, 1, "an empty chip is its name alone");
assert.ok(chips[1].classList.contains("current"));
assert.ok(chips[2].classList.contains("elsewhere"));
assert.ok(chips[3].classList.contains("urgent"));
assert.strictEqual(ids.title.textContent, "Chat (1)");
assert.ok(ids.clocks.children.length >= 1, "the clocks row");

const icons = ids.icons.children;
const byName = Object.fromEntries(icons.map((b) => [b.className.replace("icon ", ""), b]));
assert.deepStrictEqual(
  icons.map((b) => b.className),
  ["icon source", "icon awake", "icon camera", "icon mic", "icon volume", "icon wifi", "icon battery"],
);
assert.strictEqual(byName.source.textContent, "DVO");
assert.strictEqual(byName.source.attrs.title, "Dvorak");
// Each icon is a line drawing, with its state in data-state.
const state = (b) => b.attrs["data-state"];
for (const b of icons) if (b.className !== "icon source") assert.ok(b.innerHTML.startsWith("<svg "), `${b.className} is drawn`);
assert.strictEqual(state(byName.awake), "off");
assert.strictEqual(state(byName.camera), "in-use");
assert.strictEqual(byName.camera.attrs.title, "Camera in use");
assert.strictEqual(byName.mic.attrs.title, "Microphone");
assert.strictEqual(state(byName.mic), "on");
assert.ok(!byName.mic.innerHTML.includes("M2.5 2.5l11 11"), "no slash on a live microphone");
assert.strictEqual(state(byName.wifi), "bars-2");
assert.strictEqual(byName.wifi.innerHTML.split('opacity="0.3"').length - 1, 1, "two of three Wi-Fi arcs lit");
assert.strictEqual(byName.wifi.attrs.title, "home");
assert.strictEqual(state(byName.volume), "mute");
assert.ok(byName.volume.innerHTML.includes("M11 6.5l3 3"), "the speaker's cross");
assert.strictEqual(state(byName.battery), "low");
assert.strictEqual(byName.battery.attrs.title, "Battery 15%, 0:40 left");
assert.ok(byName.battery.innerHTML.includes('width="1.20"'), "a bar 15% full");
assert.strictEqual(byName.battery.children[0].textContent, "15%");

// No sizes in the fake DOM, so nothing counts as crowded.
assert.strictEqual(ids.clocks.classList.contains("compact"), false);

chips[2].listeners.click();
// An attention icon focuses its window, and the chip doesn't also show its
// workspace.
let stopped = false;
parts[3].listeners.click({ stopPropagation: () => (stopped = true) });
assert.ok(stopped, "the click stays with the icon");
parts[4].listeners.click({ stopPropagation() {} });
byName.wifi.listeners.click();
ids.clocks.listeners.click();
ids.title.listeners.dblclick();
const wheel = (deltaY) => ids.workspaces.listeners.wheel({ deltaY, preventDefault() {} });
wheel(20);
wheel(40);
wheel(-60);
byName.mic.listeners.click();
byName.volume.listeners.click();
byName.awake.listeners.click();
byName.source.listeners.click();
byName.battery.listeners.click();
const spin = (deltaY) => byName.volume.listeners.wheel({ deltaY, preventDefault() {} });
spin(-60);
spin(30);
spin(30);
assert.strictEqual(
  JSON.stringify(sent.filter((m) => !m.goodClocks)),
  JSON.stringify([
    { uuid: "B", show: "docs" },
    { uuid: "B", focus: 13 },
    { uuid: "B", focus: 14 },
    { uuid: "B", open: "wifi" },
    { uuid: "B", dashboard: true },
    { uuid: "B", maximize: true },
    { uuid: "B", step: 1 },
    { uuid: "B", step: -1 },
    { uuid: "B", toggle: "mic" },
    { uuid: "B", toggle: "volume" },
    { uuid: "B", toggle: "awake" },
    { uuid: "B", toggle: "source" },
    { uuid: "B", open: "battery" },
    { uuid: "B", volume: 1 },
    { uuid: "B", volume: -1 },
  ]),
  "every message names this bar's display",
);
sent.length = 0;

// A wire, or no network at all.
sandbox.tilemo.update({ uuid: "B", workspaces: ws, title: "", icons: { network: { kind: "wired" } } });
assert.strictEqual(ids.icons.children[0].className, "icon wired");
ids.icons.children[0].listeners.click();
sandbox.tilemo.update({ uuid: "B", workspaces: ws, title: "", icons: { network: { kind: "none" } } });
assert.strictEqual(state(ids.icons.children[0]), "none");
assert.strictEqual(ids.icons.children[0].attrs.title, "No network");
assert.strictEqual(JSON.stringify(sent), JSON.stringify([{ uuid: "B", open: "network" }]));

// The title keeps 200 px or the clocks shrink to local time.
const { crowded } = vm.runInContext('modules["./bar.js"]', sandbox);
assert.strictEqual(crowded(1920, 300, 500), false);
assert.strictEqual(crowded(1200, 300, 500), true);

// A long title is held to the room between the chips and the right side,
// centered, so it can't run over either.
Object.assign(ids.bar, { clientWidth: 1200 });
Object.assign(ids.workspaces, { offsetWidth: 300 });
Object.assign(ids.right, { offsetWidth: 500 });
sandbox.tilemo.update({ uuid: "B", workspaces: ws, title: "x".repeat(500), icons: {} });
const room = parseFloat(ids.title.style.maxWidth);
assert.strictEqual(room, 1200 - 2 * 500 - 2 * 24);
assert.ok(1200 / 2 - room / 2 >= 300, "clear of the chips");
assert.ok(1200 / 2 + room / 2 <= 1200 - 500, "clear of the clocks and icons");
assert.ok(ids.clocks.classList.contains("compact"), "and the clocks shrank");

// Off, Wi-Fi shows its bars dimmed and no name.
sandbox.tilemo.update({ uuid: "B", workspaces: ws, title: "", icons: { wifi: { on: false, bars: 0 } } });
assert.strictEqual(state(ids.icons.children[0]), "off");
assert.strictEqual(ids.icons.children[0].attrs.title, "Wi-Fi off");
// Lua's JSON leaves out a field that's nil: a chip that's only occupied
// mustn't come out urgent or elsewhere.
sandbox.tilemo.update({ uuid: "B", workspaces: [{ n: 4, occupied: true }], title: "", icons: {} });
const only = ids.workspaces.children[0];
assert.ok(only.classList.contains("occupied"));
for (const k of ["current", "elsewhere", "urgent"]) assert.ok(!only.classList.contains(k), `not ${k}`);
// Nor a microphone that's only said not to be muted come out muted.
sandbox.tilemo.update({ uuid: "B", workspaces: ws, title: "", icons: { mic: { muted: false } } });
const mic = ids.icons.children[0];
assert.strictEqual(mic.className, "icon mic");
assert.strictEqual(state(mic), "on", "not muted");
// Muted, the microphone is struck through; charging, the battery has its bolt.
sandbox.tilemo.update({
  uuid: "B",
  workspaces: ws,
  title: "",
  icons: { mic: { muted: true }, battery: { percent: 60, charging: true, text: "60%" } },
});
const [mutedMic, , charging] = ids.icons.children;
assert.strictEqual(state(mutedMic), "muted");
assert.ok(mutedMic.innerHTML.includes("M2.5 2.5l11 11"), "the slash");
assert.strictEqual(state(charging), "charging");
assert.strictEqual(charging.innerHTML.split("<svg ").length - 1, 2, "the bolt and the battery");
console.log("bar page: ok");
