// tilemo's stand-in for tileco's src/settings.js, which reads chrome.storage:
// the settings tileco's clock modules need. The clocks come from tide's
// ~/.config/tide/clocks.json and clocks.local.json (SPEC.md §15), read with
// tide's own module, so one file serves both desktops. With neither, they're
// SPEC.md §8's, tileco's defaults.

import { DAY, DEFAULT_CLOCKS, WORK, abbreviation, checkZone } from "./clocks.js";
import { cityLabel, loadClocks } from "./tide-clocks.js";

export const DEFAULT_SETTINGS = { clocks: DEFAULT_CLOCKS, day: DAY, work: WORK };

// tilemo's default list as clocks.json would hold it. It stands in for that
// file where there's none, so the settings page starts from the clocks the
// bar shows, and its first change copies them into clocks.local.json.
export const DEFAULT_FILE = JSON.stringify(DEFAULT_CLOCKS.map(({ zone, label }) => ({ zone, label })));

// The two files' texts as tide's module takes them, from tilemo's
// { shared, local }, each a file's text or absent when there's none.
export function sharedText(files) {
  return typeof files?.shared === "string" ? files.shared : DEFAULT_FILE;
}

export function localText(files) {
  return typeof files?.local === "string" ? files.local : null;
}

// Whether `zone` is one Intl knows, as tide-tz's check is on tide.
export function isZone(zone) {
  try {
    checkZone(zone);
    return true;
  } catch {
    return false;
  }
}

// tide's {zone, label} as tileco's clocks take it: a label of "abbr" is the
// zone's abbreviation at the time, and the city is the zone ID's.
function tilecoClock(c) {
  return {
    zone: c.zone,
    get label() {
      return c.label === "abbr" ? abbreviation(new Date(), c.zone) : c.label;
    },
    city: cityLabel(c.zone),
  };
}

// The settings from tide's files, as { settings, errors }. A file that
// doesn't parse, or names a zone Intl doesn't know, keeps `last`'s clocks,
// and `errors` names it.
export function loadSettings(files, last = null) {
  const lastGood = last?.tideClocks ?? JSON.parse(DEFAULT_FILE);
  const loaded = loadClocks(sharedText(files), localText(files), lastGood, isZone);
  return {
    settings: { clocks: loaded.clocks.map(tilecoClock), tideClocks: loaded.clocks, day: DAY, work: WORK },
    errors: loaded.errors,
  };
}

// A page's settings for tilemo.update(state). Where a file is wrong, the
// clocks stay the last good ones: the page's own, or for a page just opened,
// the ones tilemo kept from the pages before it (state.goodClocks).
export function nextSettings(state, settings) {
  const kept = Array.isArray(state.goodClocks) ? state.goodClocks : undefined;
  return loadSettings(state.clockFiles, settings.tideClocks ? settings : { tideClocks: kept });
}
