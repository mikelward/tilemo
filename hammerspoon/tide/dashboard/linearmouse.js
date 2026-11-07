// tide's Mouse settings in LinearMouse's config (SPEC.md §10): tide's
// own, run in JavaScriptCore beside tide's input.mjs (tide-input.js), so
// the rest of linearmouse.json stays as it was. hs.json can't tell [] from
// {}, and LinearMouse rewrites the file whenever its own window changes it.

import { shown } from "./tide-input.js";

// LinearMouse's lines a notch at tide's 1×: three, as macOS's own notch
// moves, so tide's 3× is nine.
export const LINES_AT_1X = 3;

const isObject = (v) => v !== null && typeof v === "object" && !Array.isArray(v);

// A scroll speed as whole lines a notch, LinearMouse's `distance`: at least
// one.
export function linesFor(scroll) {
  return Math.max(1, Math.round(scroll * LINES_AT_1X));
}

// What LinearMouse should do for every mouse, from tide's settings in
// effect (`input`, as loadInput gives it): lines a notch, and whether to
// reverse the wheel. macOS has one natural-scrolling switch for the mouse
// and the trackpad (`natural`, com.apple.swipescrolldirection), so the
// mouse is reversed when tide's mouse setting differs from it.
export function mouseScrolling(input, natural) {
  return {
    lines: linesFor(shown(input, "mouse", "scrollSpeed")),
    reverse: shown(input, "mouse", "naturalScroll") !== natural,
  };
}

// Whether `scheme` is for every mouse and nothing else: one condition, a
// device of the mouse category alone, as LinearMouse's own "every mouse"
// is. Its `if` and `category` may each be one or a list.
function everyMouse(scheme) {
  if (!isObject(scheme)) return false;
  const conditions = Array.isArray(scheme.if) ? scheme.if : [scheme.if];
  if (conditions.length !== 1 || !isObject(conditions[0])) return false;
  const c = conditions[0];
  if (Object.keys(c).some((k) => k !== "device") || !isObject(c.device)) return false;
  if (Object.keys(c.device).some((k) => k !== "category")) return false;
  const categories = Array.isArray(c.device.category) ? c.device.category : [c.device.category];
  return categories.length === 1 && categories[0] === "mouse";
}

// A LinearMouse pair with its vertical set to `value`, keeping its
// horizontal; one value alone stands for both directions.
function withVertical(given, value) {
  if (isObject(given)) return { ...given, vertical: value };
  if (given === undefined || given === null) return { vertical: value };
  return { vertical: value, horizontal: given };
}

// linearmouse.json's text (null when there's none) with every mouse
// scrolling `lines` a notch, reversed or not. LinearMouse merges schemes in
// order and a later one wins, so these go in a scheme for every mouse that's
// last: the last scheme itself when it's one, else a new one appended that
// sets only their vertical values. LinearMouse merges each direction on its
// own, so horizontal settings, like every other, keep their schemes and
// their precedence. Returns
// { text } when that changes the file, {} when it's as it should be already,
// or { error }.
export function withMouseScrolling(text, lines, reverse) {
  let config = {};
  if (text !== null && text !== undefined) {
    try {
      config = JSON.parse(text);
    } catch (e) {
      return { error: "linearmouse.json isn't JSON" };
    }
  }
  if (!isObject(config)) return { error: "linearmouse.json isn't an object" };
  const schemes = config.schemes === undefined ? [] : config.schemes;
  if (!Array.isArray(schemes)) return { error: "linearmouse.json's schemes aren't a list" };
  let at = -1;
  schemes.forEach((s, i) => {
    if (everyMouse(s)) at = i;
  });
  const base = at >= 0 ? schemes[at] : undefined;
  if (base && base.scrolling !== undefined && !isObject(base.scrolling)) {
    return { error: `linearmouse.json's schemes[${at}].scrolling isn't an object` };
  }
  const last = at >= 0 && at === schemes.length - 1;
  const scrolling = (last && base.scrolling) || {};
  const next = last
    ? {
        ...base,
        scrolling: {
          ...scrolling,
          distance: withVertical(scrolling.distance, lines),
          reverse: withVertical(scrolling.reverse, reverse),
        },
      }
    : { if: { device: { category: "mouse" } }, scrolling: { distance: { vertical: lines }, reverse: { vertical: reverse } } };
  const out = { ...config, schemes: last ? schemes.slice(0, -1).concat([next]) : schemes.concat([next]) };
  // Compared as JSON, not as text: LinearMouse spaces the file its own way.
  if (text !== null && text !== undefined && JSON.stringify(config) === JSON.stringify(out)) return {};
  return { text: JSON.stringify(out, null, 2) + "\n" };
}

