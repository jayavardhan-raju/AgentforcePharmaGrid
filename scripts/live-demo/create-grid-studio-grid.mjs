import { existsSync } from "node:fs";
import { resolve } from "node:path";
import { parseArgs } from "node:util";

import { ensureDir, getOrgOpenUrl, writeJsonFile } from "./lib.mjs";

/**
 * Creates the "Inventory Transfer Ops" grid in the Agentforce Grid app and
 * imports the exported CSV into it.
 *
 * Observed UI (run evidence): the Agentforce Grid app home is the Lightning
 * page `/lightning/n/standard-WorkbenchHome`. It shows an "All Grids" list view
 * with a "Create Grid" button (top-right, and a large CTA in the empty state).
 * A grid is the WORKBOOK; the "Import from CSV" action is scoped to it and needs
 * a valid WORKBOOK ID in context. With no grid, the import fails with the toast
 * "Please provide a valid workbook id." So a grid must be created AND saved
 * first — exactly the documented flow.
 *
 * Mandatory order enforced here:
 *   1. Open the Agentforce Grid app home (/lightning/n/standard-WorkbenchHome).
 *   2. Click "Create Grid", name it --grid-name, and SAVE it. Confirm a valid
 *      workbook id now exists; if not, fail early rather than reproduce the
 *      "valid workbook id" banner by importing into nothing.
 *   3. Open "Import from CSV", attach the CSV, tick "File includes headers"
 *      (the CSV's first row IS a header row), select worksheet one as the
 *      destination, and click OK to generate the records.
 *   4. Verify the grid actually populated and that no error toast fired.
 *
 * The app URL is always derived from the freshly created scratch org (via
 * `sf org open --url-only`), never hard-coded, because the instance domain
 * differs on every run. The resulting grid URL is written to
 * <artifacts>/grid-studio.json so the Mailtrap email can link to it.
 */

const { values } = parseArgs({
  options: {
    "target-org": { type: "string" },
    artifacts: { type: "string" },
    csv: { type: "string", default: "scripts/live-demo/data/inventory-transfer-ops-grid.csv" },
    "grid-name": { type: "string", default: "Inventory Transfer Ops" },
    "app-path": { type: "string", default: "/lightning/n/standard-WorkbenchHome" },
  },
});

if (!values["target-org"] || !values.artifacts) {
  throw new Error(
    "Usage: node create-grid-studio-grid.mjs --target-org <alias> --artifacts <dir> [--csv <file>] [--grid-name <name>] [--app-path <path>]",
  );
}

const csvPath = resolve(values.csv);
if (!existsSync(csvPath)) {
  throw new Error(`Grid CSV not found: ${csvPath}`);
}

const shotsDir = `${values.artifacts}/screenshots`;
await ensureDir(shotsDir);

// Authenticated, instance-specific entry into the Agentforce Grid app home for
// THIS scratch org.
const studioUrl = await getOrgOpenUrl(values["target-org"], values["app-path"]);

const { chromium } = await import("playwright");
const browser = await chromium.launch({ headless: true });
const page = await browser.newPage({ viewport: { width: 1600, height: 1000 } });

const evidence = { grid_name: values["grid-name"], app_path: values["app-path"], steps: [] };

