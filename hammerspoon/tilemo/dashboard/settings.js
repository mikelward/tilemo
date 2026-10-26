// tilemo's stand-in for tileco's src/settings.js, which reads chrome.storage:
// the settings tileco's clock modules need, at tileco's defaults.

import { DAY, DEFAULT_CLOCKS, WORK } from "./clocks.js";

export const DEFAULT_SETTINGS = { clocks: DEFAULT_CLOCKS, day: DAY, work: WORK };
