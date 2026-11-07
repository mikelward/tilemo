#!/usr/bin/env node
// Render the bar's page (from mocks/page.lua, the file named on the command
// line) in a few fixed states, to PNGs beside this script.
//
// Needs Playwright with Chromium (a global install works when NODE_PATH
// points at it; `make mocks` sets that up), and skips with a note without
// it. The clock and time zone are fixed, so a re-render only changes when
// the bar does. A script error on the page fails the render.

const path = require("path");

let chromium;
try {
  ({ chromium } = require("playwright"));
} catch {
  console.log("SKIP mocks: no Playwright");
  process.exit(0);
}

// The workspaces in bar order, by name, "in" first (SPEC.md §6.1).
const ws = (list) => list.map(([n, rest]) => ({ n, ...(rest || {}) }));

// Stand-in app icons: a rounded square in a color with a letter, as SVG
// data URLs, so the mocks need no real app's artwork.
const appIcon = (color, letter) =>
  "data:image/svg+xml," +
  encodeURIComponent(
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32"><rect width="32" height="32" rx="7" fill="${color}"/>` +
      `<text x="16" y="22" font-family="sans-serif" font-size="18" font-weight="bold" fill="white" text-anchor="middle">${letter}</text></svg>`,
  );
const APP_ICONS = {
  mail: appIcon("#2f7de1", "M"),
  term: appIcon("#333333", ">"),
  web: appIcon("#e8710a", "W"),
  notes: appIcon("#e5b100", "N"),
  chat: appIcon("#7b4bd8", "C"),
  code: appIcon("#1f9d55", "{"),
};

const STATES = [
  {
    name: "bar-wide",
    width: 1920,
    state: {
      uuid: "A",
      workspaces: ws([
        ["in", { current: true, occupied: true, urgent: true, apps: ["chat"] }],
        ["tide", { occupied: true }],
        ["ABC-123", { occupied: true }],
        ["review", { occupied: true, urgent: true, apps: ["web"] }],
      ]),
      title: "Inbox (3) — Mail",
      app_icons: APP_ICONS,
      icons: {
        source: { label: "DVO", name: "Dvorak" },
        awake: { on: true },
        camera: { in_use: true },
        mic: { muted: false },
        volume: { level: "mid", muted: false, text: "45%", tip: "Sound 45%" },
        wifi: { on: true, bars: 3, name: "home" },
        network: { kind: "wifi", vpn: true },
        battery: { percent: 84, charging: true, text: "84%", tip: "Battery 84%, charging, full in 0:35" },
        sysmon: { text: "23%", tone: "normal", tip: "CPU 23%" },
      },
    },
  },
  {
    name: "bar-crowded",
    width: 1280,
    state: {
      uuid: "A",
      workspaces: ws([
        ["in", { occupied: true }],
        ["design doc", { current: true, occupied: true }],
        ["dotfiles", { occupied: true }],
        ["the quarterly planning spreadsheet", { occupied: true }],
        ["standup", { occupied: true, urgent: true, apps: ["chat"] }],
      ]),
      app_icons: APP_ICONS,
      title: "A very long document title that won't fit in the middle of the bar — Notes",
      icons: {
        mic: { muted: false },
        volume: { level: "high", muted: false, text: "80%", tip: "Sound 80%" },
        wifi: { on: true, bars: 2 },
        network: { kind: "wifi" },
        battery: { percent: 52, charging: false, text: "52%", tip: "Battery 52%, 3:12 left" },
      },
    },
  },
  {
    // A workspace with many windows wanting attention: five icons, then how
    // many more, and an app with no icon as a blank square.
    name: "bar-apps",
    width: 1440,
    state: {
      uuid: "A",
      workspaces: ws([
        ["in", { occupied: true }],
        ["src", { current: true, occupied: true, urgent: true, apps: ["term", "web", "code", "term", "unknown"], more: 3 }],
      ]),
      title: "~/src — Terminal",
      app_icons: APP_ICONS,
      icons: {
        volume: { level: "fixed", muted: false, fixed: true, can_mute: false, tip: "Sound: LG HDR 4K has no volume control" },
        network: { kind: "wired" },
      },
    },
  },
  {
    name: "bar-quiet",
    width: 1440,
    state: {
      uuid: "A",
      workspaces: ws([["in", { current: true }]]),
      title: "",
      icons: {
        awake: { on: false },
        mic: { muted: true },
        volume: { level: "mute", muted: true, text: "30%", tip: "Sound muted" },
        network: { kind: "wired" },
        battery: { percent: 15, charging: false, text: "15%", tip: "Battery 15%, 0:40 left" },
        sysmon: { text: "97%", tone: "warn", tip: "CPU 97%, hot" },
      },
    },
  },
  {
    // A 14-inch MacBook Pro's own display: the bar over the notch, its
    // middle clear, no title, and the chips that would reach the notch
    // behind "+n".
    name: "bar-notch",
    width: 1512,
    state: {
      uuid: "A",
      notch: true,
      workspaces: ws([
        ["in", { occupied: true }],
        ["mail", { occupied: true }],
        ["design doc", { occupied: true }],
        ["dotfiles", { occupied: true }],
        ["quarterly planning", { occupied: true }],
        ["standup", { occupied: true }],
        ["recipes", { occupied: true }],
        ["taxes", { occupied: true }],
        ["music", { occupied: true }],
        ["src", { current: true, occupied: true }],
      ]),
      title: "",
      icons: {
        awake: { on: false },
        mic: { muted: false },
        volume: { level: "mid", muted: false, text: "40%", tip: "Sound 40%" },
        wifi: { on: true, bars: 3, name: "home" },
        network: { kind: "wifi" },
        battery: { percent: 64, charging: false, text: "64%" },
        sysmon: { text: "12%", tone: "normal", tip: "CPU 12%" },
      },
    },
  },
];