try {
  // Step 1: open the Agentforce Grid app home ("All Grids" list view).
  await page.goto(studioUrl, { waitUntil: "domcontentloaded", timeout: 120000 });
  await page.waitForLoadState("networkidle", { timeout: 60000 }).catch(() => {});
  await page.waitForTimeout(5000);
  await shot("GRIDSTUDIO-001-grids-home");

  // Step 2: create the grid (workbook) named --grid-name and SAVE it, then
  // confirm a valid workbook id exists. The import is gated on this.
  const workbookId = await createAndSaveGrid();
  evidence.workbook_id = workbookId;
  await shot("GRIDSTUDIO-002-grid-saved");

  // Step 3: open the CSV import. On a freshly created grid the right-hand
  // "Get Started" panel offers an "Upload File — Import data from a CSV" tile;
  // that is the documented entry point. Falls back to the top-right "..." kebab
  // menu if the panel has been dismissed.
  await openCsvImport();
  await shot("GRIDSTUDIO-003-import-opened");

  // Wait for the import modal, then make sure no workbook-id error already fired.
  const modal = page
    .locator('[role="dialog"], .slds-modal, .uiModal')
    .filter({ hasText: /import from csv|import data from|upload file/i })
    .first();
  await modal.waitFor({ state: "visible", timeout: 30000 }).catch(() => {});
  await page.waitForTimeout(1500);
  await assertNoWorkbookIdError("after opening the import modal");
  await shot("GRIDSTUDIO-004-import-modal");

  // Step 3a: attach the CSV inside the modal.
  await attachCsv();
  await page.waitForTimeout(3000);
  await shot("GRIDSTUDIO-005-csv-attached");

  // Step 3b: tick "File includes headers" (CSV row 1 is a header row).
  await checkIncludesHeaders();

  // Step 3c: select worksheet one as the destination.
  await selectDestinationWorksheet();
  await shot("GRIDSTUDIO-006-import-ready");

  // Step 3d: submit. The real button is labelled "OK".
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
  await assertNoWorkbookIdError("after clicking OK to import");
  await shot("GRIDSTUDIO-007-records-generated");

  // Step 4: verify the grid actually contains rows from the CSV.
  const populated = await gridLooksPopulated();
  if (!populated.ok) {
    throw new Error(
      `CSV import completed but the grid does not show the expected data (${populated.reason}); refusing to report success`,
    );
  }

  const gridUrl = sanitizeUrl(page.url(), studioUrl);
  await writeJsonFile(`${values.artifacts}/grid-studio.json`, {
    status: "created",
    grid_name: values["grid-name"],
    workbook_id: workbookId,
    grid_url: gridUrl,
    evidence,
  });
  console.log(`Agentforce grid "${values["grid-name"]}" created (workbook ${workbookId}): ${gridUrl}`);
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
  throw new Error(`Could not ${description}: no matching control found in the Agentforce Grid app`);
}

