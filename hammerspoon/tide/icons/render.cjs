#!/usr/bin/env node
// Render tide's logo (tide-symbolic.svg, beside this script, copied from
// tide's shell/icons unchanged) to the PNGs tide shows (brand.lua), with
// Playwright's Chromium, as `make mocks` renders the bar. Each is drawn at
// 4x its point size on a clear background; the same Chromium writes the same
// bytes, so a re-render only changes when the logo does.
//
//   tide-template.png  black, for the menu bar, where macOS tints it
//   tide.png           tide's accent blue, for notifications and the switcher

const fs = require("fs");
const path = require("path");

let chromium;
try {
  ({ chromium } = require("playwright"));
} catch {
  console.log("SKIP icons: no Playwright");
  process.exit(0);
}

const SVG = fs.readFileSync(path.join(__dirname, "tide-symbolic.svg"), "utf8");
// tide's symbolic gray, which the outputs replace.
const STROKE = "#2e3436";
const SCALE = 4;
const ICONS = [
  { file: "tide-template.png", color: "#000000", size: 16 },
  // tide's --accent (launcher.css), which reads on light and dark alike.
  { file: "tide.png", color: "#3584e4", size: 64 },
];

(async () => {
  if (!SVG.includes(STROKE)) throw new Error(`tide-symbolic.svg no longer strokes in ${STROKE}`);
  const browser = await chromium.launch();
  try {
    for (const icon of ICONS) {
      const page = await browser.newPage({
        viewport: { width: icon.size, height: icon.size },
        deviceScaleFactor: SCALE,
      });
      const svg = SVG.split(STROKE)
        .join(icon.color)
        .replace(/width="16" height="16"/, `width="${icon.size}" height="${icon.size}"`);
      await page.setContent(
        `<!doctype html><html><body style="margin:0;background:transparent">${svg}</body></html>`,
      );
      const out = path.join(__dirname, icon.file);
      await page.locator("svg").screenshot({ path: out, omitBackground: true });
      await page.close();
      console.log(`wrote ${path.relative(process.cwd(), out)}`);
    }
  } finally {
    await browser.close();
  }
})().catch((err) => {
  console.error(err);
  process.exit(1);
});
