import { existsSync } from "node:fs";
import { resolve } from "node:path";
import { parseArgs } from "node:util";

import { ensureDir, getOrgOpenUrl, writeJsonFile } from "./lib.mjs";

/**
 * Creates the "Inventory Transfer Ops" Agentforce Grid in Grid Studio
 * (/AgentforceGrid/gridStudio.app) by uploading the exported CSV.
 *
 * Observed Grid Studio UI (from run evidence): the studio opens onto an empty
 * grid with a top bar containing "Auto Update", "Advanced Filter", and a "..."
 * (three dots / kebab) menu at the top right. The CSV import lives behind that
 * kebab menu and opens an "Import from CSV" MODAL containing:
 *   - an "Upload Files" attachment control,
 *   - a "File includes headers" checkbox,
 *   - a required "*Choose a destination worksheet" dropdown, and
 *   - Cancel / OK buttons.
 *
 * The CSV cannot be imported into a non-existent worksheet: the destination
 * dropdown is a required field, so a worksheet/grid must exist first. This
 * script therefore (1) ensures a worksheet named after --grid-name exists,
 * (2) opens the import modal, (3) attaches the CSV, (4) ticks "File includes
 * headers" (the CSV's first row IS a header row), (5) selects the destination
 * worksheet, and (6) clicks OK — then verifies the grid actually populated.
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

  // Step 1: ensure a destination worksheet exists. The "Import from CSV" modal
  // requires one (it's a required field), and an empty studio has none — that
  // is exactly why a prior run's OK click failed. Best-effort: create/name a
  // worksheet/grid called --grid-name. If the studio already ships a default
  // worksheet, this is a no-op and we just select it later.
  await ensureWorksheet();
  await shot("GRIDSTUDIO-002-worksheet-ready");

  // Step 2: open the top-right "..." (kebab) menu. Ordered most-specific to
  // most-generic; the final fallback is the last button in the top bar, which
  // is where the kebab sits in the observed layout.
  await clickFirst(
    [
      page.getByRole("button", { name: /import from csv/i }),
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
  await shot("GRIDSTUDIO-003-kebab-menu");

  // Step 3: choose "Import from CSV" / "Upload CSV" from the opened menu.
  // Optional because the kebab itself may have been a direct control.
  await clickFirst(
    [
      page.getByRole("menuitem", { name: /import from csv|upload csv/i }),
      page.getByRole("option", { name: /import from csv|upload csv/i }),
      page.getByText(/import from csv/i).first(),
      page.getByText(/upload csv|import csv|from csv/i).first(),
    ],
    'choose "Import from CSV" from the menu',
    { optional: true },
  );

  // Wait for the import modal to appear before interacting with its fields.
  const modal = page.locator('[role="dialog"], .slds-modal, .uiModal').filter({ hasText: /import from csv/i }).first();
  await modal.waitFor({ state: "visible", timeout: 30000 }).catch(() => {});
  await page.waitForTimeout(1500);
  await shot("GRIDSTUDIO-004-import-modal");

  // Step 4: attach the CSV inside the modal. The modal's "Upload Files" control
  // is backed by an input[type=file]; setting it directly avoids depending on a
  // native OS chooser (which never fires in headless CI). Fall back to a fired
  // file chooser only if no input is reachable.
  await attachCsv();
  await page.waitForTimeout(3000);
  await shot("GRIDSTUDIO-005-csv-attached");

  // Step 5: tick "File includes headers". The CSV's first row is a header row,
  // so this MUST be checked or the headers import as a data row.
  await checkIncludesHeaders();

  // Step 6: select the required destination worksheet. This is the field whose
  // emptiness made the prior OK click fail.
  await selectDestinationWorksheet();
  await shot("GRIDSTUDIO-006-import-ready");

  // Step 7: submit the modal. The real button is labelled "OK" — the previous
  // confirm regex omitted it, so the import was never actually submitted.
  await clickFirst(
    [
      modal.getByRole("button", { name: /^ok$/i }),
      page.getByRole("button", { name: /^ok$/i }),
      page.getByRole("button", { name: /^(import|save|create|done|confirm|finish)$/i }),
    ],
    'click "OK" to import the CSV',
  );
  await page.waitForLoadState("networkidle", { timeout: 60000 }).catch(() => {});
  await page.waitForTimeout(8000);
  await shot("GRIDSTUDIO-007-grid-created");

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

// Best-effort creation of a worksheet/grid named --grid-name so the import
// modal's required "destination worksheet" dropdown has something to select.
// Many grid surfaces ship a default worksheet; in that case there is nothing to
// create and this safely no-ops (the dropdown selection later picks it up).
async function ensureWorksheet() {
  const created = await clickFirst(
    [
      page.getByRole("button", { name: /new (grid|worksheet|sheet|tab)/i }),
      page.getByRole("button", { name: /add (grid|worksheet|sheet|tab)/i }),
      page.getByRole("button", { name: /create (grid|worksheet)/i }),
      page.getByRole("tab", { name: /^\+$/ }),
      page.getByRole("button", { name: /^\+$/ }),
    ],
    "create a new worksheet/grid",
    { optional: true },
  );

  if (created) {
    await page.waitForTimeout(2000);
    // Name it if a name field is offered, then confirm.
    const nameInput = page
      .locator('input[name="label"], input[name="name"], input[placeholder*="name" i], input[aria-label*="name" i]')
      .first();
    if ((await nameInput.count()) > 0 && (await nameInput.isVisible().catch(() => false))) {
      await nameInput.fill(values["grid-name"]);
      evidence.steps.push({ step: "name the worksheet", ok: true });
    }
    await clickFirst(
      [page.getByRole("button", { name: /^(create|save|add|done|ok)$/i })],
      "confirm worksheet creation",
      { optional: true },
    );
    await page.waitForTimeout(2000);
  }
  return created;
}

// Attach the CSV inside the import modal. Prefer setting the modal's
// input[type=file] directly (reliable in headless CI); fall back to a native
// file chooser only if it actually fired.
async function attachCsv() {
  const fileChooserPromise = page.waitForEvent("filechooser", { timeout: 8000 }).catch(() => null);
  await clickFirst(
    [
      page.getByRole("button", { name: /upload files/i }),
      page.getByText(/upload files|or drop files/i).first(),
    ],
    'click "Upload Files" in the import modal',
    { optional: true },
  );

  const fileInput = page.locator('input[type="file"]').last();
  await fileInput.waitFor({ state: "attached", timeout: 15000 }).catch(() => {});
  if (await fileInput.count()) {
    await fileInput.setInputFiles(csvPath);
    evidence.steps.push({ step: "attach csv", ok: true, via: "file input", file: values.csv });
    return;
  }

  const fileChooser = await fileChooserPromise;
  if (fileChooser) {
    await fileChooser.setFiles(csvPath);
    evidence.steps.push({ step: "attach csv", ok: true, via: "filechooser", file: values.csv });
    return;
  }

  throw new Error(
    'Could not attach the CSV: neither an input[type="file"] nor a native file chooser appeared in the import modal',
  );
}

// Tick the "File includes headers" checkbox. The CSV's first row is a header
// row, so this must be on. Handles label-click and direct-input strategies.
async function checkIncludesHeaders() {
  const byLabel = page.getByLabel(/file includes headers/i).first();
  if ((await byLabel.count()) > 0) {
    if (!(await byLabel.isChecked().catch(() => false))) {
      await byLabel.check({ timeout: 8000 }).catch(async () => {
        await page.getByText(/file includes headers/i).first().click({ timeout: 8000 }).catch(() => {});
      });
    }
    evidence.steps.push({ step: "check 'File includes headers'", ok: true });
    return true;
  }
  // Fallback: click the visible label text next to the checkbox.
  const labelText = page.getByText(/file includes headers/i).first();
  if ((await labelText.count()) > 0) {
    await labelText.click({ timeout: 8000 }).catch(() => {});
    evidence.steps.push({ step: "check 'File includes headers'", ok: true, via: "label text" });
    return true;
  }
  evidence.steps.push({ step: "check 'File includes headers'", ok: false, note: "checkbox not found" });
  return false;
}

// Select the required destination worksheet. Opens the combobox and chooses the
// option matching --grid-name, else the first real option. Throws if the
// dropdown has no options — that means no worksheet exists and the import
// genuinely cannot proceed (surfacing the real problem instead of a silent OK).
async function selectDestinationWorksheet() {
  const combo = page
    .locator(
      'select, [role="combobox"], button[aria-haspopup="listbox"], .slds-combobox input, [class*="combobox"] input',
    )
    .filter({ hasNot: page.locator('input[type="file"]') })
    .last();

  // Native <select> path.
  const tag = await combo.evaluate((el) => el.tagName.toLowerCase()).catch(() => "");
  if (tag === "select") {
    const options = await combo.locator("option").allTextContents();
    const real = options.map((o) => o.trim()).filter((o) => o && !/choose a destination/i.test(o));
    if (real.length === 0) {
      throw new Error("Destination worksheet dropdown has no options — no worksheet exists to import into");
    }
    const target = real.find((o) => o.toLowerCase().includes(values["grid-name"].toLowerCase())) || real[0];
    await combo.selectOption({ label: target });
    evidence.steps.push({ step: "select destination worksheet", ok: true, worksheet: target });
    return true;
  }

  // Lightning combobox path: click to open the listbox, then pick an option.
  await combo.click({ timeout: 10000 });
  await page.waitForTimeout(800);
  const options = page.locator('[role="option"]:visible, .slds-listbox__option:visible');
  const count = await options.count();
  if (count === 0) {
    throw new Error("Destination worksheet dropdown opened but showed no options — no worksheet exists to import into");
  }
  // Prefer an option matching the grid name.
  const named = page.getByRole("option", { name: new RegExp(values["grid-name"], "i") }).first();
  if ((await named.count()) > 0 && (await named.isVisible().catch(() => false))) {
    await named.click({ timeout: 8000 });
    evidence.steps.push({ step: "select destination worksheet", ok: true, worksheet: values["grid-name"] });
    return true;
  }
  await options.first().click({ timeout: 8000 });
  const chosen = (await options.first().innerText().catch(() => "")) || "first option";
  evidence.steps.push({ step: "select destination worksheet", ok: true, worksheet: chosen.trim() });
  return true;
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