// Click "Create Grid" on the All Grids home, fill the "Create Grid" modal
// (Grid Name + optional Description), click "Create", and return the new grid's
// workbook id. Throws if a valid workbook id cannot be confirmed — that is the
// precondition the "Please provide a valid workbook id" toast complains about,
// so proceeding without it would only reproduce the failure.
//
// Observed modal (run evidence): title "Create Grid"; a required "Grid Name"
// text input (placeholder "Enter a name..."); an optional "Description"
// textarea (placeholder "Enter a description..."); Cancel / Create buttons,
// where Create stays disabled until a name is entered.
async function createAndSaveGrid() {
  // If we somehow already opened a grid (id present), reuse it.
  let id = getWorkbookId();
  if (id) {
    evidence.steps.push({ step: "grid already in context", ok: true, workbook_id: id });
    return id;
  }

  // The home shows two "Create Grid" controls (header button + empty-state CTA);
  // either opens the same modal. clickFirst takes the first visible one.
  await clickFirst(
    [
      page.getByRole("button", { name: /create grid/i }),
      page.getByRole("link", { name: /create grid/i }),
      page.getByText(/^create grid$/i).first(),
      page.getByRole("button", { name: /new grid/i }),
    ],
    'click "Create Grid"',
  );

  // Wait for the "Create Grid" modal.
  const dialog = page.locator('[role="dialog"], .slds-modal, .uiModal').filter({ hasText: /create grid/i }).first();
  await dialog.waitFor({ state: "visible", timeout: 30000 }).catch(() => {});
  await page.waitForTimeout(1000);
  await assertNoWorkbookIdError("after opening the Create Grid modal");

  // Fill the required Grid Name. Match strictly on the modal placeholder
  // ("Enter a name..."). Do NOT use getByLabel(/grid name/i): the All Grids list
  // view renders a hidden <th aria-label="Grid Name"> column header that
  // getByLabel matches, and .first() picks that hidden header over the modal
  // input — the exact cause of the CI TimeoutError at this step. Placeholders
  // only exist on the modal inputs, so they are unambiguous.
  const nameInput = page
    .getByPlaceholder(/enter a name/i)
    .or(page.locator('input[name="gridName"]'))
    .first();
  await nameInput.waitFor({ state: "visible", timeout: 20000 });
  await nameInput.fill(values["grid-name"]);
  evidence.steps.push({ step: "fill Grid Name", ok: true, name: values["grid-name"] });

  // Fill the optional Description (same placeholder-only rationale; avoids the
  // hidden <th aria-label="Description"> column header).
  const descInput = page
    .getByPlaceholder(/enter a description/i)
    .or(page.locator('textarea[name="description"]'))
    .first();
  if ((await descInput.count()) > 0 && (await descInput.isVisible().catch(() => false))) {
    await descInput.fill(`${values["grid-name"]} — inventory positions imported from CSV.`);
    evidence.steps.push({ step: "fill Description", ok: true });
  }

  // Click "Create" (scoped to the modal so it cannot re-hit the home "Create
  // Grid" button). The button enables once the name is present.
  await clickFirst(
    [
      dialog.getByRole("button", { name: /^create$/i }),
      page.getByRole("button", { name: /^create$/i }),
      dialog.getByRole("button", { name: /^(save|done)$/i }),
    ],
    'click "Create" in the Create Grid modal',
  );

  // Wait for persistence and the id to appear (the URL updates when the new grid
  // opens in the builder).
  for (let attempt = 0; attempt < 12; attempt += 1) {
    await page.waitForLoadState("networkidle", { timeout: 15000 }).catch(() => {});
    await page.waitForTimeout(1500);
    await assertNoWorkbookIdError("while creating the grid");
    id = getWorkbookId();
    if (id) break;
  }

  if (!id) {
    throw new Error(
      "Filled and submitted the Create Grid modal but could not confirm a valid workbook id " +
        "(no id found in the URL or page state). The import is not attempted, since it would fail " +
        "with 'Please provide a valid workbook id'. Inspect GRIDSTUDIO-002-grid-saved.png to pin " +
        "the post-create URL and id location.",
    );
  }
  const worksheetId = getWorksheetId();
  evidence.worksheet_id = worksheetId;
  evidence.steps.push({ step: "grid created", ok: true, workbook_id: id, worksheet_id: worksheetId });
  return id;
}

// Collect query params from both the standard query string AND the hash route.
// After the grid is created the app navigates to (reference URL, ids differ per
// scratch org):
//   .../AgentforceGrid/gridStudio.app#/grid?gridId=1W4JW...&worksheetId=1W1JW...
// so the ids live in the HASH query, not the normal query string.
function getUrlParams() {
  const out = {};
  try {
    const u = new URL(page.url());
    for (const [k, v] of u.searchParams) out[k] = v;
    if (u.hash && u.hash.includes("?")) {
      const hp = new URLSearchParams(u.hash.slice(u.hash.indexOf("?") + 1));
      for (const [k, v] of hp) out[k] = v;
    }
  } catch {
    /* ignore malformed URL */
  }
  return out;
}

// The workbook id Grid Studio requires is the `gridId` hash param. Accept a few
// aliases defensively, but prefer gridId.
function getWorkbookId() {
  const p = getUrlParams();
  return p.gridId || p.workbookId || p.workbook_id || p.wbId || p.c__workbookId || p.c__gridId || null;
}

// Worksheet one's id from the same hash route, used as the import destination.
function getWorksheetId() {
  const p = getUrlParams();
  return p.worksheetId || p.c__worksheetId || p.sheetId || null;
}

