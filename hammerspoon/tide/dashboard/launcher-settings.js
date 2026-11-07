// The dashboard launcher's stand-in for tileco's settings.js (SPEC.md §9.2):
// tileco's page loads its settings from Chrome's storage, and here they're
// tide's clocks, from its clocks files, with the Mac's apps as its app keys.
// The clock view's defaults are tide's settings.js's.

import { DEFAULT_SETTINGS as TIDE_DEFAULTS } from "./settings.js";
import { currentSettings, feed } from "./launcher-chrome.js";

export const SETTINGS_KEY = "settings";
export const DEFAULT_SETTINGS = TIDE_DEFAULTS;

export async function load() {
  return { settings: { ...currentSettings(), apps: feed.apps }, errors: [] };
}
