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
    // Custom properties, as style.setProperty sets them, beside the rest.
    this.style = { setProperty: (k, v) => (this.style[k] = v) };
    // No layout: a test sets `rect` to give an element a box.
    this.rect = { left: 0, right: 0, top: 0, bottom: 0, width: 0, height: 0 };
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
    this.classes = () => new Set([...this.className.split(" ").filter(Boolean), ...classes]);
  }
  append(...xs) {
    for (const x of xs) {
      if (typeof x !== "string") x.parent = this;
      this.children.push(typeof x === "string" ? { text: x } : x);
    }
  }
  // One compound selector: tag, #id and .classes.
  is(compound) {
    const tag = compound.match(/^[a-z]+/)?.[0];
    const id = compound.match(/#([\w-]+)/)?.[1];
    const classes = [...compound.matchAll(/\.([\w-]+)/g)].map((m) => m[1]);
    return (!tag || tag === this.tag) && (!id || id === this.id) && classes.every((c) => this.classes().has(c));
  }
  // Enough of the DOM's: compounds joined by " " and " > ".
  matches(selector) {
    return selector.split(",").some((sel) => {
      const parts = sel.trim().split(/\s+/);
      const at = (e, i) => {
        if (!e || !e.is(parts[i])) return false;
        if (i === 0) return true;
        if (parts[i - 1] === ">") return at(e.parent, i - 2);
        for (let a = e.parent; a; a = a.parent) if (at(a, i - 1)) return true;
        return false;
      };
      return at(this, parts.length - 1);
    });
  }
  closest(selector) {
    for (let e = this; e; e = e.parent) if (e.matches(selector)) return e;
    return null;
  }
  getBoundingClientRect() {
    return this.rect;
  }
  replaceChildren() {
    this.children = [];
  }
  setAttribute(k, v) {
    this.attrs[k] = v;
  }
  getAttribute(k) {
    return k in this.attrs ? this.attrs[k] : null;
  }
  addEventListener(type, fn) {
    this.listeners[type] = fn;
  }
}

