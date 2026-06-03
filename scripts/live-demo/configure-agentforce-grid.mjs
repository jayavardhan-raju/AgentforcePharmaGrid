import { parseArgs } from "node:util";

import { ensureDir, getOrgOpenUrl, querySalesforce, writeJsonFile } from "./lib.mjs";

const { values } = parseArgs({
  options: {
    "target-org": { type: "string" },
    artifacts: { type: "string" },
  },
});

if (!values["target-org"] || !values.artifacts) {
  throw new Error("Usage: node configure-agentforce-grid.mjs --target-org <alias> --artifacts <dir>");
}

await ensureDir(`${values.artifacts}/screenshots`);

const listViews = await querySalesforce(
  values["target-org"],
  "SELECT Id, DeveloperName, Name FROM ListView WHERE SobjectType = 'Inventory_Position__c' AND DeveloperName = 'Inventory_Transfer_Ops' LIMIT 1",
);

const { chromium } = await import("playwright");
const browser = await chromium.launch({ headless: true });
const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });

try {
  const listUrl = await getOrgOpenUrl(
    values["target-org"],
    "/lightning/o/Inventory_Position__c/list?filterName=Inventory_Transfer_Ops",
  );
  await page.goto(listUrl, { waitUntil: "domcontentloaded", timeout: 120000 });
  await page.waitForTimeout(5000);
  await page.screenshot({ path: `${values.artifacts}/screenshots/GRID-001-inventory-list.png`, fullPage: true });

  const gridEvidence = await detectGrid(page);
  await writeJsonFile(`${values.artifacts}/agentforce-grid.json`, {
    status: gridEvidence.ok ? "detected" : "not_detected",
    list_view_found: listViews.length > 0,
    evidence: gridEvidence,
  });

  if (!gridEvidence.ok) {
    const setupUrl = await getOrgOpenUrl(
      values["target-org"],
      "/lightning/setup/FlexiPageList/home",
    );
    await page.goto(setupUrl, { waitUntil: "domcontentloaded", timeout: 120000 });
    await page.waitForTimeout(5000);
    await page.screenshot({ path: `${values.artifacts}/screenshots/GRID-002-app-builder-entry.png`, fullPage: true });

    throw new Error(
      "Real Agentforce Grid was not detected on Inventory_Transfer_Ops. Evidence captured; workflow stops rather than faking the UI demo.",
    );
  }

  console.log("Real Agentforce Grid detected with Transfer/Optimize action");
} finally {
  await browser.close();
}

async function detectGrid(page) {
  const bodyText = await page.locator("body").innerText({ timeout: 30000 }).catch(() => "");
  const transferOptimizeVisible =
    (await page.getByRole("button", { name: /transfer\/optimize/i }).count()) > 0 ||
    (await page.getByRole("link", { name: /transfer\/optimize/i }).count()) > 0 ||
    /Transfer\/Optimize/i.test(bodyText);

  return {
    ok: /Agentforce|Einstein|Recommendation/i.test(bodyText) && transferOptimizeVisible,
    transfer_optimize_visible: transferOptimizeVisible,
    body_sample: bodyText.slice(0, 2000),
  };
}