// Hover, as tide tells the page where the pointer is: over an item's
// edge, so the mock shows its whole target, in light and dark.
const HOVER = {
  uuid: "A",
  workspaces: ws([
    ["in", { occupied: true }],
    ["src", { current: true, occupied: true, apps: ["term", "web"] }],
    ["docs", { occupied: true }],
  ]),
  title: "~/src — Terminal",
  app_icons: APP_ICONS,
  icons: {
    mic: { muted: false },
    volume: { level: "mid", muted: false, text: "40%", tip: "Sound 40%" },
    network: { kind: "wired" },
    battery: { percent: 84, charging: false, text: "84%" },
  },
};
STATES.push(
  { name: "bar-hover-chip", width: 1440, state: HOVER, pointer: ["#workspaces button:nth-child(3)"] },
  { name: "bar-hover-icon", width: 1440, state: HOVER, pointer: ["#icons .battery"], scheme: "dark" },
  { name: "bar-hover-clocks", width: 1440, state: HOVER, pointer: ["#clocks"], scheme: "dark" },
  // Keep awake beside the microphone: the same room around each on hover.
  { name: "bar-hover-awake", width: 1440, state: { ...HOVER, icons: { awake: { on: false }, ...HOVER.icons } }, pointer: ["#icons .awake"] },
);

(async () => {
  const page = process.argv[2];
  if (!page) {
    console.error("usage: render.cjs bar-page.html");
    process.exit(2);
  }
  const browser = await chromium.launch();
  let failed = false;
  try {
    for (const { name, width, state, pointer, scheme } of STATES) {
      const context = await browser.newContext({
        viewport: { width, height: 36 },
        deviceScaleFactor: 2,
        timezoneId: "Europe/Dublin",
        locale: "en-US",
        colorScheme: scheme ?? "light",
      });
      const tab = await context.newPage();
      tab.on("pageerror", (e) => {
        console.error(`${name}: ${e.message}`);
        failed = true;
      });
      await tab.clock.setFixedTime(new Date("2026-10-26T09:30:00Z"));
      await tab.goto("file://" + path.resolve(page));
      // The Apple logo is a glyph only Apple's fonts have; here a dot
      // stands in for it, where a Mac draws the logo.
      await tab.evaluate(() => {
        document.getElementById("apple").textContent = "\u25cf";
      });
      await tab.evaluate((s) => window.tide.update(s), state);
      if (pointer) {
        // At the item's middle, 1px from the bar's top: outside its own box.
        await tab.evaluate(([sel]) => {
          const r = document.querySelector(sel).getBoundingClientRect();
          window.tide.pointer(Math.round((r.left + r.right) / 2), 1);
        }, pointer);
      }
      const out = path.join(__dirname, `${name}.png`);
      await tab.screenshot({ path: out });
      console.log(`wrote ${path.relative(process.cwd(), out)}`);
      await context.close();
    }
  } finally {
    await browser.close();
  }
  process.exit(failed ? 1 : 0);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
