import { existsSync } from "node:fs";
import { resolve } from "node:path";
import { parseArgs } from "node:util";

import { ensureDir, getOrgOpenUrl, writeJsonFile } from "./lib.mjs";

/**
 * Creates the "Inventory Transfer Ops" Agentforce Grid in Grid Studio
 * (/AgentforceGrid/gridStudio.app) by uploading the exported CSV.
 *
 * Observed Grid Studio UI (from run evidence): the studio opens straight onto
 * an empty grid with a top bar containing "Auto Update", "Advanced Filter",
 * and a "..." (three dots / kebab) menu at the top right. The CSV import lives
 * behind that kebab menu as an "Upload CSV" item. There is no separate
 * "New Grid" button — the grid is created from the uploaded CSV.
 *
 * The Grid Studio URL is always derived from the freshly created scratch org
 * (via `sf org open --url-only`), never hard-coded, because the instance
 * domain differs on every run. The resulting grid URL is written to
 * <artifacts>/grid-studio.json so the Mailtrap email can link to it.
 */

const { values } = parseArgs({
  options: {
    "target-org": { type: "string" },
    artifacts: { type: "string" },
    csv: { type: "string", default: "scripts/live-demo/data/inventory-transfer-ops-grid.csv" },
    "grid-name": { type: "string", default: "Inventory Transfer Ops" },
  },
});

if (!values["target-org"] || !values.artifacts) {
  throw new Error(
    "Usage: node create-grid-studio-grid.mjs --target-org <alias> --artifacts <dir> [--csv <file>] [--grid-name <name>]",
  );
}

const csvPath = resolve(values.csv);
if (!existsSync(csvPath)) {
  throw new Error(`Grid CSV not found: ${csvPath}`);
}

const shotsDir = `${values.artifacts}/screenshots`;
await ensureDir(shotsDir);

// Authenticated, instance-specific entry into Grid Studio for THIS scratch org.
const studioUrl = await getOrgOpenUrl(values["target-org"], "/AgentforceGrid/gridStudio.app");

const { chromium } = await import("playwright");
const browser = await chromium.launch({ headless: true });
const page = await browser.newPage({ viewport: { width: 1600, height: 1000 } });

const evidence = { grid_name: values["grid-name"], steps: [] };

try {
  await page.goto(studioUrl, { waitUntil: "domcontentloaded", timeout: 120000 });
  await page.waitForLoadState("networkidle", { timeout: 60000 }).catch(() => {});
  await page.waitForTimeout(5000);
  await shot("GRIDSTUDIO-001-studio-home");

  // Arm the native file chooser listener BEFORE any clicks: depending on the
  // org, "Upload CSV" may be a direct button (step 1's first locator) or a
  // kebab menu item (step 2), and the chooser must not be missed either way.
  const fileChooserPromise = page.waitForEvent("filechooser", { timeout: 45000 }).catch(() => null);

  // Step 1: open the top-right "..." (kebab) menu. Ordered most-specific to
  // most-generic; the final fallback is the last button in the top bar, which
  // is where the kebab sits in the observed layout.
  await clickFirst(
    [
      page.getByRole("button", { name: /upload csv/i }),
      page.getByRole("button", { name: /more (options|actions)/i }),
      page.getByRole("button", { name: /^(menu|options|actions|show more)$/i }),
      page.locator('button[aria-haspopup="true"]:visible').last(),
      page.locator("header button:visible, [class*='header'] button:visible, [class*='toolbar'] button:visible").last(),
      page.locator("button:visible").last(),
    ],
    "open the top-right kebab (...) menu",
  );
  await page.waitForTimeout(2000);
  await shot("GRIDSTUDIO-002-kebab-menu");

  // Step 2: choose "Upload CSV" from the opened menu. Optional because the
  // kebab itself may have been a direct Upload CSV control on some layouts.
  await clickFirst(
    [
      page.getByRole("menuitem", { name: /upload csv/i }),
      page.getByRole("option", { name: /upload csv/i }),
      page.getByText(/upload csv/i).first(),
      page.getByText(/import csv|from csv/i).first(),
    ],
    'choose "Upload CSV" from the menu',
    { optional: true },
  );

  // Step 3: hand the CSV to whichever upload mechanism appeared. Prefer a
  // native chooser that actually fired from our clicks (give it 5s) over a
  // DOM file input, which could be an unrelated hidden element.
  const fileChooser = await Promise.race([
    fileChooserPromise,
    new Promise((resolve) => setTimeout(() => resolve(null), 5000)),
  ]);
  if (fileChooser) {
    await fileChooser.setFiles(csvPath);
    evidence.steps.push({ step: "upload csv", ok: true, via: "filechooser", file: values.csv });
  } else {
    const fileInput = page.locator('input[type="file"]').first();
    await fileInput.waitFor({ state: "attached", timeout: 20000 }).catch(() => {});
    if (!(await fileInput.count())) {
      throw new Error(
        'Could not reach the CSV upload: neither a native file chooser nor an input[type="file"] appeared after opening the kebab menu',
      );
    }
    await fileInput.setInputFiles(csvPath);
    evidence.steps.push({ step: "upload csv", ok: true, via: "file input", file: values.csv });
  }

  await page.waitForLoadState("networkidle", { timeout: 60000 }).catch(() => {});
  await page.waitForTimeout(8000);
  await shot("GRIDSTUDIO-003-csv-uploaded");

  // Step 4: confirm grid creation if the studio asks (optional — the upload
  // may populate the grid directly).
  await clickFirst(
    [
      page.getByRole("button", { name: /create grid/i }),
      page.getByRole("button", { name: /^(create|save|import|done|confirm|finish)$/i }),
    ],
    "confirm grid creation",
    { optional: true },
  );
  await page.waitForLoadState("networkidle", { timeout: 60000 }).catch(() => {});
  await page.waitForTimeout(5000);

  // Step 5: name the grid when a name input is offered.
  await fillGridName();
  await shot("GRIDSTUDIO-004-grid-created");

  // Sanity check: the grid should now actually contain rows from the CSV.
  const populated = await gridLooksPopulated();
  if (!populated.ok) {
    throw new Error(
      `CSV upload completed but the grid does not show the expected data (${populated.reason}); refusing to report success`,
    );
  }

  const gridUrl = sanitizeUrl(page.url(), studioUrl);
  await writeJsonFile(`${values.artifacts}/grid-studio.json`, {
    status: "created",
    grid_name: values["grid-name"],
    grid_url: gridUrl,
    evidence,
  });
  console.log(`Grid Studio grid "${values["grid-name"]}" created: ${gridUrl}`);
} catch (error) {
  await shot("GRIDSTUDIO-999-failure").catch(() => {});
  await writeJsonFile(`${values.artifacts}/grid-studio.json`, {
    status: "failed",
    grid_name: values["grid-name"],
    error: error?.message || String(error),
    evidence,
  });
  throw error;
} finally {
  await browser.close();
}

