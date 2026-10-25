// timo's stand-in for tico's src/settings.js, which reads chrome.storage:
// the settings tico's clock modules need, at tico's defaults.

import { DAY, DEFAULT_CLOCKS, WORK } from "./clocks.js";

export const DEFAULT_SETTINGS = { clocks: DEFAULT_CLOCKS, day: DAY, work: WORK };
