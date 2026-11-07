// Runs the volume popover's script (hammerspoon/tide/dashboard/volume.js)
// against a small fake DOM, and checks what tide.update() draws and what
// the slider, mute, outputs, settings and Esc send back.

const fs = require("fs");
const vm = require("vm");
const assert = require("assert");

class Element {
  constructor(tag, id) {
    this.tag = tag;
    this.id = id;
    this.children = [];
    this.attrs = {};
    this.listeners = {};
    this.textContent = "";
    this.innerHTML = "";
    this.className = "";
    this.hidden = false;
    this.disabled = false;
    this.value = "";
  }
  addEventListener(type, f) {
    this.listeners[type] = f;
  }
  setAttribute(k, v) {
    this.attrs[k] = v;
  }
  append(...xs) {
    this.children.push(...xs);
  }
  replaceChildren() {
    this.children = [];
  }
}

const ids = {};
for (const id of ["name", "mute", "slider", "percent", "none", "outputs", "settings"]) ids[id] = new Element("div", id);
const docListeners = {};
const sent = [];
const sandbox = {
  document: {
    getElementById: (id) => ids[id],
    createElement: (tag) => new Element(tag),
    addEventListener: (type, f) => (docListeners[type] = f),
  },
  window: { webkit: { messageHandlers: { tide: { postMessage: (m) => sent.push(m) } } } },
};
vm.createContext(sandbox);
vm.runInContext(fs.readFileSync(process.argv[2], "utf8"), sandbox);
const update = sandbox.window.tide.update;
const last = () => JSON.stringify(sent.at(-1));

// macOS's own volume: the slider sets it as it moves, and on release.
update({
  name: "MacBook Speakers",
  volume: 40,
  muted: false,
  can_mute: true,
  live: true,
  outputs: [
    { uid: "a", name: "LG", current: false },
    { uid: "b", name: "MacBook Speakers", current: true },
  ],
});
assert.strictEqual(ids.name.textContent, "MacBook Speakers");
assert.strictEqual(ids.slider.value, "40");
assert.strictEqual(ids.percent.textContent, "40%");
assert.strictEqual(ids.none.hidden, true);
assert.strictEqual(ids.mute.disabled, false);
assert.strictEqual(ids.mute.attrs["aria-label"], "Mute");
ids.slider.listeners.input({ target: { value: "55" } });
assert.strictEqual(last(), JSON.stringify({ volume: 55 }), "live: sent as it moves");
assert.strictEqual(ids.percent.textContent, "55%");
update({ name: "MacBook Speakers", volume: 41, muted: false, can_mute: true, live: true, outputs: [] });
assert.strictEqual(ids.slider.value, "40", "an update doesn't move the slider under a drag");
ids.slider.listeners.change({ target: { value: "60" } });
assert.strictEqual(last(), JSON.stringify({ volume: 60 }));
ids.mute.listeners.click();
assert.strictEqual(last(), JSON.stringify({ mute: true }));

// The outputs: the one in use is checked, another is a click away.
update({
  name: "MacBook Speakers",
  volume: 40,
  muted: true,
  can_mute: true,
  live: true,
  outputs: [
    { uid: "a", name: "LG", current: false },
    { uid: "b", name: "MacBook Speakers", current: true },
  ],
});
assert.strictEqual(ids.percent.textContent, "0%", "muted");
assert.strictEqual(ids.mute.attrs["aria-label"], "Unmute");
ids.mute.listeners.click();
assert.strictEqual(last(), JSON.stringify({ mute: false }));
const rows = ids.outputs.children;
assert.deepStrictEqual(rows.map((r) => r.children[1].textContent), ["LG", "MacBook Speakers"]);
assert.deepStrictEqual(rows.map((r) => r.children[0].textContent), ["", "✓"]);
assert.strictEqual(rows[1].listeners.click, undefined, "the one in use does nothing");
rows[0].listeners.click();
assert.strictEqual(last(), JSON.stringify({ output: "a" }));

// A DDC monitor: set once the slider's let go.
sent.length = 0;
update({ name: "LG", volume: 30, muted: false, can_mute: true, live: false, outputs: [] });
ids.slider.listeners.input({ target: { value: "35" } });
assert.strictEqual(sent.length, 0, "not while dragging");
ids.slider.listeners.change({ target: { value: "35" } });
assert.strictEqual(last(), JSON.stringify({ volume: 35 }));

// No volume control: no slider, says so, and mute only if it can.
update({ name: "LG", muted: false, can_mute: false, live: true, outputs: [] });
assert.strictEqual(ids.slider.hidden, true);
assert.strictEqual(ids.none.hidden, false);
assert.strictEqual(ids.mute.disabled, true);
update(null);
assert.strictEqual(ids.name.textContent, "No output");

ids.settings.listeners.click();
assert.strictEqual(last(), JSON.stringify({ settings: true }));
docListeners.keydown({ key: "Escape" });
assert.strictEqual(last(), JSON.stringify({ close: true }));
console.log("volume page: ok");
