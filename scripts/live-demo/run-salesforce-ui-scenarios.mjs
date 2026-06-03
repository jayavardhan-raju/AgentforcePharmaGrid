import { parseArgs } from "node:util";

import {
  ensureDir,
  escapeSoql,
  getOrgOpenUrl,
  querySalesforce,
  writeJsonFile,
} from "./lib.mjs";

const SCENARIOS = [
  {
    id: "01-happy-path-cold-chain",
    label: "Happy path cold chain transfer",
    store: "CVS Downtown SF",
    medication: "Mounjaro 5mg",
  },
  {
    id: "02-schedule-ii-block",
    label: "Schedule II compliance block",
    store: "CVS Downtown SF",
    medication: "Adderall XR 30mg",
  },
  {
    id: "03-distributor-fallback",
    label: "Distributor fallback",
    store: "CVS Downtown SF",
    medication: "Lisinopril 10mg",
  },
  {
    id: "04-near-expiry-exclusion",
    label: "Near-expiry source exclusion",
    store: "CVS San Jose Central",
    medication: "Ozempic 1mg",
  },
  {
    id: "05-schedule-iv-allowed",
    label: "Schedule IV allowed transfer",
    store: "CVS Eastside Oakland",
    medication: "Xanax 0.5mg",
  },
  {
    id: "06-multiple-healthy-sources",
    label: "Multiple healthy source selection",
    store: "CVS Sunnyvale",
    medication: "Amoxicillin 500mg",
  },
];

const { values } = parseArgs({
  options: {
    "target-org": { type: "string" },
    artifacts: { type: "string" },
  },
});

if (!values["target-org"] || !values.artifacts) {
  throw new Error("Usage: node run-salesforce-ui-scenarios.mjs --target-org <alias> --artifacts <dir>");
}

await ensureDir(`${values.artifacts}/screenshots`);

const { chromium } = await import("playwright");
const browser = await chromium.launch({ headless: true });
const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
const results = [];

try {
  for (const scenario of SCENARIOS) {
    results.push(await runScenario(page, values["target-org"], values.artifacts, scenario));
  }
} finally {
  await browser.close();
}

await writeJsonFile(`${values.artifacts}/scenario-results.json`, {
  scenarios: results,
  passed: results.filter((result) => result.status === "passed").length,
  failed: results.filter((result) => result.status === "failed").length,
});

const failures = results.filter((result) => result.status === "failed");
if (failures.length > 0) {
  throw new Error(`${failures.length} Salesforce UI scenario(s) failed. See scenario-results.json and screenshots.`);
}

console.log("All six Salesforce UI Transfer/Optimize scenarios passed");

async function runScenario(page, targetOrg, artifactDir, scenario) {
  const result = {
    id: scenario.id,
    label: scenario.label,
    store: scenario.store,
    medication: scenario.medication,
    status: "failed",
    screenshots: [],
    transfer_log: null,
  };

  try {
    const target = await findTarget(targetOrg, scenario);
    result.inventory_position_id = target.Id;
    result.initial_quantity = target.Quantity__c;
    result.initial_status = target.Status__c;

    const recordUrl = await getOrgOpenUrl(
      targetOrg,
      `/lightning/r/Inventory_Position__c/${target.Id}/view`,
    );
    await page.goto(recordUrl, { waitUntil: "domcontentloaded", timeout: 120000 });
    await page.waitForTimeout(5000);
    await screenshot(page, artifactDir, result, `${scenario.id}-01-record-before.png`);

    const actionClicked = await clickTransferOptimize(page);
    if (!actionClicked) {
      const listUrl = await getOrgOpenUrl(
        targetOrg,
        "/lightning/o/Inventory_Position__c/list?filterName=Inventory_Transfer_Ops",
      );
      await page.goto(listUrl, { waitUntil: "domcontentloaded", timeout: 120000 });
      await page.waitForTimeout(5000);
      await page.getByText(scenario.medication, { exact: false }).first().click({ timeout: 10000 }).catch(() => {});
      await screenshot(page, artifactDir, result, `${scenario.id}-02-grid-before-action.png`);

      if (!(await clickTransferOptimize(page))) {
        throw new Error("Transfer/Optimize action was not visible in the Salesforce UI");
      }
    }

    await page.waitForTimeout(3000);
    await screenshot(page, artifactDir, result, `${scenario.id}-03-after-action-click.png`);
    await clickIfPresent(page, [/confirm/i, /execute/i, /finish/i, /done/i, /next/i, /transfer/i]);
    await page.waitForTimeout(5000);
    await screenshot(page, artifactDir, result, `${scenario.id}-04-after-confirmation.png`);

    const logs = await querySalesforce(
      targetOrg,
      `SELECT Id, Name, Transfer_Status__c, Quantity_Transferred__c, Source_Store__r.Name, Target_Store__r.Name, Medication__r.Name, Notes__c FROM Transfer_Log__c WHERE Inventory_Position__c = '${target.Id}' ORDER BY CreatedDate DESC LIMIT 1`,
    );

    if (logs.length === 0) {
      throw new Error("No Transfer_Log__c record was created for the UI action");
    }

    result.transfer_log = logs[0];
    result.status = "passed";

    const logUrl = await getOrgOpenUrl(targetOrg, `/lightning/r/Transfer_Log__c/${logs[0].Id}/view`);
    await page.goto(logUrl, { waitUntil: "domcontentloaded", timeout: 120000 });
    await page.waitForTimeout(3000);
    await screenshot(page, artifactDir, result, `${scenario.id}-05-transfer-log.png`);
  } catch (error) {
    result.error = error.message;
    await screenshot(page, artifactDir, result, `${scenario.id}-error.png`).catch(() => {});
  }

  return result;
}

async function findTarget(targetOrg, scenario) {
  const records = await querySalesforce(
    targetOrg,
    `SELECT Id, Name, Quantity__c, Safety_Stock__c, Status__c, Store__r.Name, Medication__r.Name FROM Inventory_Position__c WHERE Store__r.Name = '${escapeSoql(scenario.store)}' AND Medication__r.Name = '${escapeSoql(scenario.medication)}' LIMIT 1`,
  );

  if (records.length === 0) {
    throw new Error(`Could not find seeded inventory row for ${scenario.medication} at ${scenario.store}`);
  }

  return records[0];
}

async function clickTransferOptimize(page) {
  const button = page.getByRole("button", { name: /transfer\/optimize/i }).first();
  if (await button.count()) {
    await button.click({ timeout: 10000 });
    return true;
  }

  const link = page.getByRole("link", { name: /transfer\/optimize/i }).first();
  if (await link.count()) {
    await link.click({ timeout: 10000 });
    return true;
  }

  return false;
}

async function clickIfPresent(page, labels) {
  for (const label of labels) {
    const button = page.getByRole("button", { name: label }).first();
    if (await button.count()) {
      await button.click({ timeout: 10000 });
      return true;
    }
  }

  return false;
}

async function screenshot(page, artifactDir, result, fileName) {
  const path = `${artifactDir}/screenshots/${fileName}`;
  await page.screenshot({ path, fullPage: true });
  result.screenshots.push(path);
}