// A mouse's pointer, as the Mac's Speed and Acceleration rows set it:
// LinearMouse's own `pointer.speed` (0 to 1) and `pointer.acceleration`
// (macOS's, 0 to 20), kept in linearmouse.json, not tide's input.json. A
// curve tuned for macOS means nothing to libinput's, so the Mac keeps its
// own (SPEC.md §10).
export const POINTER_KEYS = Object.freeze(["speed", "acceleration"]);
export const POINTER_LADDERS = Object.freeze({
  speed: Object.freeze([0.05, 0.1, 0.15, 0.2, 0.25, 0.3, 0.35, 0.4, 0.45, 0.5, 0.6, 0.7, 0.8, 0.9, 1]),
  acceleration: Object.freeze([0, 0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3, 4]),
});
// Where − and + start from while LinearMouse leaves one to macOS:
// setup-macos's, tried by hand on a PC mouse.
export const POINTER_START = Object.freeze({ speed: 0.35, acceleration: 1.5 });

function parsed(text) {
  if (text === null || text === undefined) return { config: {} };
  try {
    return { config: JSON.parse(text) };
  } catch (e) {
    return { error: "linearmouse.json isn't JSON" };
  }
}

// What every mouse's pointer is set to: each of POINTER_KEYS that's set,
// as the last every-mouse scheme that sets it has it, as LinearMouse
// merges them. One that's missing is left to macOS. {} when the file
// can't say.
export function mousePointer(text) {
  const { config, error } = parsed(text);
  const out = {};
  if (error || !isObject(config) || !Array.isArray(config.schemes)) return out;
  for (const s of config.schemes) {
    if (!everyMouse(s) || !isObject(s.pointer)) continue;
    for (const k of POINTER_KEYS) {
      if (typeof s.pointer[k] === "number") out[k] = s.pointer[k];
    }
  }
  return out;
}

// The next rung of `key`'s ladder from `value` (undefined, left to macOS:
// POINTER_START, which is where the first step lands), up (1) or down (-1), staying put
// at either end.
export function steppedPointer(key, value, step) {
  const ladder = POINTER_LADDERS[key];
  if (value === null || value === undefined) return POINTER_START[key];
  if (step > 0) {
    const up = ladder.find((v) => v > value);
    return up === undefined ? value : up;
  }
  const down = ladder.filter((v) => v < value);
  return down.length === 0 ? value : down[down.length - 1];
}

// linearmouse.json's text with every mouse's pointer `key` set to `value`,
// in the same last every-mouse scheme the scrolling goes in, so it wins.
// Returns { text } when that changes the file, {} when it doesn't, or
// { error }.
export function withMousePointer(text, key, value) {
  if (!POINTER_KEYS.includes(key)) return { error: `"${key}" isn't a pointer setting; expected ${POINTER_KEYS.join(" or ")}` };
  const ladder = POINTER_LADDERS[key];
  if (typeof value !== "number" || !isFinite(value) || value < 0 || value > ladder[ladder.length - 1]) {
    return { error: `pointer ${key} must be from 0 to ${ladder[ladder.length - 1]}` };
  }
  const { config, error } = parsed(text);
  if (error) return { error };
  if (!isObject(config)) return { error: "linearmouse.json isn't an object" };
  const schemes = config.schemes === undefined ? [] : config.schemes;
  if (!Array.isArray(schemes)) return { error: "linearmouse.json's schemes aren't a list" };
  const lastAt = schemes.length - 1;
  const last = lastAt >= 0 && everyMouse(schemes[lastAt]) ? schemes[lastAt] : null;
  if (last && last.pointer !== undefined && !isObject(last.pointer)) {
    return { error: `linearmouse.json's schemes[${lastAt}].pointer isn't an object` };
  }
  const next = last
    ? { ...last, pointer: { ...(last.pointer || {}), [key]: value } }
    : { if: { device: { category: "mouse" } }, pointer: { [key]: value } };
  const out = { ...config, schemes: last ? schemes.slice(0, -1).concat([next]) : schemes.concat([next]) };
  if (text !== null && text !== undefined && JSON.stringify(config) === JSON.stringify(out)) return {};
  return { text: JSON.stringify(out, null, 2) + "\n" };
}
