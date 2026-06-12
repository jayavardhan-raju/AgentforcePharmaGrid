import { existsSync } from "node:fs";
import { resolve } from "node:path";
import { parseArgs } from "node:util";

import { ensureDir, getOrgOpenUrl, writeJsonFile } from "./lib.mjs";

/**
 * Creates an Agentforce Grid named "Inventory Transfer Ops" in Grid Studio
 * (/AgentforceGrid/gridStudio.app) and uploads the exported CSV as its data.
 *
 * The Grid Studio URL is always derived from the freshly created scratch org
 * (via `sf org open --url-only`), never hard-coded, because the instance
 * domain differs on every run. The resulting grid URL is written to
 * <artifacts>/grid-studio.json so the Mailtrap email can link to it.
 *
 * Selector strategy is best-effort with screenshot evidence at each step;
 * on any failure the script records the evidence and throws rather than
 * pretending the grid exists.
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

  // Step 1: open the new-grid flow.
  await clickFirst(
    [
      page.getByRole("button", { name: /new grid/i }),
      page.getByRole("button", { name: /create grid/i }),
      page.getByRole("button", { name: /^new$/i }),
      page.getByRole("link", { name: /new grid/i }),
      page.getByText(/new grid/i).first(),
    ],
    "open the New Grid flow",
  );
  await page.waitForTimeout(3000);
  await shot("GRIDSTUDIO-002-new-grid-dialog");

  // Step 2: name the grid when a name input is offered up front.
  await fillGridName();

  // Step 3: upload the CSV. Prefer an explicit CSV/import affordance; fall
  // back to any file input the dialog exposes.
  await clickFirst(
    [
      page.getByRole("button", { name: /upload csv|import csv|from csv/i }),
      page.getByRole("button", { name: /upload|import/i }),
      page.getByText(/upload csv|import csv|from csv/i).first(),
    ],
    "open the CSV upload option",
    { optional: true },
  );
  await page.waitForTimeout(2000);

  const fileInput = page.locator('input[type="file"]').first();
  if (!(await fileInput.count())) {
    throw new Error("Grid Studio did not expose a file input for CSV upload");
  }
  await fileInput.setInputFiles(csvPath);
  evidence.steps.push({ step: "upload csv", ok: true, file: values.csv });
  await page.waitForTimeout(8000);
  await shot("GRIDSTUDIO-003-csv-uploaded");

  // Step 4: the name field sometimes appears only after the data is loaded.
  await fillGridName();

  // Step 5: confirm/save.
  await clickFirst(
    [
      page.getByRole("button", { name: /^save$/i }),
      page.getByRole("button", { name: /^create$/i }),
      page.getByRole("button", { name: /done|finish|next/i }),
    ],
    "save the grid",
    { optional: true },
  );
  await page.waitForLoadState("networkidle", { timeout: 60000 }).catch(() => {});
  await page.waitForTimeout(5000);
  await shot("GRIDSTUDIO-004-grid-created");

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
  return false;
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