// Detect the Grid error toast and fail with its text, so a workbook-id problem
// is reported precisely instead of as a vague downstream timeout.
async function assertNoWorkbookIdError(context) {
  const toast = page
    .locator('[role="alert"], .slds-notify, .toastMessage, .slds-notify__content')
    .filter({ hasText: /workbook id|valid workbook/i })
    .first();
  if ((await toast.count()) > 0 && (await toast.isVisible().catch(() => false))) {
    const text = (await toast.innerText().catch(() => "")) || "Please provide a valid workbook id.";
    evidence.steps.push({ step: `error toast ${context}`, ok: false, message: text.trim() });
    throw new Error(`Agentforce Grid reported "${text.trim()}" ${context}`);
  }
}

// Open the "Import from CSV" modal. Primary path is the "Get Started" panel's
// "Upload File" / "Import data from a CSV" tile shown on a new grid; fallback is
// the top-right "..." kebab -> "Import from CSV".
async function openCsvImport() {
  const opened = await clickFirst(
    [
      page.getByText(/import data from a csv/i).first(),
      page.getByRole("button", { name: /upload file/i }),
      page.getByRole("menuitem", { name: /upload file/i }),
      page.getByText(/^upload file$/i).first(),
    ],
    'click "Upload File" (Import data from a CSV) in the Get Started panel',
    { optional: true },
  );

  if (!opened) {
    // Fallback: the top-right "..." (kebab) menu -> Import from CSV.
    await clickFirst(
      [
        page.getByRole("button", { name: /import from csv|upload csv/i }),
        page.getByRole("button", { name: /more (options|actions)/i }),
        page.locator('button[aria-haspopup="true"]:visible').last(),
        page.locator("header button:visible, [class*='header'] button:visible, [class*='toolbar'] button:visible").last(),
      ],
      "open the top-right (...) menu",
    );
    await page.waitForTimeout(1500);
    await clickFirst(
      [
        page.getByRole("menuitem", { name: /import from csv|upload csv/i }),
        page.getByRole("option", { name: /import from csv|upload csv/i }),
        page.getByText(/import from csv/i).first(),
      ],
      'choose "Import from CSV" from the menu',
      { optional: true },
    );
  }
  await page.waitForTimeout(1500);
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
// row, so this must be on. Optional — only renders once a grid is in context.
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
  const labelText = page.getByText(/file includes headers/i).first();
  if ((await labelText.count()) > 0) {
    await labelText.click({ timeout: 8000 }).catch(() => {});
    evidence.steps.push({ step: "check 'File includes headers'", ok: true, via: "label text" });
    return true;
  }
  evidence.steps.push({ step: "check 'File includes headers'", ok: false, note: "checkbox not shown (skipped)" });
  return false;
}

// Select worksheet one as the destination. Optional — only renders once a grid
// is in context. Prefers the named worksheet, else the first option.
async function selectDestinationWorksheet() {
  const combo = page
    .locator(
      'select, [role="combobox"], button[aria-haspopup="listbox"], .slds-combobox input, [class*="combobox"] input',
    )
    .filter({ hasNot: page.locator('input[type="file"]') })
    .last();

  if ((await combo.count()) === 0) {
    evidence.steps.push({ step: "select destination worksheet", ok: false, note: "no worksheet dropdown shown (skipped)" });
    return false;
  }

  const tag = await combo.evaluate((el) => el.tagName.toLowerCase()).catch(() => "");
  if (tag === "select") {
    const options = await combo.locator("option").allTextContents();
    const real = options.map((o) => o.trim()).filter((o) => o && !/choose a destination/i.test(o));
    if (real.length === 0) {
      evidence.steps.push({ step: "select destination worksheet", ok: false, note: "dropdown empty (skipped)" });
      return false;
    }
    const target = real.find((o) => o.toLowerCase().includes(values["grid-name"].toLowerCase())) || real[0];
    await combo.selectOption({ label: target });
    evidence.steps.push({ step: "select destination worksheet", ok: true, worksheet: target });
    return true;
  }

  await combo.click({ timeout: 10000 });
  await page.waitForTimeout(800);
  const options = page.locator('[role="option"]:visible, .slds-listbox__option:visible');
  if ((await options.count()) === 0) {
    evidence.steps.push({ step: "select destination worksheet", ok: false, note: "no options shown (skipped)" });
    return false;
  }
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
