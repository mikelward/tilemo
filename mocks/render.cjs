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

const ws = (spec) =>
  Array.from({ length: 9 }, (_, i) => ({ n: i + 1, ...(spec[i + 1] || {}) }));

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
      workspaces: ws({
        1: { current: true, occupied: true, apps: ["mail", "web"] },
        2: { occupied: true, apps: ["term", "term"] },
        3: { elsewhere: true, occupied: true, apps: ["code"] },
        5: { occupied: true, urgent: true, apps: ["chat"] },
      }),
      title: "Inbox (3) — Mail",
      app_icons: APP_ICONS,
      icons: {
        source: { label: "DVO", name: "Dvorak" },
        awake: { on: true },
        camera: { in_use: true },
        mic: { muted: false },
        volume: { level: "mid", muted: false },
        wifi: { on: true, bars: 3, name: "home" },
        network: { kind: "wifi" },
        battery: { percent: 84, charging: true, text: "84%", tip: "Battery 84%, charging, full in 0:35" },
      },
    },
  },
  {
    name: "bar-crowded",
    width: 1280,
    state: {
      uuid: "A",
      workspaces: ws({
        1: { occupied: true, apps: ["web"] },
        2: { current: true, occupied: true, apps: ["notes"] },
        4: { occupied: true, apps: ["term"] },
        6: { occupied: true, apps: ["chat"] },
        9: { occupied: true, apps: ["mail"] },
      }),
      app_icons: APP_ICONS,
      title: "A very long document title that won't fit in the middle of the bar — Notes",
      icons: {
        mic: { muted: false },
        volume: { level: "high", muted: false },
        wifi: { on: true, bars: 2 },
        network: { kind: "wifi" },
        battery: { percent: 52, charging: false, text: "52%", tip: "Battery 52%, 3:12 left" },
      },
    },
  },
  {
    // A full workspace: five icons, then how many more, and an app with no
    // icon as a blank square.
    name: "bar-apps",
    width: 1440,
    state: {
      uuid: "A",
      workspaces: ws({
        1: { current: true, occupied: true, apps: ["term", "web", "code", "term", "unknown"], more: 3 },
        2: { occupied: true, apps: ["mail"] },
      }),
      title: "~/src — Terminal",
      app_icons: APP_ICONS,
      icons: {
        volume: { level: "mid", muted: false },
        network: { kind: "wired" },
      },
    },
  },
  {
    name: "bar-quiet",
    width: 1440,
    state: {
      uuid: "A",
      workspaces: ws({ 1: { current: true } }),
      title: "",
      icons: {
        awake: { on: false },
        mic: { muted: true },
        volume: { level: "mute", muted: true },
        network: { kind: "wired" },
        battery: { percent: 15, charging: false, text: "15%", tip: "Battery 15%, 0:40 left" },
      },
    },
  },
];

(async () => {
  const page = process.argv[2];
  if (!page) {
    console.error("usage: render.cjs bar-page.html");
    process.exit(2);
  }
  const browser = await chromium.launch();
  let failed = false;
  try {
    for (const { name, width, state } of STATES) {
      const context = await browser.newContext({
        viewport: { width, height: 36 },
        deviceScaleFactor: 2,
        timezoneId: "Europe/Dublin",
        locale: "en-US",
        colorScheme: "light",
      });
      const tab = await context.newPage();
      tab.on("pageerror", (e) => {
        console.error(`${name}: ${e.message}`);
        failed = true;
      });
      await tab.clock.setFixedTime(new Date("2026-10-26T09:30:00Z"));
      await tab.goto("file://" + path.resolve(page));
      await tab.evaluate((s) => window.tilemo.update(s), state);
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
