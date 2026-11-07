// Stand-ins for the Chrome extension APIs tileco's launcher page
// (launcherview.js) calls, so it runs unchanged in tide's webview on the Mac
// (SPEC.md §9.2). They answer from the feed tide sends (launcherpage.lua's
// feed(), through tide.open() and tide.update()), and what the page asks
// of Chrome goes to tide through the message handler:
//   - its tabs are the switcher's windows and browser tabs;
//   - its settings' apps are the Mac's apps and System Settings' panes;
//   - its manifest's commands are tide's;
//   - storage holds the view and the windows' workspaces, keep awake, and
//     the extras card dismissed, since the Mac needs none of them;
//   - every permission is granted: nothing here asks Chrome for one.
// tide's clocks come from its clocks files, as on the dashboard.

import { DEFAULT_SETTINGS, nextSettings } from "./settings.js";

const send = (msg) => window.webkit?.messageHandlers?.tide?.postMessage(msg);

export const feed = { tabs: [], apps: [], actions: [], commands: [], sections: [], view: null, state: null, keepAwake: false };

let settings = DEFAULT_SETTINGS;
let goodSent = null;
const session = {};
const changeListeners = [];

export function currentSettings() {
  return settings;
}

// The keys `keys` asks for out of `from`, as chrome.storage's get() gives
// them: one key, a list, or every key for null.
function pick(from, keys) {
  const wanted = keys == null ? Object.keys(from) : Array.isArray(keys) ? keys : [keys];
  const out = {};
  for (const k of wanted) if (from[k] !== undefined && from[k] !== null) out[k] = from[k];
  return out;
}

const event = (list = []) => ({ addListener: (fn) => list.push(fn) });

globalThis.chrome = {
  runtime: {
    sendMessage: async (msg) => send(msg),
    getManifest: () => ({ commands: Object.fromEntries(feed.commands.map((c) => [c.name, { description: c.description }])) }),
    getURL: (path) => `tide-page://launcher/${path}`,
    // tide tiles and has workspaces, as tileco does only on chromeOS.
    getPlatformInfo: async () => ({ os: "cros" }),
    // Tide Settings, at the section the page left in session storage.
    openOptionsPage: async () => {
      const section = session.settingsSection ?? null;
      delete session.settingsSection;
      send({ settings: section ?? true });
    },
    reload: () => send({ reload: true }),
  },
  windows: { getCurrent: async () => ({ id: "here" }) },
  tabs: { query: async () => feed.tabs.map((t) => ({ ...t })) },
  permissions: {
    contains: async () => true,
    request: async () => true,
    onAdded: event(),
    onRemoved: event(),
  },
  storage: {
    local: {
      get: async (keys) => pick({ view: feed.view, state: feed.state, extrasDismissed: true }, keys),
      set: async () => {},
    },
    session: {
      get: async (keys) => pick({ ...session, keepAwake: feed.keepAwake }, keys),
      set: async (values) => {
        Object.assign(session, values);
      },
    },
    sync: { get: async () => ({}), set: async () => {} },
    onChanged: event(changeListeners),
  },
};

// The page closes itself after a choice, on Esc and on losing focus; tide
// closes its window.
window.close = () => send({ close: true });

// A new feed: the page draws it as it draws a change in Chrome's storage.
// A clocks file that's wrong keeps the clocks, and tide hears which and why,
// and the clocks to keep, as from the dashboard.
export function update(next) {
  Object.assign(feed, next);
  // Lua's JSON can't tell an empty list from an empty object.
  const list = (x) => (Array.isArray(x) ? x : []);
  for (const k of ["tabs", "apps", "actions", "commands", "sections"]) feed[k] = list(feed[k]);
  if (feed.view) for (const k of ["bar", "made", "urgent"]) feed.view[k] = list(feed.view[k]);
  const loaded = nextSettings({ clockFiles: feed.clockFiles ?? {}, goodClocks: feed.goodClocks }, settings);
  settings = loaded.settings;
  if (loaded.errors.length > 0) send({ clockErrors: loaded.errors });
  const good = JSON.stringify(settings.tideClocks);
  if (good !== goodSent) {
    goodSent = good;
    send({ goodClocks: settings.tideClocks });
  }
  for (const fn of changeListeners) fn({ view: {}, state: {}, settings: {} }, "local");
  for (const fn of changeListeners) fn({ keepAwake: {} }, "session");
}
