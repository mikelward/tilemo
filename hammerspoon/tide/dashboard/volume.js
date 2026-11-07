// The volume popover's page (SPEC.md §8): volume.lua's state in, and what a
// click, a drag or a key asks for out, as messages to tide.

const send = (msg) => window.webkit?.messageHandlers?.tide?.postMessage(msg);
const $ = (id) => document.getElementById(id);

// The speaker, as the bar draws it (bar.js's PATHS), with three waves or
// its cross.
const SPEAKER = '<path d="M2.5 6h2.5l3.5-3v10l-3.5-3h-2.5z"/>';
const CROSS = '<path d="M11 6.5l3 3M14 6.5l-3 3"/>';
const WAVES =
  '<path d="M10.5 6.5a2 2 0 0 1 0 3"/><path d="M12 5a4 4 0 0 1 0 6"/><path d="M13.5 3.5a6.4 6.4 0 0 1 0 9"/>';
const speaker = (muted) =>
  '<svg viewBox="0 0 16 16" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.5" ' +
  `stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${SPEAKER}${muted ? CROSS : WAVES}</svg>`;

let state = { outputs: [] };
// While dragging, an update from tide mustn't move the slider under you.
let dragging = false;

function update(s) {
  state = s || { outputs: [] };
  $("name").textContent = state.name || "No output";
  const fixed = state.volume === undefined || state.volume === null;
  const slider = $("slider");
  slider.hidden = fixed;
  $("percent").hidden = fixed;
  $("none").hidden = !fixed;
  if (!fixed && !dragging) slider.value = String(state.volume);
  $("percent").textContent = fixed ? "" : `${state.muted ? 0 : state.volume}%`;
  const mute = $("mute");
  mute.innerHTML = speaker(state.muted);
  mute.disabled = !state.can_mute;
  mute.setAttribute("aria-label", state.muted ? "Unmute" : "Mute");
  const list = $("outputs");
  list.replaceChildren();
  for (const o of state.outputs || []) {
    const b = document.createElement("button");
    b.type = "button";
    b.className = "row";
    const check = document.createElement("span");
    check.className = "check";
    check.textContent = o.current ? "✓" : "";
    const name = document.createElement("span");
    name.className = "name";
    name.textContent = o.name;
    b.append(check, name);
    if (!o.current) b.addEventListener("click", () => send({ output: o.uid }));
    list.append(b);
  }
}

// macOS's own volume follows the slider as it moves; a DDC monitor's is
// set once it's let go, since each change is a slow run of its tool.
$("slider").addEventListener("input", (e) => {
  dragging = true;
  $("percent").textContent = `${e.target.value}%`;
  if (state.live) send({ volume: Number(e.target.value) });
});
$("slider").addEventListener("change", (e) => {
  dragging = false;
  send({ volume: Number(e.target.value) });
});
$("mute").addEventListener("click", () => send({ mute: !state.muted }));
$("settings").addEventListener("click", () => send({ settings: true }));
document.addEventListener("keydown", (e) => {
  if (e.key === "Escape") send({ close: true });
});

window.tide = { update };
