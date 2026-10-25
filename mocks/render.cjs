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

const STATES = [
  {
    name: "bar-wide",
    width: 1920,
    state: {
      uuid: "A",
      workspaces: ws({ 1: { current: true, occupied: true }, 2: { occupied: true }, 3: { elsewhere: true, occupied: true }, 5: { occupied: true, urgent: true } }),
      title: "Inbox (3) — Mail",
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
      workspaces: ws({ 1: { occupied: true }, 2: { current: true, occupied: true }, 4: { occupied: true }, 6: { occupied: true }, 9: { occupied: true } }),
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
      await tab.evaluate((s) => window.timo.update(s), state);
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