async function shot(name) {
  await page.screenshot({ path: `${shotsDir}/${name}.png`, fullPage: true });
}

async function clickFirst(locators, description, { optional = false } = {}) {
  for (const locator of locators) {
    const target = locator.first();
    if ((await target.count()) > 0 && (await target.isVisible().catch(() => false))) {
      await target.click({ timeout: 15000 });
      evidence.steps.push({ step: description, ok: true });
      return true;
    }
  }
  if (optional) {
    evidence.steps.push({ step: description, ok: false, note: "no matching control; skipped (optional)" });
    return false;
  }
  throw new Error(`Could not ${description}: no matching control found in Grid Studio`);
}

async function fillGridName() {
  const nameInput = page
    .locator('input[name="label"], input[name="name"], input[placeholder*="name" i], input[aria-label*="name" i]')
    .first();
  if ((await nameInput.count()) > 0 && (await nameInput.isVisible().catch(() => false))) {
    await nameInput.fill(values["grid-name"]);
    evidence.steps.push({ step: "name the grid", ok: true });
    return true;
  }
  evidence.steps.push({ step: "name the grid", ok: false, note: "no name input offered; skipped" });
  return false;
}

async function gridLooksPopulated() {
  const bodyText = await page.locator("body").innerText({ timeout: 30000 }).catch(() => "");
  // Markers that exist in the uploaded CSV and would only render if rows loaded.
  const markers = ["Mounjaro 5mg", "CVS Downtown SF", "INV-"];
  const found = markers.filter((m) => bodyText.includes(m));
  evidence.steps.push({ step: "verify grid populated", markers_found: found });
  if (found.length === 0) {
    return { ok: false, reason: "none of the CSV row markers are visible on the page" };
  }
  return { ok: true };
}

function sanitizeUrl(url, fallback) {
  try {
    const parsed = new URL(url);
    // Never leak session parameters into artifacts or email.
    for (const param of ["sid", "startURL", "retURL"]) {
      parsed.searchParams.delete(param);
    }
    if (/login\.salesforce\.com|frontdoor/i.test(parsed.href)) {
      return stripQuery(fallback);
    }
    return parsed.href;
  } catch {
    return stripQuery(fallback);
  }
}

function stripQuery(url) {
  try {
    const parsed = new URL(url);
    return `${parsed.origin}${parsed.pathname}`;
  } catch {
    return "";
  }
}