const ids = {};
// The page's own elements, as bar.html has them.
const TAGS = { bar: "header", workspaces: "nav", title: "span", "title-text": "span", right: "div", clocks: "ol", icons: "div" };
const byId = (id) => {
  const e = new Element(TAGS[id] ?? id);
  e.id = id;
  return e;
};
// What's under a point, as a test sets it.
let under = null;
const sent = [];
const sandbox = {
  document: {
    createElement: (tag) => new Element(tag),
    getElementById: (id) => (ids[id] ??= byId(id)),
    elementFromPoint: () => under,
    addEventListener: () => {},
  },
  // The page's clock tick, which fits the bar again.
  setInterval: (fn) => {
    sandbox.tick = fn;
    return 0;
  },
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
// The bar's window is never key, so WebKit would show no title attribute's
// tooltip: a tip is data-tip, which tilemo draws on hover (below).
assert.strictEqual(chips[3].attrs["data-tip"], "ABC-123 fix the login page", "the whole name on hover");
assert.strictEqual(chips[1].getAttribute("data-tip"), null, "a whole name has no tip");
for (const e of [...chips, ...ids.icons.children]) assert.ok(e.attrs.title === undefined && e.title === undefined, `${e.className || "a chip"} has no title attribute`);
// A chip's name, then one icon per window wanting attention, then how many
// more.
const parts = chips[3].children;
assert.deepStrictEqual(
  parts.map((c) => c.tag + "." + c.className),
  ["span.n", "img.app win", "img.app win", "img.app win", "span.app none win", "span.app none win", "span.more"],
);
assert.strictEqual(parts[1].src, "data:image/png;base64,QQ==");
assert.strictEqual(parts[3].src, parts[1].src, "one icon per window, so an app's second window repeats it");
assert.strictEqual(parts[6].textContent, "+2");
assert.strictEqual(chips[0].children.length, 1, "an empty chip is its name alone");
assert.ok(chips[1].classList.contains("current"));
assert.ok(chips[2].classList.contains("elsewhere"));
assert.ok(chips[3].classList.contains("urgent"));
assert.strictEqual(ids["title-text"].textContent, "Chat (1)");
assert.ok(ids.clocks.children.length >= 1, "the clocks row");

const icons = ids.icons.children;
const byName = Object.fromEntries(icons.map((b) => [b.className.replace("icon ", ""), b]));
assert.deepStrictEqual(
  icons.map((b) => b.className),
  ["icon source", "icon awake", "icon camera", "icon mic", "icon volume", "icon wifi", "icon battery"],
);
assert.strictEqual(byName.source.textContent, "DVO");
assert.strictEqual(byName.source.attrs["data-tip"], "Dvorak");
// Each icon is a line drawing, with its state in data-state.
const state = (b) => b.attrs["data-state"];
for (const b of icons) if (b.className !== "icon source") assert.ok(b.innerHTML.startsWith("<svg "), `${b.className} is drawn`);
assert.strictEqual(state(byName.awake), "off");
assert.strictEqual(state(byName.camera), "in-use");
assert.strictEqual(byName.camera.attrs["data-tip"], "Camera in use");
assert.strictEqual(byName.mic.attrs["data-tip"], "Microphone");
assert.strictEqual(state(byName.mic), "on");
assert.ok(!byName.mic.innerHTML.includes("M2.5 2.5l11 11"), "no slash on a live microphone");
assert.strictEqual(state(byName.wifi), "bars-2");
assert.strictEqual(byName.wifi.innerHTML.split('opacity="0.3"').length - 1, 1, "two of three Wi-Fi arcs lit");
assert.strictEqual(byName.wifi.attrs["data-tip"], "home");
assert.strictEqual(state(byName.volume), "mute");
assert.ok(byName.volume.innerHTML.includes("M11 6.5l3 3"), "the speaker's cross");
assert.strictEqual(state(byName.battery), "low");
assert.strictEqual(byName.battery.attrs["data-tip"], "Battery 15%, 0:40 left");
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
ids.bar.listeners.dblclick({ target: ids.title });
// The free bar around the title is the title's too, but a double click on
// an item isn't.
ids.bar.listeners.dblclick({ target: ids.bar });
ids.bar.listeners.dblclick({ target: chips[0] });
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

// Each connected Bluetooth audio device, beside the speaker, named on
// hover, and a click opens Bluetooth settings.
sandbox.tilemo.update({
  uuid: "B",
  workspaces: ws,
  title: "",
  icons: { headphones: { devices: [{ name: "Buds" }, { name: "Car" }] }, volume: { level: "high", muted: false }, network: { kind: "wired" } },
});
{
  const shown = ids.icons.children;
  assert.strictEqual(shown.map((b) => b.className).join("|"), "icon headphones|icon headphones|icon volume|icon wired");
  assert.strictEqual(shown.slice(0, 2).map((b) => b.attrs["data-tip"]).join("|"), "Buds|Car");
  assert.strictEqual(shown[0].attrs["aria-label"], "Buds");
  assert.ok(shown[0].innerHTML.startsWith("<svg "), "drawn");
  shown[1].listeners.click();
  assert.strictEqual(JSON.stringify(sent.at(-1)), JSON.stringify({ uuid: "B", open: "bluetooth" }));
  sent.length = 0;
}

// A wire, or no network at all.
sandbox.tilemo.update({ uuid: "B", workspaces: ws, title: "", icons: { network: { kind: "wired" } } });
assert.strictEqual(ids.icons.children[0].className, "icon wired");
ids.icons.children[0].listeners.click();
sandbox.tilemo.update({ uuid: "B", workspaces: ws, title: "", icons: { network: { kind: "none" } } });
assert.strictEqual(state(ids.icons.children[0]), "none");
assert.strictEqual(ids.icons.children[0].attrs["data-tip"], "No network");
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
const room = parseFloat(ids["title-text"].style.maxWidth);
assert.strictEqual(room, 1200 - 2 * 500 - 2 * 24);
assert.ok(1200 / 2 - room / 2 >= 300, "clear of the chips");
assert.ok(1200 / 2 + room / 2 <= 1200 - 500, "clear of the clocks and icons");
assert.ok(ids.clocks.classList.contains("compact"), "and the clocks shrank");

// Click targets: each item reaches the bar's top and bottom and halfway to
// each neighbor, a group's outer end reaches the bar's edge, and the room
// between the groups is left to the title.
const { hitInsets } = vm.runInContext('modules["./bar.js"]', sandbox);
const barBox = { left: 0, right: 400, top: 0, bottom: 36 };
const box = (left, right, top = 5, bottom = 31) => ({ left, right, top, bottom });
const lefts = [box(10, 40), box(44, 80), box(84, 120)];
// From the page's realm, so compared as plain data.
const hits = (...args) => JSON.parse(JSON.stringify(hitInsets(...args)));
const leftHits = hits(barBox, lefts, { start: true });
assert.deepStrictEqual(leftHits[0], { top: 5, bottom: 5, left: 10, right: 2 });
assert.deepStrictEqual(leftHits[1], { top: 5, bottom: 5, left: 2, right: 2 });
assert.deepStrictEqual(leftHits[2], { top: 5, bottom: 5, left: 2, right: 0 }, "stops short of the title's room");
// The clocks' line is shorter than the icons, and 14px from them.
const rights = [box(200, 300, 10, 26), box(314, 340), box(342, 390)];
const rightHits = hits(barBox, rights, { end: true });
assert.deepStrictEqual(rightHits[0], { top: 10, bottom: 10, left: 0, right: 7 });
assert.deepStrictEqual(rightHits[2], { top: 5, bottom: 5, left: 1, right: 10 });
// Every point from a group's outer edge to its last item's far side, top to
// bottom, is in exactly one item's target.
const owners = (items, hits, x, y) =>
  items.filter((r, i) => x >= r.left - hits[i].left && x < r.right + hits[i].right && y >= r.top - hits[i].top && y < r.bottom + hits[i].bottom).length;
for (const [items, hits, from, to] of [
  [lefts, leftHits, 0, 120],
  [rights, rightHits, 200, 400],
]) {
  for (let x = from; x < to; x += 0.5) {
    for (const y of [0, 4, 18, 35.5]) assert.strictEqual(owners(items, hits, x, y), 1, `one target at ${x},${y}`);
  }
}
assert.strictEqual(hits(barBox, [box(10, 50), box(45, 90)])[0].right, 0, "overlapping items reach no further");

// fit() gives each shown item its reach, as the --reach-* its ::before uses.
sandbox.tilemo.update({ uuid: "B", workspaces: [{ n: "in" }, { n: "web" }], title: "", icons: { mic: { muted: false } } });
ids.bar.rect = { ...barBox, width: 400, height: 36 };
const [inChip, webChip] = ids.workspaces.children;
inChip.rect = { ...box(10, 40), width: 30 };
webChip.rect = { ...box(44, 80), width: 36 };
ids.clocks.rect = { ...box(200, 300, 10, 26), width: 100 };
const micItem = ids.icons.children[0];
micItem.rect = { ...box(314, 390), width: 76 };
sandbox.tick();
const reachOf = (e) => ["top", "bottom", "left", "right"].map((k) => e.style[`--reach-${k}`]).join(" ");
assert.strictEqual(reachOf(inChip), "5px 5px 10px 2px");
assert.strictEqual(reachOf(webChip), "5px 5px 2px 0px");
assert.strictEqual(reachOf(ids.clocks), "10px 10px 0px 7px");
assert.strictEqual(reachOf(micItem), "5px 5px 7px 10px");
// The title's target is the free bar between the groups: here from the
// "web" chip's right edge to the clocks.
assert.strictEqual(reachOf(ids.title), "0px 0px 0px 0px", "no target with no title");
const { titleInsets } = vm.runInContext('modules["./bar.js"]', sandbox);
assert.strictEqual(JSON.stringify(titleInsets(barBox, box(150, 170, 10, 26), 80, 200)), '{"top":10,"bottom":10,"left":70,"right":30}');
sandbox.tilemo.update({ uuid: "B", workspaces: [{ n: "in" }, { n: "web" }], title: "Notes", icons: { mic: { muted: false } } });
const [inChip2, webChip2] = ids.workspaces.children;
inChip2.rect = { ...box(10, 40), width: 30 };
webChip2.rect = { ...box(44, 80), width: 36 };
ids.icons.children[0].rect = { ...box(314, 390), width: 76 };
ids.title.rect = { ...box(150, 170, 10, 26), width: 20 };
sandbox.tick();
assert.strictEqual(reachOf(ids.title), "10px 10px 70px 30px");

// Hover: tilemo says where the pointer is, and the target under it, its
// innermost, is marked .hover, one at a time, until the pointer leaves.
ids["title-text"].parent = ids.title;
sandbox.tilemo.update({
  uuid: "B",
  workspaces: [{ n: "in", apps: ["com.a", "com.b"], wins: [7] }],
  title: "Notes",
  app_icons: {},
  icons: { mic: { muted: false } },
});
const chip = ids.workspaces.children[0];
const [, winIcon, plainIcon] = chip.children;
const hoverOf = () =>
  [chip, winIcon, plainIcon, ids.title, ids.clocks, ids.icons.children[0]].filter((e) => e.classList.contains("hover"));
const point = (e) => {
  under = e;
  sandbox.tilemo.pointer(1, 1);
  return hoverOf();
};
assert.deepStrictEqual(point(winIcon), [winIcon], "a window icon, not its chip");
assert.deepStrictEqual(point(plainIcon), [chip], "an icon with no window to focus is the chip's");
assert.deepStrictEqual(point(chip.children[0]), [chip], "the chip's name");
sent.length = 0;
ids["title-text"].rect = { left: 150, right: 250, top: 10, bottom: 26, width: 100, height: 16 };
assert.deepStrictEqual(point(ids["title-text"]), [ids.title]);
// The page can't draw past its strip, so tilemo draws the uncut title's tip,
// centered on the title; once, however often the pointer moves.
point(ids["title-text"]);
assert.strictEqual(JSON.stringify(sent.filter((m) => m.tip)), JSON.stringify([{ uuid: "B", tip: { text: "Notes", x: 200 } }]));
assert.deepStrictEqual(point(ids.clocks), [ids.clocks]);
assert.strictEqual(JSON.stringify(sent.filter((m) => m.tip).pop()), JSON.stringify({ uuid: "B", tip: { text: "" } }), "gone off the title");
assert.deepStrictEqual(point(ids.icons.children[0]), [ids.icons.children[0]]);
assert.deepStrictEqual(point(ids.bar), [], "the bar itself is no target");
point(chip);
sandbox.tilemo.pointer(null);
assert.deepStrictEqual(hoverOf(), [], "gone once the pointer leaves");
// A title changing under the pointer changes the tip: it's always uncut.
point(ids["title-text"]);
const long = "x".repeat(500);
sandbox.tilemo.update({ uuid: "B", workspaces: [{ n: "in" }], title: long, icons: {} });
assert.strictEqual(sent.filter((m) => m.tip).pop().tip.text, long);
// An empty title is no target, and has no tip.
sandbox.tilemo.update({ uuid: "B", workspaces: [{ n: "in" }], title: "", icons: {} });
assert.strictEqual(JSON.stringify(sent.filter((m) => m.tip).pop().tip), JSON.stringify({ text: "" }));
assert.deepStrictEqual(point(ids.title), []);
sandbox.tilemo.pointer(null);
// A status item's tip, a cut chip's whole name and the camera's tip take
// the title's path, centered on the item; a window icon and a whole name
// have none.
sandbox.tilemo.update({
  uuid: "B",
  workspaces: [{ n: "in", apps: ["com.a"], wins: [7] }, { n: "ABC-123 fix the login page" }],
  title: "",
  app_icons: {},
  icons: { camera: { in_use: true }, mic: { muted: true } },
});
const tipOf = () => JSON.stringify(sent.filter((m) => m.tip).pop().tip);
const [shortChip, cutChip] = ids.workspaces.children;
const [camera, mutedMicIcon] = ids.icons.children;
cutChip.children[0].parent = cutChip;
cutChip.rect = { left: 40, right: 140, top: 4, bottom: 32, width: 100, height: 28 };
point(cutChip.children[0]);
assert.strictEqual(tipOf(), JSON.stringify({ text: "ABC-123 fix the login page", x: 90 }));
mutedMicIcon.rect = { left: 1800, right: 1820, top: 10, bottom: 26, width: 20, height: 16 };
point(mutedMicIcon);
assert.strictEqual(tipOf(), JSON.stringify({ text: "Microphone muted", x: 1810 }));
point(shortChip);
assert.strictEqual(tipOf(), JSON.stringify({ text: "" }), "a whole name has no tip");
point(shortChip.children[1]);
assert.strictEqual(tipOf(), JSON.stringify({ text: "" }), "nor a window icon");
camera.parent = ids.icons;
camera.rect = { left: 1770, right: 1786, top: 10, bottom: 26, width: 16, height: 16 };
assert.deepStrictEqual(point(camera).length, 0, "the camera is no target");
assert.ok(!camera.classList.contains("hover"));
assert.strictEqual(tipOf(), JSON.stringify({ text: "Camera in use", x: 1778 }), "but has a tip");
sandbox.tilemo.pointer(null);
assert.strictEqual(tipOf(), JSON.stringify({ text: "" }), "gone once the pointer leaves");
under = null;

// Off, Wi-Fi shows its bars dimmed and no name.
sandbox.tilemo.update({ uuid: "B", workspaces: ws, title: "", icons: { wifi: { on: false, bars: 0 } } });
assert.strictEqual(state(ids.icons.children[0]), "off");
assert.strictEqual(ids.icons.children[0].attrs["data-tip"], "Wi-Fi off");
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
// Presenting, keep awake says so in words, and a click ends presenter mode
// rather than turning keep awake off alone.
sent.length = 0;
sandbox.tilemo.update({ uuid: "B", workspaces: ws, title: "", icons: { awake: { on: true, presenting: true } } });
const presenting = ids.icons.children[0];
assert.strictEqual(presenting.className, "icon awake");
assert.strictEqual(state(presenting), "presenting");
assert.strictEqual(presenting.attrs["data-tip"], "Presenting: Do Not Disturb and keep awake");
assert.strictEqual(presenting.children[0].textContent, "Presenting");
presenting.listeners.click();
assert.strictEqual(JSON.stringify(sent.filter((m) => !m.goodClocks)), JSON.stringify([{ uuid: "B", toggle: "presenter" }]));
console.log("bar page: ok");
